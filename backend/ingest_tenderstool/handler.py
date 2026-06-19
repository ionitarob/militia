"""
ingest_tenderstool – Lambda (no VPC, internet access).

Fetches licitaciones from the TendersTool REST API and writes them to S3
in the same JSON format expected by the scraper_write Lambda, which picks
them up via S3 ObjectCreated and upserts into RDS.

Runs daily at 06:00 Europe/Madrid (before the portal scraper at 20:00),
so both sources complement each other.

Environment variables required:
  TENDERSTOOL_SECRET_ARN – Secrets Manager ARN with TendersTool credentials
                           {"username": "...", "password": "..."}
  S3_BUCKET              – S3 bucket for staging data (same as scraper)
"""

import json
import logging
import os
import re
import urllib.request
import urllib.parse
import urllib.error
from datetime import date, timedelta

import boto3

log = logging.getLogger()
log.setLevel(logging.INFO)

BASE_URL   = "https://apies.tenderstool.com"
PAGE_SIZE  = 50   # safe page size to avoid timeouts


# ── Enum translation tables ───────────────────────────────────────────────────
# Maps TendersTool string values → our PostgreSQL enum values.
# Unknown values map to None (stored as NULL rather than crashing).

_PROCEDURE_MAP = {
    # English → DB enum exact value
    "open":                              "Abierto",
    "open simplified":                   "Simplificado",
    "simplified":                        "Simplificado",
    "restricted":                        "Restringido",
    "negotiated without publication":    "Negociado sin Publicidad",
    "negotiated with publication":       "Negociado con Publicidad",
    "competitive dialogue":              "Diálogo Competitivo",
    "competitive procedure with negotiation": "Negociado con Publicidad",
    "minor contract":                    "Contrato Menor",
    "framework agreement":               "Acuerdo Marco",
    "dynamic purchasing system":         "Sistema Dinámico de Adquisición",
    # Spanish (exact DB enum values — TendersTool returns Spanish strings)
    "abierto":                           "Abierto",
    "simplificado":                      "Simplificado",
    "abierto simplificado":              "Simplificado",
    "restringido":                       "Restringido",
    "negociado sin publicidad":          "Negociado sin Publicidad",
    "negociado con publicidad":          "Negociado con Publicidad",
    "negociado":                         "Negociado",
    "diálogo competitivo":               "Diálogo Competitivo",
    "procedimiento con negociación":     "Negociado con Publicidad",
    "contrato menor":                    "Contrato Menor",
    "acuerdo marco":                     "Acuerdo Marco",
    "sistema dinámico de adquisición":   "Sistema Dinámico de Adquisición",
    "normas internas":                   "Normas internas",
    "negociado por exclusividad":        "Negociado por exclusividad",
}

_TRAMITACION_MAP = {
    "ordinary":     "Ordinaria",
    "ordinaria":    "Ordinaria",
    "urgent":       "Urgente",
    "urgente":      "Urgente",
    "emergency":    "Emergencia",
    "emergencia":   "Emergencia",
}

_MERCADO_MAP = {
    # TendersTool vertical_market values → DB mercado_vertical_tipo exact values
    "ciencia e innovación":              "CIENCIA E INNOVACIÓN",
    "defensa":                           "DEFENSA",
    "economía y hacienda":               "ECONOMÍA Y HACIENDA",
    "educación":                         "EDUCACIÓN",
    "educación, cultura y deportes":     "EDUCACIÓN CULTURA Y DEPORTES",
    "educación cultura y deportes":      "EDUCACIÓN CULTURA Y DEPORTES",
    "empleo y seguridad social":         "EMPLEO Y SEGURIDAD SOCIAL",
    "fomento":                           "FOMENTO",
    "industria, energía y turismo":      "INDUSTRIA ENERGÍA Y TURISMO",
    "industria energía y turismo":       "INDUSTRIA ENERGÍA Y TURISMO",
    "información y comunicaciones":      "INFORMACIÓN Y COMUNICACIONES",
    "interior":                          "INTERIOR",
    "interior, emergencias  y protección civil": "INTERIOR EMERGENCIAS Y PROTECCIÓN CIVIL",
    "interior emergencias y protección civil":   "INTERIOR EMERGENCIAS Y PROTECCIÓN CIVIL",
    "justicia":                          "OTROS",
    "medioambiente":                     "OTROS",
    "otros":                             "OTROS",
    "otros eell":                        "OTROS EELL",
    "sanidad":                           "SANIDAD",
    "transporte":                        "TRANSPORTE",
}

