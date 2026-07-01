"""
HTML parsers for adjudicacionestic.com.

Licitaciones listing → licitacion records (basic fields from table row).
Licitacion detail   → full licitacion record.
Adjudicaciones listing → list of external_ids.
Adjudicacion detail → full adjudicacion record.
"""

import re
from typing import Optional
from bs4 import BeautifulSoup

BASE = "https://www.adjudicacionestic.com/front"

# ── Enum normalisation ────────────────────────────────────────────────────────

_COMUNIDAD_MAP = {
    "Andalucía": "Andalucía",
    "Aragón": "Aragón",
    "Asturias, Principado de": "Asturias Principado de",
    "Asturias Principado de": "Asturias Principado de",
    "Canarias": "Canarias",
    "Cantabria": "Cantabria",
    "Castilla - La Mancha": "Castilla - La Mancha",
    "Castilla y León": "Castilla y León",
    "Catalunya": "Catalunya",
    "Ceuta": "Ceuta",
    "Comunitat Valenciana": "Comunitat Valenciana",
    "Extremadura": "Extremadura",
    "Galicia": "Galicia",
    "Illes Balears": "Illes Balears",
    "Madrid, Comunidad de": "Madrid Comunidad de",
    "Madrid Comunidad de": "Madrid Comunidad de",
    "Melilla": "Melilla",
    "Murcia, Región de": "Murcia Región de",
    "Murcia Región de": "Murcia Región de",
    "Navarra, Comunidad Foral de": "Navarra Comunidad Floral de",
    "Navarra Comunidad Foral de": "Navarra Comunidad Floral de",
    "País Vasco": "País Vasco",
    "Rioja, La": "Rioja La",
    "Rioja La": "Rioja La",
}

def _norm_comunidad(raw: str) -> Optional[str]:
    if not raw:
        return None
    raw = raw.strip()
    return _COMUNIDAD_MAP.get(raw) or _COMUNIDAD_MAP.get(raw.replace(",", "").strip())


_MERCADO_VALID = {
    "CIENCIA E INNOVACIÓN",
    "DEFENSA",
    "ECONOMÍA Y HACIENDA",
    "EDUCACIÓN",
    "EDUCACIÓN CULTURA Y DEPORTES",
    "EMPLEO Y SEGURIDAD SOCIAL",
    "FOMENTO",
    "INDUSTRIA ENERGÍA Y TURISMO",
    "INFORMACIÓN Y COMUNICACIONES",
    "INTERIOR",
    "INTERIOR EMERGENCIAS Y PROTECCIÓN CIVIL",
    "JUSTICIA",
    "OTROS",
    "OTROS EELL",
    "SANIDAD",
    "TRANSPORTE",
}

def _norm_mercado(raw: str) -> Optional[str]:
    if not raw:
        return None
    normalised = raw.strip().replace(",", "")
    return normalised if normalised in _MERCADO_VALID else None


_PROCEDIMIENTO_VALID = {
    "Abierto", "Acuerdo Marco", "Contrato Menor", "Diálogo Competitivo",
    "Negociado", "Negociado con Publicidad", "Negociado por exclusividad",
    "Negociado sin Publicidad", "Normas internas", "Restringido",
    "Simplificado", "Sistema Dinámico de Adquisición",
}

def _norm_procedimiento(raw: str) -> Optional[str]:
    if not raw:
        return None
    return raw.strip() if raw.strip() in _PROCEDIMIENTO_VALID else None


# ── Money helpers ─────────────────────────────────────────────────────────────

def _parse_money(raw: str) -> Optional[float]:
    """'1.280.313,94€ (IVA no incluido)' → 1280313.94"""
    if not raw:
        return None
    digits = re.sub(r"[^\d,]", "", raw)   # keep digits and comma
    digits = digits.replace(",", ".")      # Spanish decimal comma → dot
    try:
        return float(digits)
    except ValueError:
        return None


def _parse_int(raw: str) -> Optional[int]:
    m = re.search(r"\d+", raw)
    return int(m.group()) if m else None


