#!/bin/bash
# 615 (Mon 16 Nov 2026, 16:25). Peter: "run all jobs, it's to make money". Heavy work waits for the upgraded server (18 GB): exits 75 (retried
# every cycle, costs seconds) until memory >= 14 GB and the disk has >= 100 GB free, then:
#  1. In-play fair-price engine (fairprice_inplay.py, H1b) on every sport with results, then the Verifier -> in-play cells for the bot's paper
#  2. Restore the large dropped tables from their dumps (bf_price_log, bf_racing_log, bf_tennis_log, finder logs)
#  3. History loader guard back to 20 GB so it fills owned months freely
#  4. Reading for the stream recorder: subscription code, so cricket, golf and American football can be added next
MEM=$(free -g | awk '/Mem:/{print $2}'); FREE=$(df -BG --output=avail / | tail -1 | tr -dc 0-9)
[ "$MEM" -ge 14 ] && [ "$FREE" -ge 100 ] || { echo "waiting for the upgrade (memory ${MEM} GB, free ${FREE} GB)"; exit 75; }
set -o pipefail
R=/root/pe-queue/reports/after_upgrade.md; cd /root/pe-sports/team
{ echo "# After-upgrade money jobs $(date -u '+%F %H:%M') UTC (job 615)"; echo
echo "## 1. In-play fair-price engine"; echo '```'
for S in Soccer Tennis Cricket "Horse Racing" "Greyhound Racing"; do FP_SPORTS="$S" timeout 7200 nice -n 10 python3 fairprice_inplay.py > "fairprice_inplay_${S// /_}.log" 2>&1; echo "$S exit $? RESULT lines $(grep -c ^RESULT fairprice_inplay_${S// /_}.log)"; done
python3 verifier_cells.py 2>&1 | grep -v Deprecation | tail -40
echo '```'
echo "## 2. Restore large dropped tables"; echo '```'
DSN=$(python3 -c "import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds; print(creds.pg_local())")
for f in /root/pe-archive/tables/*.sql.zst; do t=$(basename $f .sql.zst | sed 's/^public\.//'); psql "$DSN" -At -c "select to_regclass('public.$t')" | grep -q "$t" && continue; zstdcat "$f" | psql -q "$DSN" >/dev/null 2>&1 && echo "restored $t: $(psql "$DSN" -At -c "select count(*) from $t") rows" || echo "$t: restore failed"; done
echo '```'
echo "## 3. Loader guard"; sed -i "s/free<10e9: print('WAITING: box disk under 10 GB free')/free<20e9: print('WAITING: box disk under 20 GB free')/" /root/pe-hist/loader_core.py; grep -n "disk under" /root/pe-hist/loader_core.py | cut -c1-120
echo "## 4. Stream recorder subscription"; echo '```'; grep -n -i "eventType\|event_type\|EVENT_TYPES\|marketTypes\|market_types\|countries\|subscribe\|def " /root/pe-stream/stream_client.py | head -40 | cut -c1-200; echo '```'
df -h / | tail -1; free -g | head -2
} > $R 2>&1
cd /root/pe-queue && git add reports/after_upgrade.md && git commit -qm "615: after-upgrade money jobs" && git pull -q --no-rebase --no-edit && git push -q && echo pushed
echo "615 done"