_CCAA_MAP = {
    # Keys lowercase; values = EXACT DB comunidad_autonoma_tipo enum values
    "andalucía":                         "Andalucía",
    "andalucia":                         "Andalucía",
    "aragón":                            "Aragón",
    "aragon":                            "Aragón",
    "asturias":                          "Asturias Principado de",
    "principado de asturias":            "Asturias Principado de",
    "asturias principado de":            "Asturias Principado de",
    "baleares":                          "Illes Balears",
    "islas baleares":                    "Illes Balears",
    "illes balears":                     "Illes Balears",
    "canarias":                          "Canarias",
    "cantabria":                         "Cantabria",
    "castilla la mancha":                "Castilla - La Mancha",
    "castilla-la mancha":                "Castilla - La Mancha",
    "castilla - la mancha":              "Castilla - La Mancha",
    "castilla y leon":                   "Castilla y León",
    "castilla y león":                   "Castilla y León",
    "cataluña":                          "Catalunya",
    "cataluna":                          "Catalunya",
    "catalunya":                         "Catalunya",
    "extremadura":                       "Extremadura",
    "galicia":                           "Galicia",
    "la rioja":                          "Rioja La",
    "rioja la":                          "Rioja La",
    "madrid":                            "Madrid Comunidad de",
    "comunidad de madrid":               "Madrid Comunidad de",
    "madrid comunidad de":               "Madrid Comunidad de",
    "murcia":                            "Murcia Región de",
    "región de murcia":                  "Murcia Región de",
    "murcia región de":                  "Murcia Región de",
    "navarra":                           "Navarra Comunidad Floral de",
    "comunidad foral de navarra":        "Navarra Comunidad Floral de",
    "navarra comunidad foral de":        "Navarra Comunidad Floral de",
    "pais vasco":                        "País Vasco",
    "país vasco":                        "País Vasco",
    "valencia":                          "Comunitat Valenciana",
    "comunitat valenciana":              "Comunitat Valenciana",
    "ceuta":                             "Ceuta",
    "ciudad de ceuta":                   "Ceuta",
    "melilla":                           "Melilla",
    "ciudad de melilla":                 "Melilla",
    "hacienda y administraciones públicas": None,
}

