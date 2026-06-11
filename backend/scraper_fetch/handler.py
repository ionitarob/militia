"""
scraper_fetch – Lambda A (no VPC, internet access).

Two modes, selected by the event payload  {"mode": "daily" | "refresh_open"}:

  daily        – fetch NEW licitaciones (7-day listing window) + new adjudicaciones.
                 Uses S3 cache to skip records already known whose deadline passed.
                 Auto-checkpoints: if ~90 s remain, writes completed records to
                 a partial S3 file and re-invokes self with remaining IDs — so a
                 cold-start 7-day ingest (~390 records, ~17 min) runs across two
                 Lambda invocations automatically, with no manual intervention.
                 Runs daily at 20:00 Europe/Madrid via EventBridge.

  refresh_open – re-fetch detail pages for licitaciones still open in the DB
                 (fecha_limite_oferta >= today).  Queries Aurora via Data API so
                 we track field changes (deadline extensions, cancellations) even
                 after the record falls outside the publication window.
                 Runs every 3 days at 08:00 Europe/Madrid via EventBridge.
                 Self-re-invokes with an offset if the batch is too large for
                 one Lambda execution.

Environment variables required:
  PORTAL_SECRET_ARN  – Secrets Manager ARN with portal credentials
  S3_BUCKET          – S3 bucket for staging scraped data
  DB_CLUSTER_ARN     – Aurora cluster ARN (refresh_open only)
  DB_SECRET_ARN      – Aurora master secret ARN (refresh_open only)
"""

import json
import logging
import os
import re
from datetime import date, timedelta

import boto3
from botocore.exceptions import ClientError

import portal
import parsers

log = logging.getLogger()
log.setLevel(logging.INFO)

BASE           = "https://www.adjudicacionestic.com/front"
ADJ_PAGES_MAX  = 10
DAILY_WINDOW   = int(os.environ.get("DAILY_WINDOW_DAYS", "7"))
REFRESH_BATCH  = int(os.environ.get("REFRESH_BATCH_SIZE", "200"))
MIN_TIME_MS    = 90_000  # re-invoke self when less than 90 s remain


def lambda_handler(event, context):
    mode       = event.get("mode", "daily")
    secret_arn = os.environ["PORTAL_SECRET_ARN"]
    bucket     = os.environ["S3_BUCKET"]
    creds      = _get_portal_creds(secret_arn)

    if mode == "refresh_open":
        return _run_refresh_open(event, context, creds, bucket)
    if mode == "refresh_all":
        return _run_refresh_all(event, context, creds, bucket)
    if mode == "scrape_documents":
        return _run_scrape_documents(event, context, creds, bucket)
    return _run_daily(event, context, creds, bucket)


# ── Daily mode ────────────────────────────────────────────────────────────────

