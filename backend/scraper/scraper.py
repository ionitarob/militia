"""
IMLiti Scraper — Azure Container App Job.

Replaces the two-Lambda (scraper_fetch + scraper_write) design.
Runs as a single Python process with no Lambda timeout constraints.

Modes (set via SCRAPER_MODE env var, default: daily):
  daily        – fetch new licitaciones (7-day window) + adjudicaciones
  refresh_open – re-fetch detail pages for licitaciones still open in DB

Environment variables required:
  SCRAPER_MODE            – daily | refresh_open (default: daily)
  PORTAL_USERNAME         – portal login
  PORTAL_PASSWORD         – portal password
  DATABASE_URL            – postgresql://...
  AZURE_STORAGE_ACCOUNT   – blob storage account name
  AZURE_STORAGE_KEY       – blob storage account key
  AZURE_BLOB_CONTAINER    – blob container name (default: documents)
  DAILY_WINDOW_DAYS       – days to look back in listing (default: 7)
"""

import hashlib
import json
import logging
import os
import re
import sys
from datetime import date, timedelta

from azure.storage.blob import BlobServiceClient, ContentSettings
from azure.core.exceptions import ResourceNotFoundError

import db
import parsers
import portal

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    stream=sys.stdout,
)
log = logging.getLogger(__name__)

BASE          = "https://www.adjudicacionestic.com/front"
ADJ_PAGES_MAX = 10
DAILY_WINDOW  = int(os.environ.get("DAILY_WINDOW_DAYS", "7"))


def main():
    mode         = os.environ.get("SCRAPER_MODE", "daily")
    portal_user  = os.environ["PORTAL_USERNAME"]
    portal_pass  = os.environ["PORTAL_PASSWORD"]
    db_url       = os.environ["DATABASE_URL"]
    blob_account = os.environ["AZURE_STORAGE_ACCOUNT"]
    blob_key     = os.environ["AZURE_STORAGE_KEY"]
    blob_container = os.environ.get("AZURE_BLOB_CONTAINER", "documents")

    blob_client = BlobServiceClient(
        account_url=f"https://{blob_account}.blob.core.windows.net",
        credential=blob_key,
    )
    conn = db.build_conn(db_url)

    creds = {"username": portal_user, "password": portal_pass}

    if mode == "refresh_open":
        _run_refresh_open(creds, blob_client, blob_container, conn)
    else:
        _run_daily(creds, blob_client, blob_container, conn)

    conn.close()
    log.info("Done.")


# ── Daily mode ────────────────────────────────────────────────────────────────

def _run_daily(creds, blob_client, blob_container, conn):
    today     = date.today()
    date_from = (today - timedelta(days=DAILY_WINDOW)).strftime("%d/%m/%Y")
    date_to   = today.strftime("%d/%m/%Y")

    session = portal.create_session(creds["username"], creds["password"])
    log.info("Login successful")

    cache = _load_blob_cache(blob_client, blob_container, today)
    log.info("Cache: %d licitaciones, %d adjudicaciones", len(cache["lic"]), len(cache["adj"]))

    resp = portal.post(session, f"{BASE}/licitaciones.php", {
        "buscador_fecha_inicio": date_from,
        "buscador_fecha_fin":    date_to,
    }, delay=0.5)
    listing_rows = parsers.parse_licitacion_listing(resp.text)
    log.info("Listing: %d rows", len(listing_rows))

    cached_records = []
    rows_to_fetch  = []
    for row in listing_rows:
        eid    = row["external_id"]
        cached = cache["lic"].get(eid)
        if cached and not _deadline_is_open(cached, today):
            cached_records.append({**cached, **_fresh_listing_fields(row)})
        else:
            rows_to_fetch.append(row)

    log.info("%d from cache, %d need fetch", len(cached_records), len(rows_to_fetch))

    fetched_records = _fetch_detail_pages(session, rows_to_fetch, blob_client, blob_container)
    licitaciones = cached_records + fetched_records
    log.info("Licitaciones done: %d total", len(licitaciones))

    adj_ids = _fetch_adj_ids(session, date_from, date_to)
    log.info("Found %d adjudicacion IDs", len(adj_ids))
    adjudicaciones = []
    for eid in adj_ids:
        if eid in cache["adj"]:
            adjudicaciones.append(cache["adj"][eid])
        else:
            try:
                r      = portal.get(session, f"{BASE}/adjudicaciones-ficha.php?id={eid}", delay=0.3)
                detail = parsers.parse_adjudicacion_detail(r.text, eid)
                adjudicaciones.append(detail)
            except Exception as e:
                log.warning("adjudicacion %s failed: %s", eid, e)

    log.info("Adjudicaciones done: %d total", len(adjudicaciones))

    _write_blob_cache(blob_client, blob_container, f"scrapes/{today.isoformat()}.json",
                      licitaciones, adjudicaciones)

    _write_to_db(conn, licitaciones, adjudicaciones)
    log.info("Daily done: %d licitaciones, %d adjudicaciones written to DB",
             len(licitaciones), len(adjudicaciones))