# TendersTool categories → DB mercado_vertical_tipo enum values.
# Categories are consistently populated when vertical_market is null.
# First matching category wins (ordered most-specific to generic).
_CATEGORY_MERCADO_MAP = {
    # INFORMACIÓN Y COMUNICACIONES — IT/tech categories
    "it/tecnología":                          "INFORMACIÓN Y COMUNICACIONES",
    "microinformática":                       "INFORMACIÓN Y COMUNICACIONES",
    "desarrollo de software":                 "INFORMACIÓN Y COMUNICACIONES",
    "software":                               "INFORMACIÓN Y COMUNICACIONES",
    "otros software":                         "INFORMACIÓN Y COMUNICACIONES",
    "software específico":                    "INFORMACIÓN Y COMUNICACIONES",
    "outsourcing it":                         "INFORMACIÓN Y COMUNICACIONES",
    "integración/migración de sistemas":      "INFORMACIÓN Y COMUNICACIONES",
    "sistemas de control":                    "INFORMACIÓN Y COMUNICACIONES",
    "sistemas autónomos":                     "INFORMACIÓN Y COMUNICACIONES",
    "hardware":                               "INFORMACIÓN Y COMUNICACIONES",
    "mantenimiento aplicaciones/software":    "INFORMACIÓN Y COMUNICACIONES",
    "mantenimiento sistemas/hardware":        "INFORMACIÓN Y COMUNICACIONES",
    "tecnología":                             "INFORMACIÓN Y COMUNICACIONES",
    "cloud":                                  "INFORMACIÓN Y COMUNICACIONES",
    "cloud computing":                        "INFORMACIÓN Y COMUNICACIONES",
    "telecomunicaciones":                     "INFORMACIÓN Y COMUNICACIONES",
    "redes de telecomunicaciones (hardware)": "INFORMACIÓN Y COMUNICACIONES",
    "redes y comunicaciones":                 "INFORMACIÓN Y COMUNICACIONES",
    "impresoras/multifuncionales/scanner":    "INFORMACIÓN Y COMUNICACIONES",
    "impresión/pago por uso":                 "INFORMACIÓN Y COMUNICACIONES",
    "impresión":                              "INFORMACIÓN Y COMUNICACIONES",
    "audiovisual":                            "INFORMACIÓN Y COMUNICACIONES",
    "av":                                     "INFORMACIÓN Y COMUNICACIONES",
    "electromedicina":                        "SANIDAD",
    "ciberseguridad":                         "INTERIOR EMERGENCIAS Y PROTECCIÓN CIVIL",
    "seguridad/rgpd":                         "INTERIOR EMERGENCIAS Y PROTECCIÓN CIVIL",
    "software de seguridad":                  "INTERIOR EMERGENCIAS Y PROTECCIÓN CIVIL",
    "servicios de ciberseguridad - soc":      "INTERIOR EMERGENCIAS Y PROTECCIÓN CIVIL",
    # OTROS — generic service/consulting categories
    "helpdesk":                               "OTROS",
    "oficina técnica":                        "OTROS",
    "outsourcing":                            "OTROS",
    "consultoría":                            "OTROS",
    "asistencia técnica":                     "OTROS",
    "mantenimiento":                          "OTROS",
    "servicios":                              "OTROS",
    "negocio":                                "OTROS",
}

# Source URL domain → DB comunidad_autonoma_tipo exact enum values.
# Used when jurisdiction/scope is null.
_DOMAIN_CCAA_MAP = {
    "contractaciopublica.cat":              "Catalunya",
    "www.contractaciopublica.cat":          "Catalunya",
    "contratacion.gob.es":                  None,   # Estado not in enum
    "sede.contratos.hacienda.gob.es":       None,
    "contrataciondelestado.es":             None,
    "www.contrataciondelestado.es":         None,
    "contratacion.madrid.org":              "Madrid Comunidad de",
    "www.comunidad.madrid":                 "Madrid Comunidad de",
    "contratacion.juntadeandalucia.es":     "Andalucía",
    "www.juntadeandalucia.es":              "Andalucía",
    "www.aragon.es":                        "Aragón",
    "contratacion.aragon.es":               "Aragón",
    "contratacion.asturias.es":             "Asturias Principado de",
    "www.asturias.es":                      "Asturias Principado de",
    "www.caib.es":                          "Illes Balears",
    "contratacion.caib.es":                 "Illes Balears",
    "www.gobiernodecanarias.org":           "Canarias",
    "contratacion.cantabria.es":            "Cantabria",
    "www.cantabria.es":                     "Cantabria",
    "contratacion.jccm.es":                 "Castilla - La Mancha",
    "contratacion.jcyl.es":                 "Castilla y León",
    "contratacion.gva.es":                  "Comunitat Valenciana",
    "www.contratosdelalep.es":              "Extremadura",
    "contratacion.xunta.gal":               "Galicia",
    "www.riojasalud.es":                    "Rioja La",
    "contratacion.larioja.org":             "Rioja La",
    "contratacion.carm.es":                 "Murcia Región de",
    "www.navarra.es":                       "Navarra Comunidad Floral de",
    "contratacion.navarra.es":              "Navarra Comunidad Floral de",
    "www.euskadi.eus":                      "País Vasco",
    "contratacion.euskadi.eus":             "País Vasco",
}


