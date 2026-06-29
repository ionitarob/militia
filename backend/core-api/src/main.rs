use axum::{body::to_bytes, extract::State, routing::any, Router};
use bytes::Bytes;
use core_api::{build_blob_client, build_pool, AppState};
use http::{Request, Response};
use lambda_http::Body as LambdaBody;
use std::sync::Arc;

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .json()
        .without_time()
        .init();

    let db_url = std::env::var("DATABASE_URL").expect("DATABASE_URL required");
    let pool = build_pool(&db_url).await.expect("DB pool failed");

    sqlx::migrate!("./migrations")
        .run(&pool)
        .await
        .expect("DB migration failed");

    let jwt_secret  = std::env::var("JWT_SECRET").expect("JWT_SECRET required");
    let smtp_user   = std::env::var("SMTP_USER").expect("SMTP_USER required");
    let smtp_pass   = std::env::var("SMTP_PASS").expect("SMTP_PASS required");
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
        smtp_user,
        smtp_pass,
        blob_client,
        blob_container,
        http_client,
        azure_openai_key,
        azure_openai_endpoint,
        scraper_fetch_url,
    });

    let app = Router::new()
        .route("/", any(handle_any))
        .route("/*path", any(handle_any))
        .with_state(state);

    let port = std::env::var("PORT").unwrap_or_else(|_| "8080".to_string());
    let listener = tokio::net::TcpListener::bind(format!("0.0.0.0:{}", port))
        .await
        .expect("bind failed");

    tracing::info!(port, "core-api listening");
    axum::serve(listener, app).await.unwrap();
}

async fn handle_any(
    State(state): State<Arc<AppState>>,
    axum_req: axum::extract::Request,
) -> impl axum::response::IntoResponse {
    let (parts, body) = axum_req.into_parts();
    let body_bytes: Bytes = to_bytes(body, 50 * 1024 * 1024).await.unwrap_or_default();

    let lambda_body = if body_bytes.is_empty() {
        LambdaBody::Empty
    } else {
        LambdaBody::Binary(body_bytes.to_vec())
    };

    // Build lambda_http-compatible request
    let mut req_builder = Request::builder()
        .method(parts.method.clone())
        .uri(parts.uri.clone());
    for (name, val) in &parts.headers {
        req_builder = req_builder.header(name, val);
    }
    let lambda_req = req_builder.body(lambda_body).unwrap();

    match core_api::http_handler::handle(state, lambda_req).await {
        Ok(resp) => {
            let (rparts, rbody) = resp.into_parts();
            let body_bytes: Vec<u8> = match rbody {
                LambdaBody::Empty     => vec![],
                LambdaBody::Text(s)   => s.into_bytes(),
                LambdaBody::Binary(b) => b,
            };
            let mut builder = Response::builder().status(rparts.status);
            for (name, val) in &rparts.headers {
                builder = builder.header(name, val);
            }
            // CORS headers
            builder = builder
                .header("access-control-allow-origin", "*")
                .header("access-control-allow-headers", "Authorization, Content-Type")
                .header("access-control-allow-methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS");

            builder.body(axum::body::Body::from(body_bytes)).unwrap()
        }
        Err(e) => {
            tracing::error!("handler error: {e:?}");
            Response::builder()
                .status(500)
                .header("content-type", "application/json")
                .header("access-control-allow-origin", "*")
                .body(axum::body::Body::from(
                    format!(r#"{{"error":"internal server error: {e}"}}"#),
                ))
                .unwrap()
        }
    }
}
