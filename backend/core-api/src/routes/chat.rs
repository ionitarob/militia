use std::sync::Arc;
use lambda_http::{Body, Error, Request, Response};
use serde::Deserialize;

use crate::AppState;
use crate::routes::pipeline::require_auth;

pub const MODEL_ID: &str = "gpt-5-mini";
const API_VERSION: &str = "2024-12-01-preview";
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
    fetch_licitacion_docs_limited(state, licitacion_id, MAX_DOCS, MAX_DOC_BYTES).await
}

pub async fn fetch_licitacion_docs_limited(
    state: &AppState,
    licitacion_id: i64,
    max_docs: usize,
    max_bytes: usize,
) -> Vec<DocBlob> {
    let mut keys: Vec<(String, String, Option<String>)> = Vec::new();

    if let Ok(rows) = sqlx::query_as::<_, (String, String, Option<String>)>(
        "SELECT nombre, s3_key, content_type FROM licitacion_documento \
         WHERE licitacion_id = $1 ORDER BY id ASC LIMIT $2",
    )
    .bind(licitacion_id as i32)
    .bind(max_docs as i32)
    .fetch_all(&state.pool)
    .await
    {
        keys.extend(rows);
    }

    if keys.len() < max_docs {
        let remaining = (max_docs - keys.len()) as i32;
        if let Ok(rows) = sqlx::query_as::<_, (String, String, Option<String>)>(
            "SELECT nombre, s3_key, content_type FROM cotizacion_adjunto \
             WHERE licitacion_id = $1 ORDER BY id ASC LIMIT $2",
        )
        .bind(licitacion_id as i32)
        .bind(remaining)
        .fetch_all(&state.pool)
        .await
        {
            keys.extend(rows);
        }
    }

    let futures: Vec<_> = keys.into_iter().map(|(nombre, blob_key, ct)| {
        let blob_client = state.blob_client.clone();
        let container = state.blob_container.clone();
        async move { download_blob_doc_owned(blob_client, container, blob_key, nombre, ct, max_bytes).await }
    }).collect();

    futures_util::future::join_all(futures)
        .await
        .into_iter()
        .flatten()
        .collect()
}

/// Smart document selector for AI summaries.
/// Scores all available docs by relevance, deduplicates by byte size,
/// and picks the best ones within a total byte budget.
pub async fn fetch_summary_docs(state: &AppState, licitacion_id: i64) -> Vec<DocBlob> {
    const TOTAL_BUDGET: usize = 3_000_000; // 3 MB total — ~60–80 PDF pages
    const MAX_SUMMARY_DOCS: usize = 3;

    // Fetch all portal doc metadata (no LIMIT — we need to rank them all)
    let mut candidates: Vec<(String, String, Option<String>)> = Vec::new();
    if let Ok(rows) = sqlx::query_as::<_, (String, String, Option<String>)>(
        "SELECT nombre, s3_key, content_type FROM licitacion_documento \
         WHERE licitacion_id = $1 ORDER BY id ASC",
    )
    .bind(licitacion_id as i32)
    .fetch_all(&state.pool)
    .await
    {
        candidates.extend(rows);
    }

    // Sort by priority (lower score = more useful for a summary)
    candidates.sort_by_key(|(nombre, _, _)| doc_summary_score(nombre));

    // Download in priority order, dedup by exact byte size, stop at budget
    let mut docs: Vec<DocBlob> = Vec::new();
    let mut seen_sizes = std::collections::HashSet::<usize>::new();
    let mut total_bytes = 0usize;

    for (nombre, s3_key, ct) in candidates {
        if docs.len() >= MAX_SUMMARY_DOCS || total_bytes >= TOTAL_BUDGET {
            break;
        }
        let remaining_budget = TOTAL_BUDGET - total_bytes;
        let blob = download_blob_doc_owned(
            state.blob_client.clone(),
            state.blob_container.clone(),
            s3_key,
            nombre,
            ct,
            remaining_budget,
        )
        .await;
        if let Some(b) = blob {
            let size = b.data.len();
            if seen_sizes.contains(&size) {
                continue; // exact duplicate — skip
            }
            seen_sizes.insert(size);
            total_bytes += size;
            docs.push(b);
        }
    }

    docs
}