def lambda_handler(event, context):
    secret_arn = os.environ["TENDERSTOOL_SECRET_ARN"]
    bucket     = os.environ["S3_BUCKET"]
    today      = date.today()

    # Determine date window: event can override for backfill
    days_back = int(event.get("days_back", 2))
    date_from = (today - timedelta(days=days_back)).isoformat()

    creds = _get_secret(secret_arn)
    token = _get_token(creds.get("email") or creds["username"], creds["password"])
    log.info("TendersTool auth OK")

    # Licitaciones come exclusively from the portal scraper (adjudicacionestic.com)
    # which provides complete data (organismo, provincia, CCAA, criterios, etc.).
    # TendersTool is used only for adjudicaciones which it covers well.
    awards = _fetch_all_awards(token, date_from)
    log.info("Fetched %d awards from TendersTool (date_from=%s)", len(awards), date_from)

    adjudicaciones = [_map_award(a) for a in awards]
    adjudicaciones = [r for r in adjudicaciones if r]

    _write_s3(bucket, f"scrapes/tenderstool-{today.isoformat()}.json", [], adjudicaciones)
    log.info("Wrote 0 licitaciones + %d adjudicaciones to S3", len(adjudicaciones))

    return {
        "statusCode": 200,
        "ingested_licitaciones": 0,
        "ingested_adjudicaciones": len(adjudicaciones),
        "date_from": date_from,
    }


# ── API helpers ───────────────────────────────────────────────────────────────

def _get_token(username: str, password: str) -> str:
    payload = json.dumps({"email": username, "password": password}).encode()
    req = urllib.request.Request(
        f"{BASE_URL}/api/v1/auth/login",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = json.loads(resp.read())
    return data["access_token"]


def _api_get(token: str, path: str, params: dict = None) -> dict:
    url = f"{BASE_URL}{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(
        url,
        headers={"Authorization": f"Bearer {token}"},
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read())


def _fetch_all_awards(token: str, date_from: str) -> list:
    all_awards = []
    page = 1
    while True:
        params = {"date_from": date_from, "page": page, "page_size": PAGE_SIZE}
        try:
            data = _api_get(token, "/api/v1/awards/", params)
        except Exception as e:
            log.error("Error fetching awards page %d: %s", page, e)
            break

        results = data.get("items") or []
        if not results:
            break

        all_awards.extend(results)
        total_pages = data.get("pages") or 1
        log.info("Awards page %d/%d: %d items (total so far: %d)", page, total_pages, len(results), len(all_awards))

        if page >= total_pages or len(results) < PAGE_SIZE:
            break
        page += 1

    return all_awards


def _fetch_all_tenders(token: str, date_from: str) -> list:
    all_tenders = []
    page = 1
    while True:
        params = {
            "date_from": date_from,
            "page":      page,
            "page_size": PAGE_SIZE,
        }
        try:
            data = _api_get(token, "/api/v1/tenders/", params)
        except Exception as e:
            log.error("Error fetching page %d: %s", page, e)
            break

        results = data.get("items") or data.get("results") or data.get("tenders") or []
        if not results:
            break

        all_tenders.extend(results)
        total_pages = data.get("pages") or 1
        log.info("Page %d/%d: %d tenders (total so far: %d)", page, total_pages, len(results), len(all_tenders))

        if page >= total_pages or len(results) < PAGE_SIZE:
            break

        page += 1

    return all_tenders


# ── Field mapping ─────────────────────────────────────────────────────────────

