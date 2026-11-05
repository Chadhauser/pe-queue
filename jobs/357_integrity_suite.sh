#!/bin/bash
# 357: INTEGRITY SUITE — the gate. One PASS/FAIL per component with the number, every morning 07:00 (cron) and on demand.
# Writes integrity_suite (run_at, check, status, value, detail) on the local DB and prints the table. The Watchman reads it.
set -o pipefail
mkdir -p /root/pe-data
cat > /root/pe-data/integrity_suite.py <<'PY'
import sys,os,shutil,datetime,subprocess,psycopg2
sys.path.insert(0,'/root/pe-queue/runner'); import creds
R=psycopg2.connect(creds.pg_railway(), sslmode='require'); R.autocommit=True; rc=R.cursor(); rc.execute("SET statement_timeout='120s'")
L=psycopg2.connect(creds.pg_local()); L.autocommit=True; lc=L.cursor()
lc.execute("CREATE TABLE IF NOT EXISTS integrity_suite (run_at TIMESTAMPTZ, chk TEXT, status TEXT, value TEXT, detail TEXT)")
out=[]
def chk(name, ok, value, detail=''): out.append((name,'PASS' if ok else 'FAIL',str(value),detail))
def q(cur,sql,default=None):
    try: cur.execute(sql); r=cur.fetchone(); return r[0] if r else default
    except Exception as e:
        try: cur.connection.rollback()
        except Exception: pass
        return default
# recorders writing (Railway)
for t,ts,mins in (('liq_sample','ts',15),('stream_ticks','ts_recv',5),('ip_tape','ts',30)):
    n=q(rc,f"select count(*) from {t} where {ts}>now()-interval '{mins} minutes'",-1); chk(f"recorder {t} rows last {mins}m", n and n>0, n)
n=q(rc,"select count(*) from player_liq where ts>now()-interval '6 hours'",-1); chk("player markets rows last 6h", n is not None and n>=0, n, "0 is acceptable outside football hours; FAIL only if the recorder is not running" if n==0 else "")
# retention / pruning
d=q(rc,"select n_tup_del from pg_stat_user_tables where relname='liq_sample'",0); lc.execute("select coalesce(max(value::bigint),0) from integrity_suite where chk='liq_sample n_tup_del'"); prev=lc.fetchone()[0] or 0
chk("liq_sample n_tup_del", True, d, "counter; compare with yesterday"); chk("tape pruned since last run", d<=prev, d-prev, "rows deleted on Railway since the previous run (0 expected once the pruner is off)")
trap=q(rc,"select count(*) from delete_trap",0); chk("delete trap events", True, trap, q(rc,"select left(string_agg(distinct coalesce(app,'')||'@'||coalesce(addr,''),' | '),200) from delete_trap",'') or '')
# archive freshness (local)
for t in ('liq_sample','ip_tape','stream_ticks'):
    age=q(lc,f"select extract(epoch from now()-wm)/60 from tape_archive_wm where tbl='{t}'",None); chk(f"archive {t} watermark age (min)", age is not None and age<180, None if age is None else round(age), "job 355 not run yet" if age is None else "")
# loader
done=q(lc,"select count(*) from bf_hist_months where status='DONE'",0); tot=q(lc,"select count(*) from bf_hist_months",0); chk("history months DONE/known", True, f"{done}/{tot}")
newest=q(lc,"select max(loaded_at) from bf_hist_other_files",None); chk("history loader advanced last 2h", newest is not None and (datetime.datetime.now(datetime.timezone.utc)-newest).total_seconds()<7200, str(newest)[:16])
dup=q(lc,"select count(*) from (select market_id, sel, ts from bf_hist_other group by 1,2,3 having count(*)>1 limit 1) x",-1); chk("bf_hist_other duplicates", dup==0, dup)
# engine
rows=q(rc,"select count(*) from goal_live_predictions where captured_at>now()-interval '24 hours'",0); fav=q(rc,"select count(fav_price) from goal_live_predictions where captured_at>now()-interval '24 hours'",0)
chk("engine predictions 24h", rows>0, rows); chk("engine real fav price fill 24h", rows==0 or fav/max(rows,1)>0.3, f"{fav}/{rows}")
al=q(rc,"select count(*) from goal_alerts where sent_at>now()-interval '24 hours' and alert_type<>'BOOT_TEST'",0); alr=q(rc,"select count(real_price) from goal_alerts where sent_at>now()-interval '24 hours' and alert_type<>'BOOT_TEST'",0)
chk("alerts with real price 24h", al==0 or alr/max(al,1)>=0.5, f"{alr}/{al}")
uns=q(rc,"select count(*) from goal_alerts where sent_at<now()-interval '36 hours' and sent_at>now()-interval '7 days' and coalesce(settled,false)=false and alert_type<>'BOOT_TEST'",0); chk("alerts unsettled >36h (7d)", uns==0, uns)
# heartbeats
for t in ('liq_heartbeat','stream_heartbeat','player_heartbeat','xx_heartbeat'):
    age=q(rc,f"select extract(epoch from now()-max(last_seen))/60 from {t}",None); chk(f"heartbeat {t} (min)", age is not None and age<15, None if age is None else round(age))
# box
free=shutil.disk_usage('/').free/1e9; chk("box disk free GB", free>25, round(free,1))
sz=q(lc,"select pg_database_size(current_database())/1e9",0); chk("local DB size GB", sz<110, round(sz,1))
rsz=q(rc,"select pg_database_size(current_database())/1e9",0); chk("railway DB size GB", True, round(rsz,1))
for proc in ('pe-hist/loader.py','liq_recorder.py','stream_client.py','ip_recorder.py','keepalive_preoff_scalp.sh'):
    r=subprocess.run(['pgrep','-f',proc],capture_output=True); chk(f"process {proc}", r.returncode==0, 'up' if r.returncode==0 else 'down')
now=datetime.datetime.now(datetime.timezone.utc)
for n,s,v,d in out: lc.execute("INSERT INTO integrity_suite VALUES (%s,%s,%s,%s,%s)",(now,n,s,v,d))
fails=[o for o in out if o[1]=='FAIL']
print(f"INTEGRITY {now:%Y-%m-%d %H:%M}Z: {len(out)-len(fails)} PASS, {len(fails)} FAIL")
for n,s,v,d in out: print(f"  {s:4s} {n:42s} {v:>12s}  {d}")
PY
python3 -m py_compile /root/pe-data/integrity_suite.py || exit 1
( crontab -l 2>/dev/null | grep -v integrity_suite; echo "0 7 * * * cd /root/pe-data && python3 integrity_suite.py >> integrity.log 2>&1" ) | crontab -
cd /root/pe-data && python3 integrity_suite.py
