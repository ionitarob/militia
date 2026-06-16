use lambda_http::{http::Method, Body, Error, Request, Response};
use std::sync::Arc;

use crate::{auth, routes, AppState};

pub async fn handle(state: Arc<AppState>, event: Request) -> Result<Response<Body>, Error> {
    let method = event.method().clone();
    let path = event
        .uri()
        .path()
        .trim_start_matches("/prod")
        .trim_end_matches('/')
        .to_string();
    let path = if path.is_empty() { "/".to_string() } else { path };

    // Path segments for parametric matching (strips leading slash)
    let segs: Vec<&str> = path.trim_start_matches('/').split('/').collect();

    // ── Public routes ─────────────────────────────────────────────────────────
    match (method.clone(), path.as_str()) {
        (Method::GET,  "/")                      => return ok_json(r#"{"status":"ok"}"#),
        (Method::POST, "/auth/login")            => return routes::auth::login(state, event).await,
        (Method::POST, "/auth/refresh")          => return routes::auth::refresh(state, event).await,
        (Method::POST, "/auth/register")         => return routes::register::register(state, event).await,
        (Method::POST, "/auth/register/verify")  => return routes::register::verify(state, event).await,
        _ => {}
    }

    // ── Auth guard ────────────────────────────────────────────────────────────
    let claims = match auth::bearer_from_request(&event) {
        Some(token) => match auth::verify(&token, &state.jwt_secret) {
            Ok(c) => c,
            Err(_) => return Ok(auth::unauthorized("Token inválido o expirado")),
        },
        None => return Ok(auth::unauthorized("Autenticación requerida")),
    };

    // ── Parametric routes (matched on segments) ───────────────────────────────
    match (method.clone(), segs.as_slice()) {

        // Licitaciones – parametric
        (Method::POST, ["licitaciones", id, "assign"]) => {
            if let Ok(lid) = id.parse::<i64>() {
                return routes::pipeline::assign(state, event, lid).await;
            }
        }
        (Method::POST, ["licitaciones", id, "decline"]) => {
            if let Ok(lid) = id.parse::<i64>() {
                return routes::pipeline::decline(state, event, lid).await;
            }
        }
        (Method::POST, ["licitaciones", id, "force-assign"]) => {
            if let Ok(lid) = id.parse::<i64>() {
                return routes::pipeline::force_assign(state, event, lid).await;
            }
        }
        (Method::POST, ["licitaciones", id, "unassign"]) => {
            if let Ok(lid) = id.parse::<i64>() {
                return routes::pipeline::unassign(state, event, lid).await;
            }
        }
        (Method::PATCH, ["licitaciones", id, "stage"]) => {
            if let Ok(lid) = id.parse::<i64>() {
                return routes::pipeline::update_stage(state, event, lid).await;
            }
        }
        (Method::PATCH, ["licitaciones", id, "fabricante"]) => {
            if let Ok(lid) = id.parse::<i64>() {
                return routes::pipeline::update_fabricante(state, event, lid).await;
            }
        }
        (Method::GET, ["licitaciones", id, "stage-history"]) => {
            if let Ok(lid) = id.parse::<i64>() {
                return routes::pipeline::get_stage_history(state, event, lid).await;
            }
        }
        (Method::GET, ["licitaciones", id, "client-cotizaciones"]) => {
            if let Ok(lid) = id.parse::<i64>() {
                return routes::licitaciones::list_client_cotizaciones(state, event, lid).await;
            }
        }
        (Method::PUT, ["licitaciones", id, "client-cotizaciones", cliente]) => {
            if let Ok(lid) = id.parse::<i64>() {
                return routes::licitaciones::upsert_client_cotizacion(
                    state, event, lid, cliente.to_string(),
                ).await;
            }
        }

        // Quotes
        (Method::GET, ["licitaciones", id, "quotes"]) => {
            if let Ok(lid) = id.parse::<i64>() {
                return routes::quotes::list(state, event, lid).await;
            }
        }
        (Method::POST, ["licitaciones", id, "quotes"]) => {
            if let Ok(lid) = id.parse::<i64>() {
                return routes::quotes::create(state, event, lid).await;
            }
        }
        (Method::PATCH, ["licitaciones", id, "quotes", qid]) => {
            if let (Ok(lid), Ok(q)) = (id.parse::<i64>(), qid.parse::<i32>()) {
                return routes::quotes::update(state, event, lid, q).await;
            }
        }
        (Method::DELETE, ["licitaciones", id, "quotes", qid]) => {
            if let (Ok(lid), Ok(q)) = (id.parse::<i64>(), qid.parse::<i32>()) {
                return routes::quotes::delete(state, event, lid, q).await;
            }
        }

        // Cotizacion adjuntos
        (Method::GET, ["licitaciones", id, "cotizacion-adjuntos"]) => {
            if let Ok(lid) = id.parse::<i64>() {
                return routes::cotizacion_adjuntos::list(state, event, lid).await;
            }
        }
        (Method::POST, ["licitaciones", id, "cotizacion-adjuntos"]) => {
            if let Ok(lid) = id.parse::<i64>() {
                return routes::cotizacion_adjuntos::create(state, event, lid).await;
            }
        }
        (Method::DELETE, ["licitaciones", id, "cotizacion-adjuntos", aid]) => {
            if let (Ok(lid), Ok(a)) = (id.parse::<i64>(), aid.parse::<i64>()) {
                return routes::cotizacion_adjuntos::delete(state, event, lid, a).await;
            }
        }

        // Documents
        (Method::GET, ["licitaciones", id, "documentos"]) => {
            if let Ok(lid) = id.parse::<i64>() {
                return routes::documents::list(state, event, lid).await;
            }
        }

        // Notes
        (Method::GET, ["licitaciones", id, "notes"]) => {
            if let Ok(lid) = id.parse::<i64>() {
                return routes::notes::list(state, event, lid).await;
            }
        }
        (Method::POST, ["licitaciones", id, "notes"]) => {
            if let Ok(lid) = id.parse::<i64>() {
                return routes::notes::create(state, event, lid).await;
            }
        }

        // Teams – parametric
        (Method::POST, ["teams", id, "members"]) => {
            if let Ok(tid) = id.parse::<i32>() {
                return routes::teams::add_member(state, event, tid).await;
            }
        }
        (Method::DELETE, ["teams", id, "members", uid]) => {
            if let (Ok(tid), Ok(uid)) = (id.parse::<i32>(), uid.parse::<i32>()) {
                return routes::teams::remove_member(state, event, tid, uid).await;
            }
        }

        // Admin registrations – parametric
        (Method::POST, ["admin", "pending-registrations", id, "approve"]) => {
            if let Ok(rid) = id.parse::<i64>() {
                return routes::register::approve(state, event, rid).await;
            }
        }
        (Method::POST, ["admin", "pending-registrations", id, "reject"]) => {
            if let Ok(rid) = id.parse::<i64>() {
                return routes::register::reject(state, event, rid).await;
            }
        }

        _ => {}
    }

    // ── Exact protected routes ────────────────────────────────────────────────
    match (method, path.as_str()) {
        (Method::GET,  "/auth/me")                        => routes::auth::me(state, event).await,
        (Method::GET,  "/admin/pending-registrations")    => routes::register::list_pending(state, event).await,
        (Method::GET,  "/users")             => routes::users::list(state, event).await,
        (Method::GET,  "/teams")             => routes::teams::list(state, event).await,
        (Method::POST, "/teams")             => routes::teams::create(state, event).await,
        (Method::GET,  "/dashboard/stats")   => routes::pipeline::dashboard_stats(state, event).await,
        (Method::GET,  "/licitaciones/mine") => routes::pipeline::my_licitaciones(state, event).await,
        (Method::GET,  "/team/workload")     => routes::pipeline::team_workload(state, event).await,
        (Method::GET,  "/licitaciones") => routes::licitaciones::list(state, event).await,
        (Method::POST, "/licitaciones") => {
            if claims.role != "admin" {
                return Ok(auth::unauthorized("Solo administradores pueden crear licitaciones"));
            }
            routes::licitaciones::create(state, event).await
        }
        _ => ok_json_status(404, r#"{"error":"not found"}"#),
    }
}

pub fn ok_json(body: &str) -> Result<Response<Body>, Error> {
    ok_json_status(200, body)
}

pub fn ok_json_status(status: u16, body: &str) -> Result<Response<Body>, Error> {
    Ok(Response::builder()
        .status(status)
        .header("content-type", "application/json")
        .body(Body::Text(body.to_string()))
        .map_err(Box::new)?)
}
