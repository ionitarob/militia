"""
Local historical backfill script using Playwright (real Chromium browser).

Runs from your Spanish residential IP — bypasses all bot detection because it IS
a real browser. No Lambda timeout, no session expiry issues.

Usage:
  python scripts/backfill.py --days 30         # last 30 days
  python scripts/backfill.py --from 01/04/2026 --to 09/06/2026

The script writes one S3 file per day-chunk and uploads it to the scrape bucket.
scraper_write Lambda will fire automatically for each uploaded file and upsert
everything into Aurora.

Requirements:
  pip install playwright boto3 beautifulsoup4 lxml
  python -m playwright install chromium
"""

import argparse
import json
import logging
import sys
import time
from datetime import date, timedelta
from pathlib import Path

import boto3
from playwright.sync_api import sync_playwright

sys.path.insert(0, str(Path(__file__).parent.parent / "backend" / "scraper_fetch"))
import parsers

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)

BASE    = "https://www.adjudicacionestic.com/front"
BUCKET  = "imliti-scrapes-340303438174"
CHUNK   = 7  # days per S3 file (keeps files manageable)


# ── Playwright session helpers ────────────────────────────────────────────────

def login(page, username: str, password: str):
    log.info("Logging in as %s", username)
    page.goto(f"{BASE}/acceso.php", wait_until="networkidle")
    page.fill('input[name="username"]', username)
    page.fill('input[name="password"]', password)
    page.click('input[type="submit"], button[type="submit"]')
    page.wait_for_load_state("networkidle")
    if "registro.php" in page.url:
        raise RuntimeError(f"Login failed — landed on {page.url}")
    log.info("Login successful, at %s", page.url)


def _req(page, method: str, url: str, data: dict | None = None) -> str:
    """
    Use the browser's live cookie session to make an HTTP request.
    Faster than full page navigation; inherits all browser cookies/headers.
    """
    if method == "POST":
        resp = page.request.post(url, form=data or {})
    else:
        resp = page.request.get(url)
    # Decode body with charset from headers; fall back to latin-1 (common on Spanish portals)
    body    = resp.body()
    charset = "utf-8"
    ct      = resp.headers.get("content-type", "")
    if "charset=" in ct:
        charset = ct.split("charset=")[-1].split(";")[0].strip()
    html = body.decode(charset, errors="replace")
    if "registro.php" in resp.url:
        raise RuntimeError(f"Session expired — redirected to {resp.url}")
    return html


def fetch_licitacion_listing(page, date_from: str, date_to: str) -> list[dict]:
    html = _req(page, "POST", f"{BASE}/licitaciones.php", {
        "buscador_fecha_inicio": date_from,
        "buscador_fecha_fin":    date_to,
    })
    rows = parsers.parse_licitacion_listing(html)
    log.info("Listing %s → %s: %d rows", date_from, date_to, len(rows))
    return rows


def fetch_licitacion_detail(page, eid: str) -> dict:
    html = _req(page, "GET", f"{BASE}/licitaciones-ficha.php?id={eid}")
    return parsers.parse_licitacion_detail(html, eid)


def fetch_adjudicacion_ids(page, date_from: str, date_to: str) -> set[str]:
    adj_ids: set[str] = set()
    for pg in range(1, 11):
        html    = _req(page, "POST", f"{BASE}/adjudicaciones.php", {
            "defecto":               "NO",
            "buscador_fecha_inicio": date_from,
            "buscador_fecha_fin":    date_to,
            "paginacion_indice":     str(pg),
        })
        ids     = parsers.parse_adjudicacion_listing_ids(html)
        new_ids = set(ids) - adj_ids
        if not new_ids:
            break
        adj_ids.update(new_ids)
        log.info("  adj page %d: %d new ids", pg, len(new_ids))
    return adj_ids


def fetch_adjudicacion_detail(page, eid: str) -> dict:
    html = _req(page, "GET", f"{BASE}/adjudicaciones-ficha.php?id={eid}")
    return parsers.parse_adjudicacion_detail(html, eid)


# ── S3 upload ─────────────────────────────────────────────────────────────────

