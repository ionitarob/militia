use lambda_http::{Body, Error, Request, Response};
use serde::Deserialize;
use sqlx::Row;
use std::sync::Arc;

use crate::routes::pipeline::require_auth;
use crate::AppState;

#[derive(Deserialize)]
struct CreateNoteReq {
    content: String,
}

// ── GET /licitaciones/{id}/notes ──────────────────────────────────────────────

pub async fn list(
    state: Arc<AppState>,
    event: Request,
    lic_id: i64,
) -> Result<Response<Body>, Error> {
    require_auth(&event, &state.jwt_secret)
        .map_err(|_| "unauthorized".to_string())?;

    let rows = sqlx::query(
        r#"
        SELECT
            n.id,
            n.user_id,
            u.nombre       AS user_nombre,
            n.content,
            n.created_at::TEXT AS created_at
        FROM licitacion_note n
        JOIN app_user u ON u.id = n.user_id
        WHERE n.licitacion_id = $1
        ORDER BY n.created_at ASC
        "#,
    )
    .bind(lic_id)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| format!("db: {e}"))?;

    let list: Vec<serde_json::Value> = rows
        .iter()
        .map(|r| {
            serde_json::json!({
                "id":           r.get::<i32, _>("id"),
                "user_id":      r.get::<i32, _>("user_id"),
                "user_nombre":  r.try_get::<String, _>("user_nombre").ok(),
                "content":      r.get::<String, _>("content"),
                "created_at":   r.get::<String, _>("created_at"),
            })
        })
        .collect();

    json(200, &serde_json::to_string(&list)?)
}

// ── POST /licitaciones/{id}/notes ─────────────────────────────────────────────

pub async fn create(
    state: Arc<AppState>,
    event: Request,
    lic_id: i64,
) -> Result<Response<Body>, Error> {
    let claims = require_auth(&event, &state.jwt_secret)
        .map_err(|_| "unauthorized".to_string())?;

    let req = parse_body::<CreateNoteReq>(&event)
        .map_err(|e| format!("parse: {e}"))?;

    if req.content.trim().is_empty() {
        return json(400, r#"{"error":"content requerido"}"#);
    }

    let id: i32 = sqlx::query_scalar(
        "INSERT INTO licitacion_note (licitacion_id, user_id, content)
         VALUES ($1, $2, $3) RETURNING id",
    )
    .bind(lic_id)
    .bind(claims.sub)
    .bind(req.content.trim())
    .fetch_one(&state.pool)
    .await
    .map_err(|e| format!("db: {e}"))?;

    json(201, &serde_json::json!({"id": id}).to_string())
}

// ── Helpers ───────────────────────────────────────────────────────────────────

fn parse_body<T: serde::de::DeserializeOwned>(event: &Request) -> Result<T, String> {
    let raw = match event.body() {
        Body::Text(s)   => s.as_bytes().to_vec(),
        Body::Binary(b) => b.clone(),
        Body::Empty     => return Err("empty body".to_string()),
    };
    serde_json::from_slice(&raw).map_err(|e| e.to_string())
}

fn json(status: u16, body: &str) -> Result<Response<Body>, Error> {
    Ok(Response::builder()
        .status(status)
        .header("content-type", "application/json")
        .body(Body::Text(body.to_string()))
        .map_err(Box::new)?)
}
