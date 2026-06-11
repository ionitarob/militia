use bcrypt::verify as bcrypt_verify;
use lambda_http::{Body, Error, Request, Response};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use std::sync::Arc;

use crate::{auth, AppState};

// ── POST /auth/login ──────────────────────────────────────────────────────────

#[derive(Deserialize)]
struct LoginRequest {
    email: String,
    password: String,
}

#[derive(Serialize)]
struct LoginResponse {
    access_token: String,
    refresh_token: String,
    user: UserDto,
}

#[derive(Serialize)]
struct UserDto {
    id: i32,
    email: String,
    role: String,
    nombre: Option<String>,
}

pub async fn login(state: Arc<AppState>, event: Request) -> Result<Response<Body>, Error> {
    let raw = match event.body() {
        Body::Text(s) => s.as_bytes().to_vec(),
        Body::Binary(b) => b.clone(),
        Body::Empty => return json(400, r#"{"error":"empty body"}"#),
    };

    let req: LoginRequest = match serde_json::from_slice(&raw) {
        Ok(r) => r,
        Err(e) => return json(400, &serde_json::json!({"error": e.to_string()}).to_string()),
    };

    let email = req.email.to_lowercase();
    let email = email.trim();

    let row = sqlx::query(
        "SELECT id, email, password_hash, role::TEXT AS role, nombre \
         FROM app_user WHERE LOWER(email) = $1",
    )
    .bind(email)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| format!("db error: {e}"))?;

    let row = match row {
        Some(r) => r,
        None => return json(401, r#"{"error":"Credenciales incorrectas"}"#),
    };

    let id: i32          = row.get("id");
    let db_email: String = row.get("email");
    let hash: String     = row.get("password_hash");
    let role: String     = row.try_get("role").unwrap_or_default();
    let nombre: Option<String> = row.try_get("nombre").ok().flatten();

    if !bcrypt_verify(&req.password, &hash).unwrap_or(false) {
        return json(401, r#"{"error":"Credenciales incorrectas"}"#);
    }

    let _ = sqlx::query("UPDATE app_user SET last_login = NOW() WHERE id = $1")
        .bind(id)
        .execute(&state.pool)
        .await;

    let access  = auth::issue_access(id, &db_email, &role, &state.jwt_secret);
    let refresh = auth::issue_refresh(id, &db_email, &role, &state.jwt_secret);

    json(200, &serde_json::to_string(&LoginResponse {
        access_token: access,
        refresh_token: refresh,
        user: UserDto { id, email: db_email, role, nombre },
    })?)
}

// ── POST /auth/refresh ────────────────────────────────────────────────────────

#[derive(Deserialize)]
struct RefreshRequest {
    refresh_token: String,
}

pub async fn refresh(state: Arc<AppState>, event: Request) -> Result<Response<Body>, Error> {
    let raw = match event.body() {
        Body::Text(s) => s.as_bytes().to_vec(),
        Body::Binary(b) => b.clone(),
        Body::Empty => return json(400, r#"{"error":"empty body"}"#),
    };

    let req: RefreshRequest = match serde_json::from_slice(&raw) {
        Ok(r) => r,
        Err(_) => return json(400, r#"{"error":"invalid body"}"#),
    };

    let claims = match auth::verify(&req.refresh_token, &state.jwt_secret) {
        Ok(c) => c,
        Err(_) => return json(401, r#"{"error":"Token inválido o expirado"}"#),
    };

    let access = auth::issue_access(claims.sub, &claims.email, &claims.role, &state.jwt_secret);
    json(200, &serde_json::json!({"access_token": access}).to_string())
}

// ── GET /auth/me ──────────────────────────────────────────────────────────────

pub async fn me(state: Arc<AppState>, event: Request) -> Result<Response<Body>, Error> {
    let token = match auth::bearer_from_request(&event) {
        Some(t) => t,
        None => return Ok(auth::unauthorized("No token provided")),
    };

    let claims = match auth::verify(&token, &state.jwt_secret) {
        Ok(c) => c,
        Err(_) => return Ok(auth::unauthorized("Token inválido o expirado")),
    };

    let row = sqlx::query(
        "SELECT id, email, role::TEXT AS role, nombre FROM app_user WHERE id = $1",
    )
    .bind(claims.sub)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| format!("db error: {e}"))?;

    match row {
        Some(r) => {
            let role: String = r.try_get("role").unwrap_or_default();
            let nombre: Option<String> = r.try_get("nombre").ok().flatten();
            json(200, &serde_json::json!({
                "id":     r.get::<i32, _>("id"),
                "email":  r.get::<String, _>("email"),
                "role":   role,
                "nombre": nombre,
            }).to_string())
        }
        None => json(404, r#"{"error":"Usuario no encontrado"}"#),
    }
}

fn json(status: u16, body: &str) -> Result<Response<Body>, Error> {
    Ok(Response::builder()
        .status(status)
        .header("content-type", "application/json")
        .body(Body::Text(body.to_string()))
        .map_err(Box::new)?)
}
