use chrono::{Duration, Utc};
use jsonwebtoken::{decode, encode, DecodingKey, EncodingKey, Header, Validation};
use lambda_http::{Body, Response};
use serde::{Deserialize, Serialize};

// ── Token claims ──────────────────────────────────────────────────────────────

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Claims {
    pub sub: i32,        // user id
    pub email: String,
    pub role: String,    // "admin" | "ventas"
    pub exp: i64,        // unix timestamp
    pub iat: i64,
}

// ── Token types ───────────────────────────────────────────────────────────────

pub const ACCESS_TTL_HOURS: i64 = 8;
pub const REFRESH_TTL_DAYS: i64 = 30;

pub fn issue_access(user_id: i32, email: &str, role: &str, secret: &str) -> String {
    let now = Utc::now();
    let claims = Claims {
        sub: user_id,
        email: email.to_string(),
        role: role.to_string(),
        iat: now.timestamp(),
        exp: (now + Duration::hours(ACCESS_TTL_HOURS)).timestamp(),
    };
    encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(secret.as_bytes()),
    )
    .expect("JWT encode failed")
}

pub fn issue_refresh(user_id: i32, email: &str, role: &str, secret: &str) -> String {
    let now = Utc::now();
    let claims = Claims {
        sub: user_id,
        email: email.to_string(),
        role: role.to_string(),
        iat: now.timestamp(),
        exp: (now + Duration::days(REFRESH_TTL_DAYS)).timestamp(),
    };
    encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(secret.as_bytes()),
    )
    .expect("JWT encode failed")
}

pub fn verify(token: &str, secret: &str) -> Result<Claims, jsonwebtoken::errors::Error> {
    let data = decode::<Claims>(
        token,
        &DecodingKey::from_secret(secret.as_bytes()),
        &Validation::default(),
    )?;
    Ok(data.claims)
}

// ── Bearer extractor ──────────────────────────────────────────────────────────

pub fn bearer_from_request(req: &lambda_http::Request) -> Option<String> {
    req.headers()
        .get("authorization")
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.strip_prefix("Bearer "))
        .map(|s| s.to_string())
}

// ── Shared JSON error helper ──────────────────────────────────────────────────

pub fn unauthorized(msg: &str) -> Response<Body> {
    Response::builder()
        .status(401)
        .header("content-type", "application/json")
        .body(Body::Text(
            serde_json::json!({"error": msg}).to_string(),
        ))
        .unwrap()
}
