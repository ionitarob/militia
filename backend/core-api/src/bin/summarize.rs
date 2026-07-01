/// Summarize — purpose-built for Resumen Liti.
/// Uses Haiku (fast + cheap), parallel blob downloads, no session/history/tools overhead.
/// Streams SSE tokens and auto-saves the result to DB on completion.
use std::sync::Arc;

use axum::{body::to_bytes, extract::State, routing::post, Router};
use bytes::Bytes;
use core_api::{
    build_blob_client, build_pool,
    routes::chat::{
        extract_doc_text, fetch_summary_docs, follow_pdf_links_direct,
        invoke_scraper_fetch_for_licitacion, is_ppt_doc, openai_url, DocBlob,
    },
    AppState,
};
use futures_util::StreamExt as _;
use http::{Request, Response};
use http_body_util::{BodyExt, StreamBody};
use http_body::Frame;
use lambda_http::{Body as LambdaBody};
use serde::Deserialize;
use tokio::sync::mpsc;
use tokio_stream::wrappers::ReceiverStream;

type Error = lambda_http::Error;
type BoxBody = http_body_util::combinators::BoxBody<Bytes, Error>;

const SYSTEM_PROMPT: &str = "Eres un analista experto en licitaciones públicas españolas para el equipo comercial de Ingram Micro.\n\
Tu única tarea: leer los documentos adjuntos y generar un resumen ejecutivo conciso.\n\
\n\
ESTRUCTURA (en este orden):\n\
1. **Objeto**: qué producto o servicio se contrata exactamente\n\
2. **Presupuesto base**: importe total (y desglose por lotes si aplica)\n\
3. **Plazo de ejecución**: duración del contrato\n\
4. **Criterios de adjudicación**: % precio vs. criterios técnicos, con sus puntuaciones\n\
5. **Solvencia requerida**: requisitos técnicos y económicos mínimos exigidos\n\
6. **Puntos clave**: marcas autorizadas, modelos, condiciones especiales o cualquier aspecto relevante\n\
\n\
Sé directo y conciso. Usa **negrita** para datos numéricos y nombres clave. Máximo 350 palabras.\n\
NUNCA digas que el usuario debe consultar los documentos. Tú los lees por ellos.\n\
Si no hay documentos adjuntos, responde solo: 'Esta licitación no tiene documentos disponibles para analizar.'";

#[derive(Deserialize)]
struct SummarizeRequest {
    licitacion_id: i64,
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .json()
        .without_time()
        .init();

    let db_url = std::env::var("DATABASE_URL").expect("DATABASE_URL required");
    let pool = build_pool(&db_url).await.expect("DB pool failed");

    let jwt_secret  = std::env::var("JWT_SECRET").expect("JWT_SECRET required");
    let blob_account   = std::env::var("AZURE_STORAGE_ACCOUNT").expect("AZURE_STORAGE_ACCOUNT required");
    let blob_key       = std::env::var("AZURE_STORAGE_KEY").expect("AZURE_STORAGE_KEY required");
    let blob_container = std::env::var("AZURE_BLOB_CONTAINER").unwrap_or_else(|_| "documents".to_string());
    let azure_openai_key      = std::env::var("AZURE_OPENAI_KEY").expect("AZURE_OPENAI_KEY required");
    let azure_openai_endpoint = std::env::var("AZURE_OPENAI_ENDPOINT").expect("AZURE_OPENAI_ENDPOINT required");
    let scraper_fetch_url = std::env::var("SCRAPER_FETCH_URL").ok();

    let blob_client = build_blob_client(&blob_account, &blob_key);
    let http_client = reqwest::Client::new();

    let state = Arc::new(AppState {
        pool,
        jwt_secret,
        smtp_user: String::new(),
        smtp_pass: String::new(),
        blob_client,
        blob_container,
        http_client,
        azure_openai_key,
        azure_openai_endpoint,
        scraper_fetch_url,
    });

    let app = Router::new()
        .route("/", post(handle_post))
        .with_state(state);

    let port = std::env::var("PORT").unwrap_or_else(|_| "8081".to_string());
    let listener = tokio::net::TcpListener::bind(format!("0.0.0.0:{}", port))
        .await
        .expect("bind failed");

