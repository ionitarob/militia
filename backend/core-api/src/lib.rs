use sqlx::PgPool;
use azure_storage_blobs::prelude::BlobServiceClient;
use lambda_http::Error;

pub mod auth;
pub mod http_handler;
pub mod routes;

pub struct AppState {
    pub pool: PgPool,
    pub jwt_secret: String,
    pub smtp_user: String,
    pub smtp_pass: String,
    /// Azure Blob Storage service client (replaces aws_sdk_s3::Client)
    pub blob_client: BlobServiceClient,
    pub blob_container: String,
    /// reqwest client for Azure OpenAI API and scraper HTTP calls
    pub http_client: reqwest::Client,
    pub azure_openai_key: String,
    pub azure_openai_endpoint: String,
    /// HTTP URL of the scraper_fetch service (replaces Lambda ARN)
    pub scraper_fetch_url: Option<String>,
}

pub async fn build_pool(db_url: &str) -> Result<PgPool, Error> {
    let pool = PgPool::connect(db_url)
        .await
        .map_err(|e| format!("DB connect failed: {e}"))?;
    Ok(pool)
}

pub fn build_blob_client(account: &str, key: &str) -> BlobServiceClient {
    let credentials = azure_storage::StorageCredentials::access_key(account.to_string(), key.to_string());
    BlobServiceClient::new(account, credentials)
}
