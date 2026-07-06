#!/usr/bin/env bash
# db-testbed wrapper: up [core|full] | verify | status | shell <svc> | load [target]
#                     | down | destroy | destroy-all
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$HERE/../docker"
COMPOSE=(docker compose -f "$DOCKER_DIR/compose.yml")

cmd="${1:-status}"
case "$cmd" in
  up)
    tier="${2:-core}"
    args=(up -d --wait --build)
    if [ "$tier" = "full" ] || [ "$tier" = "replication" ]; then
      "${COMPOSE[@]}" --profile "$tier" "${args[@]}"
      bash "$HERE/setup-replica.sh"
    else
      "${COMPOSE[@]}" "${args[@]}"
    fi
    echo "testbed up ($tier)."
    ;;
  verify)
    bash "$HERE/verify.sh"
    ;;
  status)
    "${COMPOSE[@]}" --profile full ps --format 'table {{.Name}}\t{{.Status}}'
    ;;
  shell)
    svc="${2:?usage: testbed.sh shell <service>}"
    "${COMPOSE[@]}" exec "$svc" bash
    ;;
  load)
    # ~15s of query load against a target (default mysql84) for live-metric tests
    target="${2:-mysql84}"
    "${COMPOSE[@]}" exec -T runner-mysql bash -c \
      "for i in \$(seq 1 400); do mysql -h $target -umon -pmonpass -e 'SELECT SLEEP(0.01); SELECT 1;' mysql >/dev/null 2>&1; done" &
    echo "load running against $target (pid $!)"
    ;;
  down)
    "${COMPOSE[@]}" --profile full down
    echo "stopped (volumes + images kept; 'up' restarts fast)."
    ;;
  destroy)
    "${COMPOSE[@]}" --profile full down -v --remove-orphans
    echo "destroyed containers, volumes, network (runner images kept)."
    ;;
  destroy-all)
    "${COMPOSE[@]}" --profile full down -v --remove-orphans --rmi local
    echo "destroyed everything including built runner images."
    ;;
  *)
    echo "usage: testbed.sh up [core|full] | verify | status | shell <svc> | load [target] | down | destroy | destroy-all" >&2
    exit 2
    ;;
esac
