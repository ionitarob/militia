use core_api::{AppState, build_pool, fetch_secret_string};
use lambda_http::{run, service_fn, Error};
use std::sync::Arc;

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

    let _ = sqlx::query("DELETE FROM _sqlx_migrations WHERE version IN (20260616000000, 20260616010000)")
        .execute(&pool)
        .await;

    sqlx::migrate!("./migrations")
        .run(&pool)
        .await
        .expect("DB migration failed");

    let jwt_secret_arn = std::env::var("JWT_SECRET_ARN").expect("JWT_SECRET_ARN env var is required");
    let jwt_secret = fetch_secret_string(&sm, &jwt_secret_arn).await?;

    let smtp_user = std::env::var("SMTP_USER").expect("SMTP_USER required");
    let smtp_pass = std::env::var("SMTP_PASS").expect("SMTP_PASS required");
    let s3_bucket = std::env::var("S3_BUCKET").expect("S3_BUCKET required");
    let s3_client = aws_sdk_s3::Client::new(&aws_cfg);
    let bedrock   = aws_sdk_bedrockruntime::Client::new(&aws_cfg);

    let state = Arc::new(AppState { pool, jwt_secret, smtp_user, smtp_pass, s3_client, s3_bucket, bedrock });

    run(service_fn(move |event| {
        let state = Arc::clone(&state);
        async move { core_api::http_handler::handle(state, event).await }
    }))
    .await
}
