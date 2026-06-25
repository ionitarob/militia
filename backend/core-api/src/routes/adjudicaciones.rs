use std::sync::Arc;
use lambda_http::{Body, Error, Request, RequestExt, Response};
use serde::Serialize;

use crate::AppState;
use crate::routes::pipeline::require_auth;

// ── Shared DTOs ───────────────────────────────────────────────────────────────

#[derive(Serialize)]
struct CotizacionDto {
    cliente_nombre: String,
    cotizacion_xv: Option<String>,
    oportunidad: Option<String>,
    cotizacion_id: Option<String>,
    oportunidad_id: Option<String>,
    estado: Option<String>,
    divisiones: Vec<String>,
    fabricante_proteccion: bool,
    fabricante_nombre: Option<String>,
    se_presenta: bool,
    user_id: Option<i64>,
    va_con_pliego: Option<bool>,
}

async fn fetch_cotizaciones(pool: &sqlx::PgPool, licitacion_id: i64) -> Vec<CotizacionDto> {
    let rows = sqlx::query(
        r#"SELECT cliente_nombre, cotizacion_xv, oportunidad, cotizacion_id, oportunidad_id,
                  estado, divisiones, fabricante_proteccion, fabricante_nombre,
                  se_presenta, user_id, va_con_pliego
           FROM licitacion_cotizacion
           WHERE licitacion_id = $1
           ORDER BY cliente_nombre, user_id NULLS FIRST"#,
    )
    .bind(licitacion_id)
    .fetch_all(pool)
    .await
    .unwrap_or_default();

    rows.iter().map(|r| {
        use sqlx::Row;
        CotizacionDto {
            cliente_nombre:        r.get("cliente_nombre"),
            cotizacion_xv:         r.try_get("cotizacion_xv").ok().flatten(),
            oportunidad:           r.try_get("oportunidad").ok().flatten(),
            cotizacion_id:         r.try_get("cotizacion_id").ok().flatten(),
            oportunidad_id:        r.try_get("oportunidad_id").ok().flatten(),
            estado:                r.try_get("estado").ok().flatten(),
            divisiones:            r.try_get::<Vec<String>, _>("divisiones").unwrap_or_default(),
            fabricante_proteccion: r.try_get("fabricante_proteccion").ok().unwrap_or(false),
            fabricante_nombre:     r.try_get("fabricante_nombre").ok().flatten(),
            se_presenta:           r.try_get("se_presenta").ok().unwrap_or(false),
            user_id:               r.try_get("user_id").ok().flatten(),
            va_con_pliego:         r.try_get("va_con_pliego").ok().flatten(),
        }
    }).collect()
}

#[derive(sqlx::FromRow)]
struct AdjudicacionRow {
    pub id: i64,
    pub external_id: Option<String>,
    pub titulo: String,
    pub numero_expediente: String,
    pub fecha_adjudicacion: Option<chrono::NaiveDate>,
    pub importe: Option<f64>,
    pub importe_adjudicado: Option<f64>,
    pub valor_estimado: Option<f64>,
    pub ratio_adjudicacion_vs_licitacion: Option<f64>,
    pub comunidad_autonoma: Option<String>,
    pub mercado_vertical: Option<String>,
    pub tipo_procedimiento: Option<String>,
    pub duracion_meses: Option<i16>,
    pub organismo_nombre: Option<String>,
    pub adjudicatario_nombre: Option<String>,
    pub licitacion_id: Option<i64>,
    pub created_at: chrono::DateTime<chrono::Utc>,
}

