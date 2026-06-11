use bcrypt::{hash as bcrypt_hash, DEFAULT_COST};
use lettre::{
    message::header::ContentType, AsyncSmtpTransport, AsyncTransport, Message as EmailMessage,
    Tokio1Executor,
    transport::smtp::authentication::Credentials,
};
use lambda_http::{Body as LBody, Error, Request, Response};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use std::sync::Arc;

use crate::{auth, AppState};

fn json(status: u16, body: &str) -> Result<Response<LBody>, Error> {
    Ok(Response::builder()
        .status(status)
        .header("content-type", "application/json")
        .body(LBody::Text(body.to_string()))
        .map_err(Box::new)?)
}

fn parse_body<T: for<'de> Deserialize<'de>>(event: &Request) -> Result<T, Response<LBody>> {
    let raw = match event.body() {
        LBody::Text(s) => s.as_bytes().to_vec(),
        LBody::Binary(b) => b.clone(),
        LBody::Empty => return Err(json(400, r#"{"error":"empty body"}"#).unwrap()),
    };
    serde_json::from_slice(&raw).map_err(|e| {
        json(400, &serde_json::json!({"error": e.to_string()}).to_string()).unwrap()
    })
}

fn generate_otp() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let seed = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .subsec_nanos();
    format!("{:06}", seed % 1_000_000)
}

// ── POST /auth/register ───────────────────────────────────────────────────────

#[derive(Deserialize)]
struct RegisterRequest {
    email: String,
    nombre: String,
    password: String,
    role: String, // "ventas" or "admin"
}

pub async fn register(state: Arc<AppState>, event: Request) -> Result<Response<LBody>, Error> {
    let req: RegisterRequest = match parse_body(&event) {
        Ok(r) => r,
        Err(e) => return Ok(e),
    };

    let email = req.email.to_lowercase();
    let email = email.trim().to_string();

    if !email.ends_with("@ingrammicro.com") {
        return json(400, r#"{"error":"Solo se permiten correos @ingrammicro.com"}"#);
    }

    let role = match req.role.as_str() {
        "ventas" | "admin" => req.role.clone(),
        _ => return json(400, r#"{"error":"Rol inválido. Use 'ventas' o 'admin'"}"#),
    };

    // Check no existing active user with same email
    let existing = sqlx::query("SELECT id FROM app_user WHERE email = $1")
        .bind(&email)
        .fetch_optional(&state.pool)
        .await
        .map_err(|e| format!("db: {e}"))?;
    if existing.is_some() {
        return json(409, r#"{"error":"Ya existe una cuenta con ese correo"}"#);
    }

    // Check no pending OTP or pending approval for same email
    let pending = sqlx::query(
        "SELECT id FROM registration_request WHERE email = $1 AND status IN ('pending_otp','pending_approval') ORDER BY created_at DESC LIMIT 1"
    )
    .bind(&email)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| format!("db: {e}"))?;
    if pending.is_some() {
        return json(409, r#"{"error":"Ya existe una solicitud pendiente para ese correo"}"#);
    }

    let password_hash = bcrypt_hash(&req.password, DEFAULT_COST)
        .map_err(|e| format!("bcrypt: {e}"))?;

    let otp = generate_otp();
    let otp_expires_at = chrono::Utc::now() + chrono::Duration::minutes(15);

    let row = sqlx::query(
        "INSERT INTO registration_request (email, nombre, password_hash, role, otp_code, otp_expires_at)
         VALUES ($1, $2, $3, $4, $5, $6) RETURNING id",
    )
    .bind(&email)
    .bind(&req.nombre)
    .bind(&password_hash)
    .bind(&role)
    .bind(&otp)
    .bind(otp_expires_at)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| format!("db: {e}"))?;

    let request_id: i64 = row.get("id");

    // Send OTP via Gmail SMTP
    let body_html = format!(
        "<p>Tu código de verificación para <strong>IMLiti</strong> es:</p>\
         <h2 style=\"letter-spacing:8px;font-family:monospace\">{otp}</h2>\
         <p>Este código expira en 15 minutos.</p>"
    );

    let mail = EmailMessage::builder()
        .from(format!("IMLiti <{}>", state.smtp_user).parse().map_err(|e| format!("mail: {e}"))?)
        .to(email.parse().map_err(|e| format!("mail: {e}"))?)
        .subject("Código de verificación IMLiti")
        .header(ContentType::TEXT_HTML)
        .body(body_html)
        .map_err(|e| format!("mail: {e}"))?;

    let creds = Credentials::new(state.smtp_user.clone(), state.smtp_pass.clone());
    let mailer = AsyncSmtpTransport::<Tokio1Executor>::relay("smtp.gmail.com")
        .map_err(|e| format!("smtp: {e}"))?
        .credentials(creds)
        .build();

    if let Err(e) = mailer.send(mail).await {
        tracing::error!("SMTP send failed: {e}");
        let _ = sqlx::query("DELETE FROM registration_request WHERE id = $1")
            .bind(request_id)
            .execute(&state.pool)
            .await;
        return json(500, r#"{"error":"No se pudo enviar el correo de verificación. Inténtalo de nuevo."}"#);
    }

    json(200, &serde_json::json!({"request_id": request_id}).to_string())
}

// ── POST /auth/register/verify ────────────────────────────────────────────────

#[derive(Deserialize)]
struct VerifyRequest {
    request_id: i64,
    otp_code: String,
}

#[derive(Serialize)]
struct VerifyResponse {
    status: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    access_token: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    refresh_token: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    user: Option<UserDto>,
}

#[derive(Serialize)]
struct UserDto {
    id: i32,
    email: String,
    role: String,
    nombre: Option<String>,
}

pub async fn verify(state: Arc<AppState>, event: Request) -> Result<Response<LBody>, Error> {
    let req: VerifyRequest = match parse_body(&event) {
        Ok(r) => r,
        Err(e) => return Ok(e),
    };

    let row = sqlx::query(
        "SELECT id, email, nombre, password_hash, role, otp_code, otp_expires_at, status
         FROM registration_request WHERE id = $1",
    )
    .bind(req.request_id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| format!("db: {e}"))?;

    let row = match row {
        Some(r) => r,
        None => return json(404, r#"{"error":"Solicitud no encontrada"}"#),
    };

    let status: String = row.get("status");
    if status != "pending_otp" {
        return json(400, r#"{"error":"Esta solicitud ya fue procesada"}"#);
    }

    let stored_otp: String = row.get("otp_code");
    let expires_at: chrono::DateTime<chrono::Utc> = row.get("otp_expires_at");

    if chrono::Utc::now() > expires_at {
        return json(400, r#"{"error":"El código ha expirado. Solicita uno nuevo."}"#);
    }

    if req.otp_code.trim() != stored_otp {
        return json(400, r#"{"error":"Código incorrecto"}"#);
    }

    let email: String          = row.get("email");
    let nombre: String         = row.get("nombre");
    let password_hash: String  = row.get("password_hash");
    let role: String           = row.get("role");

    // Mark OTP verified
    sqlx::query("UPDATE registration_request SET otp_verified = TRUE WHERE id = $1")
        .bind(req.request_id)
        .execute(&state.pool)
        .await
        .map_err(|e| format!("db: {e}"))?;

    if role == "ventas" {
        // Create user immediately
        let user_row = sqlx::query(
            "INSERT INTO app_user (email, password_hash, role, nombre)
             VALUES ($1, $2, $3::user_role, $4) RETURNING id",
        )
        .bind(&email)
        .bind(&password_hash)
        .bind(&role)
        .bind(&nombre)
        .fetch_one(&state.pool)
        .await
        .map_err(|e| format!("db: {e}"))?;

        let user_id: i32 = user_row.get("id");

        sqlx::query(
            "UPDATE registration_request SET status = 'approved', approved_by = $1 WHERE id = $2",
        )
        .bind(user_id)
        .bind(req.request_id)
        .execute(&state.pool)
        .await
        .map_err(|e| format!("db: {e}"))?;

        let access  = auth::issue_access(user_id, &email, &role, &state.jwt_secret);
        let refresh = auth::issue_refresh(user_id, &email, &role, &state.jwt_secret);

        return json(
            200,
            &serde_json::to_string(&VerifyResponse {
                status: "approved".to_string(),
                access_token: Some(access),
                refresh_token: Some(refresh),
                user: Some(UserDto { id: user_id, email, role, nombre: Some(nombre) }),
            })?,
        );
    }

    // Admin: mark pending approval
    sqlx::query(
        "UPDATE registration_request SET status = 'pending_approval' WHERE id = $1",
    )
    .bind(req.request_id)
    .execute(&state.pool)
    .await
    .map_err(|e| format!("db: {e}"))?;

    json(
        200,
        &serde_json::to_string(&VerifyResponse {
            status: "pending_approval".to_string(),
            access_token: None,
            refresh_token: None,
            user: None,
        })?,
    )
}

// ── GET /admin/pending-registrations ─────────────────────────────────────────

#[derive(Serialize)]
struct PendingRegistration {
    id: i64,
    email: String,
    nombre: String,
    role: String,
    created_at: String,
}

pub async fn list_pending(state: Arc<AppState>, event: Request) -> Result<Response<LBody>, Error> {
    let claims = match auth::bearer_from_request(&event) {
        Some(t) => match auth::verify(&t, &state.jwt_secret) {
            Ok(c) => c,
            Err(_) => return Ok(auth::unauthorized("Token inválido o expirado")),
        },
        None => return Ok(auth::unauthorized("Autenticación requerida")),
    };
    if claims.role != "admin" {
        return Ok(auth::unauthorized("Solo administradores"));
    }

    let rows = sqlx::query(
        "SELECT id, email, nombre, role, created_at FROM registration_request
         WHERE status = 'pending_approval' ORDER BY created_at ASC",
    )
    .fetch_all(&state.pool)
    .await
    .map_err(|e| format!("db: {e}"))?;

    let items: Vec<PendingRegistration> = rows
        .iter()
        .map(|r| PendingRegistration {
            id: r.get("id"),
            email: r.get("email"),
            nombre: r.get("nombre"),
            role: r.get("role"),
            created_at: r
                .get::<chrono::DateTime<chrono::Utc>, _>("created_at")
                .to_rfc3339(),
        })
        .collect();

    json(200, &serde_json::to_string(&items)?)
}

// ── POST /admin/pending-registrations/{id}/approve ────────────────────────────

pub async fn approve(
    state: Arc<AppState>,
    event: Request,
    request_id: i64,
) -> Result<Response<LBody>, Error> {
    let claims = match auth::bearer_from_request(&event) {
        Some(t) => match auth::verify(&t, &state.jwt_secret) {
            Ok(c) => c,
            Err(_) => return Ok(auth::unauthorized("Token inválido o expirado")),
        },
        None => return Ok(auth::unauthorized("Autenticación requerida")),
    };
    if claims.role != "admin" {
        return Ok(auth::unauthorized("Solo administradores"));
    }

    let row = sqlx::query(
        "SELECT email, nombre, password_hash, role, status
         FROM registration_request WHERE id = $1",
    )
    .bind(request_id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| format!("db: {e}"))?;

    let row = match row {
        Some(r) => r,
        None => return json(404, r#"{"error":"Solicitud no encontrada"}"#),
    };

    let status: String = row.get("status");
    if status != "pending_approval" {
        return json(400, r#"{"error":"Esta solicitud no está pendiente de aprobación"}"#);
    }

    let email: String         = row.get("email");
    let nombre: String        = row.get("nombre");
    let password_hash: String = row.get("password_hash");
    let role: String          = row.get("role");

    let user_row = sqlx::query(
        "INSERT INTO app_user (email, password_hash, role, nombre)
         VALUES ($1, $2, $3::user_role, $4) RETURNING id",
    )
    .bind(&email)
    .bind(&password_hash)
    .bind(&role)
    .bind(&nombre)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| format!("db: {e}"))?;

    let user_id: i32 = user_row.get("id");

    sqlx::query(
        "UPDATE registration_request SET status = 'approved', approved_by = $1 WHERE id = $2",
    )
    .bind(user_id)
    .bind(request_id)
    .execute(&state.pool)
    .await
    .map_err(|e| format!("db: {e}"))?;

    json(200, &serde_json::json!({"id": user_id, "email": email}).to_string())
}

// ── POST /admin/pending-registrations/{id}/reject ─────────────────────────────

pub async fn reject(
    state: Arc<AppState>,
    event: Request,
    request_id: i64,
) -> Result<Response<LBody>, Error> {
    let claims = match auth::bearer_from_request(&event) {
        Some(t) => match auth::verify(&t, &state.jwt_secret) {
            Ok(c) => c,
            Err(_) => return Ok(auth::unauthorized("Token inválido o expirado")),
        },
        None => return Ok(auth::unauthorized("Autenticación requerida")),
    };
    if claims.role != "admin" {
        return Ok(auth::unauthorized("Solo administradores"));
    }

    let result = sqlx::query(
        "UPDATE registration_request SET status = 'rejected' WHERE id = $1 AND status = 'pending_approval'",
    )
    .bind(request_id)
    .execute(&state.pool)
    .await
    .map_err(|e| format!("db: {e}"))?;

    if result.rows_affected() == 0 {
        return json(404, r#"{"error":"Solicitud no encontrada o ya procesada"}"#);
    }

    json(200, r#"{"ok":true}"#)
}
