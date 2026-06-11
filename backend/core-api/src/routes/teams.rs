use lambda_http::{Body, Error, Request, Response};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use std::sync::Arc;

use crate::{auth, AppState};

macro_rules! bail {
    ($e:expr) => {
        match $e {
            Ok(v) => v,
            Err(e) => return Ok(e),
        }
    };
}

#[derive(Serialize)]
struct TeamMemberDto {
    user_id: i32,
    nombre:  Option<String>,
    email:   String,
    role:    String,
}

#[derive(Serialize)]
struct TeamDto {
    id:         i32,
    nombre:     String,
    created_by: i32,
    members:    Vec<TeamMemberDto>,
}

#[derive(Deserialize)]
struct CreateTeamReq {
    nombre: String,
}

#[derive(Deserialize)]
struct AddMemberReq {
    user_id: i32,
}

// ── GET /teams ────────────────────────────────────────────────────────────────

pub async fn list(state: Arc<AppState>, event: Request) -> Result<Response<Body>, Error> {
    let claims = bail!(require_auth(&event, &state.jwt_secret));

    let team_ids: Vec<i32> = if claims.role == "admin" {
        sqlx::query_scalar("SELECT id FROM team WHERE created_by = $1 ORDER BY id")
            .bind(claims.sub)
            .fetch_all(&state.pool)
            .await
            .map_err(|e| format!("db: {e}"))?
    } else {
        sqlx::query_scalar(
            "SELECT team_id FROM team_member WHERE user_id = $1 ORDER BY team_id",
        )
        .bind(claims.sub)
        .fetch_all(&state.pool)
        .await
        .map_err(|e| format!("db: {e}"))?
    };

    let mut teams = Vec::new();
    for tid in team_ids {
        let row = sqlx::query("SELECT id, nombre, created_by FROM team WHERE id = $1")
            .bind(tid)
            .fetch_one(&state.pool)
            .await
            .map_err(|e| format!("db: {e}"))?;

        let member_rows = sqlx::query(
            r#"
            SELECT u.id, u.nombre, u.email, u.role::TEXT AS role
            FROM team_member tm
            JOIN app_user u ON u.id = tm.user_id
            WHERE tm.team_id = $1
            ORDER BY u.nombre
            "#,
        )
        .bind(tid)
        .fetch_all(&state.pool)
        .await
        .map_err(|e| format!("db: {e}"))?;

        teams.push(TeamDto {
            id:         row.get("id"),
            nombre:     row.get("nombre"),
            created_by: row.get("created_by"),
            members: member_rows
                .iter()
                .map(|r| TeamMemberDto {
                    user_id: r.get("id"),
                    nombre:  r.try_get("nombre").ok().flatten(),
                    email:   r.get("email"),
                    role:    r.try_get("role").unwrap_or_default(),
                })
                .collect(),
        });
    }

    json(200, &serde_json::to_string(&teams)?)
}

// ── POST /teams ───────────────────────────────────────────────────────────────

pub async fn create(state: Arc<AppState>, event: Request) -> Result<Response<Body>, Error> {
    let claims = bail!(require_auth(&event, &state.jwt_secret));
    if claims.role != "admin" {
        return Ok(auth::unauthorized("Solo administradores pueden crear equipos"));
    }

    let req = bail!(parse_body::<CreateTeamReq>(&event));

    let id: i32 = sqlx::query_scalar(
        "INSERT INTO team (nombre, created_by) VALUES ($1, $2) RETURNING id",
    )
    .bind(&req.nombre)
    .bind(claims.sub)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| format!("db: {e}"))?;

    json(201, &serde_json::json!({"id": id}).to_string())
}

// ── POST /teams/{id}/members ──────────────────────────────────────────────────

pub async fn add_member(
    state: Arc<AppState>,
    event: Request,
    team_id: i32,
) -> Result<Response<Body>, Error> {
    let claims = bail!(require_auth(&event, &state.jwt_secret));
    if claims.role != "admin" {
        return Ok(auth::unauthorized("Solo administradores"));
    }

    let req = bail!(parse_body::<AddMemberReq>(&event));

    sqlx::query(
        "INSERT INTO team_member (team_id, user_id, added_by) VALUES ($1, $2, $3)
         ON CONFLICT DO NOTHING",
    )
    .bind(team_id)
    .bind(req.user_id)
    .bind(claims.sub)
    .execute(&state.pool)
    .await
    .map_err(|e| format!("db: {e}"))?;

    json(200, r#"{"ok":true}"#)
}

// ── DELETE /teams/{id}/members/{uid} ──────────────────────────────────────────

pub async fn remove_member(
    state: Arc<AppState>,
    event: Request,
    team_id: i32,
    user_id: i32,
) -> Result<Response<Body>, Error> {
    let claims = bail!(require_auth(&event, &state.jwt_secret));
    if claims.role != "admin" {
        return Ok(auth::unauthorized("Solo administradores"));
    }

    sqlx::query("DELETE FROM team_member WHERE team_id = $1 AND user_id = $2")
        .bind(team_id)
        .bind(user_id)
        .execute(&state.pool)
        .await
        .map_err(|e| format!("db: {e}"))?;

    json(200, r#"{"ok":true}"#)
}

// ── Helpers ───────────────────────────────────────────────────────────────────

fn require_auth(
    event: &Request,
    secret: &str,
) -> Result<crate::auth::Claims, Response<Body>> {
    let token = auth::bearer_from_request(event)
        .ok_or_else(|| auth::unauthorized("Autenticación requerida"))?;
    auth::verify(&token, secret).map_err(|_| auth::unauthorized("Token inválido"))
}

fn parse_body<T: serde::de::DeserializeOwned>(event: &Request) -> Result<T, Response<Body>> {
    let raw = match event.body() {
        Body::Text(s)   => s.as_bytes().to_vec(),
        Body::Binary(b) => b.clone(),
        Body::Empty     => {
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