def _run_daily(event, context, creds, bucket):
    """
    Two sub-cases:
    (a) Normal start  – fetch listing, apply cache, fetch detail pages.
        If time runs low, write completed records to S3 (partial-*.json),
        re-invoke self with the remaining external_ids, and exit cleanly.
    (b) Checkpoint resume – skip the listing, fetch only the remaining ids
        passed in the event, then scrape adjudicaciones and write the final file.
    """
    today      = date.today()
    session    = portal.create_session(creds["username"], creds["password"])
    log.info("Login successful")

    remaining_ids = event.get("checkpoint_remaining")  # set only on resume

    if remaining_ids:
        # ── (b) Checkpoint resume ─────────────────────────────────────────────
        log.info("Checkpoint resume: %d licitaciones remaining", len(remaining_ids))
        licitaciones = _fetch_detail_pages(
            session, [{"external_id": eid} for eid in remaining_ids],
            context, bucket, today,
        )
        log.info("Resume licitaciones done: %d", len(licitaciones))

    else:
        # ── (a) Normal start ──────────────────────────────────────────────────
        date_from = (today - timedelta(days=DAILY_WINDOW)).strftime("%d/%m/%Y")
        date_to   = today.strftime("%d/%m/%Y")
        cache     = _load_s3_cache(bucket, today)
        log.info("S3 cache: %d licitaciones, %d adjudicaciones known",
                 len(cache["lic"]), len(cache["adj"]))

        resp = portal.post(session, f"{BASE}/licitaciones.php", {
            "buscador_fecha_inicio": date_from,
            "buscador_fecha_fin":    date_to,
        }, delay=0.5)
        listing_rows = parsers.parse_licitacion_listing(resp.text)
        log.info("Listing: %d rows", len(listing_rows))

        # Split rows: served from cache vs needs a network fetch
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

        fetched_records = _fetch_detail_pages(
            session, rows_to_fetch, context, bucket, today,
            on_checkpoint_write=cached_records,
        )

        # If _fetch_detail_pages triggered a checkpoint, it already re-invoked
        # self and returned None — our job here is done.
        if fetched_records is None:
            return {"statusCode": 202, "message": "checkpointed"}

        licitaciones = cached_records + fetched_records
        log.info("Licitaciones done: %d total", len(licitaciones))

        # Adjudicaciones use the same date window
        cache_adj = cache["adj"]
        adj_ids   = _fetch_adj_ids(session, date_from, date_to)
        log.info("Found %d adjudicacion IDs", len(adj_ids))
        adjudicaciones = []
        for eid in adj_ids:
            if eid in cache_adj:
                adjudicaciones.append(cache_adj[eid])
            else:
                try:
                    r      = portal.get(session, f"{BASE}/adjudicaciones-ficha.php?id={eid}", delay=0.3)
                    detail = parsers.parse_adjudicacion_detail(r.text, eid)
                    adjudicaciones.append(detail)
                except Exception as e:
                    log.warning("adjudicacion %s failed: %s", eid, e)

        log.info("Adjudicaciones done: %d total", len(adjudicaciones))
        _write_s3(bucket, f"scrapes/{today.isoformat()}.json", licitaciones, adjudicaciones)
        return {
            "statusCode": 200,
            "licitaciones": len(licitaciones),
            "adjudicaciones": len(adjudicaciones),
        }

    # Checkpoint resume: after fetching remaining licitaciones, scrape adjudicaciones
    date_from = (today - timedelta(days=DAILY_WINDOW)).strftime("%d/%m/%Y")
    date_to   = today.strftime("%d/%m/%Y")
    adj_ids   = _fetch_adj_ids(session, date_from, date_to)
    log.info("Found %d adjudicacion IDs", len(adj_ids))
    adjudicaciones = []
    for eid in adj_ids:
        try:
            r      = portal.get(session, f"{BASE}/adjudicaciones-ficha.php?id={eid}", delay=0.3)
            detail = parsers.parse_adjudicacion_detail(r.text, eid)
            adjudicaciones.append(detail)
        except Exception as e:
            log.warning("adjudicacion %s failed: %s", eid, e)

    _write_s3(bucket, f"scrapes/{today.isoformat()}.json", licitaciones, adjudicaciones)
    return {
        "statusCode": 200,
        "licitaciones": len(licitaciones),
        "adjudicaciones": len(adjudicaciones),
        "resumed": True,
    }


def _fetch_detail_pages(session, rows, context, bucket, today,
                        on_checkpoint_write=None):
    """
    Fetch detail pages for each row.  Monitors remaining Lambda time and
    checkpoints if < MIN_TIME_MS left: writes completed records to a partial
    S3 file (triggers scraper_write immediately), re-invokes self with the
    remaining external_ids, and returns None to signal the caller.

    on_checkpoint_write: list of already-resolved records to include in the
    partial S3 write (the cache hits from the normal-start path).
    """
    s3 = boto3.client("s3")
    completed = []
    for i, row in enumerate(rows):
        if context.get_remaining_time_in_millis() < MIN_TIME_MS:
            remaining_ids = [r["external_id"] for r in rows[i:]]
            log.info("Time low at record %d — checkpointing %d remaining ids", i, len(remaining_ids))

            # Write what we have so far so scraper_write can upsert it now
            partial = (on_checkpoint_write or []) + completed
            if partial:
                _write_s3(bucket, f"scrapes/partial-{today.isoformat()}.json", partial, [])

            # Re-invoke self to finish the rest
            boto3.client("lambda").invoke(
                FunctionName=context.function_name,
                InvocationType="Event",
                Payload=json.dumps({
                    "mode": "daily",
                    "checkpoint_remaining": remaining_ids,
                }).encode(),
            )
            log.info("Re-invoked self with %d remaining ids", len(remaining_ids))
            return None  # caller must check for None and return early

        eid = row["external_id"]
        try:
            dr        = portal.get(session, f"{BASE}/licitaciones-ficha.php?id={eid}", delay=0.3)
            detail    = parsers.parse_licitacion_detail(dr.text, eid)
            doc_links = parsers.parse_documents(dr.text)
            detail["documents"] = _download_documents(session, eid, doc_links, bucket, s3)
            completed.append({**row, **detail})
        except Exception as e:
            log.warning("licitacion %s failed: %s", eid, e)

        if (i + 1) % 50 == 0:
            log.info("  %d/%d detail pages fetched", i + 1, len(rows))

    return completed