#[derive(sqlx::FromRow)]
struct AdjudicacionDetailRow {
    pub id: i64,
    pub external_id: Option<String>,
    pub titulo: String,
    pub numero_expediente: String,
    pub fecha_adjudicacion: Option<chrono::NaiveDate>,
    pub fecha_vencimiento_contrato: Option<chrono::NaiveDate>,
    pub importe: Option<f64>,
    pub importe_adjudicado: Option<f64>,
    pub valor_estimado: Option<f64>,
    pub ratio_adjudicacion_vs_licitacion: Option<f64>,
    pub tipo_procedimiento: Option<String>,
    pub tipo_tramitacion: Option<String>,
    pub duracion_meses: Option<i16>,
    pub prorrogas_meses: Option<i16>,
    pub puntos_precio: Option<i16>,
    pub puntos_mejoras: Option<i16>,
    pub puntos_subjetivos: Option<i16>,
    pub comunidad_autonoma: Option<String>,
    pub provincia: Option<String>,
    pub ambito_geografico: Option<String>,
    pub mercado_vertical: Option<String>,
    pub organismo_nombre: Option<String>,
    pub adjudicatario_nombre: Option<String>,
    pub licitacion_id: Option<i64>,
    pub created_at: chrono::DateTime<chrono::Utc>,
}

const LIST_SQL: &str = r#"
SELECT
    a.id,
    a.external_id,
    a.titulo,
    a.numero_expediente,
    a.fecha_adjudicacion,
    a.importe::FLOAT8                              AS importe,
    a.importe_adjudicado::FLOAT8                   AS importe_adjudicado,
    a.valor_estimado::FLOAT8                       AS valor_estimado,
    a.ratio_adjudicacion_vs_licitacion::FLOAT8     AS ratio_adjudicacion_vs_licitacion,
    a.comunidad_autonoma::TEXT                     AS comunidad_autonoma,
    a.mercado_vertical::TEXT                       AS mercado_vertical,
    a.tipo_procedimiento::TEXT                     AS tipo_procedimiento,
    a.duracion_meses,
    o.nombre                                       AS organismo_nombre,
    adj.nombre                                     AS adjudicatario_nombre,
    a.licitacion_id,
    a.created_at
FROM adjudicacion a
LEFT JOIN organismo     o   ON o.id   = a.organismo_id
LEFT JOIN adjudicatario adj ON adj.id = a.adjudicatario_id
WHERE TRUE
  AND ($3::TEXT IS NULL OR a.fecha_adjudicacion >= CURRENT_DATE - ($3::INT || ' days')::INTERVAL)
  AND ($4::TEXT IS NULL OR a.mercado_vertical::TEXT = $4)
ORDER BY a.fecha_adjudicacion DESC NULLS LAST, a.id DESC
LIMIT $1 OFFSET $2
"#;

const COUNT_SQL: &str = r#"
SELECT COUNT(*)::BIGINT
FROM adjudicacion a
WHERE TRUE
  AND ($1::TEXT IS NULL OR a.fecha_adjudicacion >= CURRENT_DATE - ($1::INT || ' days')::INTERVAL)
  AND ($2::TEXT IS NULL OR a.mercado_vertical::TEXT = $2)
"#;

pub async fn list(
    state: Arc<AppState>,
    event: Request,
) -> Result<Response<Body>, Error> {
    match require_auth(&event, &state.jwt_secret) {
        Ok(_) => {}
        Err(r) => return Ok(r),
    };

    let params = event.query_string_parameters();

    let page: i64     = params.first("page").and_then(|v| v.parse::<i64>().ok()).unwrap_or(1).max(1);
    let per_page: i64 = params.first("per_page").and_then(|v| v.parse::<i64>().ok()).unwrap_or(25).min(100);
    let offset        = (page - 1) * per_page;

    let recientes = params.first("recientes").map(|s: &str| s.to_string());
    let mercado   = params.first("mercado").map(|s: &str| s.to_string());

    let rows = sqlx::query_as::<_, AdjudicacionRow>(LIST_SQL)
        .bind(per_page)
        .bind(offset)
        .bind(recientes.as_deref())
        .bind(mercado.as_deref())
        .fetch_all(&state.pool)
        .await
        .map_err(|e| format!("adjudicaciones list: {e}"))?;

    let total: i64 = sqlx::query_scalar::<_, i64>(COUNT_SQL)
        .bind(recientes.as_deref())
        .bind(mercado.as_deref())
        .fetch_one(&state.pool)
        .await
        .map_err(|e| format!("adjudicaciones count: {e}"))?;

    let data: Vec<serde_json::Value> = rows.iter().map(|r| serde_json::json!({
        "id":                               r.id,
        "external_id":                      r.external_id,
        "titulo":                           r.titulo,
        "numero_expediente":                r.numero_expediente,
        "fecha_adjudicacion":               r.fecha_adjudicacion.map(|d| d.to_string()),
        "importe":                          r.importe,
        "importe_adjudicado":               r.importe_adjudicado,
        "valor_estimado":                   r.valor_estimado,
        "ratio_adjudicacion_vs_licitacion": r.ratio_adjudicacion_vs_licitacion,
        "comunidad_autonoma":               r.comunidad_autonoma,
        "mercado_vertical":                 r.mercado_vertical,
        "tipo_procedimiento":               r.tipo_procedimiento,
        "duracion_meses":                   r.duracion_meses,
        "organismo_nombre":                 r.organismo_nombre,
        "adjudicatario_nombre":             r.adjudicatario_nombre,
        "licitacion_id":                    r.licitacion_id,
        "created_at":                       r.created_at.to_rfc3339(),
    })).collect();

    json(200, &serde_json::to_string(&serde_json::json!({
        "data":     data,
        "total":    total,
        "page":     page,
        "per_page": per_page,
    }))?)
}

