use sqlx::PgPool;
use lambda_http::Error;

pub mod auth;
pub mod http_handler;
pub mod routes;

pub struct AppState {
    pub pool: PgPool,
    pub jwt_secret: String,
    pub smtp_user: String,
    pub smtp_pass: String,
    pub s3_client: aws_sdk_s3::Client,
    pub s3_bucket: String,
    pub bedrock: aws_sdk_bedrockruntime::Client,
}

pub async fn build_pool(sm: &aws_sdk_secretsmanager::Client) -> Result<PgPool, Error> {
    let secret_arn = std::env::var("DB_SECRET_ARN").expect("DB_SECRET_ARN env var is required");
    let raw = fetch_secret_string(sm, &secret_arn).await?;
    let creds: serde_json::Value = serde_json::from_str(&raw).expect("DB secret is not valid JSON");
    let url = format!(
        "postgresql://{}:{}@{}:{}/{}",
        creds["username"].as_str().unwrap_or("postgres"),
        creds["password"].as_str().unwrap_or(""),
        creds["host"].as_str().unwrap_or("localhost"),
        creds["port"].as_u64().unwrap_or(5432),
        creds["dbname"].as_str().unwrap_or("imliti"),
    );
    let pool = PgPool::connect(&url).await.expect("Failed to connect to PostgreSQL");
    Ok(pool)
}

pub async fn fetch_secret_string(
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