def _download_documents(session, external_id: str, doc_links: list, bucket: str, s3) -> list:
    """Download document files and upload to S3 under documents/<external_id>/."""
    _ALLOWED_TYPES = {
        "application/pdf",
        "application/msword",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    }
    uploaded = []
    for doc in doc_links[:10]:
        href   = doc["href"]
        nombre = doc["nombre"]
        url    = href if href.startswith("http") else f"{BASE}/{href.lstrip('/')}"
        try:
            resp = session.get(url, timeout=60, allow_redirects=True)
            if resp.status_code != 200:
                log.warning("doc %s → HTTP %d", nombre, resp.status_code)
                continue
            content_type = resp.headers.get("Content-Type", "").split(";")[0].strip()
            # Infer type from magic bytes if Content-Type is generic
            if content_type not in _ALLOWED_TYPES:
                if resp.content[:4] == b"%PDF":
                    content_type = "application/pdf"
                else:
                    log.info("Skipping doc %s (type=%s)", nombre, content_type)
                    continue
            ext = ".pdf" if content_type == "application/pdf" else (
                  ".docx" if "openxmlformats" in content_type else ".doc")
            safe = re.sub(r"[^\w\- ]", "_", nombre)[:80].strip("_") or "documento"
            # Disambiguate multiple "Documento" files from descarga-otros.php
            id2_match = re.search(r"id2=(\d+)", href)
            suffix = f"_{id2_match.group(1)}" if id2_match else ""
            s3_key = f"documents/{external_id}/{safe}{suffix}{ext}"
            s3.put_object(Bucket=bucket, Key=s3_key, Body=resp.content, ContentType=content_type)
            uploaded.append({
                "nombre":       nombre,
                "s3_key":       s3_key,
                "content_type": content_type,
                "size_bytes":   len(resp.content),
            })
            log.info("Uploaded doc %s → s3://%s/%s (%d bytes)", nombre, bucket, s3_key, len(resp.content))
        except Exception as e:
            log.warning("doc download failed %s: %s", nombre, e)
    return uploaded


# ── Refresh-open mode ─────────────────────────────────────────────────────────

def _run_refresh_open(event, context, creds, bucket):
    """
    Re-fetches detail pages for all licitaciones whose deadline is today or
    in the future.  Runs in paginated batches; self-re-invokes if the page
    doesn't finish in time.
    """
    db_cluster_arn = os.environ["DB_CLUSTER_ARN"]
    db_secret_arn  = os.environ["DB_SECRET_ARN"]
    offset         = int(event.get("offset", 0))
    today          = date.today()
    page           = offset // REFRESH_BATCH + 1

    # Fetch one extra to know whether a next page exists.
    active_ids = _query_active_ids(db_cluster_arn, db_secret_arn, offset, REFRESH_BATCH + 1)
    has_more   = len(active_ids) > REFRESH_BATCH
    batch      = active_ids[:REFRESH_BATCH]
    log.info("refresh_open page=%d offset=%d ids=%d has_more=%s",
             page, offset, len(batch), has_more)

    if not batch:
        log.info("No open licitaciones to refresh")
        return {"statusCode": 200, "refreshed": 0}

    session = portal.create_session(creds["username"], creds["password"])
    log.info("Login successful")
    s3 = boto3.client("s3")

    refreshed = []
    consecutive_failures = 0
    for i, eid in enumerate(batch):
        if context.get_remaining_time_in_millis() < MIN_TIME_MS:
            log.info("Time running low at record %d/%d — writing partial and re-invoking",
                     i, len(batch))
            _write_s3(bucket, f"scrapes/refresh-{today.isoformat()}-p{page}.json",
                      refreshed, [])
            _invoke_self(context.function_name, offset + i)
            return {"statusCode": 202, "refreshed": len(refreshed), "message": "checkpointed"}

        try:
            resp      = portal.get(session, f"{BASE}/licitaciones-ficha.php?id={eid}", delay=0.2)
            detail    = parsers.parse_licitacion_detail(resp.text, eid)
            doc_links = parsers.parse_documents(resp.text)
            detail["documents"] = _download_documents(session, eid, doc_links, bucket, s3)
            refreshed.append(detail)
            consecutive_failures = 0
        except Exception as e:
            log.warning("refresh licitacion %s failed: %s", eid, e)
            consecutive_failures += 1
            # Re-login after 3 consecutive session-expired failures
            if consecutive_failures >= 3 and "session expired" in str(e).lower():
                log.info("Session expired — re-logging in")
                try:
                    session = portal.create_session(creds["username"], creds["password"])
                    log.info("Re-login successful")
                    consecutive_failures = 0
                except Exception as login_err:
                    log.error("Re-login failed: %s", login_err)

        if (i + 1) % 50 == 0:
            log.info("  refreshed %d/%d", i + 1, len(batch))

    s3_key = f"scrapes/refresh-{today.isoformat()}-p{page}.json"
    _write_s3(bucket, s3_key, refreshed, [])
    log.info("refresh_open page %d done: %d refreshed", page, len(refreshed))

    if has_more:
        _invoke_self(context.function_name, offset + REFRESH_BATCH)
        return {"statusCode": 202, "refreshed": len(refreshed), "message": "next page triggered"}

    return {"statusCode": 200, "refreshed": len(refreshed)}


