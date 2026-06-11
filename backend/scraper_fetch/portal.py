import logging
import time
import requests

BASE = "https://www.adjudicacionestic.com/front"
UA   = "Mozilla/5.0 (compatible; IMLiti-Scraper/1.0)"

log = logging.getLogger(__name__)


def create_session(username: str, password: str) -> requests.Session:
    s = requests.Session()
    s.headers["User-Agent"] = UA

    resp = s.post(
        f"{BASE}/acceso.php",
        data={"username": username, "password": password, "sec": "", "var": "", "remember": "1"},
        timeout=30,
    )
    resp.raise_for_status()

    if "PHPSESSID" not in s.cookies:
        raise RuntimeError("Login failed – no session cookie received")

    # Store credentials on the session so we can re-login when the server-side
    # session expires (happens after ~200 requests / ~2 minutes of scraping).
    s._portal_username = username
    s._portal_password = password
    return s


def _renew(session: requests.Session) -> None:
    """Re-login with stored credentials to refresh the expired PHPSESSID."""
    log.info("Session expired – re-logging in as %s", session._portal_username)
    resp = session.post(
        f"{BASE}/acceso.php",
        data={
            "username": session._portal_username,
            "password": session._portal_password,
            "sec": "", "var": "", "remember": "1",
        },
        timeout=30,
    )
    resp.raise_for_status()
    if "PHPSESSID" not in session.cookies:
        raise RuntimeError("Re-login failed – no session cookie received")
    log.info("Re-login successful")


def _session_expired(resp: requests.Response) -> bool:
    """Return True when the portal redirected us to the login/registration page."""
    return "registro.php" in resp.url


def get(session: requests.Session, url: str, delay: float = 0.25) -> requests.Response:
    time.sleep(delay)
    resp = session.get(url, timeout=30)
    resp.raise_for_status()
    if _session_expired(resp):
        _renew(session)
        resp = session.get(url, timeout=30)
        resp.raise_for_status()
    return resp


def post(session: requests.Session, url: str, data: dict, delay: float = 0.25) -> requests.Response:
    time.sleep(delay)
    resp = session.post(url, data=data, timeout=30)
    resp.raise_for_status()
    if _session_expired(resp):
        _renew(session)
        resp = session.post(url, data=data, timeout=30)
        resp.raise_for_status()
    return resp
