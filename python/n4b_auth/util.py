import plpy
import datetime

import requests

keycloak_realm = "n4brain"
keycloak_auth_client_uuid = "d2c83169-f622-4860-88eb-d81cb207b1b8"
token_url = (
    f"http://keycloak:8080/realms/{keycloak_realm}/protocol/openid-connect/token"
)
keycloak_auth_url = (
    f"http://keycloak:8080/admin/realms/{keycloak_realm}/clients/{keycloak_auth_client_uuid}"
)

python_type_to_sql = {
    str: "text",
    int: "integer",
    float: "real",
    bool: "boolean",
    datetime.datetime: "timestamp",
    datetime.date: "date",
    datetime.time: "time",
    datetime.timedelta: "interval",
}

python_value_to_sql = {
    datetime.datetime: lambda x: x.isoformat(),
    datetime.date: lambda x: x.isoformat(),
    datetime.time: lambda x: x.isoformat(),
}


def prepare(sql, data=None):
    if data is None:
        return plpy.prepare(sql), None
    else:
        sql_types = [python_type_to_sql[type(i)] for i in data]
        converted_data = [
            python_value_to_sql.get(type(i), lambda x: x)(i) for i in data
        ]
        return plpy.prepare(sql, sql_types), converted_data


def iter_execute(sql, data=[], limit=0):
    plan, converted_data = prepare(sql, data)
    yield from plpy.cursor(plan, converted_data, limit)


def execute(sql, data=[], limit=0):
    plan, converted_data = prepare(sql, data)
    return plan.execute(converted_data, limit)


def keycloak_auth(method: str, route: str, data: dict | None = None) -> dict | None:
    refresh_token = execute(
        "SELECT refresh_token FROM api.login_session WHERE username=current_user;"
    )[0]["refresh_token"]
    r = requests.post(
        token_url,
        data={
            "client_id": "n4b_auth",
            "grant_type": "refresh_token",
            "refresh_token": refresh_token,
        },
    )
    try:
        r.raise_for_status()
    except Exception:
        plpy.log("ERROR getting token from keycloak", detail=str(r.json()))
        raise
    access_token = r.json()["access_token"]
    r = requests.request(
        method,
        f"{keycloak_auth_url}/{route}",
        headers={"Authorization": f"Bearer {access_token}"},
    )
    try:
        r.raise_for_status()
    except Exception:
        plpy.log("ERROR calling keycloak API", detail=str(r.json()))
        raise
    return r.json()


def user_to_keycloak(slq_user):
    return dict(
        username= slq_user["username"],
        fisrtName= slq_user["first_name"],
        lastName= slq_user["last_name"],
        email=slq_user["email"],
        enabled=slq_user["enabled"],
        totp=slq_user["totp"],
    )

def update_user(TD):
    if TD["event"] == "INSERT":
        plpy.log("INSERT USER !!!!", detail=user_to_keycloak(TD["new"]))
        keycloak_auth("post", "users", user_to_keycloak(TD["new"]))
    elif TD["event"] == "DELETE":
        plpy.log("DELETE USER !!!!", detail=TD['old']['username'])
        keycloak_auth("delete", f"users/{TD['old']['username']}")
    elif TD["event"] == "UPDATE":
        plpy.log("UPDATE USER !!!!", detail=user_to_keycloak(TD["new"]))
        keycloak_auth("put", f"users/{TD['old']['name']}", {"name": TD["new"]["name"]})


def update_role(TD):
    plpy.log("UPDATE_ROLE !!!!", detail=str(TD))
    if TD["event"] == "INSERT":
        keycloak_auth("post", "roles", {"name": TD["new"]["name"]})
    elif TD["event"] == "DELETE":
        keycloak_auth("delete", f"roles/{TD['old']['name']}")
    elif TD["event"] == "UPDATE":
        keycloak_auth("put", f"roles/{TD['old']['name']}", {"name": TD["new"]["name"]})
