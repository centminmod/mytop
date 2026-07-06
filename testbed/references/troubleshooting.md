# Troubleshooting — quirks learned the hard way (2026-07)

## Ubuntu 24.04 has no libdbd-mariadb-perl package
`apt install libdbd-mariadb-perl` fails on noble (checked main + universe on
arm64: "no installation candidate"). The runner-mariadb image builds
DBD::MariaDB via `cpanm --notest DBD::MariaDB` against `libmariadb-dev`
instead. First build takes ~2 min (compiles XS); afterwards it's a cached
layer. If the cpanm step fails, check /root/.cpanm/build.log inside the build.

## MySQL 8.4 authentication
DBD::mysql 4.x (Ubuntu's packaged version) can't do caching_sha2_password RSA
exchange over plain TCP. The compose command sets `--mysql-native-password=ON`
and initdb creates users `IDENTIFIED WITH mysql_native_password`. If you add a
MySQL 9.x service, note native password is REMOVED there — you'll need
DBD::mysql 5.x (build from CPAN) or TLS.

## MySQL 8.4 replication
- `SHOW SLAVE STATUS` / `CHANGE MASTER TO` are REMOVED (ERROR 1064), use
  `SHOW REPLICA STATUS` / `CHANGE REPLICATION SOURCE TO`.
- Status columns are Source_* / Replica_* / Seconds_Behind_Source.
- GTID auto-position (`SOURCE_AUTO_POSITION=1`) + binlog-from-birth on the
  primary means the initdb-created mon/repl users replicate to the replica —
  do NOT create users locally on the replica (read-only + errant-GTID risk).
- setup-replica.sh polls for the replicated mon user as its readiness signal.

## Healthcheck false positives
`mysqladmin ping` can succeed against the image's temporary init server
before the real server is up. The compose healthchecks use
`start_period: 25s` + retries to ride that out; `up --wait` blocks on healthy.
MariaDB images ship `healthcheck.sh --connect --innodb_initialized`, which
doesn't have this problem.

## Runner containers can't reach the repo
The repo is mounted read-only at /mytop-repo via a relative path in
compose.yml (`../..` from testbed/docker/). If the testbed directory is
moved to a different depth, fix that volume path and the REPO var in verify.sh.

## Term::ReadKey missing → mytop's BEGIN check exits before perl -c completes
mytop hard-exits from a BEGIN block listing missing modules. If verify's
`perl -c` fails, run it manually — the error names the missing module; fix
the runner Dockerfile rather than installing ad hoc (ad-hoc installs vanish
on `destroy`).

## Orphan / name-conflict errors on up
Everything is namespaced under compose project `mytop-testbed` with
`mytop-*` container names. If an old ad-hoc container squats on a name:
`docker rm -f $(docker ps -aq --filter name=mytop-)` then re-run up.
