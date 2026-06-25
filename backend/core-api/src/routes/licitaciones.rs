use chrono::{DateTime, NaiveDate, Utc};
use lambda_http::{Body, Error, Request, RequestExt, Response};
use serde::{Deserialize, Serialize};
use std::sync::Arc;

use crate::AppState;
use crate::routes::pipeline::require_auth;

// ── Response types ────────────────────────────────────────────────────────────

fn serialize_assignees<S: serde::Serializer>(v: &Option<String>, s: S) -> Result<S::Ok, S::Error> {
    let arr = v
        .as_deref()
        .and_then(|t| serde_json::from_str::<serde_json::Value>(t).ok())
        .unwrap_or(serde_json::Value::Array(vec![]));
    arr.serialize(s)
}

#[derive(Serialize, sqlx::FromRow)]
pub struct LicitacionSummary {
    id: i64,
    fecha: NaiveDate,
    titulo: String,
    numero_expediente: String,
    importe_licitacion: Option<f64>,
    valor_estimado: Option<f64>,
    estado: Option<String>,
    pipeline_stage: String,
    owner_id: Option<i32>,
    tipo_procedimiento: Option<String>,
    tipo_tramitacion: Option<String>,
    comunidad_autonoma: Option<String>,
    provincia: Option<String>,
    mercado_vertical: Option<String>,
    plazo_oferta_estado: Option<String>,
    fecha_limite_oferta: Option<DateTime<Utc>>,
    duracion_meses: Option<i16>,
    prorrogas_meses: Option<i16>,
    puntos_precio: Option<i16>,
    puntos_mejoras: Option<i16>,
    puntos_subjetivos: Option<i16>,
    cpv_label: Option<String>,
    created_at: DateTime<Utc>,
    #[sqlx(rename = "assignees_json")]
    #[serde(rename = "assignees", serialize_with = "serialize_assignees")]
    assignees_raw: Option<String>,
    ingram_estado: Option<String>,
    ingram_owner: Option<String>,
    cotizacion_solicitada_a: Option<String>,
    fabricante_proteccion: bool,
    fabricante_nombre: Option<String>,
    motivo_perdida: Option<String>,
    motivo_perdida_texto: Option<String>,
    organismo_nombre: Option<String>,
}

#[derive(Serialize)]
struct ListResponse {
    data: Vec<LicitacionSummary>,
    total: i64,
    page: i64,
    per_page: i64,
}

#[derive(Serialize)]
struct ClientCotizacionDto {
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

// ── Request types ─────────────────────────────────────────────────────────────

#[derive(Deserialize)]
pub struct CreateLicitacionRequest {
    pub fecha: NaiveDate,
    pub titulo: String,
    pub numero_expediente: String,
    pub control_expediente: Option<i16>,
    pub subsanacion: Option<String>,
    pub importe_licitacion: Option<f64>,
    pub estado: Option<String>,
    pub comunidad_autonoma: Option<String>,
    pub provincia: Option<String>,
    pub mercado_vertical: Option<String>,
    pub tipo_procedimiento: Option<String>,
    pub ambito_geografico: Option<String>,
    pub duracion_meses: Option<i16>,
    pub prorrogas_meses: Option<i16>,
    pub competencia: Option<String>,
    pub comentarios: Option<String>,
    pub puntos_precio: Option<i16>,
    pub puntos_mejoras: Option<i16>,
    pub puntos_subjetivos: Option<i16>,
}

#[derive(Deserialize)]
struct ClientCotizacionRequest {
    cotizacion_xv: Option<String>,
    oportunidad: Option<String>,
    cotizacion_id: Option<String>,
    oportunidad_id: Option<String>,
    estado: Option<String>,
    divisiones: Option<Vec<String>>,
    fabricante_proteccion: Option<bool>,
    fabricante_nombre: Option<String>,
    se_presenta: Option<bool>,
    user_id: Option<i64>,
    va_con_pliego: Option<bool>,
}

fn order_by_clause(key: &str) -> &'static str {
    match key {
        "fecha_asc"     => "l.fecha ASC NULLS LAST, l.id ASC",
        "importe_desc"  => "l.importe_licitacion DESC NULLS LAST, l.id DESC",
        "importe_asc"   => "l.importe_licitacion ASC NULLS LAST, l.id ASC",
        "plazo_asc"     => "l.fecha_limite_oferta ASC NULLS LAST, l.id DESC",
        "titulo_asc"    => "l.titulo ASC, l.id ASC",
        _               => "l.fecha DESC NULLS LAST, l.id DESC", // fecha_desc default
    }
}