def _run_refresh_all(event, context, creds, bucket):
    """
    Re-fetches detail pages for ALL licitaciones missing area_tecnologica data.
    Same pagination/checkpoint logic as refresh_open.
    """
    db_cluster_arn = os.environ["DB_CLUSTER_ARN"]
    db_secret_arn  = os.environ["DB_SECRET_ARN"]
    offset         = int(event.get("offset", 0))
    today          = date.today()
    page           = offset // REFRESH_BATCH + 1

    rds = boto3.client("rds-data")
    result = rds.execute_statement(
        resourceArn=db_cluster_arn,
        secretArn=db_secret_arn,
        database="imliti",
        sql="""
            SELECT external_id FROM licitacion
            WHERE external_id IS NOT NULL
              AND area_tecnologica_id IS NULL
            ORDER BY id ASC
            LIMIT :lim OFFSET :off
        """,
        parameters=[
            {"name": "lim", "value": {"longValue": REFRESH_BATCH + 1}},
            {"name": "off", "value": {"longValue": offset}},
        ],
    )
    all_ids  = [row[0]["stringValue"] for row in result.get("records", [])]
    has_more = len(all_ids) > REFRESH_BATCH
    batch    = all_ids[:REFRESH_BATCH]
    log.info("refresh_all page=%d offset=%d ids=%d has_more=%s", page, offset, len(batch), has_more)

    if not batch:
        log.info("No licitaciones left to refresh")
        return {"statusCode": 200, "refreshed": 0}

    session = portal.create_session(creds["username"], creds["password"])
    log.info("Login successful")
    s3 = boto3.client("s3")

    refreshed = []
    consecutive_failures = 0
    for i, eid in enumerate(batch):
        if context.get_remaining_time_in_millis() < MIN_TIME_MS:
            log.info("Time low at record %d — checkpointing %d remaining", i, len(batch) - i)
            _write_s3(bucket, f"scrapes/refresh-all-{today.isoformat()}-p{page}.json", refreshed, [])
            boto3.client("lambda").invoke(
                FunctionName=context.function_name,
                InvocationType="Event",
                Payload=json.dumps({"mode": "refresh_all", "offset": offset + i}).encode(),
            )
            log.info("Re-invoked self with %d remaining ids", len(batch) - i)
            return {"statusCode": 202, "refreshed": len(refreshed), "message": "checkpointed"}

        try:
            resp      = portal.get(session, f"{BASE}/licitaciones-ficha.php?id={eid}", delay=0.2)
            detail    = parsers.parse_licitacion_detail(resp.text, eid)
            doc_links = parsers.parse_documents(resp.text)
            detail["documents"] = _download_documents(session, eid, doc_links, bucket, s3)
            refreshed.append(detail)
            consecutive_failures = 0
        except Exception as e:
            log.warning("refresh licitacion %s failed: %s", eid, e)
            consecutive_failures += 1
            if consecutive_failures >= 3 and "session expired" in str(e).lower():
                try:
                    session = portal.create_session(creds["username"], creds["password"])
                    log.info("Re-login successful")
                    consecutive_failures = 0
                except Exception as login_err:
                    log.error("Re-login failed: %s", login_err)

        if (i + 1) % 50 == 0:
            log.info("  refreshed %d/%d", i + 1, len(batch))

    s3_key = f"scrapes/refresh-all-{today.isoformat()}-p{page}.json"
    _write_s3(bucket, s3_key, refreshed, [])
    log.info("refresh_all page %d done: %d refreshed", page, len(refreshed))

    if has_more:
        boto3.client("lambda").invoke(
            FunctionName=context.function_name,
            InvocationType="Event",
            Payload=json.dumps({"mode": "refresh_all", "offset": offset + REFRESH_BATCH}).encode(),
        )
        return {"statusCode": 202, "refreshed": len(refreshed), "message": "next page triggered"}

    return {"statusCode": 200, "refreshed": len(refreshed)}


