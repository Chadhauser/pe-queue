#!/bin/bash
# 552 (Tue 10 Nov 2026, 15:00). RECOVERY. 550 ran three fair-price builds in parallel on a 7.9 GB box with no swap; the OOM killer took
# PostgreSQL at 13:44 UTC and everything has been down since. This job: (1) PostgreSQL back; (2) 4 GB swap so an OOM can never take the
# database again; (3) recorders restarted (they were spinning on closed cursors); (4) the other sports mapped ONE AT A TIME with work_mem
# 128 MB; (5) 551's database steps re-run (desk cells, desk start); (6) tape archive at 5 days so disk recovers (11 GB free).
set -o pipefail
export PYTHONDONTWRITEBYTECODE=1
echo "== 1. postgres =="; systemctl restart postgresql || pg_ctlcluster 18 main restart; sleep 8; systemctl is-active postgresql; pg_isready
echo "== 2. swap =="
if ! swapon --show | grep -q swap; then fallocate -l 4G /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile && grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab; fi
swapon --show; free -g | head -2
# postgres memory guard: cap per-connection work and shared buffers so a runaway read spills to disk instead of killing the server
CONF=$(sudo -u postgres psql -At -c "show config_file" 2>/dev/null || psql -At -c "show config_file" "$(python3 -c "import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds; print(creds.pg_local())")")
grep -q '^# 552' "$CONF" || printf "\n# 552 memory guard\nwork_mem = '64MB'\nshared_buffers = '1536MB'\nmaintenance_work_mem = '256MB'\nmax_parallel_workers_per_gather = 1\n" >> "$CONF"
systemctl restart postgresql; sleep 6; pg_isready
echo "== 3. recorders =="
pkill -9 -f liq_recorder.py; pkill -9 -f stream_client.py; pkill -9 -f xx_recorder; pkill -9 -f ip_recorder; pkill -f bookie_v2.py; pkill -f sports_team.py; pkill -f desk.py; sleep 3
nohup /root/pe-sports/team/run_team.sh >/dev/null 2>&1 & disown
sleep 120
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor()
for t,col in [('liq_sample','ts'),('stream_ticks','ts_recv'),('xx_tape','ts'),('ip_tape','ts')]:
    c.execute(f'select count(*), max("{col}") from "{t}" where "{col}">now()-interval \'2 minutes\''); print("LOCAL",t,"last 2 min:",c.fetchone())
PY
pgrep -fa 'liq_recorder|stream_client|xx_recorder|ip_recorder|bookie_v2|sports_team' | cut -c1-70
echo "== 4. engine: one sport at a time, work_mem 128MB =="
cd /root/pe-sports/team && sed -i "s/SET work_mem='512MB'/SET work_mem='128MB'/" fairprice_v0.py && python3 -m py_compile fairprice_v0.py
pkill -f fairprice_v0.py; sleep 2
for S in $(python3 -c "
import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor()
c.execute(\"select distinct sport from bf_hist_other where sport<>'Soccer' except select distinct sport from fair_price_calib where sport<>'Soccer'\"); print(' '.join(s.replace(' ','_') for (s,) in c.fetchall()))"); do
  N="${S//_/ }"; echo "-- $N $(date -u +%H:%M) --"; FP_SPORTS="$N" timeout 6000 python3 fairprice_v0.py > "fairprice_v1_${S}.log" 2>&1; echo "exit $? RESULT lines $(grep -c ^RESULT fairprice_v1_${S}.log)"; grep -v ^RESULT "fairprice_v1_${S}.log" | tail -2; free -m | awk 'NR==2{print "  mem used MB",$3,"free",$4}'
done
python3 verifier_cells.py | head -3
echo "== 5. desk (551 database steps) =="
python3 /root/pe-sports/team/verifier_cells_inplay.py | head -5
grep -c CELL /root/pe-sports/desk/desk.py; pkill -f desk.py; sleep 2; nohup /root/pe-sports/desk/run_desk.sh >/dev/null 2>&1 & disown; sleep 30; echo "desk pids $(pgrep -f desk.py | wc -l)"; tail -2 /root/pe-sports/desk/desk.log
echo "== 6. disk =="
KEEP_DAYS=5 timeout 5000 python3 /root/pe-archive/archive_tape.py | tail -8; ( crontab -l | sed 's/KEEP_DAYS=10/KEEP_DAYS=5/' ) | crontab -; df -h / | tail -1
python3 - <<'PY'
import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor()
c.execute("select sport, count(*) from fair_price_passed group by 1 order by 2 desc"); print("PASSED cells by sport:",c.fetchall())
c.execute("select count(*) from fair_price_passed_inplay"); print("desk in-play cells:",c.fetchone()[0])
c.execute("select fill_kind, status, count(*), round(coalesce(sum(pnl),0)::numeric,2) from bookie_paper where version='v2' and ts>now()-interval '24 hours' group by 1,2 order by 1,2"); print("bot v2 last 24h:",c.fetchall())
PY
echo "552 done"
