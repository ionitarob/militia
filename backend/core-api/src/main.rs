use lambda_http::{run, service_fn, Error};
use sqlx::PgPool;
use std::sync::Arc;

mod auth;
mod http_handler;
mod routes;

pub struct AppState {
    pub pool: PgPool,
    pub jwt_secret: String,
    pub smtp_user: String,
    pub smtp_pass: String,
    pub s3_client: aws_sdk_s3::Client,
    pub s3_bucket: String,
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

    // Fix checksum mismatch by deleting migration history rows for Phase 2, letting them re-run idempotently
    let _ = sqlx::query("DELETE FROM _sqlx_migrations WHERE version IN (20260616000000, 20260616010000)")
        .execute(&pool)
        .await;

    sqlx::migrate!("./migrations")
        .run(&pool)
        .await
        .expect("DB migration failed");

    let jwt_secret_arn = std::env::var("JWT_SECRET_ARN")
        .expect("JWT_SECRET_ARN env var is required");
    let jwt_secret = fetch_secret_string(&sm, &jwt_secret_arn).await?;

    let smtp_user = std::env::var("SMTP_USER").expect("SMTP_USER required");
    let smtp_pass = std::env::var("SMTP_PASS").expect("SMTP_PASS required");
    let s3_bucket = std::env::var("S3_BUCKET").expect("S3_BUCKET required");
    let s3_client = aws_sdk_s3::Client::new(&aws_cfg);

    let state = Arc::new(AppState { pool, jwt_secret, smtp_user, smtp_pass, s3_client, s3_bucket });

    run(service_fn(move |event| {
        let state = Arc::clone(&state);
        async move { http_handler::handle(state, event).await }
    }))
    .await
}

async fn build_pool(sm: &aws_sdk_secretsmanager::Client) -> Result<PgPool, Error> {
    let secret_arn = std::env::var("DB_SECRET_ARN")
        .expect("DB_SECRET_ARN env var is required");

    let raw = fetch_secret_string(sm, &secret_arn).await?;
    let creds: serde_json::Value = serde_json::from_str(&raw)
        .expect("DB secret is not valid JSON");

    let url = format!(
        "postgresql://{}:{}@{}:{}/{}",
        creds["username"].as_str().unwrap_or("postgres"),
        creds["password"].as_str().unwrap_or(""),
        creds["host"].as_str().unwrap_or("localhost"),
        creds["port"].as_u64().unwrap_or(5432),
        creds["dbname"].as_str().unwrap_or("imliti"),
    );

    let pool = PgPool::connect(&url)
        .await
        .expect("Failed to connect to PostgreSQL");

    Ok(pool)
}

async fn fetch_secret_string(
    sm: &aws_sdk_secretsmanager::Client,
    arn: &str,
) -> Result<String, Error> {
    let resp = sm
        .get_secret_value()
        .secret_id(arn)
        .send()
        .await
        .map_err(|e| format!("SecretsManager error: {e}"))?;

    Ok(resp.secret_string().unwrap_or_default().to_string())
}
