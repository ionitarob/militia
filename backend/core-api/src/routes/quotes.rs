use lambda_http::{Body, Error, Request, Response};
use serde::Deserialize;
use sqlx::Row;
use std::sync::Arc;

use crate::routes::pipeline::require_auth;
use crate::AppState;

#[derive(Deserialize)]
struct CreateQuoteReq {
    reseller_name: String,
    date_sent:     Option<String>,
    amount:        Option<f64>,
    status:        Option<String>,
    notes:         Option<String>,
}

#[derive(Deserialize)]
struct UpdateQuoteReq {
    reseller_name: Option<String>,
    date_sent:     Option<String>,
    amount:        Option<f64>,
    status:        Option<String>,
    notes:         Option<String>,
}

// ── GET /licitaciones/{id}/quotes ─────────────────────────────────────────────

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
            q.id,
            q.licitacion_id,
            q.vendedor_id,
            u.nombre        AS vendedor_nombre,
            q.reseller_name,
            q.date_sent::TEXT AS date_sent,
            q.amount::FLOAT8  AS amount,
            q.status::TEXT    AS status,
            q.notes,
            q.created_at::TEXT AS created_at
        FROM licitacion_quote q
        JOIN app_user u ON u.id = q.vendedor_id
        WHERE q.licitacion_id = $1
        ORDER BY q.created_at DESC
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
                "id":              r.get::<i32, _>("id"),
                "licitacion_id":   r.get::<i64, _>("licitacion_id"),
                "vendedor_id":     r.get::<i32, _>("vendedor_id"),
                "vendedor_nombre": r.try_get::<String, _>("vendedor_nombre").ok(),
                "reseller_name":   r.get::<String, _>("reseller_name"),
                "date_sent":       r.try_get::<String, _>("date_sent").ok(),
                "amount":          r.try_get::<f64, _>("amount").ok(),
                "status":          r.try_get::<String, _>("status").unwrap_or_default(),
                "notes":           r.try_get::<String, _>("notes").ok(),
                "created_at":      r.get::<String, _>("created_at"),
            })
        })
        .collect();

    json(200, &serde_json::to_string(&list)?)
}

// ── POST /licitaciones/{id}/quotes ────────────────────────────────────────────

pub async fn create(
    state: Arc<AppState>,
    event: Request,
    lic_id: i64,
) -> Result<Response<Body>, Error> {
    let claims = require_auth(&event, &state.jwt_secret)
        .map_err(|_| "unauthorized".to_string())?;

    let req = parse_body::<CreateQuoteReq>(&event)
        .map_err(|e| format!("parse: {e}"))?;

    let status = req.status.as_deref().unwrap_or("pendiente");

    let id: i32 = sqlx::query_scalar(
        r#"
        INSERT INTO licitacion_quote
          (licitacion_id, vendedor_id, reseller_name, date_sent, amount, status, notes)
        VALUES ($1, $2, $3, $4::DATE, $5, $6::quote_status, $7)
        RETURNING id
        "#,
    )
    .bind(lic_id)
    .bind(claims.sub)
    .bind(&req.reseller_name)
    .bind(req.date_sent.as_deref())
    .bind(req.amount)
    .bind(status)
    .bind(req.notes.as_deref())
    .fetch_one(&state.pool)
    .await
    .map_err(|e| format!("db: {e}"))?;

    let desc = format!(
        "Nueva cotización de distribuidor creada para {}: {}",
        req.reseller_name,
        status
    );
    let _ = crate::routes::pipeline::log_change(&state.pool, lic_id, claims.sub, &desc).await;

    json(201, &serde_json::json!({"id": id}).to_string())
}

// ── PATCH /licitaciones/{id}/quotes/{qid} ────────────────────────────────────