def _parse_cpv(raw: str) -> list[str]:
    """'45310000 - Desc09330000 - Desc' → ['45310000', '09330000']"""
    return re.findall(r"(?<!\d)(\d{8})(?!\d)", raw)


def _parse_cpv_pairs(raw: str) -> list[tuple[str, str]]:
    """'72400000 - Servicios de Internet' → [('72400000', 'Servicios de Internet')]"""
    pairs = []
    for m in re.finditer(r'(?<!\d)(\d{8})(?!\d)\s*-\s*([^0-9]*?)(?=(?<!\d)\d{8}(?!\d)|$)', raw):
        code = m.group(1)
        desc = m.group(2).strip().rstrip('-').strip()
        pairs.append((code, desc if desc else code))
    # fallback: return bare codes with no description match
    if not pairs:
        for code in _parse_cpv(raw):
            pairs.append((code, code))
    return pairs


# ── Key-value extractor ───────────────────────────────────────────────────────

def _kv(soup: BeautifulSoup) -> dict[str, str]:
    result = {}
    for d in soup.find_all("div", class_="adjudicacion-dato"):
        nombre = d.find("div", class_="adjudicacion-dato-nombre")
        valor  = d.find("div", class_="adjudicacion-dato-valor")
        if nombre:
            key = nombre.get_text(strip=True).replace("\xa0", " ")
            val = valor.get_text(strip=True) if valor else ""
            result[key] = val
    return result


# ── Licitaciones ──────────────────────────────────────────────────────────────

def parse_licitacion_listing(html: str) -> list[dict]:
    """
    Returns a list of dicts with external_id + basic fields extracted from the
    <table id="licitaciones"> rows.  Detail page is needed for the rest.
    """
    soup  = BeautifulSoup(html, "lxml")
    table = soup.find("table", {"id": "licitaciones"})
    if not table:
        return []

    records = []
    for tr in table.find_all("tr", class_="licitacion"):
        tr_id = tr.get("id", "")
        m = re.search(r"licita-(\d+)", tr_id)
        if not m:
            continue
        external_id = m.group(1)

        tds = tr.find_all("td")
        if len(tds) < 7:
            continue

        rec = {
            "external_id":        external_id,
            "fecha":              tds[1].get_text(strip=True),          # ISO date
            "fecha_limite_oferta": tds[3].get_text(strip=True),         # ISO date
            "importe_licitacion": _safe_float(tds[6].get_text(strip=True)),
        }

        # Export/hidden columns (indices 7+)
        if len(tds) >= 13:
            rec["numero_expediente"]  = tds[7].get_text(strip=True)
            rec["tipo_procedimiento"] = _norm_procedimiento(tds[9].get_text(strip=True))
            rec["puntos_precio"]      = _parse_int(tds[10].get_text())
            rec["puntos_mejoras"]     = _parse_int(tds[11].get_text())
            rec["puntos_subjetivos"]  = _parse_int(tds[12].get_text())
        if len(tds) >= 17:
            rec["organismo_nombre"]   = tds[16].get_text(strip=True)
        if len(tds) >= 18:
            titulo = tds[17].get_text(strip=True)
            rec["titulo_raw"] = titulo  # UPPERCASE; detail page gives proper case

        records.append(rec)

    return records


def _safe_float(s: str) -> Optional[float]:
    try:
        return float(s)
    except (ValueError, TypeError):
        return None


