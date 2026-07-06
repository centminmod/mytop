#!/usr/bin/env bash
# Wire mysql84-replica to mysql84 via GTID auto-position. Idempotent: safe to
# re-run; skips if replication is already running. Compose healthchecks
# guarantee both servers are up before this runs (testbed.sh up full --wait).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE=(docker compose -f "$HERE/../docker/compose.yml" --profile full)

running=$("${COMPOSE[@]}" exec -T mysql84-replica \
  mysql -uroot -prootpass -N -e "SELECT SERVICE_STATE FROM performance_schema.replication_connection_status LIMIT 1" 2>/dev/null || true)
if [ "$running" = "ON" ]; then
  echo "replica already replicating - skipping setup"
  exit 0
fi

"${COMPOSE[@]}" exec -T mysql84-replica mysql -uroot -prootpass -e "
  STOP REPLICA;
  CHANGE REPLICATION SOURCE TO
    SOURCE_HOST='mysql84', SOURCE_USER='repl', SOURCE_PASSWORD='replpass',
    SOURCE_AUTO_POSITION=1, GET_SOURCE_PUBLIC_KEY=1;
  START REPLICA;" 2>/dev/null

# Wait until the SQL thread is running and the replicated mon user has arrived
for i in $(seq 1 30); do
  state=$("${COMPOSE[@]}" exec -T mysql84-replica \
    mysql -uroot -prootpass -N -e "SHOW REPLICA STATUS" 2>/dev/null | head -1 || true)
  ok=$("${COMPOSE[@]}" exec -T mysql84-replica \
    mysql -uroot -prootpass -N -e "SELECT COUNT(*) FROM mysql.user WHERE user='mon'" 2>/dev/null || echo 0)
  if [ "${ok:-0}" -ge 1 ]; then
    echo "replica wired (mon user replicated)"
    exit 0
  fi
  sleep 2
done
echo "ERROR: replica did not reach replicating state with mon user" >&2
exit 1