# ── Refresh-open mode ─────────────────────────────────────────────────────────

def _run_refresh_open(creds, blob_client, blob_container, conn):
    today = date.today()

    with conn.cursor() as cur:
        cur.execute("""
            SELECT external_id FROM licitacion
            WHERE external_id IS NOT NULL
              AND fecha_limite_oferta IS NOT NULL
              AND fecha_limite_oferta >= CURRENT_DATE
            ORDER BY fecha_limite_oferta ASC
        """)
        active_ids = [row[0] for row in cur.fetchall()]

    log.info("refresh_open: %d open licitaciones to refresh", len(active_ids))
    if not active_ids:
        return

    session = portal.create_session(creds["username"], creds["password"])
    log.info("Login successful")

    refreshed = []
    for i, eid in enumerate(active_ids):
        try:
            resp      = portal.get(session, f"{BASE}/licitaciones-ficha.php?id={eid}", delay=0.2)
            detail    = parsers.parse_licitacion_detail(resp.text, eid)
            doc_links = parsers.parse_documents(resp.text)
            detail["documents"] = _download_documents(session, eid, doc_links, blob_client, blob_container)
            refreshed.append(detail)
        except Exception as e:
            log.warning("refresh licitacion %s failed: %s", eid, e)

        if (i + 1) % 50 == 0:
            log.info("  refreshed %d/%d", i + 1, len(active_ids))

    _write_blob_cache(blob_client, blob_container,
                      f"scrapes/refresh-{today.isoformat()}.json", refreshed, [])
    _write_to_db(conn, refreshed, [])
    log.info("refresh_open done: %d refreshed", len(refreshed))


# ── Document download ─────────────────────────────────────────────────────────

_ALLOWED_TYPES = {
    "application/pdf",
    "application/msword",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "application/vnd.ms-excel",
    "application/zip",
    "application/x-zip-compressed",
    "application/vnd.oasis.opendocument.text",
    "application/rtf",
    "text/rtf",
}
_MAGIC_TYPES = [
    (b"%PDF",              "application/pdf",    ".pdf"),
    (b"PK\x03\x04",       None,                  None),
    (b"\xd0\xcf\x11\xe0", "application/msword", ".doc"),
]
_EXT_MAP = {
    "application/pdf":    ".pdf",
    "application/msword": ".doc",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document": ".docx",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": ".xlsx",
    "application/vnd.ms-excel": ".xls",
    "application/zip":    ".zip",
    "application/x-zip-compressed": ".zip",
    "application/vnd.oasis.opendocument.text": ".odt",
    "application/rtf":    ".rtf",
    "text/rtf":           ".rtf",
}


def _download_documents(session, external_id: str, doc_links: list,
                        blob_client: BlobServiceClient, blob_container: str) -> list:
    uploaded = []
    container = blob_client.get_container_client(blob_container)

    for doc in doc_links:
        href   = doc["href"]
        nombre = doc["nombre"]
        url    = href if href.startswith("http") else f"{BASE}/{href.lstrip('/')}"
        try:
            resp = session.get(url, timeout=60, allow_redirects=True)
            if resp.status_code != 200:
                log.warning("doc %s → HTTP %d", nombre, resp.status_code)
                continue

            content_type = resp.headers.get("Content-Type", "").split(";")[0].strip()

            if content_type not in _ALLOWED_TYPES:
                inferred = None
                for magic, ct, _ in _MAGIC_TYPES:
                    if resp.content[:len(magic)] == magic:
                        inferred = ct
                        break
                if inferred:
                    content_type = inferred
                else:
                    log.warning("Skipping doc %s (type=%s, no magic match)", nombre, content_type)
                    continue

            ext = _EXT_MAP.get(content_type)
            if ext is None:
                cd = resp.headers.get("Content-Disposition", "")
                m  = re.search(r'filename=["\']?([^"\';\s]+)', cd)
                ext = ("." + m.group(1).rsplit(".", 1)[-1].lower()) if m and "." in m.group(1) else ".bin"

            safe      = re.sub(r"[^\w\- ]", "_", nombre)[:80].strip("_") or "documento"
            href_hash = hashlib.md5(href.encode()).hexdigest()[:8]
            blob_key  = f"documents/{external_id}/{safe}_{href_hash}{ext}"

            container.upload_blob(
                name=blob_key,
                data=resp.content,
                content_settings=ContentSettings(content_type=content_type),
                overwrite=True,
            )
            uploaded.append({
                "nombre":       nombre,
                "s3_key":       blob_key,
                "content_type": content_type,
                "size_bytes":   len(resp.content),
                "source_url":   url,
            })
            log.info("Uploaded %s → blob:%s (%d bytes)", nombre, blob_key, len(resp.content))
        except Exception as e:
            log.warning("doc download failed %s: %s", nombre, e)

    return uploaded


