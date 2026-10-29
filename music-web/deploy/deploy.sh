#!/bin/bash
# Pubblica music.fabiodalez.it sul cPanel (alias SSH fabiodalez.it).
#   ./deploy.sh          build dell'interfaccia, test del server, upload, riavvio
# Dati (~/music-app/data), venv e lswsgi sul server non vengono toccati.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/.."
HOST=fabiodalez.it
APP=music-app
WEB=music.fabiodalez.it

echo "== test del server"
(cd "$ROOT/server" && .venv/bin/python -m unittest -q tests.test_server)

echo "== build dell'interfaccia"
(cd "$ROOT/ui" && npm run --silent build)

echo "== upload del server"
rsync -rlz --delete --exclude '__pycache__' --exclude '.venv' --exclude '.dev' --exclude 'tests' --exclude 'devserver.py' \
  "$ROOT/server/musicweb" "$ROOT/server/passenger_wsgi.py" "$ROOT/server/manage.py" "$HOST:$APP/"

echo "== upload dell'interfaccia"
rsync -rlz --delete --exclude '.htaccess' --exclude '.well-known' --exclude 'error_log' "$ROOT/ui/dist/" "$HOST:$WEB/"
rsync -z "$HERE/htaccess" "$HOST:$WEB/.htaccess"

echo "== riavvio"
ssh "$HOST" "touch $APP/tmp/restart.txt; pkill -u \$(whoami) -f '[l]swsgi' || true"
sleep 2
code=$(curl -s -o /dev/null -w '%{http_code}' "https://$WEB/api/session")
page=$(curl -s -o /dev/null -w '%{http_code}' "https://$WEB/library")
echo "api/session -> $code (atteso 401), /library -> $page (atteso 200)"
[ "$code" = 401 ] && [ "$page" = 200 ]
