curl -L -X POST 'http://localhost:8083/realms/auth2/protocol/openid-connect/token' \
--data-urlencode 'client_id=auth2' \
--data-urlencode 'grant_type=password' \
--data-urlencode 'scope=openid' \
--data-urlencode username=$1 \
--data-urlencode password=$1
