#!/bin/bash
set -e
set -x

psql -v ON_ERROR_STOP=1 <<-EOSQL
DO \$\$
  DECLARE q TEXT;
BEGIN
  q := 'CREATE USER ${KEYCLOAK_DB_USER} WITH PASSWORD ''' || pg_read_file('/run/secrets/keycloak-db-password') || '''';
  EXECUTE q;
  q := 'CREATE USER n4b_auth_authenticator WITH PASSWORD ''' || pg_read_file('/run/secrets/n4b_auth_authenticator-password') || '''';
  EXECUTE q;
END \$\$;

CREATE DATABASE ${KEYCLOAK_DB} WITH OWNER ${KEYCLOAK_DB_USER};
CREATE DATABASE ${N4B_AUTH_DB};
EOSQL

psql -v ON_ERROR_STOP=1 --dbname ${KEYCLOAK_DB} <<-EOSQL
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${KEYCLOAK_DB};
EOSQL

# CREATE OR REPLACE FUNCTION api.rest()
#  RETURNS text
# AS \$\$
#     import requests, json
#     try:
#         r = requests.get("https://api.restful-api.dev/objects")
#     except Exception as e:
#         return e
#     else:
#         return r.content
# \$\$ LANGUAGE plpython3u;

# select routine_name from information_schema.routines where routine_schema='api';

psql -v ON_ERROR_STOP=1 --dbname ${N4B_AUTH_DB} <<-EOSQL
CREATE EXTENSION plpython3u;
CREATE EXTENSION jsonb_plpython3u;
CREATE SCHEMA api;


CREATE TABLE api."user" (username TEXT PRIMARY KEY,
                         email TEXT,
                         email_verified BOOLEAN,
                         first_name TEXT,
                         last_name TEXT,
                         enabled BOOLEAN,
                         totp BOOLEAN
                         );

CREATE TABLE api."role" (name TEXT PRIMARY KEY);
CREATE TABLE api."grant" (
    role_name TEXT REFERENCES api."role"(name),
    grantee TEXT REFERENCES api."role" (name),
    PRIMARY KEY (role_name, grantee));

CREATE TABLE api.login_session (username TEXT PRIMARY KEY REFERENCES api."user"(username), 
                                access_token TEXT NOT NULL,
                                refresh_token TEXT NOT NULL,
                                expires TIMESTAMP,
                                refresh_expires TIMESTAMP);


CREATE OR REPLACE FUNCTION api.login(username TEXT, password TEXT)
    RETURNS JSONB
    TRANSFORM FOR TYPE JSONB
AS \$\$
    import importlib
    import n4b_auth.util
    import n4b_auth.rpc
    importlib.reload(n4b_auth.util)
    importlib.reload(n4b_auth.rpc)
    return n4b_auth.rpc.login(username, password)
\$\$ LANGUAGE plpython3u SECURITY DEFINER;


CREATE OR REPLACE FUNCTION update_user() RETURNS trigger AS \$\$
    import importlib
    import n4b_auth.util
    importlib.reload(n4b_auth.util)
    return n4b_auth.util.update_user(TD)
\$\$ LANGUAGE plpython3u;

-- CREATE TRIGGER update_user BEFORE INSERT OR UPDATE OR DELETE ON api."user"
--    FOR EACH ROW EXECUTE FUNCTION update_user();


CREATE OR REPLACE FUNCTION update_role() RETURNS trigger AS \$\$
    import importlib
    import n4b_auth.util
    importlib.reload(n4b_auth.util)
    return n4b_auth.util.update_role(TD)
\$\$ LANGUAGE plpython3u;

-- CREATE TRIGGER update_role BEFORE INSERT OR UPDATE OR DELETE ON api."role"
--    FOR EACH ROW EXECUTE FUNCTION update_role();

INSERT INTO api."user" (username, email, email_verified, first_name, last_name, enabled, totp)
VALUES ('n4b_auth_admin', 'admin@n4brain.fr', TRUE, 'Admin', 'N4Brain', True, False);

CREATE ROLE n4b_auth_anonymous NOLOGIN;
GRANT n4b_auth_anonymous TO n4b_auth_authenticator;
GRANT USAGE ON SCHEMA api TO n4b_auth_anonymous;
GRANT EXECUTE ON FUNCTION api.login TO n4b_auth_anonymous;

CREATE ROLE n4b_auth_admin NOLOGIN;
GRANT n4b_auth_admin TO n4b_auth_authenticator;
GRANT n4b_auth_anonymous TO n4b_auth_admin;
GRANT USAGE ON SCHEMA api TO n4b_auth_admin;
GRANT ALL ON ALL TABLES IN SCHEMA api TO n4b_auth_admin;

-- Prevent api functions to be executable by n4b_auth_anonymous
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA api FROM PUBLIC;
EOSQL