def parse_licitacion_detail(html: str, external_id: str) -> dict:
    """Parse a licitaciones-ficha.php page into a full licitacion dict."""
    soup = BeautifulSoup(html, "lxml")
    kv   = _kv(soup)
    if not kv and "registro.php" in html:
        raise ValueError(f"licitacion {external_id}: got login/registration page — session expired")

    # Title is in the first <h3>
    h3_tags = soup.find_all("h3")
    titulo  = h3_tags[0].get_text(strip=True) if h3_tags else ""

    # Organismo is in the first <h2>
    h2_tags = soup.find_all("h2")
    organismo = h2_tags[0].get_text(strip=True) if h2_tags else ""

    # Área tecnológica — breadcrumb pills: cat1 > cat2 > cat3
    taglist = soup.find("ul", class_="taglist")
    area_tags = [li.get_text(strip=True) for li in taglist.find_all("li")] if taglist else []
    area_tecnologica = None
    if len(area_tags) >= 3:
        area_tecnologica = {"cat1": area_tags[0], "cat2": area_tags[1], "cat3": area_tags[2]}
    elif len(area_tags) == 2:
        area_tecnologica = {"cat1": area_tags[0], "cat2": area_tags[1], "cat3": ""}
    elif len(area_tags) == 1:
        area_tecnologica = {"cat1": area_tags[0], "cat2": "", "cat3": ""}

    # Puntos from "Criterios de adjudicación"
    criterios = kv.get("Criterios de adjudicación", "")
    puntos_precio    = _parse_puntos(criterios, r"precio\):\s*(\d+)")
    puntos_mejoras   = _parse_puntos(criterios, r"mejoras\)\s*(\d+)")
    puntos_subjetivos = _parse_puntos(criterios, r"[Ss]ubjetivos:\s*(\d+)")

    duracion_raw   = kv.get("Duración", "")
    duracion_m     = re.search(r"(\d+)", duracion_raw)
    prorrogas_raw  = kv.get("Prorrogas", "") or kv.get("Prórrogas", "")
    prorrogas_m    = re.search(r"(\d+)", prorrogas_raw)

    cpv_raw = kv.get("Clasificación CPV", "")

    return {
        "external_id":       external_id,
        "titulo":            titulo,
        "organismo_nombre":  organismo,
        "numero_expediente": kv.get("Número de expediente"),
        "tipo_procedimiento": _norm_procedimiento(kv.get("Tipo de procedimiento", "")),
        "tipo_tramitacion":  kv.get("Tipo de tramitación"),
        "valor_estimado":    _parse_money(kv.get("Valor estimado", "")),
        "duracion_meses":    int(duracion_m.group(1)) if duracion_m else None,
        "prorrogas_meses":   int(prorrogas_m.group(1)) if prorrogas_m else None,
        "competencia":       kv.get("Competencia"),
        "mercado_vertical":  _norm_mercado(kv.get("Mercado vertical", "")),
        "provincia":         kv.get("Provincia"),
        "comunidad_autonoma": _norm_comunidad(kv.get("Comunidad autónoma", "")),
        "cpv_codes":         _parse_cpv(cpv_raw),
        "cpv_pairs":         _parse_cpv_pairs(cpv_raw),
        "area_tags":         area_tags,
        "puntos_precio":     puntos_precio,
        "puntos_mejoras":    puntos_mejoras,
        "puntos_subjetivos": puntos_subjetivos,
        "area_tecnologica":  area_tecnologica,
    }


def _parse_puntos(criterios: str, pattern: str) -> Optional[int]:
    m = re.search(pattern, criterios)
    return int(m.group(1)) if m else None


# ── Adjudicaciones ────────────────────────────────────────────────────────────

def parse_adjudicacion_listing_ids(html: str) -> list[str]:
    """Extract all external IDs from the adjudicaciones search result page."""
    return re.findall(r"adjudicaciones-ficha\.php\?id=(\d+)", html)


