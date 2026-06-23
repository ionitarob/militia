/// Summarize Lambda — purpose-built for Resumen Liti.
/// Uses Haiku (fast + cheap), parallel S3 downloads, no session/history/tools overhead.
/// Streams SSE tokens and auto-saves the result to DB on completion.
use std::sync::Arc;

use aws_sdk_bedrockruntime::primitives::Blob;
use bytes::Bytes;
use core_api::{
    build_pool, fetch_secret_string,
    routes::chat::{fetch_summary_docs, DocBlob},
    AppState,
};
use futures_util::StreamExt;
use http::Response;
use http_body_util::{BodyExt, StreamBody};
use http_body::Frame;
use lambda_http::{run_with_streaming_response, service_fn, Body, Request};
use serde::Deserialize;
use tokio::sync::mpsc;
use tokio_stream::wrappers::ReceiverStream;

type Error = lambda_http::Error;
type BoxBody = http_body_util::combinators::BoxBody<Bytes, Error>;

const MODEL_ID: &str = "eu.anthropic.claude-haiku-4-5-20251001-v1:0";

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
async fn main() -> Result<(), Error> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .json()
        .without_time()
        .init();

    let aws_cfg = aws_config::load_from_env().await;
    let sm = aws_sdk_secretsmanager::Client::new(&aws_cfg);

    let pool = build_pool(&sm).await?;

    let jwt_secret_arn = std::env::var("JWT_SECRET_ARN").expect("JWT_SECRET_ARN required");
    let jwt_secret = fetch_secret_string(&sm, &jwt_secret_arn).await?;

    let s3_bucket = std::env::var("S3_BUCKET").expect("S3_BUCKET required");
    let s3_client = aws_sdk_s3::Client::new(&aws_cfg);
    let bedrock = aws_sdk_bedrockruntime::Client::new(&aws_cfg);

    let state = Arc::new(AppState {
        pool,
        jwt_secret,
        smtp_user: String::new(),
        smtp_pass: String::new(),
        s3_client,
        s3_bucket,
        bedrock,
    });

    run_with_streaming_response(service_fn(move |req: Request| {
        let state = Arc::clone(&state);
        async move { handle(state, req).await }
    }))
    .await
}

async fn handle(state: Arc<AppState>, req: Request) -> Result<Response<BoxBody>, Error> {
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
        Body::Text(s) => s.as_bytes().to_vec(),
        Body::Binary(b) => b.clone(),
        Body::Empty => return sse_error("empty body"),
    };
    let sum_req: SummarizeRequest = match serde_json::from_slice(&body_bytes) {
        Ok(r) => r,
        Err(_) => return sse_error("invalid json"),
    };

    let (tx, rx) = mpsc::channel::<Bytes>(128);

    tokio::spawn(async move {
        let docs = fetch_summary_docs(&state, sum_req.licitacion_id).await;
        tracing::info!(
            count = docs.len(),
            names = ?docs.iter().map(|d| &d.nombre).collect::<Vec<_>>(),
            bytes = docs.iter().map(|d| d.data.len()).sum::<usize>(),
            "selected docs for summary"
        );

        let mut content: Vec<serde_json::Value> = docs.into_iter().filter_map(|d: DocBlob| {
            let text = extract_pdf_text(&d.data)?;
            tracing::info!(nombre = %d.nombre, chars = text.len(), "extracted pdf text");
            Some(serde_json::json!({
                "type": "text",
                "text": format!("=== {} ===\n\n{}", d.nombre, text),
            }))
        }).collect();
        content.push(serde_json::json!({
            "type": "text",
            "text": "Genera el resumen ejecutivo de esta licitación siguiendo la estructura indicada."
        }));

        let messages = vec![serde_json::json!({"role": "user", "content": content})];
        let request = serde_json::json!({
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 1024,
            "system": SYSTEM_PROMPT,
            "messages": messages,
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
    let body_bytes = serde_json::to_vec(&request)?;

    tracing::info!("calling bedrock invoke_model");

    let resp = state
        .bedrock
        .invoke_model()
        .model_id(MODEL_ID)
        .content_type("application/json")
        .accept("application/json")
        .body(Blob::new(body_bytes))
        .send()
        .await
        .map_err(|e| format!("bedrock invoke: {e:?}"))?;

    tracing::info!("bedrock responded");

    let resp_json: serde_json::Value = serde_json::from_slice(resp.body().as_ref())?;
    let full_text = resp_json["content"]
        .as_array()
        .and_then(|a| a.iter().find(|b| b["type"] == "text"))
        .and_then(|b| b["text"].as_str())
        .unwrap_or("")
        .to_string();

    tracing::info!(chars = full_text.len(), "got response");

    // Stream tokens word by word so UI still animates
    for word in full_text.split_inclusive(char::is_whitespace) {
        let sse = sse_bytes(&format!(
            r#"{{"token":{}}}"#,
            serde_json::to_string(word).unwrap_or_default()
        ));
        let _ = tx.send(sse).await;
    }

    // Auto-save to DB
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

/// Extract readable text from a PDF, capping at 80 000 chars to stay within token budget.
/// Returns None if the PDF yields no usable text (e.g. scanned image-only PDF).
fn extract_pdf_text(data: &[u8]) -> Option<String> {
    let result = std::panic::catch_unwind(|| pdf_extract::extract_text_from_mem(data));
    let text = match result {
        Ok(Ok(t)) => t,
        _ => return None,
    };
    let trimmed = text.trim().to_string();
    if trimmed.is_empty() {
        return None;
    }
    // Truncate to keep token usage predictable
    if trimmed.len() > 80_000 {
        Some(trimmed[..80_000].to_string())
    } else {
        Some(trimmed)
    }
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
