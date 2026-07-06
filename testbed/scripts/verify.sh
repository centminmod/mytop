#!/usr/bin/env bash
# Grounded-truth regression suite for mytop against the live testbed.
# Auto-detects which services are running and skips checks for absent ones.
# Exit 0 = every executed check passed.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE=(docker compose -f "$HERE/../docker/compose.yml" --profile full)
MYTOP=/mytop-repo/mytop
STRIP='perl -pe "s/\e\[[0-9;?]*[a-zA-Z]//g; s/\r/\n/g"'

PASS=0; FAIL=0; SKIP=0
ok()   { echo "  PASS  $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL  $1"; FAIL=$((FAIL+1)); }
skip() { echo "  skip  $1"; SKIP=$((SKIP+1)); }
up()   { "${COMPOSE[@]}" ps --services --status running 2>/dev/null | grep -qx "$1"; }

xr()  { "${COMPOSE[@]}" exec -T runner-mysql bash -c "$1"; }    # mysql-driver runner
xrm() { "${COMPOSE[@]}" exec -T runner-mariadb bash -c "$1"; }  # mariadb-driver runner

echo "== db-testbed verify =="

## --- source-level tripwires (host-side, no containers needed) -------------
REPO="$HERE/../.."
grep -q '\$last_time = \$now_time;' "$REPO/mytop" \
  && ok "source: \$last_time assignment present (dead-metrics fix)" \
  || bad "source: \$last_time assignment MISSING - live metrics will be dead"
grep -q "eq 'K'" "$REPO/mytop" \
  && ok "source: K handler uses exact match" \
  || bad "source: K handler regressed to unanchored regex"
grep -q 'db_release > 10' "$REPO/mytop" \
  && ok "source: MariaDB version gate compares ints (10.10/10.11 fix)" \
  || bad "source: MariaDB version gate regressed to float compare"

## --- syntax + batch runs ---------------------------------------------------
if up runner-mysql; then
  xr "perl -c $MYTOP" >/dev/null 2>&1 \
    && ok "perl -c (DBD::mysql runner)" || bad "perl -c (DBD::mysql runner)"
  for t in mysql84 mysql84-replica mariadb11 mariadb1011 mariadb123; do
    if up "$t"; then
      xr "perl $MYTOP -h $t -u mon -pmonpass -d mysql -b >/dev/null 2>&1" \
        && ok "batch run vs $t exits 0" || bad "batch run vs $t"
    else skip "batch run vs $t (service not up)"; fi
  done

  # fix #8: no numeric warning on MySQL 8.4
  if up mysql84; then
    n=$(xr "perl $MYTOP -h mysql84 -u mon -pmonpass -d mysql -b 2>&1 | grep -c \"isn't numeric\"")
    [ "${n:-1}" -eq 0 ] && ok "no 'isn't numeric' warning (version parse fix)" \
                        || bad "'isn't numeric' warning returned"
  fi

  # MariaDB 12.x: first major past the "10.6+" gate fix — the version string
  # (e.g. 12.3.x-MariaDB) must parse clean and take the modern-variables path
  if up mariadb123; then
    n=$(xr "perl $MYTOP -h mariadb123 -u mon -pmonpass -d mysql -b 2>&1 | grep -c \"isn't numeric\"")
    [ "${n:-1}" -eq 0 ] && ok "no 'isn't numeric' warning on MariaDB 12.3" \
                        || bad "'isn't numeric' warning on MariaDB 12.3"
  else skip "MariaDB 12.3 version-parse check (service not up)"; fi

  # fix #5: localhost + non-default port warns
  w=$(xr "perl $MYTOP -h localhost -P 3307 -u mon -pmonpass -b 2>&1 | grep -c 'ignored for host'" || true)
  [ "${w:-0}" -ge 1 ] && ok "localhost -P warning fires" || bad "localhost -P warning missing"

  # fix #1: live per-interval metrics render under load (needs pty; 2+ ticks)
  if up mysql84; then
    "$HERE/testbed.sh" load mysql84 >/dev/null
    out=$(xr "TERM=xterm timeout 5 script -q -c 'perl $MYTOP -h mysql84 -u mon -pmonpass -d mysql -s 1' /dev/null 2>&1 | $STRIP | grep -c 'qps now'" || true)
    [ "${out:-0}" -ge 1 ] && ok "live 'qps now' metrics render (\$last_time fix)" \
                          || bad "live metrics blank - \$last_time regression"
  fi

  # fix #2: replication line renders on 8.4 replica (modern columns)
  if up mysql84-replica; then
    r=$(xr "perl $MYTOP -h mysql84-replica -u mon -pmonpass -d mysql -b 2>&1 | $STRIP | grep -c 'Replication IO:Yes'" || true)
    [ "${r:-0}" -ge 1 ] && ok "replication line renders on MySQL 8.4 replica" \
                        || bad "replication line missing on 8.4 replica"
  else skip "replication display (replica not up)"; fi
else
  skip "all runner-mysql checks (runner not up)"
fi

## --- DBD::MariaDB fallback driver path (fix #7) ----------------------------
if up runner-mariadb; then
  xrm "perl -c $MYTOP" >/dev/null 2>&1 \
    && ok "perl -c (DBD::MariaDB-only runner)" || bad "perl -c (DBD::MariaDB runner)"
  if up mariadb11; then
    xrm "perl $MYTOP -h mariadb11 -u mon -pmonpass -d mysql -b >/dev/null 2>&1" \
      && ok "DBD::MariaDB fallback driver vs mariadb11" \
      || bad "DBD::MariaDB fallback driver vs mariadb11"
  fi
  if up mariadb123; then
    xrm "perl $MYTOP -h mariadb123 -u mon -pmonpass -d mysql -b >/dev/null 2>&1" \
      && ok "DBD::MariaDB fallback driver vs mariadb123" \
      || bad "DBD::MariaDB fallback driver vs mariadb123"
  fi
else
  skip "DBD::MariaDB fallback checks (runner-mariadb not up; use 'up full')"
fi

echo "== result: $PASS passed, $FAIL failed, $SKIP skipped =="
[ "$FAIL" -eq 0 ]