# ── Scrape documents for all existing licitaciones ───────────────────────────

def _run_scrape_documents(event, context, creds, bucket):
    """
    One-shot backfill: queries all licitaciones that have no documents yet,
    fetches their detail pages, downloads attachments to S3, then writes a
    scrape file so scraper_write upserts the licitacion_documento rows.
    Self-re-invokes with an offset when time runs low.
    """
    db_cluster_arn = os.environ["DB_CLUSTER_ARN"]
    db_secret_arn  = os.environ["DB_SECRET_ARN"]
    offset         = int(event.get("offset", 0))
    today          = date.today()
    page           = offset // REFRESH_BATCH + 1

    rds = boto3.client("rds-data")
    result = rds.execute_statement(
        resourceArn=db_cluster_arn,
        secretArn=db_secret_arn,
        database="imliti",
        sql="""
            SELECT l.external_id FROM licitacion l
            LEFT JOIN licitacion_documento ld ON ld.licitacion_id = l.id
            WHERE l.external_id IS NOT NULL
              AND ld.id IS NULL
            ORDER BY l.id DESC
            LIMIT :lim OFFSET :off
        """,
        parameters=[
            {"name": "lim", "value": {"longValue": REFRESH_BATCH + 1}},
            {"name": "off", "value": {"longValue": offset}},
        ],
    )
    all_ids  = [row[0]["stringValue"] for row in result.get("records", [])]
    has_more = len(all_ids) > REFRESH_BATCH
    batch    = all_ids[:REFRESH_BATCH]
    log.info("scrape_documents page=%d offset=%d ids=%d has_more=%s",
             page, offset, len(batch), has_more)

    if not batch:
        log.info("All licitaciones already have documents (or none found)")
        return {"statusCode": 200, "scraped": 0}

    session = portal.create_session(creds["username"], creds["password"])
    log.info("Login successful")
    s3 = boto3.client("s3")

    scraped = []
    consecutive_failures = 0
    for i, eid in enumerate(batch):
        if context.get_remaining_time_in_millis() < MIN_TIME_MS:
            log.info("Time low at %d/%d — writing partial and re-invoking", i, len(batch))
            if scraped:
                _write_s3(bucket, f"scrapes/docs-{today.isoformat()}-p{page}-part.json", scraped, [])
            boto3.client("lambda").invoke(
                FunctionName=context.function_name,
                InvocationType="Event",
                Payload=json.dumps({"mode": "scrape_documents", "offset": offset + i}).encode(),
            )
            return {"statusCode": 202, "scraped": len(scraped), "message": "checkpointed"}

        try:
            resp      = portal.get(session, f"{BASE}/licitaciones-ficha.php?id={eid}", delay=0.3)
            doc_links = parsers.parse_documents(resp.text)
            docs      = _download_documents(session, eid, doc_links, bucket, s3)
            if docs:
                # Only write external_id + documents — do NOT include other parsed
                # fields to avoid overwriting existing DB values with nulls
                scraped.append({"external_id": eid, "documents": docs})
            consecutive_failures = 0
        except Exception as e:
            log.warning("scrape_documents %s failed: %s", eid, e)
            consecutive_failures += 1
            if consecutive_failures >= 3 and "session expired" in str(e).lower():
                try:
                    session = portal.create_session(creds["username"], creds["password"])
                    log.info("Re-login successful")
                    consecutive_failures = 0
                except Exception as login_err:
                    log.error("Re-login failed: %s", login_err)

        if (i + 1) % 50 == 0:
            log.info("  processed %d/%d (found docs for %d)", i + 1, len(batch), len(scraped))

    if scraped:
        _write_s3(bucket, f"scrapes/docs-{today.isoformat()}-p{page}.json", scraped, [])
    log.info("scrape_documents page %d done: %d licitaciones with docs out of %d",
             page, len(scraped), len(batch))

    if has_more:
        boto3.client("lambda").invoke(
            FunctionName=context.function_name,
            InvocationType="Event",
            Payload=json.dumps({"mode": "scrape_documents", "offset": offset + REFRESH_BATCH}).encode(),
        )
        return {"statusCode": 202, "scraped": len(scraped), "message": "next page triggered"}

    return {"statusCode": 200, "scraped": len(scraped)}