fn list_sql(order_by: &str) -> String {
    let order_by = order_by_clause(order_by);
    // Data query: $1=per_page  $2=offset
    //             $3=comunidad $4=mercado   $5=tipo_proc  $6=ingram_estado
    //             $7=competencia $8=cat1 $9=cat2 $10=cat3
    //             $11=deadline_range $12=importe_range $13=duracion_range
    //             $14=pipeline_stage_filter  $15=reciente  $16=division
    //             $17=asignada ('si'|'no')  $18=assignee_user_id (int as text)
    format!(r#"
SELECT
    l.id,
    l.fecha,
    l.titulo,
    l.numero_expediente,
    l.importe_licitacion::FLOAT8             AS importe_licitacion,
    l.valor_estimado::FLOAT8                 AS valor_estimado,
    l.estado::TEXT                           AS estado,
    COALESCE(l.pipeline_stage::TEXT,'nueva') AS pipeline_stage,
    l.owner_id,
    l.tipo_procedimiento::TEXT               AS tipo_procedimiento,
    l.tipo_tramitacion,
    l.comunidad_autonoma::TEXT               AS comunidad_autonoma,
    l.provincia,
    l.mercado_vertical::TEXT                 AS mercado_vertical,
    l.plazo_oferta_estado::TEXT              AS plazo_oferta_estado,
    l.fecha_limite_oferta,
    l.duracion_meses,
    l.prorrogas_meses,
    l.puntos_precio,
    l.puntos_mejoras,
    l.puntos_subjetivos,
    (SELECT STRING_AGG(lc.cpv_code || ' - ' || c.descripcion, '; ' ORDER BY lc.cpv_code)
     FROM licitacion_cpv lc
     JOIN cpv_code c ON c.code = lc.cpv_code
     WHERE lc.licitacion_id = l.id)          AS cpv_label,
    l.created_at,
    l.ingram_estado,
    l.ingram_owner,
    l.cotizacion_solicitada_a,
    l.fabricante_proteccion,
    l.fabricante_nombre,
    l.motivo_perdida,
    l.motivo_perdida_texto,
    COALESCE(
        (SELECT JSON_AGG(JSON_BUILD_OBJECT('id', u2.id, 'nombre', u2.nombre) ORDER BY u2.nombre)
         FROM licitacion_assignment la2
         JOIN app_user u2 ON u2.id = la2.assignee_id
         WHERE la2.licitacion_id = l.id AND la2.active = TRUE),
        '[]'::JSON
    )::TEXT                                  AS assignees_json,
    o.nombre                                 AS organismo_nombre
FROM licitacion l
LEFT JOIN area_tecnologica at ON at.id = l.area_tecnologica_id
LEFT JOIN organismo o ON o.id = l.organismo_id
WHERE TRUE
  AND ($3::TEXT IS NULL OR l.comunidad_autonoma::TEXT = ANY(string_to_array($3, ',')))
  AND ($4::TEXT IS NULL OR l.mercado_vertical::TEXT = ANY(string_to_array($4, ',')))
  AND ($5::TEXT IS NULL OR l.tipo_procedimiento::TEXT = ANY(string_to_array($5, ',')))
  AND ($6::TEXT IS NULL OR l.ingram_estado = ANY(string_to_array($6, ',')))
  AND ($7::TEXT IS NULL OR l.competencia ILIKE '%' || $7 || '%')
  AND ($8::TEXT IS NULL OR at.cat1 = ANY(string_to_array($8, ',')))
  AND ($9::TEXT IS NULL OR at.cat2 = ANY(string_to_array($9, ',')))
  AND ($10::TEXT IS NULL OR at.cat3 = ANY(string_to_array($10, ',')))
  AND CASE $11::TEXT
    WHEN 'vigentes'  THEN (l.fecha_limite_oferta IS NULL OR l.fecha_limite_oferta::DATE >= CURRENT_DATE)
    WHEN 'caducadas' THEN (l.fecha_limite_oferta IS NOT NULL AND l.fecha_limite_oferta::DATE < CURRENT_DATE)
    WHEN 'lt7'  THEN l.fecha_limite_oferta::DATE <= CURRENT_DATE + 7
    WHEN 'lt15' THEN l.fecha_limite_oferta::DATE <= CURRENT_DATE + 14
    WHEN 'lt30' THEN l.fecha_limite_oferta::DATE <= CURRENT_DATE + 29
    WHEN 'gt30' THEN l.fecha_limite_oferta::DATE >  CURRENT_DATE + 30
    ELSE TRUE
  END
  AND CASE $12::TEXT
    WHEN 'lt50k'    THEN l.importe_licitacion < 50000
    WHEN '50-100k'  THEN l.importe_licitacion BETWEEN 50000    AND 100000
    WHEN '100-250k' THEN l.importe_licitacion BETWEEN 100001   AND 250000
    WHEN '250-500k' THEN l.importe_licitacion BETWEEN 250001   AND 500000
    WHEN '500k-1m'  THEN l.importe_licitacion BETWEEN 500001   AND 1000000
    WHEN 'gt1m'     THEN l.importe_licitacion > 1000000
    ELSE TRUE
  END
  AND CASE $13::TEXT
    WHEN 'lt6'   THEN l.duracion_meses < 6
    WHEN '6-12'  THEN l.duracion_meses BETWEEN  6 AND 12
    WHEN '12-18' THEN l.duracion_meses BETWEEN 12 AND 18
    WHEN '18-24' THEN l.duracion_meses BETWEEN 18 AND 24
    WHEN '24-36' THEN l.duracion_meses BETWEEN 24 AND 36
    WHEN '36-48' THEN l.duracion_meses BETWEEN 36 AND 48
    WHEN '48-60' THEN l.duracion_meses BETWEEN 48 AND 60
    WHEN '60-72' THEN l.duracion_meses BETWEEN 60 AND 72
    WHEN 'gt72'  THEN l.duracion_meses > 72
    ELSE TRUE
  END
  AND ($14::TEXT IS NULL
       OR ($14 = 'activas' AND l.pipeline_stage NOT IN ('ganada','perdida','desierta'))
       OR ($14 != 'activas' AND l.pipeline_stage::TEXT = $14))
  AND ($15::TEXT IS NULL OR l.fecha >= CURRENT_DATE - INTERVAL '2 days')
  AND ($16::TEXT IS NULL OR l.cotizacion_solicitada_a = ANY(string_to_array($16, ',')))
  AND ($17::TEXT IS NULL
       OR ($17 = 'si' AND EXISTS (
             SELECT 1 FROM licitacion_assignment la
             WHERE la.licitacion_id = l.id AND la.active = TRUE))
       OR ($17 = 'no' AND NOT EXISTS (
             SELECT 1 FROM licitacion_assignment la
             WHERE la.licitacion_id = l.id AND la.active = TRUE)))
  AND ($18::TEXT IS NULL OR EXISTS (
        SELECT 1 FROM licitacion_assignment la
        WHERE la.licitacion_id = l.id AND la.assignee_id = ANY(string_to_array($18, ',')::INTEGER[]) AND la.active = TRUE))
  AND NOT EXISTS (SELECT 1 FROM adjudicacion WHERE licitacion_id = l.id)
ORDER BY {order_by}
LIMIT $1 OFFSET $2
"#)
}

// Count query: $1-$8=text filters, $9-$11=range filters, $12=pipeline_stage_filter $13=reciente $14=division $15=asignada $16=assignee_user_id
const COUNT_SQL: &str = r#"
SELECT COUNT(*)::BIGINT
FROM licitacion l
LEFT JOIN area_tecnologica at ON at.id = l.area_tecnologica_id
WHERE TRUE
  AND ($1::TEXT IS NULL OR l.comunidad_autonoma::TEXT = ANY(string_to_array($1, ',')))
  AND ($2::TEXT IS NULL OR l.mercado_vertical::TEXT = ANY(string_to_array($2, ',')))
  AND ($3::TEXT IS NULL OR l.tipo_procedimiento::TEXT = ANY(string_to_array($3, ',')))
  AND ($4::TEXT IS NULL OR l.ingram_estado = ANY(string_to_array($4, ',')))
  AND ($5::TEXT IS NULL OR l.competencia ILIKE '%' || $5 || '%')
  AND ($6::TEXT IS NULL OR at.cat1 = ANY(string_to_array($6, ',')))
  AND ($7::TEXT IS NULL OR at.cat2 = ANY(string_to_array($7, ',')))
  AND ($8::TEXT IS NULL OR at.cat3 = ANY(string_to_array($8, ',')))
  AND CASE $9::TEXT
    WHEN 'vigentes'  THEN (l.fecha_limite_oferta IS NULL OR l.fecha_limite_oferta::DATE >= CURRENT_DATE)
    WHEN 'caducadas' THEN (l.fecha_limite_oferta IS NOT NULL AND l.fecha_limite_oferta::DATE < CURRENT_DATE)
    WHEN 'lt7'  THEN l.fecha_limite_oferta::DATE <= CURRENT_DATE + 7
    WHEN 'lt15' THEN l.fecha_limite_oferta::DATE <= CURRENT_DATE + 14
    WHEN 'lt30' THEN l.fecha_limite_oferta::DATE <= CURRENT_DATE + 29
    WHEN 'gt30' THEN l.fecha_limite_oferta::DATE >  CURRENT_DATE + 30
    ELSE TRUE
  END
  AND CASE $10::TEXT
    WHEN 'lt50k'    THEN l.importe_licitacion < 50000
    WHEN '50-100k'  THEN l.importe_licitacion BETWEEN 50000    AND 100000
    WHEN '100-250k' THEN l.importe_licitacion BETWEEN 100001   AND 250000
    WHEN '250-500k' THEN l.importe_licitacion BETWEEN 250001   AND 500000
    WHEN '500k-1m'  THEN l.importe_licitacion BETWEEN 500001   AND 1000000
    WHEN 'gt1m'     THEN l.importe_licitacion > 1000000
    ELSE TRUE
  END
  AND CASE $11::TEXT
    WHEN 'lt6'   THEN l.duracion_meses < 6
    WHEN '6-12'  THEN l.duracion_meses BETWEEN  6 AND 12
    WHEN '12-18' THEN l.duracion_meses BETWEEN 12 AND 18
    WHEN '18-24' THEN l.duracion_meses BETWEEN 18 AND 24
    WHEN '24-36' THEN l.duracion_meses BETWEEN 24 AND 36
    WHEN '36-48' THEN l.duracion_meses BETWEEN 36 AND 48
    WHEN '48-60' THEN l.duracion_meses BETWEEN 48 AND 60
    WHEN '60-72' THEN l.duracion_meses BETWEEN 60 AND 72
    WHEN 'gt72'  THEN l.duracion_meses > 72
    ELSE TRUE
  END
  AND ($12::TEXT IS NULL
       OR ($12 = 'activas' AND l.pipeline_stage NOT IN ('ganada','perdida','desierta'))
       OR ($12 != 'activas' AND l.pipeline_stage::TEXT = $12))
  AND ($13::TEXT IS NULL OR l.fecha >= CURRENT_DATE - INTERVAL '2 days')
  AND ($14::TEXT IS NULL OR l.cotizacion_solicitada_a = ANY(string_to_array($14, ',')))
  AND ($15::TEXT IS NULL
       OR ($15 = 'si' AND EXISTS (
             SELECT 1 FROM licitacion_assignment la
             WHERE la.licitacion_id = l.id AND la.active = TRUE))
       OR ($15 = 'no' AND NOT EXISTS (
             SELECT 1 FROM licitacion_assignment la
             WHERE la.licitacion_id = l.id AND la.active = TRUE)))
  AND ($16::TEXT IS NULL OR EXISTS (
        SELECT 1 FROM licitacion_assignment la
        WHERE la.licitacion_id = l.id AND la.assignee_id = ANY(string_to_array($16, ',')::INTEGER[]) AND la.active = TRUE))
  AND NOT EXISTS (SELECT 1 FROM adjudicacion WHERE licitacion_id = l.id)
"#;

// ── GET /licitaciones ─────────────────────────────────────────────────────────

pub async fn list(state: Arc<AppState>, event: Request) -> Result<Response<Body>, Error> {
    let params = event.query_string_parameters();

    let page: i64 = params.first("page")
        .and_then(|v| v.parse().ok()).unwrap_or(1).max(1);
    let per_page: i64 = params.first("per_page")
        .and_then(|v| v.parse().ok()).unwrap_or(20).min(100);
    let offset = (page - 1) * per_page;

    // Extract filter params as owned Strings so we can borrow them as &str
    let comunidad      = params.first("comunidad").map(|s| s.to_string());
    let mercado        = params.first("mercado").map(|s| s.to_string());
    let tipo_proc      = params.first("tipo_procedimiento").map(|s| s.to_string());
    let ingram_est     = params.first("ingram_estado").map(|s| s.to_string());
    let competencia    = params.first("competencia").map(|s| s.to_string());
    let cat1           = params.first("cat1").map(|s| s.to_string());
    let cat2           = params.first("cat2").map(|s| s.to_string());
    let cat3           = params.first("cat3").map(|s| s.to_string());
    let deadline_range      = params.first("deadline_range").map(|s| s.to_string());
    let importe_range       = params.first("importe_range").map(|s| s.to_string());
    let duracion_range      = params.first("duracion_range").map(|s| s.to_string());
    let pipeline_stage_filter = params.first("pipeline_stage").map(|s| s.to_string());
    let reciente            = params.first("reciente").map(|s| s.to_string());
    let division            = params.first("cotizacion_solicitada_a").map(|s| s.to_string());
    let asignada            = params.first("asignada").map(|s| s.to_string());
    let assignee_user_ids   = params.first("assignee_user_ids")
        .or_else(|| params.first("assignee_user_id"))
        .map(|s| s.to_string());
    let order_by            = params.first("order_by").unwrap_or("fecha_desc");

    let sql = list_sql(order_by);
    let rows = sqlx::query_as::<_, LicitacionSummary>(&sql)
        .bind(per_page)
        .bind(offset)
        .bind(comunidad.as_deref())
        .bind(mercado.as_deref())
        .bind(tipo_proc.as_deref())
        .bind(ingram_est.as_deref())
        .bind(competencia.as_deref())
        .bind(cat1.as_deref())
        .bind(cat2.as_deref())
        .bind(cat3.as_deref())
        .bind(deadline_range.as_deref())
        .bind(importe_range.as_deref())
        .bind(duracion_range.as_deref())
        .bind(pipeline_stage_filter.as_deref())
        .bind(reciente.as_deref())
        .bind(division.as_deref())
        .bind(asignada.as_deref())
        .bind(assignee_user_ids.as_deref())
        .fetch_all(&state.pool)
        .await
        .map_err(|e| format!("list query failed: {e}"))?;

    let total: i64 = sqlx::query_scalar::<_, i64>(COUNT_SQL)
        .bind(comunidad.as_deref())
        .bind(mercado.as_deref())
        .bind(tipo_proc.as_deref())
        .bind(ingram_est.as_deref())
        .bind(competencia.as_deref())
        .bind(cat1.as_deref())
        .bind(cat2.as_deref())
        .bind(cat3.as_deref())
        .bind(deadline_range.as_deref())
        .bind(importe_range.as_deref())
        .bind(duracion_range.as_deref())
        .bind(pipeline_stage_filter.as_deref())
        .bind(reciente.as_deref())
        .bind(division.as_deref())
        .bind(asignada.as_deref())
        .bind(assignee_user_ids.as_deref())
        .fetch_one(&state.pool)
        .await
        .map_err(|e| format!("count query failed: {e}"))?;

    json_resp(200, serde_json::to_string(&ListResponse { data: rows, total, page, per_page })?)
}

// ── POST /licitaciones ────────────────────────────────────────────────────────

pub async fn create(state: Arc<AppState>, event: Request) -> Result<Response<Body>, Error> {
    let raw = match event.body() {
        Body::Text(s)   => s.as_bytes().to_vec(),
        Body::Binary(b) => b.clone(),
        Body::Empty     => return json_resp(400, r#"{"error":"empty body"}"#.to_string()),
    };

    let req: CreateLicitacionRequest = match serde_json::from_slice(&raw) {
        Ok(r)  => r,
        Err(e) => return json_resp(400, serde_json::json!({"error": e.to_string()}).to_string()),
    };

    let id: i64 = sqlx::query_scalar(
        r#"
        INSERT INTO licitacion (
            fecha, titulo, numero_expediente, control_expediente, subsanacion,
            importe_licitacion,
            estado, comunidad_autonoma, provincia,
            mercado_vertical, tipo_procedimiento, ambito_geografico,
            duracion_meses, prorrogas_meses,
            competencia, comentarios,
            puntos_precio, puntos_mejoras, puntos_subjetivos
        ) VALUES (
            $1, $2, $3, $4, $5,
            $6,
            $7::licitacion_estado_tipo,
            $8::comunidad_autonoma_tipo,
            $9,
            $10::mercado_vertical_tipo,
            $11::tipo_procedimiento_tipo,
            $12::ambito_geografico_tipo,
            $13, $14,
            $15, $16,
            $17, $18, $19
        )
        RETURNING id
        "#,
    )
    .bind(req.fecha)
    .bind(&req.titulo)
    .bind(&req.numero_expediente)
    .bind(req.control_expediente)
    .bind(req.subsanacion.as_deref())
    .bind(req.importe_licitacion)
    .bind(req.estado.as_deref())
    .bind(req.comunidad_autonoma.as_deref())
    .bind(req.provincia.as_deref())
    .bind(req.mercado_vertical.as_deref())
    .bind(req.tipo_procedimiento.as_deref())
    .bind(req.ambito_geografico.as_deref())
    .bind(req.duracion_meses)
    .bind(req.prorrogas_meses)
    .bind(req.competencia.as_deref())
    .bind(req.comentarios.as_deref())
    .bind(req.puntos_precio)
    .bind(req.puntos_mejoras)
    .bind(req.puntos_subjetivos)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| format!("insert failed: {e}"))?;

    json_resp(201, serde_json::json!({"id": id}).to_string())
}

// ── GET /licitaciones/{id}/adjudicacion ──────────────────────────────────────

pub async fn get_adjudicacion(
    state: Arc<AppState>,
    event: Request,
    lid: i64,
) -> Result<Response<Body>, Error> {
    match crate::routes::pipeline::require_auth(&event, &state.jwt_secret) {
        Ok(_) => {}
        Err(r) => return Ok(r),
    }

    let row = sqlx::query(r#"
        SELECT
            a.id,
            a.fecha_adjudicacion,
            a.importe_adjudicado::FLOAT8        AS importe_adjudicado,
            a.importe::FLOAT8                   AS importe,
            a.ratio_adjudicacion_vs_licitacion::FLOAT8 AS ratio,
            a.tipo_procedimiento::TEXT          AS tipo_procedimiento,
            adj.nombre                          AS adjudicatario_nombre,
            o.nombre                            AS organismo_nombre
        FROM adjudicacion a
        LEFT JOIN adjudicatario adj ON adj.id = a.adjudicatario_id
        LEFT JOIN organismo     o   ON o.id   = a.organismo_id
        WHERE a.licitacion_id = $1
        ORDER BY a.fecha_adjudicacion DESC NULLS LAST
        LIMIT 1
    "#)
    .bind(lid)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| format!("get_adjudicacion: {e}"))?;

    match row {
        None => json_resp(404, r#"{"error":"not_found"}"#.to_string()),
        Some(r) => {
            use sqlx::Row;
            let body = serde_json::json!({
                "id":                    r.get::<i64, _>("id"),
                "fecha_adjudicacion":    r.get::<Option<chrono::NaiveDate>, _>("fecha_adjudicacion").map(|d| d.to_string()),
                "importe_adjudicado":    r.get::<Option<f64>, _>("importe_adjudicado"),
                "importe":               r.get::<Option<f64>, _>("importe"),
                "ratio":                 r.get::<Option<f64>, _>("ratio"),
                "tipo_procedimiento":    r.get::<Option<String>, _>("tipo_procedimiento"),
                "adjudicatario_nombre":  r.get::<Option<String>, _>("adjudicatario_nombre"),
                "organismo_nombre":      r.get::<Option<String>, _>("organismo_nombre"),
            });
            json_resp(200, serde_json::to_string(&body)?)
        }
    }
}

// ── GET /licitaciones/{id}/client-cotizaciones ───────────────────────────────

pub async fn list_client_cotizaciones(
    state: Arc<AppState>,
    _event: Request,
    lid: i64,
) -> Result<Response<Body>, Error> {
    let rows = sqlx::query(
        r#"SELECT cliente_nombre, cotizacion_xv, oportunidad, cotizacion_id, oportunidad_id,
                  estado, divisiones, fabricante_proteccion, fabricante_nombre,
                  se_presenta, user_id, va_con_pliego
           FROM licitacion_cotizacion
           WHERE licitacion_id = $1
           ORDER BY cliente_nombre, user_id NULLS FIRST"#,
    )
    .bind(lid)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| format!("list_client_cotizaciones failed: {e}"))?;

    let dtos: Vec<ClientCotizacionDto> = rows
        .iter()
        .map(|r| {
            use sqlx::Row;
            ClientCotizacionDto {
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
        })
        .collect();

    json_resp(200, serde_json::to_string(&dtos)?)
}

// ── PUT /licitaciones/{id}/client-cotizaciones/{cliente} ─────────────────────

pub async fn upsert_client_cotizacion(
    state: Arc<AppState>,
    event: Request,
    lid: i64,
    cliente: String,
) -> Result<Response<Body>, Error> {
    let claims = match require_auth(&event, &state.jwt_secret) {
        Ok(c) => c,
        Err(r) => return Ok(r),
    };

    let raw = match event.body() {
        Body::Text(s)   => s.as_bytes().to_vec(),
        Body::Binary(b) => b.clone(),
        Body::Empty     => return json_resp(400, r#"{"error":"empty body"}"#.to_string()),
    };

    let req: ClientCotizacionRequest = match serde_json::from_slice(&raw) {
        Ok(r)  => r,
        Err(e) => return json_resp(400, serde_json::json!({"error": e.to_string()}).to_string()),
    };

    let divisiones = req.divisiones.clone().unwrap_or_default();
    // Always derive from the authenticated JWT — never trust the client-supplied user_id.
    let user_id_val: Option<i64> = Some(claims.sub as i64);

    let is_empty = req.cotizacion_xv.as_deref().unwrap_or("").trim().is_empty()
        && req.oportunidad.as_deref().unwrap_or("").trim().is_empty()
        && req.estado.as_deref().unwrap_or("").trim().is_empty()
        && divisiones.is_empty()
        && !req.fabricante_proteccion.unwrap_or(false)
        && !req.se_presenta.unwrap_or(false)
        && req.va_con_pliego.unwrap_or(false) == false;

    // Fetch existing client cotizacion to compare
    let old_info: Option<(Option<String>, Option<String>, Option<String>, Vec<String>, bool)> = sqlx::query_as(
        "SELECT cotizacion_xv, oportunidad, estado, divisiones, se_presenta \
         FROM licitacion_cotizacion \
         WHERE licitacion_id = $1 AND cliente_nombre = $2 AND COALESCE(user_id, -1) = COALESCE($3, -1)"
    )
    .bind(lid)
    .bind(&cliente)
    .bind(user_id_val)
    .fetch_optional(&state.pool)
    .await
    .unwrap_or(None);

    if is_empty {
        sqlx::query(
            r#"DELETE FROM licitacion_cotizacion
               WHERE licitacion_id = $1
                 AND cliente_nombre = $2
                 AND COALESCE(user_id, -1) = COALESCE($3, -1)"#,
        )
        .bind(lid)
        .bind(&cliente)
        .bind(user_id_val)
        .execute(&state.pool)
        .await
        .map_err(|e| format!("delete client_cotizacion failed: {e}"))?;

        let desc = format!("Cotización de cliente eliminada: {}", cliente);
        let _ = crate::routes::pipeline::log_change(&state.pool, lid, claims.sub, &desc).await;
    } else {
        sqlx::query(
            r#"INSERT INTO licitacion_cotizacion
                   (licitacion_id, cliente_nombre, cotizacion_xv, oportunidad,
                    cotizacion_id, oportunidad_id,
                    estado, divisiones, fabricante_proteccion, fabricante_nombre,
                    se_presenta, user_id, va_con_pliego)
               VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
               ON CONFLICT (licitacion_id, cliente_nombre, COALESCE(user_id, -1))
               DO UPDATE SET cotizacion_xv         = $3,
                             oportunidad           = $4,
                             cotizacion_id         = $5,
                             oportunidad_id        = $6,
                             estado                = $7,
                             divisiones            = $8,
                             fabricante_proteccion = $9,
                             fabricante_nombre     = $10,
                             se_presenta           = $11,
                             va_con_pliego         = $13"#,
        )
        .bind(lid)
        .bind(&cliente)
        .bind(req.cotizacion_xv.as_deref())
        .bind(req.oportunidad.as_deref())
        .bind(req.cotizacion_id.as_deref())
        .bind(req.oportunidad_id.as_deref())
        .bind(req.estado.as_deref())
        .bind(&divisiones)
        .bind(req.fabricante_proteccion.unwrap_or(false))
        .bind(req.fabricante_nombre.as_deref())
        .bind(req.se_presenta.unwrap_or(false))
        .bind(user_id_val)
        .bind(req.va_con_pliego)
        .execute(&state.pool)
        .await
        .map_err(|e| format!("upsert_client_cotizacion failed: {e}"))?;

        if let Some((old_xv, old_opp, old_est, old_divs, old_pres)) = old_info {
            let mut changes = Vec::new();
            let new_xv = req.cotizacion_xv.as_deref().unwrap_or("");
            let old_xv_val = old_xv.as_deref().unwrap_or("");
            if new_xv != old_xv_val {
                changes.push(format!("XV: {} -> {}", old_xv_val, new_xv));
            }

            let new_opp = req.oportunidad.as_deref().unwrap_or("");
            let old_opp_val = old_opp.as_deref().unwrap_or("");
            if new_opp != old_opp_val {
                changes.push(format!("oportunidad: {} -> {}", old_opp_val, new_opp));
            }

            let new_est = req.estado.as_deref().unwrap_or("");
            let old_est_val = old_est.as_deref().unwrap_or("");
            if new_est != old_est_val {
                changes.push(format!("estado: {} -> {}", old_est_val, new_est));
            }

            let mut sorted_new_divs = divisiones.clone();
            sorted_new_divs.sort();
            let mut sorted_old_divs = old_divs.clone();
            sorted_old_divs.sort();
            if sorted_new_divs != sorted_old_divs {
                changes.push(format!("divisiones: {:?} -> {:?}", old_divs, divisiones));
            }

            let new_pres = req.se_presenta.unwrap_or(false);
            if new_pres != old_pres {
                changes.push(format!("se presenta: {} -> {}", old_pres, new_pres));
            }

            if !changes.is_empty() {
                let desc = format!("Cotización cliente ({}) modificada: {}", cliente, changes.join(", "));
                let _ = crate::routes::pipeline::log_change(&state.pool, lid, claims.sub, &desc).await;
            }
        } else {
            let desc = format!("Nueva cotización cliente creada para: {}", cliente);
            let _ = crate::routes::pipeline::log_change(&state.pool, lid, claims.sub, &desc).await;
        }
    }

    // Auto-advance pipeline stage from client estados; never override terminal outcomes
    sqlx::query(
        r#"UPDATE licitacion
           SET pipeline_stage = CASE
             WHEN pipeline_stage::text IN ('ganada', 'perdida', 'desierta') THEN pipeline_stage
             WHEN EXISTS (
               SELECT 1 FROM licitacion_cotizacion
               WHERE licitacion_id = $1 AND estado = 'COTIZACIÓN ENVIADA A CLIENTE - X4A'
             ) THEN 'cotizaciones_enviadas'::pipeline_stage
             WHEN EXISTS (
               SELECT 1 FROM licitacion_cotizacion
               WHERE licitacion_id = $1 AND estado IS NOT NULL
             ) THEN 'en_proceso'::pipeline_stage
             ELSE pipeline_stage
           END
           WHERE id = $1"#,
    )
    .bind(lid)
    .execute(&state.pool)
    .await
    .map_err(|e| format!("auto_stage update failed: {e}"))?;

    json_resp(200, r#"{"ok":true}"#.to_string())
}

// ── GET /licitaciones/{id}/summary ───────────────────────────────────────────

pub async fn get_summary(
    state: Arc<AppState>,
    event: Request,
    lid: i64,
) -> Result<Response<Body>, Error> {
    match require_auth(&event, &state.jwt_secret) {
        Ok(_) => {}
        Err(r) => return Ok(r),
    };

    let row: Option<(Option<String>, Option<DateTime<Utc>>)> = sqlx::query_as(
        "SELECT ai_summary, ai_summary_at FROM licitacion WHERE id = $1",
    )
    .bind(lid)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| format!("get_summary: {e}"))?;

    match row {
        None => json_resp(404, r#"{"error":"not found"}"#.to_string()),
        Some((summary, saved_at)) => {
            let body = serde_json::to_string(&serde_json::json!({
                "summary":  summary,
                "saved_at": saved_at.map(|d| d.to_rfc3339()),
            }))?;
            json_resp(200, body)
        }
    }
}

// ── POST /licitaciones/{id}/summary ──────────────────────────────────────────

pub async fn save_summary(
    state: Arc<AppState>,
    event: Request,
    lid: i64,
) -> Result<Response<Body>, Error> {
    match require_auth(&event, &state.jwt_secret) {
        Ok(_) => {}
        Err(r) => return Ok(r),
    };

    #[derive(Deserialize)]
    struct Payload { summary: String }

    let body = match event.body() {
        Body::Text(s)   => s.clone(),
        Body::Binary(b) => String::from_utf8_lossy(b).into_owned(),
        Body::Empty     => return json_resp(400, r#"{"error":"empty body"}"#.to_string()),
    };
    let payload: Payload = serde_json::from_str(&body)
        .map_err(|e| format!("save_summary parse: {e}"))?;

    sqlx::query(
        "UPDATE licitacion SET ai_summary = $1, ai_summary_at = NOW() WHERE id = $2",
    )
    .bind(&payload.summary)
    .bind(lid)
    .execute(&state.pool)
    .await
    .map_err(|e| format!("save_summary update: {e}"))?;

    json_resp(200, r#"{"ok":true}"#.to_string())
}

// ── Helper ────────────────────────────────────────────────────────────────────

fn json_resp(status: u16, body: String) -> Result<Response<Body>, Error> {
    Ok(Response::builder()
        .status(status)
        .header("content-type", "application/json")
        .body(Body::Text(body))
        .map_err(Box::new)?)
}