pub async fn get(
    state: Arc<AppState>,
    event: Request,
    adj_id: i64,
) -> Result<Response<Body>, Error> {
    match require_auth(&event, &state.jwt_secret) {
        Ok(_) => {}
        Err(r) => return Ok(r),
    };

    let row = sqlx::query_as::<_, AdjudicacionDetailRow>(r#"
        SELECT
            a.id,
            a.external_id,
            a.titulo,
            a.numero_expediente,
            a.fecha_adjudicacion,
            a.fecha_vencimiento_contrato,
            a.importe::FLOAT8                              AS importe,
            a.importe_adjudicado::FLOAT8                   AS importe_adjudicado,
            a.valor_estimado::FLOAT8                       AS valor_estimado,
            a.ratio_adjudicacion_vs_licitacion::FLOAT8     AS ratio_adjudicacion_vs_licitacion,
            a.tipo_procedimiento::TEXT                     AS tipo_procedimiento,
            a.tipo_tramitacion,
            a.duracion_meses,
            a.prorrogas_meses,
            a.puntos_precio,
            a.puntos_mejoras,
            a.puntos_subjetivos,
            a.comunidad_autonoma::TEXT                     AS comunidad_autonoma,
            a.provincia,
            a.ambito_geografico::TEXT                      AS ambito_geografico,
            a.mercado_vertical::TEXT                       AS mercado_vertical,
            o.nombre                                       AS organismo_nombre,
            adj.nombre                                     AS adjudicatario_nombre,
            a.licitacion_id,
            a.created_at
        FROM adjudicacion a
        LEFT JOIN organismo     o   ON o.id   = a.organismo_id
        LEFT JOIN adjudicatario adj ON adj.id = a.adjudicatario_id
        WHERE a.id = $1
    "#)
        .bind(adj_id)
        .fetch_optional(&state.pool)
        .await
        .map_err(|e| format!("adjudicacion get: {e}"))?;

    let r = match row {
        Some(r) => r,
        None => return json(404, r#"{"error":"not found"}"#),
    };

    let cpv_rows: Vec<(String, Option<String>)> = sqlx::query_as(
        "SELECT ac.cpv_code, c.descripcion FROM adjudicacion_cpv ac LEFT JOIN cpv_code c ON c.code = ac.cpv_code WHERE ac.adjudicacion_id = $1 ORDER BY ac.cpv_code"
    )
        .bind(adj_id)
        .fetch_all(&state.pool)
        .await
        .unwrap_or_default();

    let cpv_label = cpv_rows.iter().map(|(code, desc)| {
        match desc.as_deref().filter(|d| *d != code) {
            Some(d) => format!("{code} – {d}"),
            None => code.clone(),
        }
    }).collect::<Vec<_>>().join(", ");

    let cotizaciones = if let Some(lid) = r.licitacion_id {
        fetch_cotizaciones(&state.pool, lid).await
    } else {
        vec![]
    };

    let data = serde_json::json!({
        "id":                               r.id,
        "external_id":                      r.external_id,
        "titulo":                           r.titulo,
        "numero_expediente":                r.numero_expediente,
        "fecha_adjudicacion":               r.fecha_adjudicacion.map(|d| d.to_string()),
        "fecha_vencimiento_contrato":       r.fecha_vencimiento_contrato.map(|d| d.to_string()),
        "importe":                          r.importe,
        "importe_adjudicado":               r.importe_adjudicado,
        "valor_estimado":                   r.valor_estimado,
        "ratio_adjudicacion_vs_licitacion": r.ratio_adjudicacion_vs_licitacion,
        "tipo_procedimiento":               r.tipo_procedimiento,
        "tipo_tramitacion":                 r.tipo_tramitacion,
        "duracion_meses":                   r.duracion_meses,
        "prorrogas_meses":                  r.prorrogas_meses,
        "puntos_precio":                    r.puntos_precio,
        "puntos_mejoras":                   r.puntos_mejoras,
        "puntos_subjetivos":                r.puntos_subjetivos,
        "comunidad_autonoma":               r.comunidad_autonoma,
        "provincia":                        r.provincia,
        "ambito_geografico":                r.ambito_geografico,
        "mercado_vertical":                 r.mercado_vertical,
        "organismo_nombre":                 r.organismo_nombre,
        "adjudicatario_nombre":             r.adjudicatario_nombre,
        "licitacion_id":                    r.licitacion_id,
        "cpv_label":                        if cpv_label.is_empty() { None } else { Some(cpv_label) },
        "cotizaciones":                     cotizaciones,
        "created_at":                       r.created_at.to_rfc3339(),
    });

    json(200, &serde_json::to_string(&data)?)
}

// ── GET /me/adjudicaciones ───────────────────────────────────────────────────
// Returns adjudicaciones where the authenticated user has a cotizacion on the
// linked licitacion (i.e. they worked on it as a comercial).

pub async fn me_adjudicaciones(
    state: Arc<AppState>,
    event: Request,
) -> Result<Response<Body>, Error> {
    let claims = match require_auth(&event, &state.jwt_secret) {
        Ok(c) => c,
        Err(r) => return Ok(r),
    };

    let user_id = claims.sub;

    let rows = sqlx::query_as::<_, AdjudicacionRow>(r#"
        SELECT
            a.id,
            a.external_id,
            a.titulo,
            a.numero_expediente,
            a.fecha_adjudicacion,
            a.importe::FLOAT8                              AS importe,
            a.importe_adjudicado::FLOAT8                   AS importe_adjudicado,
            a.valor_estimado::FLOAT8                       AS valor_estimado,
            a.ratio_adjudicacion_vs_licitacion::FLOAT8     AS ratio_adjudicacion_vs_licitacion,
            a.comunidad_autonoma::TEXT                     AS comunidad_autonoma,
            a.mercado_vertical::TEXT                       AS mercado_vertical,
            a.tipo_procedimiento::TEXT                     AS tipo_procedimiento,
            a.duracion_meses,
            o.nombre                                       AS organismo_nombre,
            adj.nombre                                     AS adjudicatario_nombre,
            a.licitacion_id,
            a.created_at
        FROM adjudicacion a
        LEFT JOIN organismo     o   ON o.id   = a.organismo_id
        LEFT JOIN adjudicatario adj ON adj.id = a.adjudicatario_id
        WHERE a.licitacion_id IS NOT NULL
          AND EXISTS (
            SELECT 1 FROM licitacion_cotizacion lc
            WHERE lc.licitacion_id = a.licitacion_id
              AND lc.user_id = $1
          )
        ORDER BY a.fecha_adjudicacion DESC NULLS LAST, a.id DESC
    "#)
    .bind(user_id)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| format!("me_adjudicaciones: {e}"))?;

    let data: Vec<serde_json::Value> = rows.iter().map(|r| serde_json::json!({
        "id":                               r.id,
        "external_id":                      r.external_id,
        "titulo":                           r.titulo,
        "numero_expediente":                r.numero_expediente,
        "fecha_adjudicacion":               r.fecha_adjudicacion.map(|d| d.to_string()),
        "importe":                          r.importe,
        "importe_adjudicado":               r.importe_adjudicado,
        "valor_estimado":                   r.valor_estimado,
        "ratio_adjudicacion_vs_licitacion": r.ratio_adjudicacion_vs_licitacion,
        "comunidad_autonoma":               r.comunidad_autonoma,
        "mercado_vertical":                 r.mercado_vertical,
        "tipo_procedimiento":               r.tipo_procedimiento,
        "duracion_meses":                   r.duracion_meses,
        "organismo_nombre":                 r.organismo_nombre,
        "adjudicatario_nombre":             r.adjudicatario_nombre,
        "licitacion_id":                    r.licitacion_id,
        "created_at":                       r.created_at.to_rfc3339(),
    })).collect();

    json(200, &serde_json::to_string(&data)?)
}

// ── GET /me/alertas ──────────────────────────────────────────────────────────

pub async fn me_alertas(
    state: Arc<AppState>,
    event: Request,
) -> Result<Response<Body>, Error> {
    let claims = match require_auth(&event, &state.jwt_secret) {
        Ok(c) => c,
        Err(r) => return Ok(r),
    };

    let rows = sqlx::query(r#"
        SELECT al.id, al.adjudicacion_id, al.licitacion_id, al.mensaje, al.leida, al.created_at,
               a.titulo AS adj_titulo
        FROM alerta al
        JOIN adjudicacion a ON a.id = al.adjudicacion_id
        WHERE al.user_id = $1
        ORDER BY al.created_at DESC
        LIMIT 50
    "#)
    .bind(claims.sub)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| format!("me_alertas: {e}"))?;

    use sqlx::Row;
    let data: Vec<serde_json::Value> = rows.iter().map(|r| serde_json::json!({
        "id":               r.get::<i64, _>("id"),
        "adjudicacion_id":  r.get::<i64, _>("adjudicacion_id"),
        "licitacion_id":    r.try_get::<i64, _>("licitacion_id").ok(),
        "mensaje":          r.get::<String, _>("mensaje"),
        "leida":            r.get::<bool, _>("leida"),
        "created_at":       r.get::<chrono::DateTime<chrono::Utc>, _>("created_at").to_rfc3339(),
        "adj_titulo":       r.get::<String, _>("adj_titulo"),
    })).collect();

    json(200, &serde_json::to_string(&data)?)
}

// ── PATCH /me/alertas/:id/leer ───────────────────────────────────────────────

pub async fn marcar_alerta_leida(
    state: Arc<AppState>,
    event: Request,
    alerta_id: i64,
) -> Result<Response<Body>, Error> {
    let claims = match require_auth(&event, &state.jwt_secret) {
        Ok(c) => c,
        Err(r) => return Ok(r),
    };

    sqlx::query("UPDATE alerta SET leida = TRUE WHERE id = $1 AND user_id = $2")
        .bind(alerta_id)
        .bind(claims.sub)
        .execute(&state.pool)
        .await
        .map_err(|e| format!("marcar_alerta_leida: {e}"))?;

    json(200, r#"{"ok":true}"#)
}

// ── PATCH /me/alertas/leer-todas ─────────────────────────────────────────────

pub async fn marcar_todas_alertas_leidas(
    state: Arc<AppState>,
    event: Request,
) -> Result<Response<Body>, Error> {
    let claims = match require_auth(&event, &state.jwt_secret) {
        Ok(c) => c,
        Err(r) => return Ok(r),
    };

    sqlx::query("UPDATE alerta SET leida = TRUE WHERE user_id = $1 AND leida = FALSE")
        .bind(claims.sub)
        .execute(&state.pool)
        .await
        .map_err(|e| format!("marcar_todas: {e}"))?;

    json(200, r#"{"ok":true}"#)
}

fn json(status: u16, body: &str) -> Result<Response<Body>, Error> {
    Ok(Response::builder()
        .status(status)
        .header("Content-Type", "application/json")
        .body(Body::Text(body.to_string()))
        .map_err(|e| format!("response build: {e}"))?)
}