/// Score a document name for summary usefulness.
/// Lower = more important. Based on Spanish procurement naming conventions.
fn doc_summary_score(nombre: &str) -> u8 {
    // Normalise: lowercase + strip common accent/ñ variants
    let n = nombre.to_lowercase();
    let n = n
        .replace(['á', 'à', 'â'], "a")
        .replace(['é', 'è', 'ê'], "e")
        .replace(['í', 'ì', 'î'], "i")
        .replace(['ó', 'ò', 'ô'], "o")
        .replace(['ú', 'ù', 'û'], "u")
        .replace('ñ', "n");

    // Pliego de Prescripciones Técnicas (PPT) — the most useful document
    if n.contains("prescripcion") || n.contains("tecni") && n.contains("pliego")
        || n.contains("ppt")
        || (n.contains("tecni") && (n.contains("condicion") || n.contains("clausula")))
    {
        return 1;
    }

    // Pliego de Cláusulas Administrativas Particulares (PCAP) & anuncio
    if n.contains("anuncio") || n.contains("pcap")
        || (n.contains("administrativ") && n.contains("pliego"))
        || (n.contains("clausula") && n.contains("administrativ"))
        || n.contains("convocatoria")
    {
        return 2;
    }

    // Generic pliego or main document
    if n.contains("pliego") || n.contains("condicion") || n.contains("especificacion") {
        return 3;
    }

    // Templates, forms and declarations — low value for AI summaries
    if n.contains("anexo") || n.contains("modelo") || n.contains("declaracion")
        || n.contains("oferta") || n.contains("solicitud") || n.contains("formulario")
    {
        return 10;
    }

    4 // everything else
}

async fn download_blob_doc_owned(
    blob_client: azure_storage_blobs::prelude::BlobServiceClient,
    container: String,
    blob_key: String,
    nombre: String,
    content_type: Option<String>,
    max_bytes: usize,
) -> Option<DocBlob> {
    let media_type = resolve_media_type(content_type.as_deref(), &nombre);
    let blob = blob_client.container_client(&container).blob_client(&blob_key);
    let data = blob.get_content().await.ok()?;
    if data.len() > max_bytes { return None; }
    Some(DocBlob { nombre, media_type: media_type.to_string(), data })
}

pub fn resolve_media_type<'a>(content_type: Option<&'a str>, nombre: &str) -> &'a str {
    let n = nombre.to_lowercase();
    match content_type {
        Some(ct) if ct.contains("pdf") => "application/pdf",
        Some(ct) if ct.contains("opendocument.text") || ct.contains("odt") => {
            "application/vnd.oasis.opendocument.text"
        }
        Some(ct) if ct.contains("openxmlformats") && ct.contains("word") => {
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        }
        Some(ct) if ct.contains("msword") => "application/msword",
        Some(ct) if ct.contains("text") => "text/plain",
        _ if n.ends_with(".pdf") => "application/pdf",
        _ if n.ends_with(".odt") => "application/vnd.oasis.opendocument.text",
        _ if n.ends_with(".docx") => {
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        }
        _ if n.ends_with(".doc") => "application/msword",
        _ if n.ends_with(".txt") => "text/plain",
        _ => "application/pdf",
    }
}

pub async fn download_blob_doc(state: &AppState, blob_key: &str, nombre: &str, content_type: Option<&str>) -> Option<DocBlob> {
    let media_type = resolve_media_type(content_type, nombre);
    let blob = state.blob_client.container_client(&state.blob_container).blob_client(blob_key);
    let data = blob.get_content().await.ok()?;
    if data.len() > MAX_DOC_BYTES { return None; }
    Some(DocBlob { nombre: nombre.to_string(), media_type: media_type.to_string(), data })
}

// ── Lambda-to-Lambda document fallback ───────────────────────────────────────

/// True when the document name matches a Pliego de Prescripciones Técnicas.
pub fn is_ppt_doc(nombre: &str) -> bool {
    let n = nombre.to_lowercase();
    let n = n
        .replace(['á', 'à', 'â'], "a")
        .replace(['é', 'è', 'ê'], "e")
        .replace(['í', 'ì', 'î'], "i")
        .replace(['ó', 'ò', 'ô'], "o")
        .replace(['ú', 'ù', 'û'], "u")
        .replace('ñ', "n");
    n.contains("prescripcion")
        || n.contains("ppt")
        || (n.contains("tecni") && n.contains("pliego"))
        || (n.contains("tecni") && (n.contains("condicion") || n.contains("clausula")))
}

