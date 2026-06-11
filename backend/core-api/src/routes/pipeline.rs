use lambda_http::{Body, Error, Request, Response};
use serde::Deserialize;
use sqlx::Row;
use std::sync::Arc;

use crate::{auth, AppState};

/// Early-return an HTTP error response wrapped in Ok() so the lambda handler
/// can return it as a proper HTTP response instead of a runtime error.
macro_rules! bail {
    ($e:expr) => {
        match $e {
            Ok(v) => v,
            Err(e) => return Ok(e),
        }
    };
}

// ── Request/response types ─────────────────────────────────────────────────────

#[derive(Deserialize)]
pub struct AssignReq {
    pub assignee_id: i32,
}

#[derive(Deserialize)]
pub struct DeclineReq {
    pub reason: Option<String>,
}

#[derive(Deserialize)]
pub struct StageReq {
    pub stage: String,
}

// ── POST /licitaciones/{id}/assign  (admin only) ───────────────────────────────

pub async fn assign(
    state: Arc<AppState>,
    event: Request,
    lic_id: i64,
) -> Result<Response<Body>, Error> {
    let claims = bail!(require_auth(&event, &state.jwt_secret));
    let req    = bail!(parse_body::<AssignReq>(&event));

    // Vendedores may only assign to themselves
    if claims.role != "admin" && req.assignee_id != claims.sub {
        return json(403, r#"{"error":"Solo puedes asignarte licitaciones a ti mismo"}"#);
    }

    // Deactivate existing active assignment
    sqlx::query(
        "UPDATE licitacion_assignment SET active = FALSE
         WHERE licitacion_id = $1 AND active = TRUE",
    )
    .bind(lic_id)
    .execute(&state.pool)
    .await
    .map_err(|e| format!("db: {e}"))?;

    // Insert new assignment
    sqlx::query(
        "INSERT INTO licitacion_assignment (licitacion_id, assignee_id, assigned_by)
         VALUES ($1, $2, $3)",
    )
    .bind(lic_id)
    .bind(req.assignee_id)
    .bind(claims.sub)
    .execute(&state.pool)
    .await
    .map_err(|e| format!("db: {e}"))?;

    // Advance pipeline to 'asignada'
    sqlx::query(
        "UPDATE licitacion SET pipeline_stage = 'asignada'
         WHERE id = $1 AND pipeline_stage = 'nueva'",
    )
    .bind(lic_id)
    .execute(&state.pool)
    .await
    .map_err(|e| format!("db: {e}"))?;

    json(200, r#"{"ok":true}"#)
}

// ── POST /licitaciones/{id}/decline  (vendedor only) ──────────────────────────

pub async fn decline(
    state: Arc<AppState>,
    event: Request,
    lic_id: i64,
) -> Result<Response<Body>, Error> {
    let claims = bail!(require_auth(&event, &state.jwt_secret));
    if claims.role == "admin" {
        return json(400, r#"{"error":"Los administradores no pueden declinar"}"#);
    }
    let req = bail!(parse_body::<DeclineReq>(&event));

    sqlx::query(
        "INSERT INTO licitacion_decline (licitacion_id, user_id, reason)
         VALUES ($1, $2, $3)",
    )
    .bind(lic_id)
    .bind(claims.sub)
    .bind(req.reason.as_deref())
    .execute(&state.pool)
    .await
    .map_err(|e| format!("db: {e}"))?;

    json(200, r#"{"ok":true}"#)
}

// ── POST /licitaciones/{id}/force-assign  (admin only) ────────────────────────

pub async fn force_assign(
    state: Arc<AppState>,
    event: Request,
    lic_id: i64,
) -> Result<Response<Body>, Error> {
    let claims = bail!(require_admin(&event, &state.jwt_secret));
    let req    = bail!(parse_body::<AssignReq>(&event));

    // Resolve all pending declines for this licitacion
    sqlx::query(
        "UPDATE licitacion_decline
         SET resolved = TRUE, resolved_by = $1, resolved_at = NOW()
         WHERE licitacion_id = $2 AND resolved = FALSE",
    )
    .bind(claims.sub)
    .bind(lic_id)
    .execute(&state.pool)
    .await
    .map_err(|e| format!("db: {e}"))?;

    // Deactivate existing assignment
    sqlx::query(
        "UPDATE licitacion_assignment SET active = FALSE
         WHERE licitacion_id = $1 AND active = TRUE",
    )
    .bind(lic_id)
    .execute(&state.pool)
    .await
    .map_err(|e| format!("db: {e}"))?;

    // Force assignment
    sqlx::query(
        "INSERT INTO licitacion_assignment
         (licitacion_id, assignee_id, assigned_by, is_force)
         VALUES ($1, $2, $3, TRUE)",
    )
    .bind(lic_id)
    .bind(req.assignee_id)
    .bind(claims.sub)
    .execute(&state.pool)
    .await
    .map_err(|e| format!("db: {e}"))?;

    // Re-set pipeline to asignada
    sqlx::query(
        "UPDATE licitacion SET pipeline_stage = 'asignada' WHERE id = $1",
    )
    .bind(lic_id)
    .execute(&state.pool)
    .await
    .map_err(|e| format!("db: {e}"))?;

    json(200, r#"{"ok":true}"#)
}

// ── PATCH /licitaciones/{id}/stage ────────────────────────────────────────────

pub async fn update_stage(
    state: Arc<AppState>,
    event: Request,
    lic_id: i64,
) -> Result<Response<Body>, Error> {
    let claims = bail!(require_auth(&event, &state.jwt_secret));
    let req    = bail!(parse_body::<StageReq>(&event));

    let valid_stages = [
        "nueva", "asignada", "en_proceso",
        "cotizaciones_enviadas", "presentada",
        "ganada", "perdida", "desierta",
    ];
    if !valid_stages.contains(&req.stage.as_str()) {
        return json(400, r#"{"error":"stage inválido"}"#);
    }

    // Vendedores can only update stages of their assigned licitaciones
    if claims.role != "admin" {
        let assigned: bool = sqlx::query_scalar(
            "SELECT EXISTS(
               SELECT 1 FROM licitacion_assignment
               WHERE licitacion_id = $1 AND assignee_id = $2 AND active = TRUE
             )",
        )
        .bind(lic_id)
        .bind(claims.sub)
        .fetch_one(&state.pool)
        .await
        .map_err(|e| format!("db: {e}"))?;

        if !assigned {
            return Ok(auth::unauthorized("No tienes acceso a esta licitación"));
        }
    }

    sqlx::query(
        &format!(
            "UPDATE licitacion SET pipeline_stage = '{}'::pipeline_stage WHERE id = $1",
            req.stage.replace('\'', "")
        ),
    )
    .bind(lic_id)
    .execute(&state.pool)
    .await
    .map_err(|e| format!("db: {e}"))?;

    json(200, r#"{"ok":true}"#)
}

// ── GET /dashboard/stats  (any authenticated user) ────────────────────────────

pub async fn dashboard_stats(
    state: Arc<AppState>,
    event: Request,
) -> Result<Response<Body>, Error> {
    let claims = bail!(require_auth(&event, &state.jwt_secret));
    let is_admin = claims.role == "admin";
    let uid = claims.sub;

    // Pipeline and team are scoped to the user for vendedores; all other stats are global.
    // uid is always an i32 from a verified JWT claim — safe to interpolate.
    let pipeline_scope = if is_admin {
        String::new()
    } else {
        format!("AND id IN (SELECT licitacion_id FROM licitacion_assignment WHERE assignee_id = {uid} AND active = TRUE)")
    };
    let team_scope = if is_admin {
        String::new()
    } else {
        format!("AND u.id IN (SELECT tm2.user_id FROM team_member tm2 WHERE tm2.team_id IN (SELECT tm.team_id FROM team_member tm WHERE tm.user_id = {uid}))")
    };

    let row = sqlx::query(
        r#"
        SELECT
            COUNT(*) FILTER (
                WHERE pipeline_stage NOT IN ('ganada','perdida','desierta')
            )::BIGINT                                      AS activas,
            COUNT(*) FILTER (
                WHERE pipeline_stage = 'nueva'
            )::BIGINT                                      AS sin_asignar,
            COUNT(*) FILTER (
                WHERE fecha >= CURRENT_DATE - INTERVAL '2 days'
                  AND pipeline_stage NOT IN ('ganada','perdida','desierta')
            )::BIGINT                                      AS nuevas_recientes
        FROM licitacion
        "#,
    )
    .fetch_one(&state.pool)
    .await
    .map_err(|e| format!("db: {e}"))?;

    let declines: i64 = sqlx::query_scalar(
        "SELECT COUNT(*)::BIGINT FROM licitacion_decline WHERE resolved = FALSE",
    )
    .fetch_one(&state.pool)
    .await
    .map_err(|e| format!("db: {e}"))?;

    let activity_rows = sqlx::query(&format!(
        r#"
        SELECT
            u.id            AS user_id,
            u.nombre        AS user_nombre,
            u.email,
            COUNT(la.id) FILTER (WHERE la.active = TRUE)::INT AS assigned_count,
            MAX(l.titulo)   AS latest_titulo
        FROM app_user u
        LEFT JOIN licitacion_assignment la ON la.assignee_id = u.id AND la.active = TRUE
        LEFT JOIN licitacion l             ON l.id = la.licitacion_id
        WHERE u.role != 'admin' {team_scope}
        GROUP BY u.id, u.nombre, u.email
        ORDER BY assigned_count DESC, u.nombre
        "#,
    ))
    .fetch_all(&state.pool)
    .await
    .map_err(|e| format!("db: {e}"))?;

    let team_activity: Vec<serde_json::Value> = activity_rows
        .iter()
        .map(|r| {
            serde_json::json!({
                "user_id":        r.get::<i32, _>("user_id"),
                "nombre":         r.try_get::<String, _>("user_nombre").ok(),
                "email":          r.get::<String, _>("email"),
                "assigned_count": r.get::<i32, _>("assigned_count"),
                "latest_titulo":  r.try_get::<String, _>("latest_titulo").ok(),
            })
        })
        .collect();

    let decline_rows = sqlx::query(
        r#"
        SELECT
            d.id,
            d.licitacion_id,
            l.titulo,
            u.nombre AS user_nombre,
            d.reason,
            d.created_at::TEXT AS created_at
        FROM licitacion_decline d
        JOIN licitacion l  ON l.id = d.licitacion_id
        JOIN app_user u    ON u.id = d.user_id
        WHERE d.resolved = FALSE
        ORDER BY d.created_at DESC
        LIMIT 20
        "#,
    )
    .fetch_all(&state.pool)
    .await
    .map_err(|e| format!("db: {e}"))?;

    let declines_list: Vec<serde_json::Value> = decline_rows
        .iter()
        .map(|r| {
            serde_json::json!({
                "id":            r.get::<i32, _>("id"),
                "licitacion_id": r.get::<i64, _>("licitacion_id"),
                "titulo":        r.get::<String, _>("titulo"),
                "user_nombre":   r.try_get::<String, _>("user_nombre").ok(),
                "reason":        r.try_get::<String, _>("reason").ok(),
                "created_at":    r.get::<String, _>("created_at"),
            })
        })
        .collect();

    // ── Breakdown: importe + plazo (always global) ───────────────────────────────
    let bk_global = sqlx::query(
        r#"
        SELECT
          -- Plazo urgency (active licitaciones with a deadline)
          COUNT(*) FILTER (
            WHERE fecha_limite_oferta IS NOT NULL
              AND (fecha_limite_oferta::DATE - CURRENT_DATE) BETWEEN 0 AND 7
          )::INT                                         AS plazo_lt7,
          COUNT(*) FILTER (
            WHERE fecha_limite_oferta IS NOT NULL
              AND (fecha_limite_oferta::DATE - CURRENT_DATE) BETWEEN 8 AND 15
          )::INT                                         AS plazo_lt15,
          COUNT(*) FILTER (
            WHERE fecha_limite_oferta IS NOT NULL
              AND (fecha_limite_oferta::DATE - CURRENT_DATE) BETWEEN 16 AND 30
          )::INT                                         AS plazo_lt30,
          COUNT(*) FILTER (
            WHERE fecha_limite_oferta IS NULL
              OR  (fecha_limite_oferta::DATE - CURRENT_DATE) > 30
          )::INT                                         AS plazo_gt30,
          -- Importe ranges
          COUNT(*) FILTER (WHERE importe_licitacion < 50000)::INT            AS imp_lt50k,
          COUNT(*) FILTER (WHERE importe_licitacion BETWEEN 50000 AND 99999)::INT  AS imp_50_100k,
          COUNT(*) FILTER (WHERE importe_licitacion BETWEEN 100000 AND 249999)::INT AS imp_100_250k,
          COUNT(*) FILTER (WHERE importe_licitacion BETWEEN 250000 AND 499999)::INT AS imp_250_500k,
          COUNT(*) FILTER (WHERE importe_licitacion BETWEEN 500000 AND 999999)::INT AS imp_500k_1m,
          COUNT(*) FILTER (WHERE importe_licitacion >= 1000000)::INT         AS imp_gt1m
        FROM licitacion
        WHERE pipeline_stage NOT IN ('ganada','perdida','desierta')
        "#,
    )
    .fetch_one(&state.pool)
    .await
    .map_err(|e| format!("db breakdown global: {e}"))?;

    // ── Breakdown: ingram_estado + pipeline stage (scoped for vendedores) ─────────
    let bk = sqlx::query(&format!(
        r#"
        SELECT
          -- Ingram estado funnel
          COUNT(*) FILTER (WHERE ingram_estado = 'PENDIENTE SOLICITUD DE COTIZACIÓN A LA DIVISIÓN')::INT AS igr_pend_sol,
          COUNT(*) FILTER (WHERE ingram_estado = 'COTIZACIÓN SOLICITADA (A LA DIVISIÓN)')::INT           AS igr_cotiz_sol,
          COUNT(*) FILTER (WHERE ingram_estado = 'PENDIENTE ENVÍO DE COTIZACIÓN A CLIENTE')::INT         AS igr_pend_envio,
          COUNT(*) FILTER (WHERE ingram_estado = 'COTIZACIÓN ENVIADA A CLIENTE - X4A')::INT              AS igr_enviada,
          COUNT(*) FILTER (WHERE ingram_estado = 'RECHAZADO')::INT                                       AS igr_rechazado,
          -- Pipeline stage
          COUNT(*) FILTER (WHERE pipeline_stage = 'nueva')::INT                    AS stage_nueva,
          COUNT(*) FILTER (WHERE pipeline_stage = 'asignada')::INT                 AS stage_asignada,
          COUNT(*) FILTER (WHERE pipeline_stage = 'en_proceso')::INT               AS stage_en_proceso,
          COUNT(*) FILTER (WHERE pipeline_stage = 'cotizaciones_enviadas')::INT    AS stage_cotizaciones,
          COUNT(*) FILTER (WHERE pipeline_stage = 'presentada')::INT               AS stage_presentada
        FROM licitacion
        WHERE pipeline_stage NOT IN ('ganada','perdida','desierta') {pipeline_scope}
        "#,
    ))
    .fetch_one(&state.pool)
    .await
    .map_err(|e| format!("db breakdown: {e}"))?;

    // ── Breakdown: mercado vertical top-8 ────────────────────────────────────────
    let mercado_rows = sqlx::query(
        r#"
        SELECT mercado_vertical::TEXT AS label, COUNT(*)::INT AS cnt
        FROM licitacion
        WHERE pipeline_stage NOT IN ('ganada','perdida','desierta')
          AND mercado_vertical IS NOT NULL
        GROUP BY mercado_vertical
        ORDER BY cnt DESC
        LIMIT 8
        "#,
    )
    .fetch_all(&state.pool)
    .await
    .map_err(|e| format!("db mercado: {e}"))?;

    let mercado_breakdown: Vec<serde_json::Value> = mercado_rows
        .iter()
        .map(|r| serde_json::json!({
            "label": r.get::<String, _>("label"),
            "count": r.get::<i32, _>("cnt"),
        }))
        .collect();

    // ── Breakdown: comunidades autónomas top-10 ──────────────────────────────────
    let comunidad_rows = sqlx::query(
        r#"
        SELECT comunidad_autonoma::TEXT AS label, COUNT(*)::INT AS cnt
        FROM licitacion
        WHERE pipeline_stage NOT IN ('ganada','perdida','desierta')
          AND comunidad_autonoma IS NOT NULL
        GROUP BY comunidad_autonoma
        ORDER BY cnt DESC
        LIMIT 10
        "#,
    )
    .fetch_all(&state.pool)
    .await
    .map_err(|e| format!("db comunidad: {e}"))?;

    let comunidad_breakdown: Vec<serde_json::Value> = comunidad_rows
        .iter()
        .map(|r| serde_json::json!({
            "label": r.get::<String, _>("label"),
            "value": r.get::<String, _>("label"),
            "count": r.get::<i32, _>("cnt"),
        }))
        .collect();

    // ── Breakdown: cat1 (área tecnológica) ───────────────────────────────────────
    let cat1_rows = sqlx::query(
        r#"
        SELECT at.cat1 AS label, COUNT(l.id)::INT AS cnt
        FROM licitacion l
        JOIN area_tecnologica at ON at.id = l.area_tecnologica_id
        WHERE l.pipeline_stage NOT IN ('ganada','perdida','desierta')
        GROUP BY at.cat1
        ORDER BY cnt DESC
        "#,
    )
    .fetch_all(&state.pool)
    .await
    .map_err(|e| format!("db cat1: {e}"))?;

    let cat1_breakdown: Vec<serde_json::Value> = cat1_rows
        .iter()
        .map(|r| serde_json::json!({
            "label": r.get::<String, _>("label"),
            "count": r.get::<i32, _>("cnt"),
        }))
        .collect();

    let cat2_rows = sqlx::query(
        r#"
        SELECT at.cat2 AS label, COUNT(l.id)::INT AS cnt
        FROM licitacion l
        JOIN area_tecnologica at ON at.id = l.area_tecnologica_id
        WHERE l.pipeline_stage NOT IN ('ganada','perdida','desierta')
          AND at.cat2 <> ''
        GROUP BY at.cat2
        ORDER BY cnt DESC
        "#,
    )
    .fetch_all(&state.pool)
    .await
    .map_err(|e| format!("db cat2: {e}"))?;

    let cat2_breakdown: Vec<serde_json::Value> = cat2_rows
        .iter()
        .map(|r| serde_json::json!({
            "label": r.get::<String, _>("label"),
            "count": r.get::<i32, _>("cnt"),
        }))
        .collect();

    let cat3_rows = sqlx::query(
        r#"
        SELECT at.cat3 AS label, COUNT(l.id)::INT AS cnt
        FROM licitacion l
        JOIN area_tecnologica at ON at.id = l.area_tecnologica_id
        WHERE l.pipeline_stage NOT IN ('ganada','perdida','desierta')
          AND at.cat3 <> ''
        GROUP BY at.cat3
        ORDER BY cnt DESC
        "#,
    )
    .fetch_all(&state.pool)
    .await
    .map_err(|e| format!("db cat3: {e}"))?;

    let cat3_breakdown: Vec<serde_json::Value> = cat3_rows
        .iter()
        .map(|r| serde_json::json!({
            "label": r.get::<String, _>("label"),
            "count": r.get::<i32, _>("cnt"),
        }))
        .collect();

    let tipo_proc_rows = sqlx::query(
        r#"
        SELECT tipo_procedimiento::TEXT AS label, COUNT(id)::INT AS cnt
        FROM licitacion
        WHERE pipeline_stage NOT IN ('ganada','perdida','desierta')
          AND tipo_procedimiento IS NOT NULL
        GROUP BY tipo_procedimiento
        ORDER BY cnt DESC
        "#,
    )
    .fetch_all(&state.pool)
    .await
    .map_err(|e| format!("db tipo_proc: {e}"))?;

    let tipo_proc_breakdown: Vec<serde_json::Value> = tipo_proc_rows
        .iter()
        .map(|r| serde_json::json!({
            "label": r.get::<String, _>("label"),
            "count": r.get::<i32, _>("cnt"),
        }))
        .collect();

    let dur_row = sqlx::query(
        r#"
        SELECT
            COUNT(*) FILTER (WHERE duracion_meses <  6)::INT  AS lt6,
            COUNT(*) FILTER (WHERE duracion_meses >= 6  AND duracion_meses < 12)::INT AS d6_12,
            COUNT(*) FILTER (WHERE duracion_meses >= 12 AND duracion_meses < 18)::INT AS d12_18,
            COUNT(*) FILTER (WHERE duracion_meses >= 18 AND duracion_meses < 24)::INT AS d18_24,
            COUNT(*) FILTER (WHERE duracion_meses >= 24 AND duracion_meses < 36)::INT AS d24_36,
            COUNT(*) FILTER (WHERE duracion_meses >= 36 AND duracion_meses < 48)::INT AS d36_48,
            COUNT(*) FILTER (WHERE duracion_meses >= 48 AND duracion_meses < 60)::INT AS d48_60,
            COUNT(*) FILTER (WHERE duracion_meses >= 60 AND duracion_meses < 72)::INT AS d60_72,
            COUNT(*) FILTER (WHERE duracion_meses >= 72)::INT                         AS gt72
        FROM licitacion
        WHERE pipeline_stage NOT IN ('ganada','perdida','desierta')
          AND duracion_meses IS NOT NULL
        "#,
    )
    .fetch_one(&state.pool)
    .await
    .map_err(|e| format!("db duracion: {e}"))?;

    let stats = serde_json::json!({
        "activas":             row.get::<i64, _>("activas"),
        "sin_asignar":         row.get::<i64, _>("sin_asignar"),
        "declives_pendientes": declines,
        "nuevas_recientes":    row.get::<i64, _>("nuevas_recientes"),
        "team_activity":       team_activity,
        "pending_declines":    declines_list,
        "breakdown": {
            "plazo": [
                { "label": "< 7 días",    "value": "lt7",     "count": bk_global.get::<i32,_>("plazo_lt7")  },
                { "label": "7 – 15 días", "value": "lt15",    "count": bk_global.get::<i32,_>("plazo_lt15") },
                { "label": "16 – 30 días","value": "lt30",    "count": bk_global.get::<i32,_>("plazo_lt30") },
                { "label": "> 30 días",   "value": "gt30",    "count": bk_global.get::<i32,_>("plazo_gt30") },
            ],
            "importe": [
                { "label": "< 50K",        "value": "lt50k",    "count": bk_global.get::<i32,_>("imp_lt50k")    },
                { "label": "50K – 100K",   "value": "50-100k",  "count": bk_global.get::<i32,_>("imp_50_100k")  },
                { "label": "100K – 250K",  "value": "100-250k", "count": bk_global.get::<i32,_>("imp_100_250k") },
                { "label": "250K – 500K",  "value": "250-500k", "count": bk_global.get::<i32,_>("imp_250_500k") },
                { "label": "500K – 1M",    "value": "500k-1m",  "count": bk_global.get::<i32,_>("imp_500k_1m")  },
                { "label": "> 1M",         "value": "gt1m",     "count": bk_global.get::<i32,_>("imp_gt1m")     },
            ],
            "ingram_estado": [
                { "label": "Pend. Solicitud",   "value": "PENDIENTE SOLICITUD DE COTIZACIÓN A LA DIVISIÓN", "count": bk.get::<i32,_>("igr_pend_sol")   },
                { "label": "Cotiz. Solicitada", "value": "COTIZACIÓN SOLICITADA (A LA DIVISIÓN)",           "count": bk.get::<i32,_>("igr_cotiz_sol")  },
                { "label": "Pend. Envío",       "value": "PENDIENTE ENVÍO DE COTIZACIÓN A CLIENTE",         "count": bk.get::<i32,_>("igr_pend_envio") },
                { "label": "Enviada",           "value": "COTIZACIÓN ENVIADA A CLIENTE - X4A",              "count": bk.get::<i32,_>("igr_enviada")    },
                { "label": "Rechazado",         "value": "RECHAZADO",                                       "count": bk.get::<i32,_>("igr_rechazado")  },
            ],
            "pipeline_stage": [
                { "label": "Nueva",       "value": "nueva",                  "count": bk.get::<i32,_>("stage_nueva")        },
                { "label": "Asignada",    "value": "asignada",               "count": bk.get::<i32,_>("stage_asignada")     },
                { "label": "En proceso",  "value": "en_proceso",             "count": bk.get::<i32,_>("stage_en_proceso")   },
                { "label": "Cotiz. env.", "value": "cotizaciones_enviadas",  "count": bk.get::<i32,_>("stage_cotizaciones") },
                { "label": "Presentada",  "value": "presentada",             "count": bk.get::<i32,_>("stage_presentada")   },
            ],
            "comunidad":         comunidad_breakdown,
            "mercado":           mercado_breakdown,
            "cat1":              cat1_breakdown,
            "cat2":              cat2_breakdown,
            "cat3":              cat3_breakdown,
            "tipo_procedimiento": tipo_proc_breakdown,
            "duracion": [
                { "label": "< 6 meses",    "value": "lt6",    "count": dur_row.get::<i32,_>("lt6")    },
                { "label": "6 – 12",       "value": "d6_12",  "count": dur_row.get::<i32,_>("d6_12")  },
                { "label": "12 – 18",      "value": "d12_18", "count": dur_row.get::<i32,_>("d12_18") },
                { "label": "18 – 24",      "value": "d18_24", "count": dur_row.get::<i32,_>("d18_24") },
                { "label": "24 – 36",      "value": "d24_36", "count": dur_row.get::<i32,_>("d24_36") },
                { "label": "36 – 48",      "value": "d36_48", "count": dur_row.get::<i32,_>("d36_48") },
                { "label": "48 – 60",      "value": "d48_60", "count": dur_row.get::<i32,_>("d48_60") },
                { "label": "60 – 72",      "value": "d60_72", "count": dur_row.get::<i32,_>("d60_72") },
                { "label": "> 72 meses",   "value": "gt72",   "count": dur_row.get::<i32,_>("gt72")   },
            ],
        },
    });

    json(200, &stats.to_string())
}

// ── GET /licitaciones/mine  (vendedor) ────────────────────────────────────────

pub async fn my_licitaciones(
    state: Arc<AppState>,
    event: Request,
) -> Result<Response<Body>, Error> {
    let claims = bail!(require_auth(&event, &state.jwt_secret));

    use crate::routes::licitaciones::LicitacionSummary;
    let list = sqlx::query_as::<_, LicitacionSummary>(
        r#"
        SELECT
            l.id,
            l.fecha,
            l.titulo,
            l.numero_expediente,
            l.importe_licitacion::FLOAT8              AS importe_licitacion,
            l.valor_estimado::FLOAT8                  AS valor_estimado,
            l.estado::TEXT                            AS estado,
            COALESCE(l.pipeline_stage::TEXT, 'nueva') AS pipeline_stage,
            l.owner_id,
            l.tipo_procedimiento::TEXT                AS tipo_procedimiento,
            l.tipo_tramitacion,
            l.comunidad_autonoma::TEXT                AS comunidad_autonoma,
            l.provincia,
            l.mercado_vertical::TEXT                  AS mercado_vertical,
            l.plazo_oferta_estado::TEXT               AS plazo_oferta_estado,
            l.fecha_limite_oferta,
            l.duracion_meses,
            l.prorrogas_meses,
            l.puntos_precio,
            l.puntos_mejoras,
            l.puntos_subjetivos,
            (SELECT STRING_AGG(lc.cpv_code || ' - ' || c.descripcion, '; ' ORDER BY lc.cpv_code)
             FROM licitacion_cpv lc
             JOIN cpv_code c ON c.code = lc.cpv_code
             WHERE lc.licitacion_id = l.id)           AS cpv_label,
            l.created_at,
            l.ingram_estado,
            l.ingram_owner,
            l.cotizacion_solicitada_a,
            la.assignee_id,
            u.nombre                                  AS assignee_nombre,
            o.nombre                                  AS organismo_nombre
        FROM licitacion l
        JOIN licitacion_assignment la ON la.licitacion_id = l.id AND la.active = TRUE
        LEFT JOIN app_user u     ON u.id = la.assignee_id
        LEFT JOIN organismo o    ON o.id = l.organismo_id
        WHERE la.assignee_id = $1
        ORDER BY l.fecha_limite_oferta ASC NULLS LAST, l.id DESC
        "#,
    )
    .bind(claims.sub)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| format!("db: {e}"))?;

    json(200, &serde_json::json!({"data": list}).to_string())
}

// ── GET /team/workload  (admin only) ─────────────────────────────────────────
// Returns every non-admin user with their currently active assigned licitaciones.

pub async fn team_workload(
    state: Arc<AppState>,
    event: Request,
) -> Result<Response<Body>, Error> {
    bail!(require_admin(&event, &state.jwt_secret));

    let rows = sqlx::query(
        r#"
        SELECT
            u.id            AS user_id,
            u.nombre        AS user_nombre,
            u.email,
            l.id            AS lic_id,
            l.titulo,
            l.importe_licitacion::FLOAT8   AS importe,
            l.pipeline_stage::TEXT         AS pipeline_stage,
            l.ingram_estado::TEXT          AS ingram_estado,
            l.fecha_limite_oferta
        FROM app_user u
        LEFT JOIN licitacion_assignment la ON la.assignee_id = u.id AND la.active = TRUE
        LEFT JOIN licitacion l             ON l.id = la.licitacion_id
        WHERE u.role != 'admin'
        ORDER BY u.nombre, l.fecha_limite_oferta ASC NULLS LAST
        "#,
    )
    .fetch_all(&state.pool)
    .await
    .map_err(|e| format!("db workload: {e}"))?;

    // Group by user, preserving ORDER BY u.nombre from the query
    let mut order: Vec<i32> = Vec::new();
    let mut map: std::collections::HashMap<i32, serde_json::Value> = std::collections::HashMap::new();
    for r in &rows {
        let uid: i32   = r.get("user_id");
        let nombre: Option<String> = r.try_get("user_nombre").ok().flatten();
        let email: String = r.get("email");
        if !map.contains_key(&uid) {
            order.push(uid);
            map.insert(uid, serde_json::json!({
                "user_id": uid,
                "nombre":  nombre,
                "email":   email,
                "licitaciones": [],
            }));
        }
        let lic_id: Option<i64> = r.try_get("lic_id").ok();
        if let Some(id) = lic_id {
            map.get_mut(&uid).unwrap()["licitaciones"].as_array_mut().unwrap().push(serde_json::json!({
                "id":                  id,
                "titulo":              r.get::<String, _>("titulo"),
                "importe":             r.try_get::<f64, _>("importe").ok(),
                "pipeline_stage":      r.try_get::<String, _>("pipeline_stage").unwrap_or_default(),
                "ingram_estado":       r.try_get::<String, _>("ingram_estado").ok(),
                "fecha_limite_oferta": r.try_get::<String, _>("fecha_limite_oferta").ok(),
            }));
        }
    }

    let result: Vec<serde_json::Value> = order.iter().map(|id| map.remove(id).unwrap()).collect();
    json(200, &serde_json::json!(result).to_string())
}

// ── Helpers ───────────────────────────────────────────────────────────────────

pub fn require_auth(
    event: &Request,
    secret: &str,
) -> Result<crate::auth::Claims, Response<Body>> {
    let token = auth::bearer_from_request(event)
        .ok_or_else(|| auth::unauthorized("Autenticación requerida"))?;
    auth::verify(&token, secret).map_err(|_| auth::unauthorized("Token inválido"))
}

fn require_admin(
    event: &Request,
    secret: &str,
) -> Result<crate::auth::Claims, Response<Body>> {
    let claims = require_auth(event, secret)?;
    if claims.role != "admin" {
        return Err(auth::unauthorized("Solo administradores"));
    }
    Ok(claims)
}

fn parse_body<T: serde::de::DeserializeOwned>(event: &Request) -> Result<T, Response<Body>> {
    let raw = match event.body() {
        Body::Text(s)   => s.as_bytes().to_vec(),
        Body::Binary(b) => b.clone(),
        Body::Empty => {
            return Err(Response::builder()
                .status(400)
                .header("content-type", "application/json")
                .body(Body::Text(r#"{"error":"empty body"}"#.to_string()))
                .unwrap());
        }
    };
    serde_json::from_slice(&raw).map_err(|e| {
        Response::builder()
            .status(400)
            .header("content-type", "application/json")
            .body(Body::Text(format!(r#"{{"error":"{}"}}"#, e)))
            .unwrap()
    })
}

fn json(status: u16, body: &str) -> Result<Response<Body>, Error> {
    Ok(Response::builder()
        .status(status)
        .header("content-type", "application/json")
        .body(Body::Text(body.to_string()))
        .map_err(Box::new)?)
}