    tracing::info!(port, "summarize listening");
    axum::serve(listener, app).await.unwrap();
}

async fn handle_post(
    State(state): State<Arc<AppState>>,
    axum_req: axum::extract::Request,
) -> impl axum::response::IntoResponse {
    let (parts, body) = axum_req.into_parts();
    let body_bytes: Bytes = to_bytes(body, 10 * 1024 * 1024).await.unwrap_or_default();
    let lambda_body = if body_bytes.is_empty() { LambdaBody::Empty } else { LambdaBody::Binary(body_bytes.to_vec()) };

    let mut req_builder = Request::builder().method(parts.method).uri(parts.uri);
    for (name, val) in &parts.headers { req_builder = req_builder.header(name, val); }
    let lambda_req = req_builder.body(lambda_body).unwrap();

    match handle(state, lambda_req).await {
        Ok(resp) => {
            let (rp, rb) = resp.into_parts();
            let mut builder = http::Response::builder().status(rp.status);
            for (n, v) in &rp.headers { builder = builder.header(n, v); }
            builder = builder
                .header("access-control-allow-origin", "*")
                .header("access-control-allow-headers", "Authorization, Content-Type");
            // body is already BoxBody — wrap in axum body
            builder.body(axum::body::Body::new(rb)).unwrap()
        }
        Err(e) => {
            http::Response::builder()
                .status(500)
                .header("content-type", "text/event-stream")
                .header("access-control-allow-origin", "*")
                .body(axum::body::Body::from(format!("data: {{\"error\":\"{e}\"}}\n\ndata: [DONE]\n\n")))
                .unwrap()
        }
    }
}