/// Scan raw PDF bytes for /URI (...) annotation entries and return unique http/https URLs.
pub fn extract_pdf_urls(data: &[u8]) -> Vec<String> {
    const NEEDLE: &[u8] = b"/URI (";
    let mut urls: Vec<String> = Vec::new();
    let mut seen = std::collections::HashSet::new();
    let mut pos = 0;
    while pos + NEEDLE.len() < data.len() {
        match data[pos..].windows(NEEDLE.len()).position(|w| w == NEEDLE) {
            None => break,
            Some(offset) => {
                let start = pos + offset + NEEDLE.len();
                match data[start..].iter().position(|&b| b == b')') {
                    None => break,
                    Some(end) => {
                        if let Ok(url) = std::str::from_utf8(&data[start..start + end]) {
                            let url = url.trim().to_string();
                            if url.starts_with("http") && seen.insert(url.clone()) {
                                urls.push(url);
                            }
                        }
                        pos = start + end + 1;
                    }
                }
            }
        }
    }
    urls
}

/// Call scraper_fetch HTTP service `fetch_document` mode to scrape the portal for a licitacion
/// on-demand and return the downloaded docs. Used when no docs are in the DB yet.
pub async fn invoke_scraper_fetch_for_licitacion(
    state: &AppState,
    scraper_fetch_url: &str,
    licitacion_id: i64,
) -> Vec<DocBlob> {
    let external_id: Option<String> = sqlx::query_scalar(
        "SELECT external_id FROM licitacion WHERE id = $1",
    )
    .bind(licitacion_id as i32)
    .fetch_optional(&state.pool)
    .await
    .unwrap_or(None)
    .flatten();

    let external_id = match external_id {
        Some(e) => e,
        None => {
            tracing::warn!(licitacion_id, "no external_id — cannot invoke scraper");
            return Vec::new();
        }
    };

    tracing::info!(licitacion_id, %external_id, "calling scraper_fetch fetch_document");

    let payload = serde_json::json!({
        "mode": "fetch_document",
        "external_id": external_id,
        "licitacion_id": licitacion_id,
    });

    let resp = state.http_client
        .post(scraper_fetch_url)
        .json(&payload)
        .timeout(std::time::Duration::from_secs(120))
        .send()
        .await;

    match resp {
        Ok(r) if r.status().is_success() => {
            tracing::info!("scraper_fetch returned success");
        }
        Ok(r) => {
            tracing::warn!(status = %r.status(), "scraper_fetch returned error");
            return Vec::new();
        }
        Err(e) => {
            tracing::warn!("scraper_fetch call error: {e:?}");
            return Vec::new();
        }
    }

    // Docs are now in DB — re-run fetch
    fetch_licitacion_docs(state, licitacion_id).await
}

