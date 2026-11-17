#!/bin/bash
# 633 (Tue 17 Nov 2026, 07:10). Read only. 632: the goal signal fired at 00:47 and 00:49 today with no write error, yet
# goal_advisories/goal_poisson are empty after 15 Nov 00:19. Show the code that counts "fired" and what it writes, and the
# primary keys behind the 9,300 "PRED WRITE FAIL duplicate key" lines. Report: reports/goal_fire_633.md
R=/root/pe-queue/reports/goal_fire_633.md; B=/root/pe-brain/repo/brain
{ echo "# 633 — $(date -u '+%F %H:%M') UTC"; echo '```'
grep -rnE "fired" $B/*.py | grep -v "^.*#" | head -20
F=$(grep -rlE "'fired'|\"fired\"|fired\s*\+=" $B/*.py | head -1); echo "== $F"
N=$(grep -nE "fired\s*\+=|\['fired'\]\s*\+=|fired=fired\+1" $F | head -1 | cut -d: -f1); echo "line $N"
[ -n "$N" ] && sed -n "$((N-60)),$((N+15))p" $F
echo "--- keys"
python3 - <<'PY'
import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor()
for t in ('goal_live_predictions','goal_advisories','goal_poisson','goal_alerts'):
    c.execute("SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid=%s::regclass AND contype IN ('p','u')",(t,)); print(t, c.fetchall())
    c.execute("SELECT column_name, column_default FROM information_schema.columns WHERE table_name=%s AND column_default IS NOT NULL",(t,)); print("  defaults", c.fetchall()[:4])
PY
echo '```'; } > $R 2>&1
cd /root/pe-queue && git add $R && git commit -qm "633: goal signal fire path" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
