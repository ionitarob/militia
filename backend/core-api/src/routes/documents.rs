use aws_sdk_s3::presigning::PresigningConfig;
use lambda_http::{Body, Error, Request, Response};
use serde::Serialize;
use std::sync::Arc;
use std::time::Duration;

use crate::{http_handler::ok_json_status, AppState};

#[derive(Serialize)]
struct DocResponse {
    id: i32,
    nombre: String,
    url: String,
    content_type: Option<String>,
    size_bytes: Option<i64>,
}

#[derive(sqlx::FromRow)]
struct DocRow {
    id: i32,
    nombre: String,
    s3_key: String,
    content_type: Option<String>,
    size_bytes: Option<i64>,
}

pub async fn list(
    state: Arc<AppState>,
    _event: Request,
    licitacion_id: i64,
) -> Result<Response<Body>, Error> {
    let rows = sqlx::query_as::<_, DocRow>(
        r#"SELECT id, nombre, s3_key, content_type, size_bytes
           FROM licitacion_documento
           WHERE licitacion_id = $1
           ORDER BY id ASC"#,
    )
    .bind(licitacion_id as i32)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| format!("DB error: {e}"))?;

    let presign_cfg = PresigningConfig::expires_in(Duration::from_secs(3600))
        .map_err(|e| format!("presign config: {e}"))?;

    let mut docs = Vec::new();
    for row in rows {
        let presigned = state
            .s3_client
            .get_object()
            .bucket(&state.s3_bucket)
            .key(&row.s3_key)
            .presigned(presign_cfg.clone())
            .await
            .map_err(|e| format!("presign error: {e}"))?;

        docs.push(DocResponse {
            id: row.id,
            nombre: row.nombre,
            url: presigned.uri().to_string(),
            content_type: row.content_type,
            size_bytes: row.size_bytes,
        });
    }

    ok_json_status(200, &serde_json::to_string(&docs).unwrap())
}
