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

psql -v ON_ERROR_STOP=1 --dbname ${N4B_AUTH_DB} <<-EOSQL
CREATE EXTENSION plpython3u;
CREATE SCHEMA api;

CREATE ROLE n4b_auth_anonymous NOLOGIN;
GRANT n4b_auth_anonymous TO n4b_auth_authenticator;
GRANT USAGE ON SCHEMA api TO n4b_auth_anonymous;

CREATE ROLE n4b_auth_admin NOLOGIN;
GRANT n4b_auth_anonymous TO n4b_auth_admin;
GRANT ALL ON SCHEMA api TO n4b_auth_admin;
GRANT ALL ON ALL TABLES IN SCHEMA api TO n4b_auth_admin;

EOSQL
