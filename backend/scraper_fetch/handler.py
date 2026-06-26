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

import hashlib
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
    if mode == "restore_from_s3":
        return _run_restore_from_s3(event, context, bucket)
    if mode == "fetch_document":
        return _run_fetch_document(event, context, creds, bucket)
    if mode == "fetch_document_url":
        return _run_fetch_document_url(event, context, creds, bucket)
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
        # checkpoint_remaining may be a list of dicts (new format, with listing
        # fields) or a list of bare strings (old format, backward-compatible).
        resume_rows = [
            r if isinstance(r, dict) else {"external_id": r}
            for r in remaining_ids
        ]
        log.info("Checkpoint resume: %d licitaciones remaining", len(resume_rows))
        licitaciones = _fetch_detail_pages(
            session, resume_rows,
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
            remaining_rows = rows[i:]
            log.info("Time low at record %d — checkpointing %d remaining ids", i, len(remaining_rows))

            # Write what we have so far so scraper_write can upsert it now
            partial = (on_checkpoint_write or []) + completed
            if partial:
                _write_s3(bucket, f"scrapes/partial-{today.isoformat()}.json", partial, [])

            # Pass listing fields (fecha, importe, fecha_limite) alongside the id
            # so the resumed invocation can merge them with the detail page data.
            checkpoint_rows = [
                {k: r.get(k) for k in (
                    "external_id", "fecha", "fecha_limite_oferta",
                    "importe_licitacion", "numero_expediente", "tipo_procedimiento",
                    "puntos_precio", "puntos_mejoras", "puntos_subjetivos",
                ) if r.get(k) is not None}
                for r in remaining_rows
            ]

            # Re-invoke self to finish the rest
            boto3.client("lambda").invoke(
                FunctionName=context.function_name,
                InvocationType="Event",
                Payload=json.dumps({
                    "mode": "daily",
                    "checkpoint_remaining": checkpoint_rows,
                }).encode(),
            )
            log.info("Re-invoked self with %d remaining rows", len(checkpoint_rows))
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
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "application/vnd.ms-excel",
        "application/zip",
        "application/x-zip-compressed",
        "application/vnd.oasis.opendocument.text",
        "application/rtf",
        "text/rtf",
    }
    _MAGIC_TYPES = [
        (b"%PDF",           "application/pdf",    ".pdf"),
        (b"PK\x03\x04",    None,                  None),   # ZIP / OOXML — use Content-Disposition ext
        (b"\xd0\xcf\x11\xe0", "application/msword", ".doc"),  # OLE2 (old .doc/.xls)
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

    uploaded = []
    for doc in doc_links:  # no cap — fetch every document the portal lists
        href   = doc["href"]
        nombre = doc["nombre"]
        url    = href if href.startswith("http") else f"{BASE}/{href.lstrip('/')}"
        try:
            resp = session.get(url, timeout=60, allow_redirects=True)
            if resp.status_code != 200:
                log.warning("doc %s → HTTP %d", nombre, resp.status_code)
                continue

            content_type = resp.headers.get("Content-Type", "").split(";")[0].strip()

            # Infer type from magic bytes when Content-Type is generic/missing
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

            # Derive file extension
            ext = _EXT_MAP.get(content_type)
            if ext is None:
                # Fall back to Content-Disposition filename extension
                cd = resp.headers.get("Content-Disposition", "")
                m = re.search(r'filename=["\']?([^"\';\s]+)', cd)
                ext = ("." + m.group(1).rsplit(".", 1)[-1].lower()) if m and "." in m.group(1) else ".bin"

            safe = re.sub(r"[^\w\- ]", "_", nombre)[:80].strip("_") or "documento"

            # Use a short hash of the URL to guarantee uniqueness across all docs
            # with identical names (e.g. multiple PDFs all labelled "Documento").
            href_hash = hashlib.md5(href.encode()).hexdigest()[:8]
            s3_key = f"documents/{external_id}/{safe}_{href_hash}{ext}"

            s3.put_object(Bucket=bucket, Key=s3_key, Body=resp.content, ContentType=content_type)
            uploaded.append({
                "nombre":       nombre,
                "s3_key":       s3_key,
                "content_type": content_type,
                "size_bytes":   len(resp.content),
                "source_url":   url,
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
            WHERE l.external_id IS NOT NULL
              AND (
                -- never scraped
                NOT EXISTS (SELECT 1 FROM licitacion_documento ld WHERE ld.licitacion_id = l.id)
                OR
                -- scraped before the hash-based key fix: old keys have no 8-char hex suffix,
                -- identifiable because they matched the old id2= pattern or had no suffix at all.
                -- Re-scrape any licitacion with only 1 document (almost certainly a collision victim).
                (SELECT COUNT(*) FROM licitacion_documento ld WHERE ld.licitacion_id = l.id) = 1
              )
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


# ── Fetch documents on-demand for a single licitacion ────────────────────────

def _run_fetch_document(event, context, creds, bucket):
    """
    Synchronous on-demand mode: scrapes a single licitacion's detail page,
    downloads its documents to S3, and upserts them into licitacion_documento
    via Aurora Data API.  Called by SummarizeLambda when no docs are in DB yet.

    Event: {"mode": "fetch_document", "external_id": "...", "licitacion_id": 123}
    Returns: {"documents": [{nombre, s3_key, content_type, size_bytes}, ...]}
    """
    external_id    = event.get("external_id")
    licitacion_id  = event.get("licitacion_id")
    db_cluster_arn = os.environ.get("DB_CLUSTER_ARN")
    db_secret_arn  = os.environ.get("DB_SECRET_ARN")

    if not external_id:
        return {"statusCode": 400, "error": "external_id required"}

    session = portal.create_session(creds["username"], creds["password"])
    log.info("fetch_document: login ok, fetching external_id=%s", external_id)

    s3 = boto3.client("s3")
    resp = portal.get(session, f"{BASE}/licitaciones-ficha.php?id={external_id}", delay=0.3)
    doc_links = parsers.parse_documents(resp.text)
    log.info("fetch_document: found %d doc links on portal page", len(doc_links))

    docs = _download_documents(session, external_id, doc_links, bucket, s3)
    log.info("fetch_document: downloaded %d documents", len(docs))

    # Upsert into DB if we have a licitacion_id and Data API credentials
    if licitacion_id and db_cluster_arn and db_secret_arn and docs:
        rds = boto3.client("rds-data")
        for doc in docs:
            try:
                rds.execute_statement(
                    resourceArn=db_cluster_arn,
                    secretArn=db_secret_arn,
                    database="imliti",
                    sql="""
                        INSERT INTO licitacion_documento
                            (licitacion_id, nombre, s3_key, content_type, size_bytes, source_url)
                        VALUES
                            (:lid, :nombre, :s3_key, :ct, :sz, :src)
                        ON CONFLICT (licitacion_id, s3_key) DO UPDATE
                            SET size_bytes  = EXCLUDED.size_bytes,
                                source_url  = COALESCE(EXCLUDED.source_url, licitacion_documento.source_url)
                    """,
                    parameters=[
                        {"name": "lid",    "value": {"longValue":   int(licitacion_id)}},
                        {"name": "nombre", "value": {"stringValue": doc["nombre"]}},
                        {"name": "s3_key", "value": {"stringValue": doc["s3_key"]}},
                        {"name": "ct",     "value": {"stringValue": doc.get("content_type") or "application/octet-stream"}},
                        {"name": "sz",     "value": {"longValue":   doc.get("size_bytes") or 0}},
                        {"name": "src",    "value": {"stringValue": doc.get("source_url") or ""} if doc.get("source_url") else {"isNull": True}},
                    ],
                )
            except Exception as e:
                log.warning("fetch_document: DB upsert failed for %s: %s", doc["nombre"], e)

    return {"statusCode": 200, "documents": docs}


# ── Fetch a single document by URL (called from SummarizeLambda) ─────────────

def _run_fetch_document_url(event, context, creds, bucket):
    """
    Download one document by its direct URL through the portal session.
    Called by SummarizeLambda when it finds a hyperlink inside a PDF that points
    to another document (e.g. Pliego de Prescripciones Técnicas on an external server).

    Event: {"mode": "fetch_document_url", "url": "https://...", "licitacion_id": 123,
            "nombre": "optional display name"}
    Returns: {"documents": [{nombre, s3_key, content_type, size_bytes, source_url}]}
    """
    url           = event.get("url")
    nombre        = event.get("nombre", "documento_enlazado")
    licitacion_id = event.get("licitacion_id")

    if not url:
        return {"statusCode": 400, "error": "url required", "documents": []}

    session = portal.create_session(creds["username"], creds["password"])
    s3      = boto3.client("s3")

    # Re-use _download_documents — pass a synthetic ext_id for the S3 key path
    ext_id = f"linked/{licitacion_id}" if licitacion_id else "linked/unknown"
    docs   = _download_documents(
        session,
        ext_id,
        [{"href": url, "nombre": nombre}],
        bucket,
        s3,
    )
    log.info("fetch_document_url: downloaded %d docs from %s", len(docs), url)

    # Upsert into licitacion_documento via Data API so future summaries find them
    db_cluster_arn = os.environ.get("DB_CLUSTER_ARN")
    db_secret_arn  = os.environ.get("DB_SECRET_ARN")
    if licitacion_id and db_cluster_arn and db_secret_arn and docs:
        rds = boto3.client("rds-data")
        for doc in docs:
            try:
                src_param = (
                    {"stringValue": doc["source_url"]}
                    if doc.get("source_url")
                    else {"isNull": True}
                )
                rds.execute_statement(
                    resourceArn=db_cluster_arn,
                    secretArn=db_secret_arn,
                    database="imliti",
                    sql="""
                        INSERT INTO licitacion_documento
                            (licitacion_id, nombre, s3_key, content_type, size_bytes, source_url)
                        VALUES (:lid, :nombre, :s3_key, :ct, :sz, :src)
                        ON CONFLICT (licitacion_id, s3_key) DO UPDATE
                            SET size_bytes = EXCLUDED.size_bytes,
                                source_url = COALESCE(EXCLUDED.source_url,
                                                      licitacion_documento.source_url)
                    """,
                    parameters=[
                        {"name": "lid",    "value": {"longValue":   int(licitacion_id)}},
                        {"name": "nombre", "value": {"stringValue": doc["nombre"]}},
                        {"name": "s3_key", "value": {"stringValue": doc["s3_key"]}},
                        {"name": "ct",     "value": {"stringValue": doc.get("content_type") or "application/octet-stream"}},
                        {"name": "sz",     "value": {"longValue":   doc.get("size_bytes") or 0}},
                        {"name": "src",    "value": src_param},
                    ],
                )
            except Exception as e:
                log.warning("fetch_document_url: DB upsert failed for %s: %s", doc["nombre"], e)

    return {"statusCode": 200, "documents": docs}


# ── Restore listing fields from S3 ────────────────────────────────────────────

def _run_restore_from_s3(event, context, bucket):
    """
    One-shot recovery: reads all daily scrape files from S3, collects the
    importe_licitacion and fecha_limite_oferta values that were captured at
    scrape time, then writes a restore file so scraper_write patches only
    those two fields back into any rows where they are currently NULL.

    Supports pagination via the 'page_token' event field so it can resume if
    Lambda time runs out.  Invoke with {"mode": "restore_from_s3"}.
    """
    s3        = boto3.client("s3")
    today     = date.today()
    page_token = event.get("page_token")  # continuation token for S3 listing

    # Collect one canonical value per external_id across all daily scrape files.
    # Use a dict so later files (more recent) overwrite earlier ones.
    best: dict = {}

    paginator = s3.get_paginator("list_objects_v2")
    list_kwargs = {"Bucket": bucket, "Prefix": "scrapes/"}
    if page_token:
        list_kwargs["ContinuationToken"] = page_token

    files_read = 0
    next_token = None
    for page in paginator.paginate(**list_kwargs):
        for obj in page.get("Contents", []):
            key = obj["Key"]
            # Listing data lives in partial files; final YYYY-MM-DD.json has it stripped by the detail pass
            if not re.match(r"scrapes/(partial-)?\d{4}-\d{2}-\d{2}\.json$", key):
                continue
            try:
                data = json.loads(s3.get_object(Bucket=bucket, Key=key)["Body"].read())
                for rec in data.get("licitaciones", []):
                    eid     = rec.get("external_id")
                    importe = rec.get("importe_licitacion")
                    fecha   = rec.get("fecha_limite_oferta")
                    if eid and (importe is not None or fecha is not None):
                        best[eid] = {
                            "external_id":       eid,
                            "importe_licitacion": importe,
                            "fecha_limite_oferta": fecha,
                        }
                files_read += 1
            except Exception as e:
                log.warning("restore_from_s3: could not read %s: %s", key, e)

        # Check time budget — checkpoint if < 90 s remain
        if context.get_remaining_time_in_millis() < MIN_TIME_MS:
            next_token = page.get("NextContinuationToken")
            break

    restore_records = list(best.values())
    log.info("restore_from_s3: read %d files, collected %d records with listing data",
             files_read, len(restore_records))

    if restore_records:
        payload = json.dumps({
            "scrape_date":    today.isoformat(),
            "licitaciones":   [],
            "adjudicaciones": [],
            "restore_listing": restore_records,
        }, ensure_ascii=False).encode()
        out_key = f"scrapes/restore-listing-{today.isoformat()}.json"
        s3.put_object(Bucket=bucket, Key=out_key, Body=payload, ContentType="application/json")
        log.info("Wrote restore file → s3://%s/%s (%d bytes)", bucket, out_key, len(payload))

    if next_token:
        boto3.client("lambda").invoke(
            FunctionName=context.function_name,
            InvocationType="Event",
            Payload=json.dumps({"mode": "restore_from_s3", "page_token": next_token}).encode(),
        )
        log.info("Time budget low — re-invoked with continuation token")
        return {"statusCode": 202, "restored": len(restore_records), "message": "continued"}

    return {"statusCode": 200, "restored": len(restore_records), "files_read": files_read}


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
