use lambda_http::{Body, Error, Request, Response};
use serde::Serialize;
use sqlx::Row;
use std::sync::Arc;

use crate::{auth, AppState};

#[derive(Serialize)]
struct UserDto {
    id:     i32,
    email:  String,
    role:   String,
    nombre: Option<String>,
}

// ── GET /users  (admin only) ───────────────────────────────────────────────────

pub async fn list(state: Arc<AppState>, event: Request) -> Result<Response<Body>, Error> {
    let token = match auth::bearer_from_request(&event) {
        Some(t) => t,
        None    => return Ok(auth::unauthorized("Autenticación requerida")),
    };
    let claims = match auth::verify(&token, &state.jwt_secret) {
        Ok(c)  => c,
        Err(_) => return Ok(auth::unauthorized("Token inválido")),
    };
    if claims.role != "admin" {
        return Ok(auth::unauthorized("Solo administradores"));
    }

    let rows = sqlx::query(
        "SELECT id, email, role::TEXT AS role, nombre FROM app_user ORDER BY nombre",
    )
    .fetch_all(&state.pool)
    .await
    .map_err(|e| format!("db: {e}"))?;

    let users: Vec<UserDto> = rows
        .iter()
        .map(|r| UserDto {
            id:     r.get("id"),
            email:  r.get("email"),
            role:   r.try_get("role").unwrap_or_default(),
            nombre: r.try_get("nombre").ok().flatten(),
        })
        .collect();

    json(200, &serde_json::to_string(&users)?)
}

fn json(status: u16, body: &str) -> Result<Response<Body>, Error> {
    Ok(Response::builder()
        .status(status)
        .header("content-type", "application/json")
        .body(Body::Text(body.to_string()))
        .map_err(Box::new)?)
}
