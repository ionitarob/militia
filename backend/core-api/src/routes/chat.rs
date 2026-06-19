use std::sync::Arc;
use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64};
use lambda_http::{Body, Error, Request, Response};
use serde::Deserialize;
use aws_sdk_bedrockruntime::primitives::Blob;

use crate::AppState;
use crate::routes::pipeline::require_auth;

pub const MODEL_ID: &str = "eu.anthropic.claude-sonnet-4-6";
pub const MAX_HISTORY: i64 = 20;
pub const MAX_DOC_BYTES: usize = 4 * 1024 * 1024;
pub const MAX_DOCS: usize = 5;

pub const SYSTEM_PROMPT: &str = "Eres Liti, el asistente IA experto en licitaciones públicas españolas para el equipo comercial de Ingram Micro. \
Tu misión es ahorrarle tiempo al equipo: lees, analizas y extraes la información relevante de los documentos de la licitación por ellos. \
\n\n\
COMPORTAMIENTO CON DOCUMENTOS:\n\
- Cuando se adjuntan documentos (pliegos, anuncios, anexos, etc.), LÉELOS COMPLETAMENTE antes de responder.\n\
- Extrae siempre la información específica que te preguntan directamente del contenido de los documentos.\n\
- Si la pregunta es sobre especificaciones técnicas, marcas, modelos, requisitos, criterios de valoración o cualquier detalle concreto, \
búscalo en los documentos y cita lo que encuentres literalmente.\n\
- NUNCA digas 'descarga el pliego' ni 'consulta el documento'. Tú eres quien lee los documentos; el usuario no tiene que hacerlo.\n\
- Si algo genuinamente no aparece en ningún documento adjunto, dilo claramente y explica qué sí encontraste.\n\
\n\
TONO Y FORMATO:\n\
- Responde en español, de forma directa y concisa.\n\
- Usa listas y negrita para resaltar datos clave (marcas, cantidades, plazos, importes).\n\
- Nunca inventes datos. Si no está en los documentos, dilo.\n\
- No uses frases de relleno. Ve directo al grano.\n\
\n\
HERRAMIENTAS:\n\
- Usa las herramientas solo para buscar datos de pipeline, estadísticas o información que no esté ya en el contexto de la conversación.";

#[derive(Deserialize)]
struct ChatRequest {
    message: String,
    session_id: Option<String>,
    licitacion_id: Option<i64>,
}

pub struct DocBlob {
    pub nombre: String,
    pub media_type: String,
    pub data: Vec<u8>,
}

pub async fn fetch_licitacion_docs(state: &AppState, licitacion_id: i64) -> Vec<DocBlob> {
    let mut docs: Vec<DocBlob> = Vec::new();

    // 1. Portal documents (licitacion_documento)
    if let Ok(rows) = sqlx::query_as::<_, (String, String, Option<String>)>(
        "SELECT nombre, s3_key, content_type FROM licitacion_documento WHERE licitacion_id = $1 ORDER BY id ASC"
    )
    .bind(licitacion_id as i32)
    .fetch_all(&state.pool)
    .await
    {
        for (nombre, s3_key, ct) in rows {
            if docs.len() >= MAX_DOCS { break; }
            if let Some(blob) = download_s3_doc(state, &s3_key, &nombre, ct.as_deref()).await {
                docs.push(blob);
            }
        }
    }

    // 2. Internal attachments (cotizacion_adjunto)
    if docs.len() < MAX_DOCS {
        if let Ok(rows) = sqlx::query_as::<_, (String, String, Option<String>)>(
            "SELECT nombre, s3_key, content_type FROM cotizacion_adjunto WHERE licitacion_id = $1 ORDER BY id ASC"
        )
        .bind(licitacion_id as i32)
        .fetch_all(&state.pool)
        .await
        {
            for (nombre, s3_key, ct) in rows {
                if docs.len() >= MAX_DOCS { break; }
                if let Some(blob) = download_s3_doc(state, &s3_key, &nombre, ct.as_deref()).await {
                    docs.push(blob);
                }
            }
        }
    }

    docs
}

