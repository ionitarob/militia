/// Summarize Lambda — purpose-built for Resumen Liti.
/// Uses Haiku (fast + cheap), parallel S3 downloads, no session/history/tools overhead.
/// Streams SSE tokens and auto-saves the result to DB on completion.
use std::sync::Arc;

use aws_sdk_bedrockruntime::primitives::Blob;
use bytes::Bytes;
use core_api::{
    build_pool, fetch_secret_string,
    routes::chat::{
        fetch_summary_docs, follow_pdf_links, invoke_scraper_fetch_for_licitacion,
        is_ppt_doc, DocBlob,
    },
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
    let scraper_fetch_arn = std::env::var("SCRAPER_FETCH_ARN").ok();
    let s3_client = aws_sdk_s3::Client::new(&aws_cfg);
    let bedrock = aws_sdk_bedrockruntime::Client::new(&aws_cfg);
    let lambda_client = aws_sdk_lambda::Client::new(&aws_cfg);

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
        let lambda_client = lambda_client.clone();
        let scraper_fetch_arn = scraper_fetch_arn.clone();
        async move { handle(state, lambda_client, scraper_fetch_arn, req).await }
    }))
    .await
}

async fn handle(
    state: Arc<AppState>,
    lambda_client: aws_sdk_lambda::Client,
    scraper_fetch_arn: Option<String>,
    req: Request,
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
        let mut docs = fetch_summary_docs(&state, sum_req.licitacion_id).await;

        // Lambda-to-Lambda: if no docs found at all, ask scraper_fetch to download them on-demand
        if let (true, Some(ref arn)) = (docs.is_empty(), &scraper_fetch_arn) {
            docs = invoke_scraper_fetch_for_licitacion(
                &state, &lambda_client, arn, sum_req.licitacion_id,
            ).await;
        }

        // PDF hyperlink following: if no PPT found, scan downloaded PDFs for linked documents
        if let (false, Some(ref arn)) = (docs.iter().any(|d| is_ppt_doc(&d.nombre)), &scraper_fetch_arn) {
            let linked = follow_pdf_links(
                &state, &lambda_client, arn, &docs, sum_req.licitacion_id,
            ).await;
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

        let mut content: Vec<serde_json::Value> = docs.into_iter().filter_map(|d: DocBlob| {
            let text = extract_doc_text(&d)?;
            tracing::info!(nombre = %d.nombre, media_type = %d.media_type, chars = text.len(), "extracted doc text");
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

const TEXT_CAP: usize = 80_000;

fn extract_doc_text(doc: &DocBlob) -> Option<String> {
    let mt = doc.media_type.as_str();
    let raw = if mt.contains("pdf") {
        extract_pdf_text(&doc.data)
    } else if mt.contains("opendocument.text") || mt.contains("odt") {
        extract_zip_xml_text(&doc.data, "content.xml")
    } else if mt.contains("openxmlformats") && mt.contains("word") {
        extract_zip_xml_text(&doc.data, "word/document.xml")
    } else if mt.contains("msword") {
        extract_binary_text(&doc.data)
    } else if mt.contains("text/plain") {
        std::str::from_utf8(&doc.data).ok().map(|s| s.trim().to_string())
    } else {
        // Unknown type — try PDF first, then ZIP-XML, then raw text
        extract_pdf_text(&doc.data)
            .or_else(|| extract_zip_xml_text(&doc.data, "content.xml"))
            .or_else(|| extract_zip_xml_text(&doc.data, "word/document.xml"))
    };
    let text = raw?;
    if text.trim().is_empty() { return None; }
    if text.len() > TEXT_CAP { Some(text[..TEXT_CAP].to_string()) } else { Some(text) }
}

fn extract_pdf_text(data: &[u8]) -> Option<String> {
    let result = std::panic::catch_unwind(|| pdf_extract::extract_text_from_mem(data));
    match result {
        Ok(Ok(t)) if !t.trim().is_empty() => Some(t),
        _ => None,
    }
}

/// Extract text from a ZIP-based format (DOCX or ODT) by reading the named XML entry
/// and stripping all XML tags to get plain text.
fn extract_zip_xml_text(data: &[u8], entry: &str) -> Option<String> {
    let cursor = std::io::Cursor::new(data);
    let mut archive = zip::ZipArchive::new(cursor).ok()?;
    let mut file = archive.by_name(entry).ok()?;
    use std::io::Read;
    let mut xml = String::new();
    file.read_to_string(&mut xml).ok()?;
    let text = strip_xml_tags(&xml);
    if text.trim().is_empty() { None } else { Some(text) }
}

/// Best-effort extraction for old OLE2 .doc files: pull out runs of printable ASCII/Latin.
fn extract_binary_text(data: &[u8]) -> Option<String> {
    let mut out = String::new();
    let mut run = String::new();
    for &b in data {
        if b >= 0x20 && b < 0x7f || b >= 0xa0 {
            run.push(b as char);
        } else {
            if run.len() >= 5 {
                if !out.is_empty() { out.push(' '); }
                out.push_str(run.trim());
            }
            run.clear();
        }
    }
    if run.len() >= 5 { out.push_str(run.trim()); }
    if out.trim().is_empty() { None } else { Some(out) }
}

fn strip_xml_tags(s: &str) -> String {
    let mut out = String::with_capacity(s.len() / 2);
    let mut in_tag = false;
    let mut last_space = true;
    for c in s.chars() {
        match c {
            '<' => { in_tag = true; }
            '>' => {
                in_tag = false;
                if !last_space { out.push(' '); last_space = true; }
            }
            _ if in_tag => {}
            '\n' | '\r' | '\t' | ' ' => {
                if !last_space { out.push(' '); last_space = true; }
            }
            _ => { out.push(c); last_space = false; }
        }
    }
    out.trim().to_string()
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
