/// Streaming chat Lambda — served via Lambda Function URL (RESPONSE_STREAM mode).
/// Bypasses API Gateway's 29-second limit and streams Bedrock tokens as SSE.
///
/// SSE protocol:
///   data: {"session_id":"<uuid>"}\n\n     ← first event, always
///   data: {"token":"Hello"}\n\n            ← repeated for each token
///   data: [DONE]\n\n                       ← stream end
use std::sync::Arc;

use aws_sdk_bedrockruntime::primitives::Blob;
use aws_sdk_bedrockruntime::types::ResponseStream;
use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
use bytes::Bytes;
use core_api::{
    build_pool, fetch_secret_string,
    routes::chat::{
        create_session, execute_tool, fetch_licitacion_docs, load_history, save_message,
        tool_defs, DocBlob, MODEL_ID, SYSTEM_PROMPT,
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

#[derive(Deserialize)]
struct ChatRequest {
    message: String,
    session_id: Option<String>,
    licitacion_id: Option<i64>,
}

// ── Entrypoint ────────────────────────────────────────────────────────────────

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

// ── Handler ───────────────────────────────────────────────────────────────────

async fn handle(state: Arc<AppState>, req: Request) -> Result<Response<BoxBody>, Error> {
    // JWT auth
    let auth = req
        .headers()
        .get("authorization")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("");
    let token = auth.trim_start_matches("Bearer ").trim();
    let claims = match core_api::auth::verify(token, &state.jwt_secret) {
        Ok(c) => c,
        Err(_) => return sse_error("Unauthorized"),
    };

    // Parse body
    let body_bytes = match req.body() {
        Body::Text(s) => s.as_bytes().to_vec(),
        Body::Binary(b) => b.clone(),
        Body::Empty => return sse_error("empty body"),
    };
    let chat_req: ChatRequest = match serde_json::from_slice(&body_bytes) {
        Ok(r) => r,
        Err(_) => return sse_error("invalid json"),
    };
    if chat_req.message.trim().is_empty() {
        return sse_error("message is empty");
    }

    // Session
    let session_id = if let Some(sid) = &chat_req.session_id {
        match sid.parse::<uuid::Uuid>() {
            Ok(u) => {
                let exists: bool = sqlx::query_scalar(
                    "SELECT EXISTS(SELECT 1 FROM chat_session WHERE id = $1 AND user_id = $2)",
                )
                .bind(u)
                .bind(claims.sub)
                .fetch_one(&state.pool)
                .await
                .unwrap_or(false);
                if exists { u } else { create_session(&state.pool, claims.sub).await? }
            }
            Err(_) => create_session(&state.pool, claims.sub).await?,
        }
    } else {
        create_session(&state.pool, claims.sub).await?
    };

    // Build initial message list
    let mut messages = load_history(&state.pool, session_id).await?;

    if let Some(lic_id) = chat_req.licitacion_id {
        let docs = fetch_licitacion_docs(&state, lic_id).await;
        if !docs.is_empty() {
            let mut content: Vec<serde_json::Value> = docs.into_iter().map(|d: DocBlob| {
                serde_json::json!({
                    "type": "document",
                    "source": {"type": "base64", "media_type": d.media_type, "data": BASE64.encode(&d.data)},
                    "title": d.nombre,
                })
            }).collect();
            content.push(serde_json::json!({"type": "text", "text": chat_req.message.trim()}));
            messages.push(serde_json::json!({"role": "user", "content": content}));
        } else {
            messages.push(serde_json::json!({"role": "user", "content": chat_req.message}));
        }
    } else {
        messages.push(serde_json::json!({"role": "user", "content": chat_req.message}));
    }

    // Channel: background task → SSE body
    let (tx, rx) = mpsc::channel::<Bytes>(128);
    let user_message = chat_req.message.clone();

    tokio::spawn(async move {
        // First event: session_id so Flutter can persist it
        let _ = tx
            .send(sse_bytes(&format!(r#"{{"session_id":"{}"}}"#, session_id)))
            .await;

        match stream_chat(&state, &tx, &mut messages).await {
            Ok(reply) => {
                let _ = save_message(&state.pool, session_id, "user", &user_message).await;
                let _ = save_message(&state.pool, session_id, "assistant", &reply).await;
                let _ = sqlx::query("UPDATE chat_session SET updated_at = NOW() WHERE id = $1")
                    .bind(session_id)
                    .execute(&state.pool)
                    .await;
                let _ = tx.send(sse_done()).await;
            }
            Err(e) => {
                let _ = tx.send(sse_bytes(&format!(r#"{{"error":"{}"}}"#, e))).await;
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

// ── Streaming agentic loop ────────────────────────────────────────────────────

async fn stream_chat(
    state: &AppState,
    tx: &mpsc::Sender<Bytes>,
    messages: &mut Vec<serde_json::Value>,
) -> Result<String, Error> {
    for round in 0..3_u8 {
        let request = serde_json::json!({
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 4096,
            "system": SYSTEM_PROMPT,
            "messages": messages,
            "tools": tool_defs(),
        });
        let body_bytes = serde_json::to_vec(&request)?;

        if round == 0 {
            let streamed = invoke_streaming(state, tx, messages, body_bytes).await;
            match streamed {
                Ok(reply) => return Ok(reply),
                Err(ref e) if e.to_string() == "tool_use" => {}
                Err(e) => return Err(e),
            }
        } else {
            // Subsequent rounds: buffered call to handle tools
            let resp = state
                .bedrock
                .invoke_model()
                .model_id(MODEL_ID)
                .content_type("application/json")
                .accept("application/json")
                .body(Blob::new(body_bytes))
                .send()
                .await
                .map_err(|e| format!("bedrock invoke: {e}"))?;

            let resp_json: serde_json::Value = serde_json::from_slice(resp.body().as_ref())?;
            let content = resp_json["content"].clone();
            let stop_reason = resp_json["stop_reason"].as_str().unwrap_or("end_turn");

            messages.push(serde_json::json!({"role": "assistant", "content": content}));

            if stop_reason != "tool_use" {
                let text = content
                    .as_array()
                    .and_then(|a| a.iter().find(|b| b["type"] == "text"))
                    .and_then(|b| b["text"].as_str())
                    .unwrap_or("Sin respuesta disponible.")
                    .to_string();
                for word in text.split_inclusive(char::is_whitespace) {
                    let _ = tx.send(sse_bytes(&format!(
                        r#"{{"token":{}}}"#,
                        serde_json::to_string(word).unwrap_or_default()
                    ))).await;
                }
                return Ok(text);
            }

            let empty = vec![];
            let tool_blocks = content.as_array().unwrap_or(&empty);
            let mut tool_results = vec![];
            for block in tool_blocks {
                if block["type"] != "tool_use" { continue; }
                let use_id = block["id"].as_str().unwrap_or("");
                let name = block["name"].as_str().unwrap_or("");
                let input = &block["input"];
                let result = execute_tool(&state.pool, name, input).await;
                tool_results.push(serde_json::json!({
                    "type": "tool_result",
                    "tool_use_id": use_id,
                    "content": result,
                }));
            }
            messages.push(serde_json::json!({"role": "user", "content": tool_results}));
        }
    }
    Err("bedrock loop exceeded max iterations".into())
}

async fn invoke_streaming(
    state: &AppState,
    tx: &mpsc::Sender<Bytes>,
    messages: &mut Vec<serde_json::Value>,
    body_bytes: Vec<u8>,
) -> Result<String, Error> {
    let resp = state
        .bedrock
        .invoke_model_with_response_stream()
        .model_id(MODEL_ID)
        .content_type("application/json")
        .accept("application/json")
        .body(Blob::new(body_bytes))
        .send()
        .await
        .map_err(|e| format!("bedrock stream: {e}"))?;

    let mut event_stream = resp.body;

    let mut content_blocks: Vec<serde_json::Value> = Vec::new();
    let mut current_type = String::new();
    let mut current_id = String::new();
    let mut current_name = String::new();
    let mut current_text = String::new();
    let mut current_input_json = String::new();
    let mut current_index: i64 = -1;
    let mut stop_reason = String::from("end_turn");
    let mut full_text = String::new();

    while let Ok(Some(event)) = event_stream.recv().await {
        let ResponseStream::Chunk(chunk) = event else { continue };
        let Some(bytes) = chunk.bytes else { continue };
        let Ok(json) = serde_json::from_slice::<serde_json::Value>(bytes.as_ref()) else { continue };

        match json["type"].as_str().unwrap_or("") {
            "content_block_start" => {
                let idx = json["index"].as_i64().unwrap_or(0);
                if idx != current_index && current_index >= 0 {
                    flush_block(&mut content_blocks, &current_type, &current_id, &current_name, &current_text, &current_input_json);
                    current_text.clear();
                    current_input_json.clear();
                }
                current_index = idx;
                let cb = &json["content_block"];
                current_type = cb["type"].as_str().unwrap_or("text").to_string();
                current_id = cb["id"].as_str().unwrap_or("").to_string();
                current_name = cb["name"].as_str().unwrap_or("").to_string();
            }
            "content_block_delta" => {
                let delta = &json["delta"];
                match delta["type"].as_str().unwrap_or("") {
                    "text_delta" => {
                        if let Some(t) = delta["text"].as_str() {
                            current_text.push_str(t);
                            full_text.push_str(t);
                            let sse = sse_bytes(&format!(
                                r#"{{"token":{}}}"#,
                                serde_json::to_string(t).unwrap_or_default()
                            ));
                            let _ = tx.send(sse).await;
                        }
                    }
                    "input_json_delta" => {
                        if let Some(p) = delta["partial_json"].as_str() {
                            current_input_json.push_str(p);
                        }
                    }
                    _ => {}
                }
            }
            "content_block_stop" => {
                if current_index >= 0 {
                    flush_block(&mut content_blocks, &current_type, &current_id, &current_name, &current_text, &current_input_json);
                    current_text.clear();
                    current_input_json.clear();
                    current_index = -1;
                }
            }
            "message_delta" => {
                if let Some(r) = json["delta"]["stop_reason"].as_str() {
                    stop_reason = r.to_string();
                }
            }
            _ => {}
        }
    }

    if current_index >= 0 && !current_type.is_empty() {
        flush_block(&mut content_blocks, &current_type, &current_id, &current_name, &current_text, &current_input_json);
    }

    messages.push(serde_json::json!({"role": "assistant", "content": content_blocks}));

    if stop_reason == "tool_use" {
        let mut tool_results = vec![];
        for block in &content_blocks {
            if block["type"] != "tool_use" { continue; }
            let use_id = block["id"].as_str().unwrap_or("");
            let name = block["name"].as_str().unwrap_or("");
            let input = &block["input"];
            let result = execute_tool(&state.pool, name, input).await;
            tool_results.push(serde_json::json!({
                "type": "tool_result",
                "tool_use_id": use_id,
                "content": result,
            }));
        }
        messages.push(serde_json::json!({"role": "user", "content": tool_results}));

        let request = serde_json::json!({
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 4096,
            "system": SYSTEM_PROMPT,
            "messages": messages,
            "tools": tool_defs(),
        });
        let new_body = serde_json::to_vec(&request)?;
        return Box::pin(invoke_streaming(state, tx, messages, new_body)).await;
    }

    if full_text.is_empty() {
        full_text = "Sin respuesta disponible.".to_string();
    }
    Ok(full_text)
}

fn flush_block(
    blocks: &mut Vec<serde_json::Value>,
    block_type: &str,
    id: &str,
    name: &str,
    text: &str,
    input_json: &str,
) {
    let block = if block_type == "tool_use" {
        let input: serde_json::Value = serde_json::from_str(input_json).unwrap_or(serde_json::json!({}));
        serde_json::json!({"type": "tool_use", "id": id, "name": name, "input": input})
    } else {
        serde_json::json!({"type": "text", "text": text})
    };
    blocks.push(block);
}

// ── SSE helpers ───────────────────────────────────────────────────────────────

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