# ── DB write ──────────────────────────────────────────────────────────────────

def _write_to_db(conn, licitaciones: list, adjudicaciones: list):
    inserted_lic = inserted_adj = errors = 0

    for rec in licitaciones:
        try:
            with conn:
                with conn.cursor() as cur:
                    row_id = db.upsert_licitacion(cur, rec)
            if row_id:
                inserted_lic += 1
        except Exception as e:
            log.warning("licitacion %s upsert error: %s", rec.get("external_id"), e)
            errors += 1

    for rec in adjudicaciones:
        try:
            with conn:
                with conn.cursor() as cur:
                    row_id = db.upsert_adjudicacion(cur, rec)
            if row_id:
                inserted_adj += 1
        except Exception as e:
            log.warning("adjudicacion %s upsert error: %s", rec.get("external_id"), e)
            errors += 1

    log.info("DB: %d licitaciones, %d adjudicaciones inserted, %d errors",
             inserted_lic, inserted_adj, errors)


# ── Blob cache (replaces S3 staging) ─────────────────────────────────────────

def _write_blob_cache(blob_client, container_name, key, licitaciones, adjudicaciones):
    payload = json.dumps({
        "scrape_date":    date.today().isoformat(),
        "licitaciones":   licitaciones,
        "adjudicaciones": adjudicaciones,
    }, ensure_ascii=False).encode()
    blob_client.get_container_client(container_name).upload_blob(
        name=key, data=payload, overwrite=True,
        content_settings=ContentSettings(content_type="application/json"),
    )
    log.info("Cache written → blob:%s (%d bytes)", key, len(payload))


def _load_blob_cache(blob_client, container_name, today: date) -> dict:
    container = blob_client.get_container_client(container_name)
    lic: dict = {}
    adj: dict = {}
    for days_back in range(1, 8):
        key = f"scrapes/{(today - timedelta(days=days_back)).isoformat()}.json"
        try:
            data = json.loads(
                container.download_blob(key).readall()
            )
            for rec in data.get("licitaciones", []):
                eid = rec.get("external_id")
                if eid and eid not in lic:
                    lic[eid] = rec
            for rec in data.get("adjudicaciones", []):
                eid = rec.get("external_id")
                if eid and eid not in adj:
                    adj[eid] = rec
        except ResourceNotFoundError:
            pass
        except Exception as e:
            log.warning("Cache load %s: %s", key, e)
    return {"lic": lic, "adj": adj}


# ── Shared helpers ────────────────────────────────────────────────────────────

def _fetch_detail_pages(session, rows, blob_client, blob_container):
    completed = []
    for i, row in enumerate(rows):
        eid = row["external_id"]
        try:
            dr        = portal.get(session, f"{BASE}/licitaciones-ficha.php?id={eid}", delay=0.3)
            detail    = parsers.parse_licitacion_detail(dr.text, eid)
            doc_links = parsers.parse_documents(dr.text)
            detail["documents"] = _download_documents(session, eid, doc_links, blob_client, blob_container)
            completed.append({**row, **detail})
        except Exception as e:
            log.warning("licitacion %s failed: %s", eid, e)
        if (i + 1) % 50 == 0:
            log.info("  %d/%d detail pages fetched", i + 1, len(rows))
    return completed


def _fetch_adj_ids(session, date_from, date_to) -> set:
    adj_ids: set = set()
    for page in range(1, ADJ_PAGES_MAX + 1):
        resp    = portal.post(session, f"{BASE}/adjudicaciones.php", {
            "defecto":               "NO",
            "buscador_fecha_inicio": date_from,
            "buscador_fecha_fin":    date_to,
            "paginacion_indice":     str(page),
        }, delay=0.4)
        ids     = parsers.parse_adjudicacion_listing_ids(resp.text)
        new_ids = set(ids) - adj_ids
        if not new_ids:
            break
        adj_ids.update(new_ids)
        log.info("  adj page %d: %d new ids", page, len(new_ids))
    return adj_ids


def _deadline_is_open(cached: dict, today: date) -> bool:
    raw = cached.get("fecha_limite_oferta")
    if not raw:
        return False
    try:
        return date.fromisoformat(str(raw)[:10]) >= today
    except ValueError:
        return False


def _fresh_listing_fields(row: dict) -> dict:
    return {k: v for k, v in row.items() if k in (
        "fecha", "importe_licitacion", "fecha_limite_oferta",
        "puntos_precio", "puntos_mejoras", "puntos_subjetivos",
        "numero_expediente", "tipo_procedimiento",
    )}


if __name__ == "__main__":
    main()