async fn handle(
    state: Arc<AppState>,
    req: Request<LambdaBody>,
) -> Result<Response<BoxBody>, Error> {
    // JWT auth
    let auth = req
        .headers()
        .get("authorization")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("");
    let token = auth.trim_start_matches("Bearer ").trim();
    if core_api::auth::verify(token, &state.jwt_secret).is_err() {
        return sse_error("Unauthorized");
    }

    let body_bytes = match req.body() {
        LambdaBody::Text(s) => s.as_bytes().to_vec(),
        LambdaBody::Binary(b) => b.clone(),
        LambdaBody::Empty => return sse_error("empty body"),
    };
    let sum_req: SummarizeRequest = match serde_json::from_slice(&body_bytes) {
        Ok(r) => r,
        Err(_) => return sse_error("invalid json"),
    };

    let (tx, rx) = mpsc::channel::<Bytes>(128);

    tokio::spawn(async move {
        let mut docs = fetch_summary_docs(&state, sum_req.licitacion_id).await;

        if let (true, Some(ref url)) = (docs.is_empty(), &state.scraper_fetch_url) {
            docs = invoke_scraper_fetch_for_licitacion(
                &state, url, sum_req.licitacion_id,
            ).await;
        }

        if !docs.iter().any(|d| is_ppt_doc(&d.nombre)) {
            let linked = follow_pdf_links_direct(&state, &docs).await;
            if !linked.is_empty() {
                tracing::info!(count = linked.len(), "appended docs found via PDF hyperlinks");
                docs.extend(linked);
            }
        }

        tracing::info!(
            count = docs.len(),
            names = ?docs.iter().map(|d| &d.nombre).collect::<Vec<_>>(),
            bytes = docs.iter().map(|d| d.data.len()).sum::<usize>(),
            "selected docs for summary"
        );

        let doc_parts: Vec<String> = docs.iter().filter_map(|d: &DocBlob| {
            let text = extract_doc_text(d)?;
            tracing::info!(nombre = %d.nombre, media_type = %d.media_type, chars = text.len(), "extracted doc text");
            Some(format!("=== {} ===\n\n{}", d.nombre, text))
        }).collect();

        let user_content = if doc_parts.is_empty() {
            "Genera el resumen ejecutivo de esta licitación siguiendo la estructura indicada.".to_string()
        } else {
            format!(
                "{}\n\n---\n\nGenera el resumen ejecutivo de esta licitación siguiendo la estructura indicada.",
                doc_parts.join("\n\n---\n\n")
            )
        };

        let messages = vec![
            serde_json::json!({"role": "system", "content": SYSTEM_PROMPT}),
            serde_json::json!({"role": "user", "content": user_content}),
        ];
        let request = serde_json::json!({
            "messages": messages,
            "max_completion_tokens": 16384,
            "stream": true,
        });

        match stream_summary(&state, &tx, request, sum_req.licitacion_id).await {
            Ok(_) => { let _ = tx.send(sse_done()).await; }
            Err(e) => {
                let msg = serde_json::to_string(&e.to_string()).unwrap_or_else(|_| "\"error\"".to_string());
                let _ = tx.send(sse_bytes(&format!(r#"{{"error":{}}}"#, msg))).await;
                let _ = tx.send(sse_done()).await;
            }
        }
    });

    let stream = ReceiverStream::new(rx).map(|b| Ok::<_, Error>(Frame::data(b)));
    let body = BodyExt::boxed(StreamBody::new(stream));

    Ok(Response::builder()
        .status(200)
        .header("content-type", "text/event-stream")
        .header("cache-control", "no-cache")
        .header("x-accel-buffering", "no")
        .header("access-control-allow-origin", "*")
        .header("access-control-allow-headers", "Authorization, Content-Type")
        .body(body)
        .unwrap())
}


async fn stream_summary(
    state: &AppState,
    tx: &mpsc::Sender<Bytes>,
    request: serde_json::Value,
    licitacion_id: i64,
) -> Result<(), Error> {
    tracing::info!("calling Azure OpenAI for summary (streaming)");

    let url = openai_url(&state.azure_openai_endpoint);

    let resp = state.http_client
        .post(&url)
        .header("api-key", &state.azure_openai_key)
        .header("content-type", "application/json")
        .json(&request)
        .send()
        .await
        .map_err(|e| format!("openai call: {e:?}"))?;

    tracing::info!(status = %resp.status(), "Azure OpenAI stream started");

    let mut byte_stream = resp.bytes_stream();
    let mut buf = String::new();
    let mut full_text = String::new();

    while let Some(chunk) = byte_stream.next().await {
        let chunk = chunk.map_err(|e| format!("stream read: {e}"))?;
        buf.push_str(&String::from_utf8_lossy(&chunk));

        while let Some(pos) = buf.find('\n') {
            let line = buf[..pos].trim().to_string();
            buf = buf[pos + 1..].to_string();

            if !line.starts_with("data: ") { continue; }
            let data = &line[6..];
            if data == "[DONE]" { break; }

            let Ok(json) = serde_json::from_str::<serde_json::Value>(data) else { continue };
            if let Some(token) = json["choices"][0]["delta"]["content"].as_str() {
                full_text.push_str(token);
                let _ = tx.send(sse_bytes(&format!(
                    r#"{{"token":{}}}"#,
                    serde_json::to_string(token).unwrap_or_default()
                ))).await;
            }
        }
    }

    tracing::info!(chars = full_text.len(), "summary stream complete");

    if !full_text.is_empty() {
        let _ = sqlx::query(
            "UPDATE licitacion SET ai_summary = $1, ai_summary_at = NOW() WHERE id = $2",
        )
        .bind(&full_text)
        .bind(licitacion_id)
        .execute(&state.pool)
        .await;
    }

    Ok(())
}

fn sse_bytes(payload: &str) -> Bytes {
    Bytes::from(format!("data: {}\n\n", payload))
}

fn sse_done() -> Bytes {
    Bytes::from_static(b"data: [DONE]\n\n")
}

fn sse_error(msg: &str) -> Result<Response<BoxBody>, Error> {
    let (tx, rx) = mpsc::channel::<Bytes>(2);
    let msg = msg.to_string();
    tokio::spawn(async move {
        let _ = tx.send(sse_bytes(&format!(r#"{{"error":"{}"}}"#, msg))).await;
        let _ = tx.send(sse_done()).await;
    });
    let stream = ReceiverStream::new(rx).map(|b| Ok::<_, Error>(Frame::data(b)));
    let body = BodyExt::boxed(StreamBody::new(stream));
    Ok(Response::builder()
        .status(200)
        .header("content-type", "text/event-stream")
        .header("access-control-allow-origin", "*")
        .body(body)
        .unwrap())
}