def _map_tender(t: dict) -> dict | None:
    try:
        external_id = str(t.get("id", "")).strip()
        titulo      = (t.get("title") or "").strip()
        if not external_id or not titulo:
            return None

        # CPV codes: list of {code, description} objects
        cpv_list  = t.get("cpv") or t.get("cpv_codes") or []
        cpv_pairs = [(c.get("code", ""), c.get("description", c.get("code", "")))
                     for c in cpv_list if c.get("code")]

        # Organismo
        cb              = t.get("contracting_body") or {}
        organismo_nombre = (cb.get("name") or "").strip() or None

        # Numeric fields — API may send strings or None
        importe    = _to_float(t.get("tender_amount"))
        estimado   = _to_float(t.get("estimated_value"))
        duracion   = _to_int(t.get("duration_months"))
        prorrogas  = _to_int(t.get("renewal_months"))

        # Enum fields
        procedimiento = _map_enum(
            t.get("procedure_type"), _PROCEDURE_MAP
        )
        tramitacion = _map_enum(
            t.get("processing_type"), _TRAMITACION_MAP
        )
        # mercado_vertical: prefer our IT-focused enum mapping of vertical_market,
        # fall back to categories (consistently populated, maps well to our enum).
        mercado = (
            _map_enum(t.get("vertical_market"), _MERCADO_MAP)
            or _mercado_from_categories(t.get("categories"))
        )

        # CCAA: prefer jurisdiction/scope, fall back to source portal URL domain.
        ccaa = (
            _map_enum(t.get("jurisdiction") or cb.get("scope"), _CCAA_MAP)
            or _ccaa_from_url(t.get("url"))
        )

        # Dates
        fecha         = _to_date(t.get("publication_date"))
        fecha_limite  = _to_date(t.get("submission_deadline"))

        # Scoring criteria — usually NULL in API but include when present
        puntos_precio     = _to_float(t.get("price_points") or
                                       (t.get("objective_criteria") or {}).get("price_points"))
        puntos_mejoras    = _to_float(t.get("improvement_points") or
                                       (t.get("objective_criteria") or {}).get("improvement_points"))
        puntos_subjetivos = _to_float(t.get("subjective_points") or
                                       (t.get("subjective_criteria") or {}).get("total_points"))

        return {
            "external_id":        external_id,
            "titulo":             titulo,
            "numero_expediente":  (t.get("reference_number") or "").strip(),
            "organismo_nombre":   organismo_nombre,
            "fecha":              fecha,
            "fecha_limite_oferta": fecha_limite,
            "importe_licitacion": importe,
            "valor_estimado":     estimado,
            "tipo_procedimiento": procedimiento,
            "tipo_tramitacion":   tramitacion,
            "duracion_meses":     duracion,
            "prorrogas_meses":    prorrogas,
            "mercado_vertical":   mercado,
            "comunidad_autonoma": ccaa,
            "provincia":          None,   # not available from TendersTool
            "puntos_precio":      puntos_precio,
            "puntos_mejoras":     puntos_mejoras,
            "puntos_subjetivos":  puntos_subjetivos,
            "cpv_pairs":          cpv_pairs,
        }
    except Exception as e:
        log.warning("Failed to map tender %s: %s", t.get("id"), e)
        return None


def _map_award(a: dict) -> dict | None:
    try:
        external_id = str(a.get("id", "")).strip()
        titulo      = (a.get("title") or "").strip()
        if not external_id or not titulo:
            return None

        cb                 = a.get("contracting_body") or {}
        organismo_nombre   = (cb.get("name") or "").strip() or None

        main_contractor    = a.get("main_contractor") or {}
        contractors        = a.get("contractors") or []
        adjudicatario_nombre = (
            main_contractor.get("name")
            or (contractors[0].get("name") if contractors else None)
            or None
        )

        cpv_list  = a.get("cpv") or []
        cpv_codes = [c["code"] for c in cpv_list if c.get("code")]

        importe_licitacion  = _to_float(a.get("tender_amount"))
        importe_adjudicado  = _to_float(a.get("award_amount"))
        valor_estimado      = _to_float(a.get("estimated_value"))

        procedimiento = _map_enum(a.get("procedure_type"), _PROCEDURE_MAP)
        tramitacion   = _map_enum(a.get("processing_type"), _TRAMITACION_MAP)
        mercado = (
            _map_enum(a.get("vertical_market"), _MERCADO_MAP)
            or _mercado_from_categories(a.get("categories"))
        )
        ccaa = (
            _map_enum(a.get("jurisdiction") or cb.get("scope"), _CCAA_MAP)
            or _ccaa_from_url(a.get("url"))
        )

        fecha_adj  = _to_date(a.get("award_date"))
        fecha_venc = _to_date(a.get("execution_deadline"))

        ratio = None
        if importe_licitacion and importe_adjudicado and importe_licitacion > 0:
            ratio = round(importe_adjudicado / importe_licitacion, 4)

        return {
            "external_id":                   external_id,
            "titulo":                         titulo,
            "numero_expediente":              (a.get("reference_number") or "").strip(),
            "organismo_nombre":               organismo_nombre,
            "adjudicatario_nombre":           adjudicatario_nombre,
            "fecha_adjudicacion":             fecha_adj,
            "importe_licitacion":             importe_licitacion,
            "importe_adjudicado":             importe_adjudicado,
            "ratio_adjudicacion_vs_licitacion": ratio,
            "valor_estimado":                 valor_estimado,
            "tipo_procedimiento":             procedimiento,
            "tipo_tramitacion":               tramitacion,
            "fecha_vencimiento_contrato":     fecha_venc,
            "comunidad_autonoma":             ccaa,
            "provincia":                      None,
            "mercado_vertical":               mercado,
            "cpv_codes":                      cpv_codes,
        }
    except Exception as e:
        log.warning("Failed to map award %s: %s", a.get("id"), e)
        return None