pub async fn update(
    state: Arc<AppState>,
    event: Request,
    lic_id: i64,
    quote_id: i32,
) -> Result<Response<Body>, Error> {
    let claims = require_auth(&event, &state.jwt_secret)
        .map_err(|_| "unauthorized".to_string())?;

    let req = parse_body::<UpdateQuoteReq>(&event)
        .map_err(|e| format!("parse: {e}"))?;

    let old_info: Option<(String, String)> = sqlx::query_as(
        "SELECT reseller_name, status::text FROM licitacion_quote WHERE id = $1"
    )
    .bind(quote_id)
    .fetch_optional(&state.pool)
    .await
    .unwrap_or(None);

    if let Some(name) = &req.reseller_name {
        sqlx::query("UPDATE licitacion_quote SET reseller_name = $1, updated_at = NOW() WHERE id = $2")
            .bind(name)
            .bind(quote_id)
            .execute(&state.pool)
            .await
            .map_err(|e| format!("db: {e}"))?;
    }
    if let Some(d) = &req.date_sent {
        sqlx::query("UPDATE licitacion_quote SET date_sent = $1::DATE, updated_at = NOW() WHERE id = $2")
            .bind(d)
            .bind(quote_id)
            .execute(&state.pool)
            .await
            .map_err(|e| format!("db: {e}"))?;
    }
    if let Some(a) = req.amount {
        sqlx::query("UPDATE licitacion_quote SET amount = $1, updated_at = NOW() WHERE id = $2")
            .bind(a)
            .bind(quote_id)
            .execute(&state.pool)
            .await
            .map_err(|e| format!("db: {e}"))?;
    }
    if let Some(s) = &req.status {
        sqlx::query(&format!(
            "UPDATE licitacion_quote SET status = '{}'::quote_status, updated_at = NOW() WHERE id = $1",
            s.replace('\'', "")
        ))
        .bind(quote_id)
        .execute(&state.pool)
        .await
        .map_err(|e| format!("db: {e}"))?;
    }
    if let Some(n) = &req.notes {
        sqlx::query("UPDATE licitacion_quote SET notes = $1, updated_at = NOW() WHERE id = $2")
            .bind(n)
            .bind(quote_id)
            .execute(&state.pool)
            .await
            .map_err(|e| format!("db: {e}"))?;
    }

    if let Some((reseller, old_status)) = old_info {
        let mut changes = Vec::new();
        if let Some(name) = &req.reseller_name {
            if name != &reseller {
                changes.push(format!("nombre: {} -> {}", reseller, name));
            }
        }
        if let Some(s) = &req.status {
            if s != &old_status {
                changes.push(format!("estado: {} -> {}", old_status, s));
            }
        }
        if let Some(a) = req.amount {
            changes.push(format!("importe: {}", a));
        }
        if req.notes.is_some() {
            changes.push("notas actualizadas".to_string());
        }

        if !changes.is_empty() {
            let desc = format!(
                "Cotización de distribuidor ({}) modificada: {}",
                reseller,
                changes.join(", ")
            );
            let _ = crate::routes::pipeline::log_change(&state.pool, lic_id, claims.sub, &desc).await;
        }
    }

    json(200, r#"{"ok":true}"#)
}

// ── DELETE /licitaciones/{id}/quotes/{qid} ───────────────────────────────────

pub async fn delete(
    state: Arc<AppState>,
    event: Request,
    lic_id: i64,
    quote_id: i32,
) -> Result<Response<Body>, Error> {
    let claims = require_auth(&event, &state.jwt_secret)
        .map_err(|_| "unauthorized".to_string())?;

    let reseller_name: Option<String> = sqlx::query_scalar(
        "SELECT reseller_name FROM licitacion_quote WHERE id = $1"
    )
    .bind(quote_id)
    .fetch_optional(&state.pool)
    .await
    .unwrap_or(None);

    sqlx::query("DELETE FROM licitacion_quote WHERE id = $1")
        .bind(quote_id)
        .execute(&state.pool)
        .await
        .map_err(|e| format!("db: {e}"))?;

    let desc = format!(
        "Cotización de distribuidor eliminada: {}",
        reseller_name.as_deref().unwrap_or("")
    );
    let _ = crate::routes::pipeline::log_change(&state.pool, lic_id, claims.sub, &desc).await;

    json(200, r#"{"ok":true}"#)
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
