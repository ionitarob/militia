use azure_storage::prelude::*;
use lambda_http::{Body, Error, Request, Response};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use time::OffsetDateTime;
use uuid::Uuid;

use crate::{http_handler::ok_json_status, AppState};
use crate::routes::pipeline::require_auth;

#[derive(Serialize)]
struct DocResponse {
    id: i32,
    nombre: String,
    url: String,
    content_type: Option<String>,
    size_bytes: Option<i64>,
    is_manual: bool,
}

#[derive(sqlx::FromRow)]
struct DocRow {
    id: i32,
    nombre: String,
    s3_key: String,
    content_type: Option<String>,
    size_bytes: Option<i64>,
    is_manual: bool,
}

#[derive(Deserialize)]
struct UploadReq {
    nombre: String,
    content_type: String,
    size_bytes: Option<i64>,
}

fn parse_body<T: serde::de::DeserializeOwned>(event: &Request) -> Result<T, String> {
    let raw = match event.body() {
        Body::Text(s) => s.as_bytes().to_vec(),
        Body::Binary(b) => b.clone(),
        Body::Empty => return Err("empty body".to_string()),
    };
    serde_json::from_slice(&raw).map_err(|e| e.to_string())
}

async fn blob_download_url(state: &AppState, blob_key: &str) -> Result<String, String> {
    let blob = state.blob_client
        .container_client(&state.blob_container)
        .blob_client(blob_key);
    let expiry = OffsetDateTime::now_utc() + time::Duration::hours(12);
    let sas = blob.shared_access_signature(
        BlobSasPermissions { read: true, ..Default::default() },
        expiry,
    )
    .await
    .map_err(|e| format!("SAS: {e}"))?;
    blob.generate_signed_blob_url(&sas)
        .map_err(|e| format!("URL: {e}"))
        .map(|u| u.to_string())
}

async fn blob_upload_url(state: &AppState, blob_key: &str) -> Result<String, String> {
    let blob = state.blob_client
        .container_client(&state.blob_container)
        .blob_client(blob_key);
    let expiry = OffsetDateTime::now_utc() + time::Duration::minutes(15);
    let sas = blob.shared_access_signature(
        BlobSasPermissions { write: true, create: true, ..Default::default() },
        expiry,
    )
    .await
    .map_err(|e| format!("SAS: {e}"))?;
    blob.generate_signed_blob_url(&sas)
        .map_err(|e| format!("URL: {e}"))
        .map(|u| u.to_string())
}

pub async fn list(
    state: Arc<AppState>,
    _event: Request,
    licitacion_id: i64,
) -> Result<Response<Body>, Error> {
    let rows = sqlx::query_as::<_, DocRow>(
        r#"SELECT id, nombre, s3_key, content_type, size_bytes, is_manual
           FROM licitacion_documento
           WHERE licitacion_id = $1
           ORDER BY id ASC"#,
    )
    .bind(licitacion_id as i32)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| format!("DB error: {e}"))?;

    let mut docs = Vec::new();
    for row in rows {
        let url = blob_download_url(&state, &row.s3_key)
            .await
            .unwrap_or_default();
        docs.push(DocResponse {
            id: row.id,
            nombre: row.nombre,
            url,
            content_type: row.content_type,
            size_bytes: row.size_bytes,
            is_manual: row.is_manual,
        });
    }

    ok_json_status(200, &serde_json::to_string(&docs).unwrap())
}

pub async fn upload(
    state: Arc<AppState>,
    event: Request,
    licitacion_id: i64,
) -> Result<Response<Body>, Error> {
    let claims = match require_auth(&event, &state.jwt_secret) {
        Ok(c) => c,
        Err(r) => return Ok(r),
    };

    let req = parse_body::<UploadReq>(&event).map_err(|e| format!("bad request: {e}"))?;

    let safe_name = req
        .nombre
        .chars()
        .map(|c| if c.is_alphanumeric() || c == '.' || c == '-' { c } else { '_' })
        .collect::<String>();
    let blob_key = format!(
        "documents/manual/{}/{}_{}",
        licitacion_id,
        Uuid::new_v4().simple(),
        safe_name
    );

    let id: i32 = sqlx::query_scalar(
        r#"INSERT INTO licitacion_documento
               (licitacion_id, nombre, s3_key, content_type, size_bytes, is_manual)
           VALUES ($1, $2, $3, $4, $5, TRUE)
           RETURNING id"#,
    )
    .bind(licitacion_id as i32)
    .bind(&req.nombre)
    .bind(&blob_key)
    .bind(&req.content_type)
    .bind(req.size_bytes)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| format!("DB error: {e}"))?;

    let desc = format!("Documento manual subido: {}", req.nombre);
    let _ = crate::routes::pipeline::log_change(&state.pool, licitacion_id, claims.sub, &desc).await;

    let upload_url = blob_upload_url(&state, &blob_key)
        .await
        .map_err(|e| format!("presign error: {e}"))?;

    ok_json_status(
        201,
        &serde_json::json!({ "id": id, "upload_url": upload_url }).to_string(),
    )
}

pub async fn delete_manual(
    state: Arc<AppState>,
    event: Request,
    licitacion_id: i64,
    doc_id: i64,
) -> Result<Response<Body>, Error> {
    let claims = match require_auth(&event, &state.jwt_secret) {
        Ok(c) => c,
        Err(r) => return Ok(r),
    };

    let row: Option<(String, String)> = sqlx::query_as(
        "SELECT s3_key, nombre FROM licitacion_documento WHERE id = $1 AND licitacion_id = $2 AND is_manual = TRUE",
    )
    .bind(doc_id as i32)
    .bind(licitacion_id as i32)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| format!("DB error: {e}"))?;

    let (blob_key, nombre) = match row {
        Some(r) => r,
        None => return ok_json_status(404, r#"{"error":"not found"}"#),
    };

    let _ = state.blob_client
        .container_client(&state.blob_container)
        .blob_client(&blob_key)
        .delete()
        .await;

    sqlx::query("DELETE FROM licitacion_documento WHERE id = $1")
        .bind(doc_id as i32)
        .execute(&state.pool)
        .await
        .map_err(|e| format!("DB error: {e}"))?;

    let desc = format!("Documento manual eliminado: {}", nombre);
    let _ = crate::routes::pipeline::log_change(&state.pool, licitacion_id, claims.sub, &desc).await;

    ok_json_status(200, r#"{"ok":true}"#)
}