# ── Conversion helpers ────────────────────────────────────────────────────────

def _to_float(val) -> float | None:
    if val is None:
        return None
    try:
        return float(str(val).replace(",", "."))
    except (ValueError, TypeError):
        return None


def _to_int(val) -> int | None:
    if val is None:
        return None
    try:
        return int(val)
    except (ValueError, TypeError):
        return None


def _to_date(val) -> str | None:
    """Normalise API date strings to YYYY-MM-DD."""
    if not val:
        return None
    s = str(val).strip()
    # Already YYYY-MM-DD or ISO datetime
    m = re.match(r"(\d{4}-\d{2}-\d{2})", s)
    if m:
        return m.group(1)
    # DD/MM/YYYY
    m = re.match(r"(\d{2})/(\d{2})/(\d{4})", s)
    if m:
        return f"{m.group(3)}-{m.group(2)}-{m.group(1)}"
    return None


def _map_enum(val, table: dict):
    if not val:
        return None
    return table.get(str(val).lower().strip())


def _mercado_from_categories(categories: list) -> str | None:
    """Derive mercado_vertical from TendersTool category list (first match wins)."""
    for cat in (categories or []):
        title = (cat.get("title") or "").lower().strip()
        if title in _CATEGORY_MERCADO_MAP:
            return _CATEGORY_MERCADO_MAP[title]
    return None


def _ccaa_from_url(url: str | None) -> str | None:
    """Infer comunidad_autonoma from the source portal URL domain."""
    if not url:
        return None
    try:
        from urllib.parse import urlparse
        domain = urlparse(url).netloc.lower()
        if domain in _DOMAIN_CCAA_MAP:
            return _DOMAIN_CCAA_MAP[domain]
        # Try stripping www. prefix
        if domain.startswith("www."):
            return _DOMAIN_CCAA_MAP.get(domain[4:])
    except Exception:
        pass
    return None


# ── AWS helpers ───────────────────────────────────────────────────────────────

def _get_secret(secret_arn: str) -> dict:
    sm   = boto3.client("secretsmanager")
    resp = sm.get_secret_value(SecretId=secret_arn)
    return json.loads(resp["SecretString"])


def _write_s3(bucket: str, key: str, licitaciones: list, adjudicaciones: list = None) -> None:
    payload = json.dumps({
        "scrape_date":    date.today().isoformat(),
        "licitaciones":   licitaciones,
        "adjudicaciones": adjudicaciones or [],
    }, ensure_ascii=False).encode()
    boto3.client("s3").put_object(
        Bucket=bucket, Key=key, Body=payload, ContentType="application/json",
    )
    log.info("Wrote %d bytes → s3://%s/%s", len(payload), bucket, key)
