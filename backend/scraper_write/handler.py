"""
scraper_write – Lambda B (in VPC, isolated subnet).

Triggered by S3 ObjectCreated events from the scraper_fetch Lambda.
Reads JSON from S3, upserts records into RDS PostgreSQL.

Environment variables required:
  DB_SECRET_ARN – Secrets Manager ARN with RDS credentials
"""

import json
import logging
import os

import boto3

import db

log = logging.getLogger()
log.setLevel(logging.INFO)


_conn = None  # reused across warm invocations


def lambda_handler(event, context):
    s3_records = event.get("Records", [])
    if not s3_records:
        log.warning("No S3 records in event")
        return

    conn = _get_conn()

    inserted_lic = 0
    inserted_adj = 0
    errors       = 0

    for record in s3_records:
        bucket = record["s3"]["bucket"]["name"]
        key    = record["s3"]["object"]["key"]
        log.info("Processing s3://%s/%s", bucket, key)

        s3   = boto3.client("s3")
        obj  = s3.get_object(Bucket=bucket, Key=key)
        data = json.loads(obj["Body"].read())

        licitaciones   = data.get("licitaciones", [])
        adjudicaciones = data.get("adjudicaciones", [])

        log.info("Upserting %d licitaciones, %d adjudicaciones", len(licitaciones), len(adjudicaciones))

        with conn:  # transaction per S3 file
            with conn.cursor() as cur:
                for rec in licitaciones:
                    try:
                        row_id = db.upsert_licitacion(cur, rec)
                        if row_id:
                            inserted_lic += 1
                    except Exception as e:
                        log.warning("licitacion %s upsert error: %s", rec.get("external_id"), e)
                        conn.rollback()
                        errors += 1

                for rec in adjudicaciones:
                    try:
                        row_id = db.upsert_adjudicacion(cur, rec)
                        if row_id:
                            inserted_adj += 1
                    except Exception as e:
                        log.warning("adjudicacion %s upsert error: %s", rec.get("external_id"), e)
                        conn.rollback()
                        errors += 1

    log.info(
        "Done: %d licitaciones inserted, %d adjudicaciones inserted, %d errors",
        inserted_lic, inserted_adj, errors,
    )
    return {
        "inserted_licitaciones":  inserted_lic,
        "inserted_adjudicaciones": inserted_adj,
        "errors": errors,
    }


def _get_conn():
    global _conn
    if _conn is None or _conn.closed:
        _conn = db.build_conn(_get_db_url())
    return _conn


def _get_db_url() -> str:
    secret_arn = os.environ["DB_SECRET_ARN"]
    sm         = boto3.client("secretsmanager")
    resp       = sm.get_secret_value(SecretId=secret_arn)
    creds      = json.loads(resp["SecretString"])
    return (
        f"postgresql://{creds['username']}:{creds['password']}"
        f"@{creds['host']}:{creds.get('port', 5432)}/{creds.get('dbname', 'imliti')}"
    )
