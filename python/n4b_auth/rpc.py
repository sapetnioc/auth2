from datetime import datetime, timedelta
import requests

from .util import iter_execute, execute


def login(username: str, password: str) -> dict:
    r = requests.post(
        "http://keycloak:8080/realms/n4brain/protocol/openid-connect/token",
        data={
            "client_id": "n4b_auth",
            "grant_type": "password",
            "username": username,
            "password": password,
        },
    )
    r.raise_for_status()
    sql = (
        "INSERT INTO login_session "
        "(username, access_token, refresh_token, expires, refresh_expires) "
        "VALUES ($1,$2,$3,$4,$5) "
        "ON CONFLICT (username) DO UPDATE SET "
        "  access_token=EXCLUDED.access_token,"
        "  refresh_token=EXCLUDED.refresh_token,"
        "  expires=EXCLUDED.expires,"
        "  refresh_expires=EXCLUDED.refresh_expires "
        "RETURNING *"
    )
    rjson = r.json()
    now = datetime.now()
    expires = now + timedelta(seconds=rjson["expires_in"])
    refresh_expires = now + timedelta(seconds=rjson["refresh_expires_in"])
    rows = execute(sql, [username, rjson["access_token"], rjson["refresh_token"], expires, refresh_expires])
    return rows[0]


def users(refresh_token: str) -> list[dict]:
    r = requests.post(
        "http://keycloak:8080/realms/n4brain/protocol/openid-connect/token",
        data={
            "client_id": "n4b_auth",
            "grant_type": "refresh_token",
            "refresh_token": refresh_token,
        },
    )
    r.raise_for_status()
    access_token = r.json()["access_token"]
    r = requests.get(
        f"http://keycloak:8080/admin/realms/n4brain/users",
        headers={"Authorization": f"Bearer {access_token}"},
    )
    r.raise_for_status()
    return r.json()