# ── Shared helpers ────────────────────────────────────────────────────────────

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


def _query_active_ids(cluster_arn: str, secret_arn: str, offset: int, limit: int) -> list:
    """Return external_ids for licitaciones whose deadline is today or future."""
    rds = boto3.client("rds-data")
    result = rds.execute_statement(
        resourceArn=cluster_arn,
        secretArn=secret_arn,
        database="imliti",
        sql="""
            SELECT external_id FROM licitacion
            WHERE external_id IS NOT NULL
              AND fecha_limite_oferta IS NOT NULL
              AND fecha_limite_oferta >= CURRENT_DATE
            ORDER BY fecha_limite_oferta ASC
            LIMIT :lim OFFSET :off
        """,
        parameters=[
            {"name": "lim", "value": {"longValue": limit}},
            {"name": "off", "value": {"longValue": offset}},
        ],
    )
    return [row[0]["stringValue"] for row in result.get("records", [])]


def _invoke_self(function_name: str, offset: int) -> None:
    boto3.client("lambda").invoke(
        FunctionName=function_name,
        InvocationType="Event",
        Payload=json.dumps({"mode": "refresh_open", "offset": offset}).encode(),
    )
    log.info("Re-invoked self with offset=%d", offset)


def _deadline_is_open(cached: dict, today: date) -> bool:
    """True if this licitacion's deadline is today or in the future."""
    raw = cached.get("fecha_limite_oferta")
    if not raw:
        return False
    try:
        # Handle both "YYYY-MM-DD" and ISO datetime strings from TIMESTAMPTZ
        return date.fromisoformat(str(raw)[:10]) >= today
    except ValueError:
        return False


def _fresh_listing_fields(row: dict) -> dict:
    """Listing-table fields that may be updated by the portal — always keep fresh."""
    return {k: v for k, v in row.items() if k in (
        "fecha", "importe_licitacion", "fecha_limite_oferta",
        "puntos_precio", "puntos_mejoras", "puntos_subjetivos",
        "numero_expediente", "tipo_procedimiento",
    )}


def _load_s3_cache(bucket: str, today: date) -> dict:
    """Load the most recent scrape file per external_id from the past 7 days."""
    s3  = boto3.client("s3")
    lic: dict = {}
    adj: dict = {}
    for days_back in range(1, 8):
        key = f"scrapes/{(today - timedelta(days=days_back)).isoformat()}.json"
        try:
            data = json.loads(s3.get_object(Bucket=bucket, Key=key)["Body"].read())
            for rec in data.get("licitaciones", []):
                eid = rec.get("external_id")
                if eid and eid not in lic:
                    lic[eid] = rec
            for rec in data.get("adjudicaciones", []):
                eid = rec.get("external_id")
                if eid and eid not in adj:
                    adj[eid] = rec
        except ClientError as e:
            if e.response["Error"]["Code"] != "NoSuchKey":
                log.warning("Cache load %s: %s", key, e)
    return {"lic": lic, "adj": adj}


def _write_s3(bucket: str, key: str, licitaciones: list, adjudicaciones: list) -> None:
    payload = json.dumps({
        "scrape_date":    date.today().isoformat(),
        "licitaciones":   licitaciones,
        "adjudicaciones": adjudicaciones,
    }, ensure_ascii=False).encode()
    boto3.client("s3").put_object(
        Bucket=bucket, Key=key, Body=payload, ContentType="application/json",
    )
    log.info("Wrote %d bytes to s3://%s/%s", len(payload), bucket, key)


def _get_portal_creds(secret_arn: str) -> dict:
    sm   = boto3.client("secretsmanager")
    resp = sm.get_secret_value(SecretId=secret_arn)
    return json.loads(resp["SecretString"])