pub async fn download_s3_doc(state: &AppState, s3_key: &str, nombre: &str, content_type: Option<&str>) -> Option<DocBlob> {
    let media_type = match content_type {
        Some(ct) if ct.contains("pdf") => "application/pdf",
        Some(ct) if ct.contains("word") || ct.contains("docx") => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        Some(ct) if ct.contains("text") => "text/plain",
        _ if nombre.to_lowercase().ends_with(".pdf") => "application/pdf",
        _ if nombre.to_lowercase().ends_with(".txt") => "text/plain",
        _ => "application/pdf", // assume PDF for unknown types
    };

    let result = state.s3_client
        .get_object()
        .bucket(&state.s3_bucket)
        .key(s3_key)
        .send()
        .await;

    let output = result.ok()?;
    let bytes = output.body.collect().await.ok()?.into_bytes();
    if bytes.len() > MAX_DOC_BYTES {
        return None; // skip oversized files
    }

    Some(DocBlob {
        nombre: nombre.to_string(),
        media_type: media_type.to_string(),
        data: bytes.to_vec(),
    })
}

pub async fn send(state: Arc<AppState>, event: Request) -> Result<Response<Body>, Error> {
    let claims = match require_auth(&event, &state.jwt_secret) {
        Ok(c) => c,
        Err(r) => return Ok(r),
    };

    let body_bytes = match event.body() {
        Body::Text(s)   => s.as_bytes().to_vec(),
        Body::Binary(b) => b.clone(),
        Body::Empty     => return json(400, r#"{"error":"empty body"}"#),
    };
    let req: ChatRequest = match serde_json::from_slice(&body_bytes) {
        Ok(r)  => r,
        Err(_) => return json(400, r#"{"error":"invalid json"}"#),
    };
    if req.message.trim().is_empty() {
        return json(400, r#"{"error":"message is empty"}"#);
    }

    // Load or create session
    let session_id: uuid::Uuid = if let Some(sid) = &req.session_id {
        match sid.parse::<uuid::Uuid>() {
            Ok(u) => {
                let exists: bool = sqlx::query_scalar(
                    "SELECT EXISTS(SELECT 1 FROM chat_session WHERE id = $1 AND user_id = $2)"
                )
                .bind(u)
                .bind(claims.sub)
                .fetch_one(&state.pool)
                .await
                .unwrap_or(false);
                if exists { u } else { create_session(&state.pool, claims.sub).await? }
            }
            Err(_) => create_session(&state.pool, claims.sub).await?,
        }
    } else {
        create_session(&state.pool, claims.sub).await?
    };

    // Build message list (history + new user message)
    let mut messages = load_history(&state.pool, session_id).await?;

    // If licitacion_id provided, fetch and embed documents (works on fresh sessions
    // AND mid-session context switches when user navigates to a different licitacion)
    if let Some(lic_id) = req.licitacion_id {
        let docs = fetch_licitacion_docs(&state, lic_id).await;
        if !docs.is_empty() {
            let mut content: Vec<serde_json::Value> = docs.into_iter().map(|d| {
                serde_json::json!({
                    "type": "document",
                    "source": {
                        "type": "base64",
                        "media_type": d.media_type,
                        "data": BASE64.encode(&d.data),
                    },
                    "title": d.nombre,
                })
            }).collect();
            content.push(serde_json::json!({"type": "text", "text": req.message.trim()}));
            messages.push(serde_json::json!({"role": "user", "content": content}));
        } else {
            messages.push(serde_json::json!({"role": "user", "content": req.message}));
        }
    } else {
        messages.push(serde_json::json!({"role": "user", "content": req.message}));
    }

    // Agentic loop
    let reply = bedrock_loop(&state, &mut messages).await?;

    // Persist
    save_message(&state.pool, session_id, "user", &req.message).await?;
    save_message(&state.pool, session_id, "assistant", &reply).await?;
    let _ = sqlx::query("UPDATE chat_session SET updated_at = NOW() WHERE id = $1")
        .bind(session_id)
        .execute(&state.pool)
        .await;

    json(200, &serde_json::to_string(&serde_json::json!({
        "session_id": session_id.to_string(),
        "reply":      reply,
    }))?)
}

// ── Bedrock agentic loop ──────────────────────────────────────────────────────

pub async fn bedrock_loop(
    state: &AppState,
    messages: &mut Vec<serde_json::Value>,
) -> Result<String, Error> {
    for _ in 0..3 {
        let request = serde_json::json!({
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 4096,
            "system": SYSTEM_PROMPT,
            "messages": messages,
            "tools": tool_defs(),
        });

        let body_bytes = serde_json::to_vec(&request)
            .map_err(|e| format!("json serialize: {e}"))?;

        let resp = state.bedrock
            .invoke_model()
            .model_id(MODEL_ID)
            .content_type("application/json")
            .accept("application/json")
            .body(Blob::new(body_bytes))
            .send()
            .await
            .map_err(|e| format!("bedrock invoke: {e}"))?;

        let resp_json: serde_json::Value = serde_json::from_slice(resp.body().as_ref())
            .map_err(|e| format!("bedrock parse: {e}"))?;

        let content = resp_json["content"].clone();
        let stop_reason = resp_json["stop_reason"].as_str().unwrap_or("end_turn");

        // Record assistant turn
        messages.push(serde_json::json!({"role": "assistant", "content": content}));

        if stop_reason != "tool_use" {
            // Extract the text reply
            let text = content.as_array()
                .and_then(|arr| arr.iter().find(|b| b["type"] == "text"))
                .and_then(|b| b["text"].as_str())
                .unwrap_or("Sin respuesta disponible.")
                .to_string();
            return Ok(text);
        }

        // Execute tool calls
        let empty = vec![];
        let tool_blocks = content.as_array().unwrap_or(&empty);
        let mut tool_results: Vec<serde_json::Value> = Vec::new();

        for block in tool_blocks {
            if block["type"] != "tool_use" { continue; }
            let use_id = block["id"].as_str().unwrap_or("");
            let name   = block["name"].as_str().unwrap_or("");
            let input  = &block["input"];
            let result = execute_tool(&state.pool, name, input).await;
            tool_results.push(serde_json::json!({
                "type":        "tool_result",
                "tool_use_id": use_id,
                "content":     result,
            }));
        }

        messages.push(serde_json::json!({"role": "user", "content": tool_results}));
    }

    Err("bedrock loop exceeded max iterations".into())
}

// ── Tool definitions (JSON schema) ───────────────────────────────────────────

pub fn tool_defs() -> serde_json::Value {
    serde_json::json!([
        {
            "name": "buscar_licitaciones",
            "description": "Busca licitaciones públicas por texto, mercado, CC.AA, estado o importe.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "query":              {"type": "string",  "description": "Texto libre (título o expediente)"},
                    "mercado":            {"type": "string",  "description": "Mercado vertical (ej: Telecom, Healthcare)"},
                    "comunidad_autonoma": {"type": "string",  "description": "Comunidad autónoma (ej: Cataluña, Madrid)"},
                    "estado":             {"type": "string",  "description": "activas | caducadas | todas (default: activas)"},
                    "importe_max":        {"type": "number",  "description": "Importe máximo en euros"},
                    "limit":              {"type": "integer", "description": "Resultados a devolver (máx 20)"}
                },
                "required": []
            }
        },
        {
            "name": "buscar_adjudicaciones",
            "description": "Busca adjudicaciones por texto, mercado o rango de días recientes.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "query":        {"type": "string",  "description": "Texto libre (título)"},
                    "mercado":      {"type": "string",  "description": "Mercado vertical"},
                    "ultimos_dias": {"type": "integer", "description": "Filtrar últimos N días"},
                    "limit":        {"type": "integer", "description": "Resultados a devolver (máx 20)"}
                },
                "required": []
            }
        },
        {
            "name": "detalle_licitacion",
            "description": "Obtiene todos los detalles de una licitación por número de expediente o título.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "query": {"type": "string", "description": "Número de expediente o parte del título"}
                },
                "required": ["query"]
            }
        },
        {
            "name": "estadisticas_pipeline",
            "description": "Estadísticas generales: licitaciones activas/caducadas, adjudicaciones totales y recientes, distribución del pipeline.",
            "input_schema": {
                "type": "object",
                "properties": {},
                "required": []
            }
        }
    ])
}