/// Scan every PDF in `docs` for embedded hyperlinks, call scraper_fetch for each URL,
/// and return any newly-downloaded documents. Capped at 3 URLs.
pub async fn follow_pdf_links(
    state: &AppState,
    scraper_fetch_url: &str,
    docs: &[DocBlob],
    licitacion_id: i64,
) -> Vec<DocBlob> {
    const MAX_LINKED: usize = 3;

    let mut all_urls: Vec<String> = Vec::new();
    let mut seen_urls = std::collections::HashSet::new();

    for doc in docs {
        if doc.media_type.contains("pdf") {
            for url in extract_pdf_urls(&doc.data) {
                if seen_urls.insert(url.clone()) {
                    all_urls.push(url);
                }
            }
        }
    }

    tracing::info!(count = all_urls.len(), "PDF hyperlinks found");
    if all_urls.is_empty() {
        return Vec::new();
    }
    all_urls.truncate(MAX_LINKED);

    let mut linked_docs = Vec::new();
    for url in &all_urls {
        tracing::info!(%url, "fetching linked doc via scraper");
        let payload = serde_json::json!({
            "mode": "fetch_document_url",
            "url": url,
            "licitacion_id": licitacion_id,
        });

        let resp = state.http_client
            .post(scraper_fetch_url)
            .json(&payload)
            .timeout(std::time::Duration::from_secs(120))
            .send()
            .await;

        let resp = match resp {
            Ok(r) if r.status().is_success() => r,
            Ok(r) => { tracing::warn!(status = %r.status(), "scraper link error"); continue; }
            Err(e) => { tracing::warn!("scraper link call error: {e:?}"); continue; }
        };

        let result: serde_json::Value = match resp.json().await {
            Ok(v) => v,
            Err(_) => continue,
        };

        let documents = match result.get("documents").and_then(|d| d.as_array()) {
            Some(d) if !d.is_empty() => d,
            _ => continue,
        };

        for doc_info in documents {
            let blob_key = match doc_info.get("s3_key").and_then(|v| v.as_str()) {
                Some(k) => k,
                None => continue,
            };
            let nombre = doc_info.get("nombre").and_then(|v| v.as_str()).unwrap_or("Documento enlazado");
            let ct = doc_info.get("content_type").and_then(|v| v.as_str());
            if let Some(blob) = download_blob_doc(state, blob_key, nombre, ct).await {
                tracing::info!(nombre = %blob.nombre, bytes = blob.data.len(), "linked doc added");
                linked_docs.push(blob);
            }
        }
    }

    linked_docs
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

    // If licitacion_id provided, fetch docs and embed extracted text
    if let Some(lic_id) = req.licitacion_id {
        let docs = fetch_licitacion_docs(&state, lic_id).await;
        let doc_text = docs_to_text_block(&docs);
        if let Some(text_block) = doc_text {
            let combined = format!("{}\n\n---\n\n{}", text_block, req.message.trim());
            messages.push(serde_json::json!({"role": "user", "content": combined}));
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

// ── Azure OpenAI agentic loop ─────────────────────────────────────────────────

pub fn openai_url(endpoint: &str) -> String {
    format!(
        "{}openai/deployments/{}/chat/completions?api-version={}",
        endpoint, MODEL_ID, API_VERSION
    )
}

pub async fn bedrock_loop(
    state: &AppState,
    messages: &mut Vec<serde_json::Value>,
) -> Result<String, Error> {
    let url = openai_url(&state.azure_openai_endpoint);

    for _ in 0..3 {
        let mut openai_msgs = vec![serde_json::json!({"role": "system", "content": SYSTEM_PROMPT})];
        openai_msgs.extend(messages.iter().cloned());

        let request = serde_json::json!({
            "messages": openai_msgs,
            "max_tokens": 4096,
            "tools": tool_defs(),
            "tool_choice": "auto",
        });

        let resp = state.http_client
            .post(&url)
            .header("api-key", &state.azure_openai_key)
            .header("content-type", "application/json")
            .json(&request)
            .send()
            .await
            .map_err(|e| format!("openai call: {e}"))?;

        let resp_json: serde_json::Value = resp.json()
            .await
            .map_err(|e| format!("openai parse: {e}"))?;

        let choice = &resp_json["choices"][0];
        let message = choice["message"].clone();
        let finish_reason = choice["finish_reason"].as_str().unwrap_or("stop");

        messages.push(message.clone());

        if finish_reason != "tool_calls" {
            let text = message["content"].as_str()
                .unwrap_or("Sin respuesta disponible.")
                .to_string();
            return Ok(text);
        }

        // Execute tool calls
        let tool_calls = message["tool_calls"].as_array().cloned().unwrap_or_default();
        for tc in &tool_calls {
            let call_id = tc["id"].as_str().unwrap_or("");
            let name = tc["function"]["name"].as_str().unwrap_or("");
            let args: serde_json::Value = serde_json::from_str(
                tc["function"]["arguments"].as_str().unwrap_or("{}")
            ).unwrap_or(serde_json::json!({}));
            let result = execute_tool(&state.pool, name, &args).await;
            messages.push(serde_json::json!({
                "role": "tool",
                "tool_call_id": call_id,
                "content": result,
            }));
        }
    }

    Err("ai loop exceeded max iterations".into())
}

// ── Tool definitions (OpenAI function format) ─────────────────────────────────

pub fn tool_defs() -> serde_json::Value {
    serde_json::json!([
        {
            "type": "function",
            "function": {
                "name": "buscar_licitaciones",
                "description": "Busca licitaciones públicas por texto, mercado, CC.AA, estado o importe.",
                "parameters": {
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
            }
        },
        {
            "type": "function",
            "function": {
                "name": "buscar_adjudicaciones",
                "description": "Busca adjudicaciones por texto, mercado o rango de días recientes.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "query":        {"type": "string",  "description": "Texto libre (título)"},
                        "mercado":      {"type": "string",  "description": "Mercado vertical"},
                        "ultimos_dias": {"type": "integer", "description": "Filtrar últimos N días"},
                        "limit":        {"type": "integer", "description": "Resultados a devolver (máx 20)"}
                    },
                    "required": []
                }
            }
        },
        {
            "type": "function",
            "function": {
                "name": "detalle_licitacion",
                "description": "Obtiene todos los detalles de una licitación por número de expediente o título.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "query": {"type": "string", "description": "Número de expediente o parte del título"}
                    },
                    "required": ["query"]
                }
            }
        },
        {
            "type": "function",
            "function": {
                "name": "estadisticas_pipeline",
                "description": "Estadísticas generales: licitaciones activas/caducadas, adjudicaciones totales y recientes, distribución del pipeline.",
                "parameters": {
                    "type": "object",
                    "properties": {},
                    "required": []
                }
            }
        }
    ])
}

