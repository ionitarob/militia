"""
PostgreSQL upsert helpers for scraped portal data.
Uses psycopg2 directly (no ORM).
"""

import logging
from typing import Optional

import psycopg2
import psycopg2.extras

log = logging.getLogger(__name__)


def restore_listing_fields(cur, rec: dict) -> None:
    """
    Restore importe_licitacion / fecha_limite_oferta from the original listing
    scrape data.  Only updates rows where the value is currently NULL (safe to
    run repeatedly).  Does not touch any other field.
    """
    cur.execute(
        """
        UPDATE licitacion SET
            importe_licitacion  = COALESCE(importe_licitacion,  %(importe)s),
            fecha_limite_oferta = COALESCE(fecha_limite_oferta, %(fecha_limite)s)
        WHERE external_id = %(external_id)s
          AND (%(importe)s IS NOT NULL OR %(fecha_limite)s IS NOT NULL)
        """,
        {
            "external_id":  rec.get("external_id"),
            "importe":      rec.get("importe_licitacion"),
            "fecha_limite": rec.get("fecha_limite_oferta"),
        },
    )


def upsert_licitacion(cur, rec: dict) -> Optional[int]:
    """
    Upsert a licitacion by external_id.
    Returns the internal id, or None if the row already existed and was skipped.
    """
    # Upsert organismo → get organismo_id
    organismo_id = None
    if rec.get("organismo_nombre"):
        cur.execute(
            """
            INSERT INTO organismo (nombre) VALUES (%s)
            ON CONFLICT (nombre) DO UPDATE SET nombre = EXCLUDED.nombre
            RETURNING id
            """,
            (rec["organismo_nombre"],),
        )
        row = cur.fetchone()
        organismo_id = row[0] if row else None

    # Upsert area_tecnologica → get area_tecnologica_id
    area_tecnologica_id = None
    at = rec.get("area_tecnologica")
    if at:
        cur.execute(
            """
            INSERT INTO area_tecnologica (cat1, cat2, cat3)
            VALUES (%s, %s, %s)
            ON CONFLICT (cat1, cat2, cat3) DO UPDATE SET cat1 = EXCLUDED.cat1
            RETURNING id
            """,
            (at["cat1"], at["cat2"], at["cat3"]),
        )
        row = cur.fetchone()
        area_tecnologica_id = row[0] if row else None

    params = {
        "external_id":          rec.get("external_id"),
        "fecha":                rec.get("fecha"),
        "titulo":               rec.get("titulo") or rec.get("titulo_raw", ""),
        "numero_expediente":    rec.get("numero_expediente") or "",
        "importe_licitacion":   rec.get("importe_licitacion"),
        "valor_estimado":       rec.get("valor_estimado"),
        "tipo_procedimiento":   rec.get("tipo_procedimiento"),
        "tipo_tramitacion":     rec.get("tipo_tramitacion"),
        "fecha_limite_oferta":  rec.get("fecha_limite_oferta"),
        "comunidad_autonoma":   rec.get("comunidad_autonoma"),
        "provincia":            rec.get("provincia"),
        "mercado_vertical":     rec.get("mercado_vertical"),
        "competencia":          rec.get("competencia"),
        "duracion_meses":       rec.get("duracion_meses"),
        "prorrogas_meses":      rec.get("prorrogas_meses"),
        "puntos_precio":        rec.get("puntos_precio"),
        "puntos_mejoras":       rec.get("puntos_mejoras"),
        "puntos_subjetivos":    rec.get("puntos_subjetivos"),
        "organismo_id":         organismo_id,
        "area_tecnologica_id":  area_tecnologica_id,
    }

    if not params["titulo"]:
        # Documents-only record — look up existing row without touching any fields.
        cur.execute(
            "SELECT id FROM licitacion WHERE external_id = %(external_id)s",
            params,
        )
        row = cur.fetchone()
        licitacion_id = row[0] if row else None
        documents = rec.get("documents") or []
        if licitacion_id and documents:
            for doc in documents:
                cur.execute(
                    """
                    INSERT INTO licitacion_documento
                        (licitacion_id, nombre, s3_key, content_type, size_bytes)
                    VALUES (%s, %s, %s, %s, %s)
                    ON CONFLICT (licitacion_id, s3_key) DO UPDATE SET
                        nombre       = EXCLUDED.nombre,
                        content_type = EXCLUDED.content_type,
                        size_bytes   = EXCLUDED.size_bytes
                    """,
                    (licitacion_id, doc["nombre"], doc["s3_key"],
                     doc.get("content_type"), doc.get("size_bytes")),
                )
        return licitacion_id

    if params["fecha"] is None:
        # Refresh record — fecha not scraped from detail page. Only UPDATE existing row.
        # importe_licitacion and fecha_limite_oferta come from the listing table,
        # not the detail page — use COALESCE so a refresh never wipes them out.
        cur.execute(
            """
            UPDATE licitacion SET
                titulo              = %(titulo)s,
                numero_expediente   = %(numero_expediente)s,
                importe_licitacion  = COALESCE(%(importe_licitacion)s, importe_licitacion),
                valor_estimado      = %(valor_estimado)s,
                tipo_procedimiento  = %(tipo_procedimiento)s::tipo_procedimiento_tipo,
                tipo_tramitacion    = %(tipo_tramitacion)s,
                fecha_limite_oferta = COALESCE(%(fecha_limite_oferta)s, fecha_limite_oferta),
                comunidad_autonoma  = %(comunidad_autonoma)s::comunidad_autonoma_tipo,
                provincia           = %(provincia)s,
                mercado_vertical    = %(mercado_vertical)s::mercado_vertical_tipo,
                competencia         = %(competencia)s,
                duracion_meses      = %(duracion_meses)s,
                prorrogas_meses     = %(prorrogas_meses)s,
                puntos_precio       = %(puntos_precio)s,
                puntos_mejoras      = %(puntos_mejoras)s,
                puntos_subjetivos   = %(puntos_subjetivos)s,
                organismo_id        = %(organismo_id)s,
                area_tecnologica_id = %(area_tecnologica_id)s
            WHERE external_id = %(external_id)s
            RETURNING id
            """,
            params,
        )
    else:
        cur.execute(
            """
            INSERT INTO licitacion (
                external_id, fecha, titulo, numero_expediente,
                importe_licitacion, valor_estimado,
                tipo_procedimiento, tipo_tramitacion,
                fecha_limite_oferta,
                comunidad_autonoma, provincia,
                mercado_vertical, competencia,
                duracion_meses, prorrogas_meses,
                puntos_precio, puntos_mejoras, puntos_subjetivos,
                organismo_id, area_tecnologica_id
            ) VALUES (
                %(external_id)s, %(fecha)s, %(titulo)s, %(numero_expediente)s,
                %(importe_licitacion)s, %(valor_estimado)s,
                %(tipo_procedimiento)s::tipo_procedimiento_tipo,
                %(tipo_tramitacion)s, %(fecha_limite_oferta)s,
                %(comunidad_autonoma)s::comunidad_autonoma_tipo,
                %(provincia)s, %(mercado_vertical)s::mercado_vertical_tipo,
                %(competencia)s, %(duracion_meses)s, %(prorrogas_meses)s,
                %(puntos_precio)s, %(puntos_mejoras)s, %(puntos_subjetivos)s,
                %(organismo_id)s, %(area_tecnologica_id)s
            )
            ON CONFLICT (external_id) DO UPDATE SET
                fecha               = EXCLUDED.fecha,
                titulo              = EXCLUDED.titulo,
                numero_expediente   = EXCLUDED.numero_expediente,
                importe_licitacion  = COALESCE(EXCLUDED.importe_licitacion,  licitacion.importe_licitacion),
                valor_estimado      = COALESCE(EXCLUDED.valor_estimado,      licitacion.valor_estimado),
                tipo_procedimiento  = COALESCE(EXCLUDED.tipo_procedimiento,  licitacion.tipo_procedimiento),
                tipo_tramitacion    = COALESCE(EXCLUDED.tipo_tramitacion,    licitacion.tipo_tramitacion),
                fecha_limite_oferta = COALESCE(EXCLUDED.fecha_limite_oferta, licitacion.fecha_limite_oferta),
                comunidad_autonoma  = COALESCE(EXCLUDED.comunidad_autonoma,  licitacion.comunidad_autonoma),
                provincia           = COALESCE(EXCLUDED.provincia,           licitacion.provincia),
                mercado_vertical    = COALESCE(EXCLUDED.mercado_vertical,    licitacion.mercado_vertical),
                competencia         = COALESCE(EXCLUDED.competencia,         licitacion.competencia),
                duracion_meses      = COALESCE(EXCLUDED.duracion_meses,      licitacion.duracion_meses),
                prorrogas_meses     = COALESCE(EXCLUDED.prorrogas_meses,     licitacion.prorrogas_meses),
                puntos_precio       = COALESCE(EXCLUDED.puntos_precio,       licitacion.puntos_precio),
                puntos_mejoras      = COALESCE(EXCLUDED.puntos_mejoras,      licitacion.puntos_mejoras),
                puntos_subjetivos   = COALESCE(EXCLUDED.puntos_subjetivos,   licitacion.puntos_subjetivos),
                organismo_id        = COALESCE(EXCLUDED.organismo_id,        licitacion.organismo_id),
                area_tecnologica_id = COALESCE(EXCLUDED.area_tecnologica_id, licitacion.area_tecnologica_id)
            RETURNING id
            """,
            params,
        )

    row = cur.fetchone()
    licitacion_id = row[0] if row else None

    # Write CPV codes with descriptions ──────────────────────────────────────
    cpv_pairs = rec.get("cpv_pairs") or [(c, c) for c in (rec.get("cpv_codes") or [])]
    if licitacion_id and cpv_pairs:
        cur.execute("DELETE FROM licitacion_cpv WHERE licitacion_id = %s", (licitacion_id,))
        for code, desc in cpv_pairs:
            cur.execute(
                """INSERT INTO cpv_code (code, descripcion) VALUES (%s, %s)
                   ON CONFLICT (code) DO UPDATE SET descripcion = EXCLUDED.descripcion
                   WHERE cpv_code.descripcion = cpv_code.code""",
                (code, desc),
            )
            cur.execute(
                "INSERT INTO licitacion_cpv (licitacion_id, cpv_code) VALUES (%s, %s) ON CONFLICT DO NOTHING",
                (licitacion_id, code),
            )

    # Write document attachments
    documents = rec.get("documents") or []
    if licitacion_id and documents:
        for doc in documents:
            cur.execute(
                """
                INSERT INTO licitacion_documento (licitacion_id, nombre, s3_key, content_type, size_bytes)
                VALUES (%s, %s, %s, %s, %s)
                ON CONFLICT (licitacion_id, s3_key) DO UPDATE SET
                    nombre       = EXCLUDED.nombre,
                    content_type = EXCLUDED.content_type,
                    size_bytes   = EXCLUDED.size_bytes
                """,
                (licitacion_id, doc["nombre"], doc["s3_key"],
                 doc.get("content_type"), doc.get("size_bytes")),
            )

    return licitacion_id