def upload_to_s3(s3, key: str, licitaciones: list, adjudicaciones: list):
    payload = json.dumps({
        "scrape_date":    date.today().isoformat(),
        "licitaciones":   licitaciones,
        "adjudicaciones": adjudicaciones,
    }, ensure_ascii=False).encode()
    s3.put_object(Bucket=BUCKET, Key=key, Body=payload, ContentType="application/json")
    log.info("Uploaded %d bytes → s3://%s/%s  (%d lic, %d adj)",
             len(payload), BUCKET, key, len(licitaciones), len(adjudicaciones))


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=30,
                    help="How many days back to scrape (default: 30)")
    ap.add_argument("--from", dest="date_from",
                    help="Start date dd/mm/yyyy (overrides --days)")
    ap.add_argument("--to", dest="date_to",
                    help="End date dd/mm/yyyy (default: today)")
    ap.add_argument("--username", default="Cristina.Giraldo@ingrammicro.com")
    ap.add_argument("--password", default="ADJU2025")
    ap.add_argument("--headless", action="store_true", default=True)
    args = ap.parse_args()

    today = date.today()
    end   = today
    if args.date_to:
        d, m, y = args.date_to.split("/")
        end = date(int(y), int(m), int(d))

    if args.date_from:
        d, m, y = args.date_from.split("/")
        start = date(int(y), int(m), int(d))
    else:
        start = today - timedelta(days=args.days)

    log.info("Backfill %s → %s  (%d days)",
             start.strftime("%d/%m/%Y"), end.strftime("%d/%m/%Y"), (end - start).days)

    s3 = boto3.client("s3", region_name="eu-west-3")

    with sync_playwright() as pw:
        browser = pw.chromium.launch(headless=args.headless)
        ctx     = browser.new_context(
            user_agent=(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/124.0.0.0 Safari/537.36"
            ),
            locale="es-ES",
            timezone_id="Europe/Madrid",
        )
        page = ctx.new_page()

        login(page, args.username, args.password)

        # Process in CHUNK-day windows so each S3 file stays manageable
        cursor = start
        while cursor <= end:
            chunk_end  = min(cursor + timedelta(days=CHUNK - 1), end)
            date_from  = cursor.strftime("%d/%m/%Y")
            date_to    = chunk_end.strftime("%d/%m/%Y")
            s3_key     = f"scrapes/backfill-{cursor.isoformat()}.json"

            log.info("=== Chunk %s → %s ===", date_from, date_to)

            # ── licitaciones ──────────────────────────────────────────────────
            listing_rows = fetch_licitacion_listing(page, date_from, date_to)
            licitaciones = []
            for i, row in enumerate(listing_rows):
                eid = row["external_id"]
                try:
                    detail = fetch_licitacion_detail(page, eid)
                    licitaciones.append({**row, **detail})
                    time.sleep(0.15)
                except Exception as e:
                    log.warning("licitacion %s: %s", eid, e)
                    if "Session expired" in str(e):
                        log.info("Re-logging in...")
                        login(page, args.username, args.password)

                if (i + 1) % 25 == 0:
                    log.info("  %d/%d licitaciones done", i + 1, len(listing_rows))

            log.info("Chunk licitaciones: %d scraped", len(licitaciones))

            # ── adjudicaciones ────────────────────────────────────────────────
            adj_ids      = fetch_adjudicacion_ids(page, date_from, date_to)
            adjudicaciones = []
            for eid in adj_ids:
                try:
                    detail = fetch_adjudicacion_detail(page, eid)
                    adjudicaciones.append(detail)
                    time.sleep(0.15)
                except Exception as e:
                    log.warning("adjudicacion %s: %s", eid, e)
                    if "Session expired" in str(e):
                        login(page, args.username, args.password)

            log.info("Chunk adjudicaciones: %d scraped", len(adjudicaciones))

            # ── upload ────────────────────────────────────────────────────────
            upload_to_s3(s3, s3_key, licitaciones, adjudicaciones)

            cursor = chunk_end + timedelta(days=1)
            time.sleep(2)  # polite pause between chunks

        browser.close()

    log.info("Backfill complete. scraper_write will upsert everything into Aurora.")


if __name__ == "__main__":
    main()
