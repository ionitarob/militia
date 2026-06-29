/// Streaming chat — served as an HTTP endpoint on Azure Container Apps.
/// Replaces the Lambda Function URL (RESPONSE_STREAM) pattern.
/// Streams Anthropic API SSE tokens as SSE to the client.
///
/// SSE protocol:
///   data: {"session_id":"<uuid>"}\n\n     ← first event, always
///   data: {"token":"Hello"}\n\n            ← repeated for each token
///   data: [DONE]\n\n                       ← stream end
use std::sync::Arc;

use axum::{body::to_bytes, extract::State, routing::post, Router};
use bytes::Bytes;
use core_api::{
    build_blob_client, build_pool,
    routes::chat::{
        create_session, docs_to_text_block, execute_tool, fetch_licitacion_docs, follow_pdf_links,
        invoke_scraper_fetch_for_licitacion, is_ppt_doc, load_history, openai_url, save_message,
        tool_defs, SYSTEM_PROMPT,
    },
    AppState,
};
use futures_util::StreamExt;
use http::{Request, Response};
use http_body_util::{BodyExt, StreamBody};
use http_body::Frame;
use lambda_http::Body as LambdaBody;
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
    let blob_key_env   = std::env::var("AZURE_STORAGE_KEY").expect("AZURE_STORAGE_KEY required");
    let blob_container = std::env::var("AZURE_BLOB_CONTAINER").unwrap_or_else(|_| "documents".to_string());
    let azure_openai_key      = std::env::var("AZURE_OPENAI_KEY").expect("AZURE_OPENAI_KEY required");
    let azure_openai_endpoint = std::env::var("AZURE_OPENAI_ENDPOINT").expect("AZURE_OPENAI_ENDPOINT required");
    let scraper_fetch_url = std::env::var("SCRAPER_FETCH_URL").ok();

    let blob_client = build_blob_client(&blob_account, &blob_key_env);
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

    let port = std::env::var("PORT").unwrap_or_else(|_| "8082".to_string());
    let listener = tokio::net::TcpListener::bind(format!("0.0.0.0:{}", port))
        .await
        .expect("bind failed");

    tracing::info!(port, "chat-stream listening");
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

    let body_bytes = match req.body() {
        LambdaBody::Text(s) => s.as_bytes().to_vec(),
        LambdaBody::Binary(b) => b.clone(),
        LambdaBody::Empty => return sse_error("empty body"),
    };
    let chat_req: ChatRequest = match serde_json::from_slice(&body_bytes) {
        Ok(r) => r,
        Err(_) => return sse_error("invalid json"),
    };
    if chat_req.message.trim().is_empty() {
        return sse_error("message is empty");
    }

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

    let mut messages = load_history(&state.pool, session_id).await?;

    if let Some(lic_id) = chat_req.licitacion_id {
        let mut docs = fetch_licitacion_docs(&state, lic_id).await;

        if let (true, Some(ref url)) = (docs.is_empty(), &state.scraper_fetch_url) {
            docs = invoke_scraper_fetch_for_licitacion(&state, url, lic_id).await;
        }

        if let (false, Some(ref url)) = (docs.iter().any(|d| is_ppt_doc(&d.nombre)), &state.scraper_fetch_url) {
            let linked = follow_pdf_links(&state, url, &docs, lic_id).await;
            if !linked.is_empty() {
                docs.extend(linked);
            }
        }

        let doc_text = docs_to_text_block(&docs);
        if let Some(text_block) = doc_text {
            let combined = format!("{}\n\n---\n\n{}", text_block, chat_req.message.trim());
            messages.push(serde_json::json!({"role": "user", "content": combined}));
        } else {
            messages.push(serde_json::json!({"role": "user", "content": chat_req.message}));
        }
    } else {
        messages.push(serde_json::json!({"role": "user", "content": chat_req.message}));
    }

    let (tx, rx) = mpsc::channel::<Bytes>(128);
    let user_message = chat_req.message.clone();

    tokio::spawn(async move {
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

// ── Azure OpenAI streaming agentic loop ───────────────────────────────────────

async fn stream_chat(
    state: &AppState,
    tx: &mpsc::Sender<Bytes>,
    messages: &mut Vec<serde_json::Value>,
) -> Result<String, Error> {
    let url = openai_url(&state.azure_openai_endpoint);

    for _ in 0..3_u8 {
        let mut openai_msgs = vec![serde_json::json!({"role": "system", "content": SYSTEM_PROMPT})];
        openai_msgs.extend(messages.iter().cloned());

        let request = serde_json::json!({
            "messages": openai_msgs,
            "max_tokens": 4096,
            "tools": tool_defs(),
            "tool_choice": "auto",
            "stream": true,
        });

        let resp = state.http_client
            .post(&url)
            .header("api-key", &state.azure_openai_key)
            .header("content-type", "application/json")
            .json(&request)
            .send()
            .await
            .map_err(|e| format!("openai stream: {e}"))?;

        let mut byte_stream = resp.bytes_stream();
        let mut buf = String::new();
        let mut full_text = String::new();
        let mut finish_reason = String::new();
        let mut assistant_msg = serde_json::json!({"role": "assistant", "content": null});

        // Accumulate tool call fragments: index → (id, name, arguments)
        let mut tool_call_acc: std::collections::HashMap<usize, (String, String, String)> =
            std::collections::HashMap::new();

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
                let choice = &json["choices"][0];
                let delta = &choice["delta"];

                // Text token
                if let Some(token) = delta["content"].as_str() {
                    full_text.push_str(token);
                    let _ = tx.send(sse_bytes(&format!(
                        r#"{{"token":{}}}"#,
                        serde_json::to_string(token).unwrap_or_default()
                    ))).await;
                }

                // Tool call fragments
                if let Some(tcs) = delta["tool_calls"].as_array() {
                    for tc in tcs {
                        let idx = tc["index"].as_u64().unwrap_or(0) as usize;
                        let entry = tool_call_acc.entry(idx).or_insert_with(|| (String::new(), String::new(), String::new()));
                        if let Some(id) = tc["id"].as_str() { entry.0 = id.to_string(); }
                        if let Some(name) = tc["function"]["name"].as_str() { entry.1 = name.to_string(); }
                        if let Some(args) = tc["function"]["arguments"].as_str() { entry.2.push_str(args); }
                    }
                }

                if let Some(fr) = choice["finish_reason"].as_str() {
                    if !fr.is_empty() { finish_reason = fr.to_string(); }
                }
            }
        }

        if finish_reason == "tool_calls" {
            // Build assistant message with tool_calls array
            let mut tc_list: Vec<(usize, &(String, String, String))> = tool_call_acc.iter().map(|(k, v)| (*k, v)).collect();
            tc_list.sort_by_key(|(i, _)| *i);
            let tool_calls_json: Vec<serde_json::Value> = tc_list.iter().map(|(_, (id, name, args))| {
                serde_json::json!({"id": id, "type": "function", "function": {"name": name, "arguments": args}})
            }).collect();
            assistant_msg = serde_json::json!({"role": "assistant", "content": null, "tool_calls": tool_calls_json});
            messages.push(assistant_msg);

            for (_, (id, name, args_str)) in &tc_list {
                let args: serde_json::Value = serde_json::from_str(args_str).unwrap_or(serde_json::json!({}));
                let result = execute_tool(&state.pool, name, &args).await;
                messages.push(serde_json::json!({
                    "role": "tool",
                    "tool_call_id": id,
                    "content": result,
                }));
            }
            continue;
        }

        // Normal stop
        assistant_msg["content"] = serde_json::json!(full_text);
        messages.push(assistant_msg);
        if full_text.is_empty() {
            return Ok("Sin respuesta disponible.".to_string());
        }
        return Ok(full_text);
    }

    Err("ai loop exceeded max iterations".into())
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