// ── Tool executors ────────────────────────────────────────────────────────────

pub async fn execute_tool(pool: &sqlx::PgPool, name: &str, input: &serde_json::Value) -> String {
    match name {
        "buscar_licitaciones"   => tool_buscar_licitaciones(pool, input).await,
        "buscar_adjudicaciones" => tool_buscar_adjudicaciones(pool, input).await,
        "detalle_licitacion"    => tool_detalle_licitacion(pool, input).await,
        "estadisticas_pipeline" => tool_estadisticas(pool).await,
        _                       => format!("Herramienta desconocida: {name}"),
    }
}

async fn tool_buscar_licitaciones(pool: &sqlx::PgPool, input: &serde_json::Value) -> String {
    let query       = input["query"].as_str().unwrap_or("");
    let mercado     = input["mercado"].as_str();
    let ccaa        = input["comunidad_autonoma"].as_str();
    let estado      = input["estado"].as_str().unwrap_or("activas");
    let importe_max = input["importe_max"].as_f64();
    let limit: i64  = input["limit"].as_i64().unwrap_or(10).min(20);

    let deadline_filter = match estado {
        "activas"   => "AND (l.fecha_limite_oferta IS NULL OR l.fecha_limite_oferta::DATE >= CURRENT_DATE)",
        "caducadas" => "AND (l.fecha_limite_oferta IS NOT NULL AND l.fecha_limite_oferta::DATE < CURRENT_DATE)",
        _           => "",
    };

    let sql = format!(r#"
        SELECT l.titulo, l.numero_expediente, l.importe_licitacion,
               l.fecha_limite_oferta, l.pipeline_stage, l.comunidad_autonoma,
               l.mercado_vertical, o.nombre AS organismo
        FROM licitacion l
        LEFT JOIN organismo o ON o.id = l.organismo_id
        WHERE ($1 = '' OR l.titulo ILIKE '%' || $1 || '%' OR l.numero_expediente ILIKE '%' || $1 || '%')
          AND ($2::TEXT IS NULL OR l.mercado_vertical::TEXT = $2)
          AND ($3::TEXT IS NULL OR l.comunidad_autonoma::TEXT = $3)
          AND ($4::FLOAT8 IS NULL OR l.importe_licitacion <= $4)
          {deadline_filter}
        ORDER BY l.fecha_limite_oferta ASC NULLS LAST
        LIMIT $5
    "#);

    match sqlx::query(&sql)
        .bind(query).bind(mercado).bind(ccaa).bind(importe_max).bind(limit)
        .fetch_all(pool).await
    {
        Err(e) => format!("Error: {e}"),
        Ok(rows) if rows.is_empty() => "No se encontraron licitaciones.".to_string(),
        Ok(rows) => {
            use sqlx::Row;
            let lines: Vec<String> = rows.iter().map(|r| {
                let titulo:   String             = r.try_get("titulo").unwrap_or_default();
                let exp:      String             = r.try_get("numero_expediente").unwrap_or_default();
                let importe:  Option<f64>        = r.try_get("importe_licitacion").ok().flatten();
                let fecha:    Option<chrono::NaiveDate> = r.try_get("fecha_limite_oferta").ok().flatten();
                let stage:    Option<String>     = r.try_get("pipeline_stage").ok().flatten();
                let org:      Option<String>     = r.try_get("organismo").ok().flatten();
                let mercado_v: Option<String>    = r.try_get("mercado_vertical").ok().flatten();
                format!("• [{}] {} | {} | Plazo: {} | Stage: {} | {} | {}",
                    exp, titulo,
                    importe.map(|v| format!("{:.0}€", v)).unwrap_or("-".into()),
                    fecha.map(|d| d.to_string()).unwrap_or("-".into()),
                    stage.as_deref().unwrap_or("nueva"),
                    org.as_deref().unwrap_or("-"),
                    mercado_v.as_deref().unwrap_or("-"),
                )
            }).collect();
            format!("{} licitaciones:\n{}", lines.len(), lines.join("\n"))
        }
    }
}

async fn tool_buscar_adjudicaciones(pool: &sqlx::PgPool, input: &serde_json::Value) -> String {
    let query   = input["query"].as_str().unwrap_or("");
    let mercado = input["mercado"].as_str();
    let dias    = input["ultimos_dias"].as_i64().map(|d| d as i32);
    let limit: i64 = input["limit"].as_i64().unwrap_or(10).min(20);

    match sqlx::query(r#"
        SELECT a.titulo, a.fecha_adjudicacion, a.importe_adjudicado,
               o.nombre AS organismo, adj.nombre AS adjudicatario, a.mercado_vertical
        FROM adjudicacion a
        LEFT JOIN organismo     o   ON o.id   = a.organismo_id
        LEFT JOIN adjudicatario adj ON adj.id = a.adjudicatario_id
        WHERE ($1 = '' OR a.titulo ILIKE '%' || $1 || '%')
          AND ($2::TEXT IS NULL OR a.mercado_vertical::TEXT = $2)
          AND ($3::INT IS NULL OR a.fecha_adjudicacion >= CURRENT_DATE - ($3 || ' days')::INTERVAL)
        ORDER BY a.fecha_adjudicacion DESC NULLS LAST
        LIMIT $4
    "#)
    .bind(query).bind(mercado).bind(dias).bind(limit)
    .fetch_all(pool).await
    {
        Err(e) => format!("Error: {e}"),
        Ok(rows) if rows.is_empty() => "No se encontraron adjudicaciones.".to_string(),
        Ok(rows) => {
            use sqlx::Row;
            let lines: Vec<String> = rows.iter().map(|r| {
                let titulo:   String = r.try_get("titulo").unwrap_or_default();
                let importe:  Option<f64> = r.try_get("importe_adjudicado").ok().flatten();
                let fecha:    Option<chrono::NaiveDate> = r.try_get("fecha_adjudicacion").ok().flatten();
                let adj:      Option<String> = r.try_get("adjudicatario").ok().flatten();
                let org:      Option<String> = r.try_get("organismo").ok().flatten();
                format!("• {} | {} | {} | {} | {}",
                    titulo,
                    adj.as_deref().unwrap_or("-"),
                    importe.map(|v| format!("{:.0}€", v)).unwrap_or("-".into()),
                    fecha.map(|d| d.to_string()).unwrap_or("-".into()),
                    org.as_deref().unwrap_or("-"),
                )
            }).collect();
            format!("{} adjudicaciones:\n{}", lines.len(), lines.join("\n"))
        }
    }
}

async fn tool_detalle_licitacion(pool: &sqlx::PgPool, input: &serde_json::Value) -> String {
    let query = input["query"].as_str().unwrap_or("");
    match sqlx::query(r#"
        SELECT l.titulo, l.numero_expediente, l.descripcion,
               l.importe_licitacion, l.valor_estimado,
               l.fecha_publicacion, l.fecha_limite_oferta, l.pipeline_stage,
               l.comunidad_autonoma, l.mercado_vertical, l.tipo_procedimiento,
               l.tipo_tramitacion, l.duracion_meses, l.va_con_pliego,
               o.nombre AS organismo
        FROM licitacion l
        LEFT JOIN organismo o ON o.id = l.organismo_id
        WHERE l.numero_expediente ILIKE '%' || $1 || '%' OR l.titulo ILIKE '%' || $1 || '%'
        ORDER BY l.created_at DESC
        LIMIT 1
    "#)
    .bind(query)
    .fetch_optional(pool).await
    {
        Err(e)      => format!("Error: {e}"),
        Ok(None)    => format!("No encontrada: '{query}'"),
        Ok(Some(r)) => {
            use sqlx::Row;
            let titulo:   String = r.try_get("titulo").unwrap_or_default();
            let exp:      String = r.try_get("numero_expediente").unwrap_or_default();
            let desc:     Option<String> = r.try_get("descripcion").ok().flatten();
            let importe:  Option<f64>    = r.try_get("importe_licitacion").ok().flatten();
            let vest:     Option<f64>    = r.try_get("valor_estimado").ok().flatten();
            let pub_d:    Option<chrono::NaiveDate> = r.try_get("fecha_publicacion").ok().flatten();
            let dead:     Option<chrono::NaiveDate> = r.try_get("fecha_limite_oferta").ok().flatten();
            let stage:    Option<String> = r.try_get("pipeline_stage").ok().flatten();
            let ccaa:     Option<String> = r.try_get("comunidad_autonoma").ok().flatten();
            let mercado:  Option<String> = r.try_get("mercado_vertical").ok().flatten();
            let proc_t:   Option<String> = r.try_get("tipo_procedimiento").ok().flatten();
            let tram:     Option<String> = r.try_get("tipo_tramitacion").ok().flatten();
            let dur:      Option<i16>    = r.try_get("duracion_meses").ok().flatten();
            let pliego:   Option<bool>   = r.try_get("va_con_pliego").ok().flatten();
            let org:      Option<String> = r.try_get("organismo").ok().flatten();
            format!(
                "Título: {titulo}\nExpediente: {exp}\nOrganismo: {}\nImporte: {}\nValor estimado: {}\nPublicación: {}\nPlazo: {}\nStage: {}\nCC.AA: {}\nMercado: {}\nProcedimiento: {}\nTramitación: {}\nDuración: {} meses\nCon pliego: {}\nDescripción: {}",
                org.as_deref().unwrap_or("-"),
                importe.map(|v| format!("{:.0}€", v)).unwrap_or("-".into()),
                vest.map(|v| format!("{:.0}€", v)).unwrap_or("-".into()),
                pub_d.map(|d| d.to_string()).unwrap_or("-".into()),
                dead.map(|d| d.to_string()).unwrap_or("-".into()),
                stage.as_deref().unwrap_or("nueva"),
                ccaa.as_deref().unwrap_or("-"),
                mercado.as_deref().unwrap_or("-"),
                proc_t.as_deref().unwrap_or("-"),
                tram.as_deref().unwrap_or("-"),
                dur.map(|d| d.to_string()).unwrap_or("-".into()),
                pliego.map(|b| if b { "Sí" } else { "No" }).unwrap_or("-"),
                desc.as_deref().unwrap_or("Sin descripción"),
            )
        }
    }
}

async fn tool_estadisticas(pool: &sqlx::PgPool) -> String {
    let activas: i64 = sqlx::query_scalar(
        "SELECT COUNT(*)::BIGINT FROM licitacion WHERE fecha_limite_oferta IS NULL OR fecha_limite_oferta::DATE >= CURRENT_DATE"
    ).fetch_one(pool).await.unwrap_or(0);

    let caducadas: i64 = sqlx::query_scalar(
        "SELECT COUNT(*)::BIGINT FROM licitacion WHERE fecha_limite_oferta IS NOT NULL AND fecha_limite_oferta::DATE < CURRENT_DATE"
    ).fetch_one(pool).await.unwrap_or(0);

    let adj_total: i64 = sqlx::query_scalar(
        "SELECT COUNT(*)::BIGINT FROM adjudicacion"
    ).fetch_one(pool).await.unwrap_or(0);

    let adj_48h: i64 = sqlx::query_scalar(
        "SELECT COUNT(*)::BIGINT FROM adjudicacion WHERE fecha_adjudicacion >= CURRENT_DATE - INTERVAL '2 days'"
    ).fetch_one(pool).await.unwrap_or(0);

    let pipeline: Vec<(String, i64)> = sqlx::query_as(
        "SELECT pipeline_stage::TEXT, COUNT(*)::BIGINT FROM licitacion WHERE pipeline_stage IS NOT NULL GROUP BY pipeline_stage ORDER BY COUNT(*) DESC"
    ).fetch_all(pool).await.unwrap_or_default();

    let pipeline_str: Vec<String> = pipeline.iter().map(|(s, c)| format!("  {s}: {c}")).collect();

    format!(
        "Activas: {activas} | Caducadas: {caducadas}\nAdjudicaciones: {adj_total} (48h: {adj_48h})\nPipeline:\n{}",
        if pipeline_str.is_empty() { "  Sin datos".into() } else { pipeline_str.join("\n") }
    )
}

// ── DB helpers ────────────────────────────────────────────────────────────────

pub async fn create_session(pool: &sqlx::PgPool, user_id: i32) -> Result<uuid::Uuid, Error> {
    sqlx::query_scalar("INSERT INTO chat_session (user_id) VALUES ($1) RETURNING id")
        .bind(user_id)
        .fetch_one(pool)
        .await
        .map_err(|e| format!("create session: {e}").into())
}

pub async fn load_history(pool: &sqlx::PgPool, session_id: uuid::Uuid) -> Result<Vec<serde_json::Value>, Error> {
    let rows: Vec<(String, String)> = sqlx::query_as(
        "SELECT role, content FROM chat_message WHERE session_id = $1 ORDER BY created_at ASC LIMIT $2"
    )
    .bind(session_id)
    .bind(MAX_HISTORY)
    .fetch_all(pool)
    .await
    .map_err(|e| format!("load history: {e}"))?;

    Ok(rows.into_iter().map(|(role, content)| serde_json::json!({"role": role, "content": content})).collect())
}

pub async fn save_message(pool: &sqlx::PgPool, session_id: uuid::Uuid, role: &str, content: &str) -> Result<(), Error> {
    sqlx::query("INSERT INTO chat_message (session_id, role, content) VALUES ($1, $2, $3)")
        .bind(session_id).bind(role).bind(content)
        .execute(pool)
        .await
        .map_err(|e| format!("save message: {e}"))?;
    Ok(())
}

// ── Session list / history ────────────────────────────────────────────────────

pub async fn list_sessions(state: Arc<AppState>, event: Request) -> Result<Response<Body>, Error> {
    let claims = match require_auth(&event, &state.jwt_secret) {
        Ok(c) => c,
        Err(r) => return Ok(r),
    };

    let rows: Vec<(uuid::Uuid, Option<String>, chrono::DateTime<chrono::Utc>, i64)> = sqlx::query_as(
        r#"
        SELECT s.id,
               (SELECT content FROM chat_message WHERE session_id = s.id AND role = 'user' ORDER BY created_at ASC LIMIT 1),
               s.updated_at,
               (SELECT COUNT(*) FROM chat_message WHERE session_id = s.id)::BIGINT
        FROM chat_session s
        WHERE s.user_id = $1
        ORDER BY s.updated_at DESC
        LIMIT 50
        "#,
    )
    .bind(claims.sub)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| format!("list sessions: {e}"))?;

    let items: Vec<serde_json::Value> = rows
        .into_iter()
        .map(|(id, first_msg, updated_at, count)| {
            let preview = first_msg
                .as_deref()
                .map(|s| if s.len() > 80 { format!("{}…", &s[..80]) } else { s.to_string() })
                .unwrap_or_else(|| "Nueva conversación".to_string());
            serde_json::json!({
                "id": id.to_string(),
                "preview": preview,
                "updated_at": updated_at.to_rfc3339(),
                "message_count": count,
            })
        })
        .collect();

    json(200, &serde_json::to_string(&items)?)
}

pub async fn get_session_messages(
    state: Arc<AppState>,
    event: Request,
    session_id: uuid::Uuid,
) -> Result<Response<Body>, Error> {
    let claims = match require_auth(&event, &state.jwt_secret) {
        Ok(c) => c,
        Err(r) => return Ok(r),
    };

    let exists: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM chat_session WHERE id = $1 AND user_id = $2)",
    )
    .bind(session_id)
    .bind(claims.sub)
    .fetch_one(&state.pool)
    .await
    .unwrap_or(false);

    if !exists {
        return json(404, r#"{"error":"session not found"}"#);
    }

    let rows: Vec<(String, String, chrono::DateTime<chrono::Utc>)> = sqlx::query_as(
        "SELECT role, content, created_at FROM chat_message WHERE session_id = $1 ORDER BY created_at ASC",
    )
    .bind(session_id)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| format!("get session: {e}"))?;

    let messages: Vec<serde_json::Value> = rows
        .into_iter()
        .map(|(role, content, created_at)| {
            serde_json::json!({ "role": role, "content": content, "created_at": created_at.to_rfc3339() })
        })
        .collect();

    json(200, &serde_json::to_string(&serde_json::json!({
        "id": session_id.to_string(),
        "messages": messages,
    }))?)
}

fn json(status: u16, body: &str) -> Result<Response<Body>, Error> {
    Ok(Response::builder()
        .status(status)
        .header("Content-Type", "application/json")
        .body(Body::Text(body.to_string()))
        .map_err(|e| format!("response build: {e}"))?)
}