def upsert_adjudicacion(cur, rec: dict) -> Optional[int]:
    """Upsert an adjudicacion by external_id."""
    organismo_id    = None
    adjudicatario_id = None

    if rec.get("organismo_nombre"):
        cur.execute(
            "INSERT INTO organismo (nombre) VALUES (%s) ON CONFLICT (nombre) DO UPDATE SET nombre = EXCLUDED.nombre RETURNING id",
            (rec["organismo_nombre"],),
        )
        row = cur.fetchone()
        organismo_id = row[0] if row else None

    if rec.get("adjudicatario_nombre"):
        cur.execute(
            "INSERT INTO adjudicatario (nombre) VALUES (%s) ON CONFLICT (nombre) DO UPDATE SET nombre = EXCLUDED.nombre RETURNING id",
            (rec["adjudicatario_nombre"],),
        )
        row = cur.fetchone()
        adjudicatario_id = row[0] if row else None

    # Try to link to an existing licitacion by expediente number
    licitacion_id = None
    if rec.get("numero_expediente"):
        cur.execute(
            "SELECT id FROM licitacion WHERE numero_expediente = %s LIMIT 1",
            (rec["numero_expediente"],),
        )
        row = cur.fetchone()
        licitacion_id = row[0] if row else None

    cur.execute(
        """
        INSERT INTO adjudicacion (
            external_id,
            licitacion_id,
            titulo, numero_expediente,
            fecha_adjudicacion,
            importe, importe_adjudicado,
            ratio_adjudicacion_vs_licitacion,
            valor_estimado,
            tipo_procedimiento, tipo_tramitacion,
            fecha_vencimiento_contrato,
            comunidad_autonoma, provincia,
            mercado_vertical,
            organismo_id, adjudicatario_id
        ) VALUES (
            %(external_id)s,
            %(licitacion_id)s,
            %(titulo)s, %(numero_expediente)s,
            %(fecha_adjudicacion)s,
            %(importe_licitacion)s, %(importe_adjudicado)s,
            %(ratio)s,
            %(valor_estimado)s,
            %(tipo_procedimiento)s::tipo_procedimiento_tipo,
            %(tipo_tramitacion)s,
            %(fecha_vencimiento_contrato)s,
            %(comunidad_autonoma)s::comunidad_autonoma_tipo,
            %(provincia)s,
            %(mercado_vertical)s::mercado_vertical_tipo,
            %(organismo_id)s, %(adjudicatario_id)s
        )
        ON CONFLICT (external_id) DO UPDATE SET
            licitacion_id     = EXCLUDED.licitacion_id,
            titulo            = EXCLUDED.titulo,
            numero_expediente = EXCLUDED.numero_expediente,
            fecha_adjudicacion = EXCLUDED.fecha_adjudicacion,
            importe           = EXCLUDED.importe,
            importe_adjudicado = EXCLUDED.importe_adjudicado,
            ratio_adjudicacion_vs_licitacion = EXCLUDED.ratio_adjudicacion_vs_licitacion,
            valor_estimado    = EXCLUDED.valor_estimado,
            tipo_procedimiento = EXCLUDED.tipo_procedimiento,
            tipo_tramitacion  = EXCLUDED.tipo_tramitacion,
            fecha_vencimiento_contrato = EXCLUDED.fecha_vencimiento_contrato,
            comunidad_autonoma = EXCLUDED.comunidad_autonoma,
            provincia         = EXCLUDED.provincia,
            mercado_vertical  = EXCLUDED.mercado_vertical,
            organismo_id      = EXCLUDED.organismo_id,
            adjudicatario_id  = EXCLUDED.adjudicatario_id
        RETURNING id
        """,
        {
            "external_id":           rec.get("external_id"),
            "licitacion_id":         licitacion_id,
            "titulo":                rec.get("titulo", ""),
            "numero_expediente":     rec.get("numero_expediente") or "",
            "fecha_adjudicacion":    rec.get("fecha_adjudicacion"),
            "importe_licitacion":    rec.get("importe_licitacion"),
            "importe_adjudicado":    rec.get("importe_adjudicado"),
            "ratio":                 rec.get("ratio_adjudicacion_vs_licitacion"),
            "valor_estimado":        rec.get("valor_estimado"),
            "tipo_procedimiento":    rec.get("tipo_procedimiento"),
            "tipo_tramitacion":      rec.get("tipo_tramitacion"),
            "fecha_vencimiento_contrato": rec.get("fecha_vencimiento_contrato"),
            "comunidad_autonoma":    rec.get("comunidad_autonoma"),
            "provincia":             rec.get("provincia"),
            "mercado_vertical":      rec.get("mercado_vertical"),
            "organismo_id":          organismo_id,
            "adjudicatario_id":      adjudicatario_id,
        },
    )
    adjudicacion_id = row[0] if row else None

    # Send in-app alerts to comerciales who worked on the linked licitacion
    if adjudicacion_id and licitacion_id:
        cur.execute(
            """SELECT DISTINCT user_id FROM licitacion_cotizacion
               WHERE licitacion_id = %s AND user_id IS NOT NULL""",
            (licitacion_id,),
        )
        comercial_ids = [row[0] for row in cur.fetchall()]
        titulo = rec.get("titulo", "Adjudicación")
        for uid in comercial_ids:
            cur.execute(
                """INSERT INTO alerta (user_id, adjudicacion_id, licitacion_id, mensaje)
                   VALUES (%s, %s, %s, %s)
                   ON CONFLICT (user_id, adjudicacion_id) DO NOTHING""",
                (uid, adjudicacion_id, licitacion_id,
                 f"El pliego «{titulo}» que trabajaste ha sido adjudicado."),
            )

    # Write CPV codes
    cpv_codes = rec.get("cpv_codes") or []
    if adjudicacion_id and cpv_codes:
        cur.execute("DELETE FROM adjudicacion_cpv WHERE adjudicacion_id = %s", (adjudicacion_id,))
        for code in cpv_codes:
            cur.execute(
                "INSERT INTO cpv_code (code, descripcion) VALUES (%s, %s) ON CONFLICT DO NOTHING",
                (code, code),
            )
            cur.execute(
                "INSERT INTO adjudicacion_cpv (adjudicacion_id, cpv_code) VALUES (%s, %s) ON CONFLICT DO NOTHING",
                (adjudicacion_id, code),
            )

    return adjudicacion_id


def build_conn(db_url: str):
    return psycopg2.connect(db_url)