// ── Document text extraction ──────────────────────────────────────────────────

const TEXT_CAP: usize = 80_000;

pub fn docs_to_text_block(docs: &[DocBlob]) -> Option<String> {
    let parts: Vec<String> = docs.iter().filter_map(|d| {
        let text = extract_doc_text(d)?;
        Some(format!("=== {} ===\n\n{}", d.nombre, text))
    }).collect();
    if parts.is_empty() { None } else { Some(parts.join("\n\n---\n\n")) }
}

pub fn extract_doc_text(doc: &DocBlob) -> Option<String> {
    let mt = doc.media_type.as_str();
    let raw = if mt.contains("pdf") {
        extract_pdf_text(&doc.data)
    } else if mt.contains("opendocument.text") || mt.contains("odt") {
        extract_zip_xml_text(&doc.data, "content.xml")
    } else if mt.contains("openxmlformats") && mt.contains("word") {
        extract_zip_xml_text(&doc.data, "word/document.xml")
    } else if mt.contains("msword") {
        extract_binary_text(&doc.data)
    } else if mt.contains("text/plain") {
        std::str::from_utf8(&doc.data).ok().map(|s| s.trim().to_string())
    } else {
        extract_pdf_text(&doc.data)
            .or_else(|| extract_zip_xml_text(&doc.data, "content.xml"))
            .or_else(|| extract_zip_xml_text(&doc.data, "word/document.xml"))
    };
    let text = raw?;
    if text.trim().is_empty() { return None; }
    if text.len() > TEXT_CAP { Some(text[..TEXT_CAP].to_string()) } else { Some(text) }
}

pub fn extract_pdf_text(data: &[u8]) -> Option<String> {
    let result = std::panic::catch_unwind(|| pdf_extract::extract_text_from_mem(data));
    match result {
        Ok(Ok(t)) if !t.trim().is_empty() => Some(t),
        _ => None,
    }
}

pub fn extract_zip_xml_text(data: &[u8], entry: &str) -> Option<String> {
    let cursor = std::io::Cursor::new(data);
    let mut archive = zip::ZipArchive::new(cursor).ok()?;
    let mut file = archive.by_name(entry).ok()?;
    use std::io::Read;
    let mut xml = String::new();
    file.read_to_string(&mut xml).ok()?;
    let text = strip_xml_tags(&xml);
    if text.trim().is_empty() { None } else { Some(text) }
}

pub fn extract_binary_text(data: &[u8]) -> Option<String> {
    let mut out = String::new();
    let mut run = String::new();
    for &b in data {
        if b >= 0x20 && b < 0x7f || b >= 0xa0 {
            run.push(b as char);
        } else {
            if run.len() >= 5 {
                if !out.is_empty() { out.push(' '); }
                out.push_str(run.trim());
            }
            run.clear();
        }
    }
    if run.len() >= 5 { out.push_str(run.trim()); }
    if out.trim().is_empty() { None } else { Some(out) }
}

pub fn strip_xml_tags(s: &str) -> String {
    let mut out = String::with_capacity(s.len() / 2);
    let mut in_tag = false;
    let mut last_space = true;
    for c in s.chars() {
        match c {
            '<' => { in_tag = true; }
            '>' => {
                in_tag = false;
                if !last_space { out.push(' '); last_space = true; }
            }
            _ if in_tag => {}
            '\n' | '\r' | '\t' | ' ' => {
                if !last_space { out.push(' '); last_space = true; }
            }
            _ => { out.push(c); last_space = false; }
        }
    }
    out.trim().to_string()
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