def parse_adjudicacion_detail(html: str, external_id: str) -> dict:
    """Parse an adjudicaciones-ficha.php page into a full adjudicacion dict."""
    soup = BeautifulSoup(html, "lxml")
    kv   = _kv(soup)
    if not kv and "registro.php" in html:
        raise ValueError(f"adjudicacion {external_id}: got login/registration page — session expired")

    h3_tags = soup.find_all("h3")
    h2_tags = soup.find_all("h2")

    titulo           = h3_tags[0].get_text(strip=True) if h3_tags else ""
    organismo        = h2_tags[0].get_text(strip=True) if len(h2_tags) > 0 else ""
    adjudicatario    = h2_tags[1].get_text(strip=True) if len(h2_tags) > 1 else ""
    importe_h2       = h2_tags[2].get_text(strip=True) if len(h2_tags) > 2 else ""
    fecha_h2         = h2_tags[3].get_text(strip=True) if len(h2_tags) > 3 else ""

    taglist = soup.find("ul", class_="taglist")
    area_tags = [li.get_text(strip=True) for li in taglist.find_all("li")] if taglist else []
    area_tecnologica = None
    if len(area_tags) >= 3:
        area_tecnologica = {"cat1": area_tags[0], "cat2": area_tags[1], "cat3": area_tags[2]}
    elif len(area_tags) == 2:
        area_tecnologica = {"cat1": area_tags[0], "cat2": area_tags[1], "cat3": ""}
    elif len(area_tags) == 1:
        area_tecnologica = {"cat1": area_tags[0], "cat2": "", "cat3": ""}

    # Ratio: "-2,01%" → -0.0201
    ratio_raw = kv.get("Importe adjudicación vs licitación", "")
    ratio_m   = re.search(r"(-?\d+[,.]?\d*)\s*%", ratio_raw)
    ratio     = float(ratio_m.group(1).replace(",", ".")) / 100 if ratio_m else None

    # Fecha vencimiento contrato: "08/06/2026" → "2026-06-08"
    fecha_vc_raw = kv.get("Fecha de vencimientodel contrato") or kv.get("Fecha de vencimiento del contrato", "")
    fecha_vc     = _parse_date_dmy(fecha_vc_raw)

    # Fecha adjudicacion from H2: "08/06/2026"
    fecha_adj = _parse_date_dmy(fecha_h2)

    return {
        "external_id":                    external_id,
        "titulo":                         titulo,
        "organismo_nombre":               organismo,
        "adjudicatario_nombre":           adjudicatario,
        "importe_adjudicado":             _parse_money(importe_h2),
        "fecha_adjudicacion":             fecha_adj,
        "importe_licitacion":             _parse_money(kv.get("Importe licitación", "")),
        "ratio_adjudicacion_vs_licitacion": ratio,
        "valor_estimado":                 _parse_money(kv.get("Valor estimado", "")),
        "numero_expediente":              kv.get("Número de expediente"),
        "tipo_procedimiento":             _norm_procedimiento(kv.get("Tipo de procedimiento", "")),
        "tipo_tramitacion":               kv.get("Tipo de tramitación"),
        "fecha_vencimiento_contrato":     fecha_vc,
        "mercado_vertical":               _norm_mercado(kv.get("Mercado vertical", "")),
        "provincia":                      kv.get("Provincia"),
        "comunidad_autonoma":             _norm_comunidad(kv.get("Comunidad autónoma", "")),
        "cpv_codes":                      _parse_cpv(kv.get("Clasificación CPV", "")),
        "area_tecnologica":               area_tecnologica,
    }


def _parse_date_dmy(raw: str) -> Optional[str]:
    """'29/06/2026' → '2026-06-29'"""
    m = re.search(r"(\d{2})/(\d{2})/(\d{4})", raw)
    if m:
        return f"{m.group(3)}-{m.group(2)}-{m.group(1)}"
    return None


_TIPO_NOMBRES = {
    "ANUNCIO": "Anuncio licitación",
    "PPT":     "Prescripciones técnicas",
    "PCAP":    "Cláusulas administrativas",
}


def parse_documents(html: str) -> list[dict]:
    """Return [{nombre, href}] for document links on a licitacion detail page.

    The portal serves documents via:
      descarga-adjudicacion.php?tipo=ANUNCIO|PPT|PCAP&id=…
      descarga-otros.php?tipo=OTROS&id=…&id2=…
    """
    soup = BeautifulSoup(html, "lxml")
    docs: list[dict] = []
    seen: set[str] = set()

    for a in soup.find_all("a", href=True):
        href = a["href"].strip()
        if not href or href in seen:
            continue
        if "descarga-adjudicacion.php" in href or "descarga-otros.php" in href:
            seen.add(href)
            label = a.get_text(strip=True)
            if not label:
                m = re.search(r"tipo=([^&]+)", href)
                label = _TIPO_NOMBRES.get(m.group(1), "Documento") if m else "Documento"
            docs.append({"nombre": label, "href": href})

    return docs
