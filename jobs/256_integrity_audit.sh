#!/bin/bash
# 256: DATA INTEGRITY AUDIT — the standing check every feed and every paper book should always have had. Runs now and nightly
# 06:30 (before the digest) + every 2 h in daytime. Each invariant is PASS/FAIL with the number; any FAIL is pushed. Table
# integrity_log keeps every run so a regression is visible the day it starts.
set -e
cat > /root/pe-push/integrity.py <<'PYFILE'
import sys, subprocess, psycopg2, datetime
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("CREATE TABLE IF NOT EXISTS integrity_log (ts TIMESTAMPTZ DEFAULT now(), chk TEXT, ok BOOLEAN, val TEXT)")
R=[]
def q(sql):
    try: cur.execute(sql); return cur.fetchone()[0]
    except Exception as e: return 'ERR '+str(e)[:80]
def chk(name,val,ok):
    R.append((name,bool(ok),str(val))); cur.execute("INSERT INTO integrity_log(chk,ok,val) VALUES (%s,%s,%s)",(name,bool(ok),str(val)))
def num(v): return isinstance(v,(int,float)) or (hasattr(v,'is_finite'))
# ---- feeds: fresh, carrying a book, book sane, cadence
feeds=[('stream football MO','stream_ticks',"sport='football' AND mkt='MO'",'ts_recv'),('stream racing WIN','stream_ticks',"sport='racing'",'ts_recv'),
       ('liq recorder','liq_sample','1=1','ts'),('xx matchbook','xx_tape',"exchange='matchbook'",'ts'),('xx smarkets','xx_tape',"exchange='smarkets'",'ts')]
for name,t,w,tc in feeds:
    n=q(f"SELECT count(*) FROM {t} WHERE {w} AND {tc}>now()-interval '1 hour'"); chk(f"{name}: rows last hour",n,num(n) and n>0)
    if num(n) and n>0:
        nb=q(f"SELECT round(100.0*sum(CASE WHEN back_px IS NOT NULL OR lay_px IS NOT NULL THEN 1 ELSE 0 END)/count(*),1) FROM {t} WHERE {w} AND {tc}>now()-interval '1 hour'"); chk(f"{name}: % rows with a book",nb,num(nb) and float(nb)>=50)
        inv=q(f"SELECT count(*) FROM {t} WHERE {w} AND {tc}>now()-interval '1 hour' AND lay_px<back_px"); chk(f"{name}: inverted books (lay<back)",inv,num(inv) and inv<=max(5,0.01*float(n)))
g=q("""WITH d AS (SELECT ts_recv-lag(ts_recv) OVER (PARTITION BY market_id,sel_id ORDER BY ts_recv) g FROM stream_ticks WHERE ts_recv>now()-interval '1 hour' AND sport='football')
       SELECT round(percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(epoch FROM g))::numeric,1) FROM d WHERE g IS NOT NULL"""); chk("stream: median secs between ticks (same runner)",g,num(g) and float(g)<30)
lat=q("SELECT round(avg(latency_ms)) FROM stream_ticks WHERE ts_recv>now()-interval '1 hour'"); chk("stream: mean latency ms",lat,num(lat) and float(lat)<500)
e=q("SELECT count(*) FROM espn_stats WHERE ts>now()-interval '6 hours'"); chk("espn rows last 6h (0 ok overnight)",e,True)
em=q("SELECT round(100.0*count(*) FILTER (WHERE market_id IS NOT NULL)/greatest(count(*),1),1) FROM espn_stats WHERE ts>now()-interval '24 hours'"); chk("espn: % rows matched to a market",em,num(em) and float(em)>=80)
xg=q("SELECT count(*) FROM ip_stats WHERE ts>now()-interval '24 hours' AND (xg_h IS NOT NULL OR xg_a IS NOT NULL)"); chk("api-football xG rows 24h",xg,True)
# ---- heartbeats
for hb in ['stream_heartbeat','liq_heartbeat','espn_heartbeat','stats_heartbeat','xx_heartbeat','xg_heartbeat','late_over_heartbeat','s9_heartbeat','racing_mm_stream_hb','job_heartbeat']:
    cur.execute("SELECT column_name FROM information_schema.columns WHERE table_name=%s AND data_type LIKE 'timestamp%%' ORDER BY ordinal_position LIMIT 1",(hb,)); c=cur.fetchone()
    if not c: chk(f"heartbeat {hb}",'missing table',False); continue
    a=q(f"SELECT round(EXTRACT(epoch FROM now()-max({c[0]}))/60) FROM {hb}"); chk(f"heartbeat {hb}: minutes old",a,num(a) and float(a)<=12)
# ---- paper books: settled on time, no impossible prices, pnl present when settled
books=[('late_over_paper','entry_ts','exit_ts','lay_px'),('xg_paper','entry_ts','exit_ts','lay_px'),('ltd_inplay_paper','entry_ts','exit_ts','lay_px'),('s9_paper','entry_ts','exit_ts','lay_px')]
for t,et,xt,px in books:
    u=q(f"SELECT count(*) FROM {t} WHERE {xt} IS NULL AND {et}<now()-interval '4 hours'"); chk(f"{t}: trades unsettled >4h",u,num(u) and u==0)
    b=q(f"SELECT count(*) FROM {t} WHERE {px} IS NOT NULL AND ({px}<1.01 OR {px}>1000)"); chk(f"{t}: impossible entry prices",b,num(b) and b==0)
    p=q(f"SELECT count(*) FROM {t} WHERE {xt} IS NOT NULL AND pnl_per_10 IS NULL AND coalesce(exit_reason,'')<>'UNKNOWN'"); chk(f"{t}: settled without pnl",p,num(p) and p==0)
    uk=q(f"SELECT round(100.0*count(*) FILTER (WHERE exit_reason='UNKNOWN')/greatest(count(*) FILTER (WHERE {xt} IS NOT NULL),1),1) FROM {t}"); chk(f"{t}: % UNKNOWN settlements",uk,num(uk) and float(uk)<=15)
# ---- queue
j=q("SELECT count(*) FROM job_results WHERE status='running' AND started<now()-interval '3 hours'"); chk("queue: jobs running >3h",j,num(j) and j==0)
jf=q("SELECT string_agg(job,', ') FROM job_results WHERE status='failed' AND finished>now()-interval '24 hours'"); chk("queue: failed jobs 24h",jf or 'none',True)
fails=[r for r in R if not r[1]]
print(f"integrity {datetime.datetime.utcnow():%Y-%m-%d %H:%M}: {len(R)} checks, {len(fails)} FAIL")
for n,ok,v in R: print(("FAIL " if not ok else "ok   ")+n+" = "+v)
if fails and '--push' in sys.argv:
    body="INTEGRITY "+str(len(fails))+" FAIL: "+"; ".join(f"{n}={v}" for n,ok,v in fails)[:400]
    subprocess.run(["python3","/root/pe-push/send_push.py",body],timeout=30)
PYFILE
python3 -m py_compile /root/pe-push/integrity.py
( crontab -l 2>/dev/null | grep -v "pe-push/integrity.py" ; echo "30 6,9,11,13,15,17,19,21,23 * * * python3 /root/pe-push/integrity.py --push >> /root/pe-push/integrity.log 2>&1" ) | crontab -
python3 /root/pe-push/integrity.py
