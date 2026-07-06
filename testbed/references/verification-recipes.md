# Verification recipes

How the runtime checks in `scripts/verify.sh` work, for writing new checks or
debugging failing ones.

## Interactive-mode capture (pty)

mytop's per-interval metrics ("qps now", "Now in/out") only exist from the
SECOND refresh onward, and interactive mode needs a tty. Batch mode (`-b`)
does a single iteration, so it can never show them. Recipe:

```bash
docker compose exec -T runner-mysql bash -c \
  "TERM=xterm timeout 5 script -q -c 'perl /mytop-repo/mytop -h mysql84 -u mon -pmonpass -d mysql -s 1' /dev/null"
```

- `script -q -c ... /dev/null` allocates a pty inside the container (works
  under `exec -T`, no docker tty needed). `script` is in util-linux (baked
  into runner images).
- `timeout 5` with `-s 1` (1s refresh) yields ~4 refreshes — enough for deltas.
- `TERM=xterm` avoids "TERM environment variable not set".

## ANSI stripping

mytop emits color codes even when piped. Strip before grepping:

```bash
... | perl -pe 's/\e\[[0-9;?]*[a-zA-Z]//g; s/\r/\n/g'
```

(`col -b` is NOT available in the runner images — don't use it.)

## Generating query load

Live metrics read 0 on an idle server. `testbed.sh load [target]` runs ~15s of
background queries via the mysql client in runner-mysql. Start load BEFORE the
pty capture so the deltas have something to show.

## Before/after comparison against a git rev

To prove a fix changes behavior (not just that current code passes), run the
pre-fix version from git against the same server:

```bash
git -C <repo> show <rev>:mytop > /tmp/mytop-before
docker compose cp /tmp/mytop-before runner-mysql:/tmp/mytop-before
docker compose exec -T runner-mysql perl /tmp/mytop-before -h mysql84 -u mon -pmonpass -b
```

Compare grep counts between before and after (e.g. "qps now" 0 vs >=1;
"isn't numeric" 1 vs 0; exit codes). This is the strongest form of grounded
truth: the same harness shows the bug and its absence.

## Forcing the server-side-prepare edge case

DBD defaults to client-side (emulated) prepares, so syntax errors surface at
execute() and return undef. To exercise the prepare-time die path
(mytop reads the `[mytop]` group from ~/.my.cnf):

```bash
docker compose exec -T runner-mariadb bash -c \
  "printf '[mytop]\nmariadb_server_prepare=1\n' > /root/.my.cnf; \
   perl /mytop-repo/mytop -h mysql84-replica -u mon -pmonpass -b; echo exit=\$?; rm -f /root/.my.cnf"
```

Pre-fix v2.1 died (exit 2) here on MySQL 8.4 (SHOW SLAVE STATUS removed);
fixed code exits 0.

## Verifying replication state directly

```bash
docker compose --profile full exec -T mysql84-replica \
  mysql -uroot -prootpass -e "SHOW REPLICA STATUS\G" | \
  grep -E "Replica_IO_Running|Replica_SQL_Running|Source_Host|Seconds_Behind_Source"
```

MySQL 8.0.22+ uses Source_*/Replica_* column names; 8.4 removed
`SHOW SLAVE STATUS` entirely (ERROR 1064) — both facts are what fix #2 guards.
