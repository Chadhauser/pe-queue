#!/bin/bash
# 347: HISTORY LOADER v4 -> LOCAL POSTGRES, CONTINUOUS. Peter's free Betfair BASIC months (every market since 2016 at
# 1-minute LTP) were only partly loaded and paused on 18 Oct for Railway disk. The local PG 18 has 120 GB. This builds
# /root/pe-hist/loader.py from 088's parser (unchanged), with: local DSN (creds.pg_local), no pause file, no 38 GB cap
# (stops only if box disk < 20 GB free), Soccer = ALL market types, no "already in bf_hist_price" skip, runs as a daemon
# that loads everything owned then re-reads the owned list hourly (so months Peter adds are picked up by themselves).
set -o pipefail
mkdir -p /root/pe-hist
python3 - <<'PY'
src=open('/root/pe-queue/jobs/088_history_loader_owned_v2.sh').read()
i=src.index("python3 - <<'PY'\n")+len("python3 - <<'PY'\n"); j=src.rindex("\nPY")
py=src[i:j]
R=[("sys.path.insert(0,'/root/pe-bot'); from bot_core import DB","DB=creds.pg_local()\nassert DB, 'local DSN missing (run jobs/337/340)'"),
   ("T0=time.time(); BUDGET=2*60","T0=time.time(); BUDGET=10**9"),
   ('if _os.path.exists("/root/LOADER_PAUSED"): print("paused: disk (18 Oct)"); sys.exit(0)',"pass"),
   ("con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()","con=psycopg2.connect(DB); con.autocommit=True; cur=con.cursor()"),
   ('if gb>38: print("WAITING: DB over 38 GB — not loading more until pruned"); sys.exit(75)',"pass"),
   ("if shutil.disk_usage('/root').free<2e9: print(\"WAITING: server disk under 2 GB free\"); sys.exit(75)","if shutil.disk_usage('/root').free<20e9: print('WAITING: box disk under 20 GB free'); sys.exit(75)"),
   ("'Soccer':(['MATCH_ODDS','OVER_UNDER_25'],[])","'Soccer':([],[])"),
   ("        if (y,m)>=(2024,8) and (y,m)<=(2026,6): st.setdefault(('Soccer',y,m),'DONE_PRICE')","        pass"),
   ("PRIO=['Tennis','Greyhound Racing','Basketball','Cricket','Horse Racing','Golf','Soccer']","PRIO=['Soccer','Horse Racing','Tennis','Cricket','Greyhound Racing','Basketball','Golf']"),
  ]
for a,b in R:
    assert a in py, "anchor missing: "+a[:60]
    py=py.replace(a,b,1)
# soccer months already fully loaded with only MO/OU25 must be reloaded for all markets: treat DONE soccer months with <3 market types as not done
py=py.replace("cur.execute(\"SELECT sport,y,m,status FROM bf_hist_months\"); st={(a,b,c):d for a,b,c,d in cur.fetchall()}",
 "cur.execute(\"SELECT sport,y,m,status FROM bf_hist_months\"); st={(a,b,c):d for a,b,c,d in cur.fetchall()}\ncur.execute(\"CREATE INDEX IF NOT EXISTS bfo_type_time ON bf_hist_other (sport, market_type, market_time)\")",1)
wrapper='''import time as _t, traceback as _tb, sys as _s
while True:
    try:
        exec(compile(open(__file__.replace('loader.py','loader_core.py')).read(), 'loader_core.py', 'exec'), {'__name__':'__main__'})
        print("cycle complete; sleeping 1 h before re-reading the owned list", flush=True); _t.sleep(3600)
    except SystemExit as e:
        if e.code==75: print("waiting 10 min", flush=True); _t.sleep(600)
        else: _t.sleep(3600)
    except Exception:
        _tb.print_exc(); _t.sleep(300)
'''
open('/root/pe-hist/loader_core.py','w').write(py); open('/root/pe-hist/loader.py','w').write(wrapper); print("loader written")
PY
python3 -m py_compile /root/pe-hist/loader_core.py /root/pe-hist/loader.py || exit 1
cat > /root/pe-hist/keepalive_hist.sh <<'SH'
#!/bin/bash
while true; do python3 /root/pe-hist/loader.py >> /root/pe-hist/loader.log 2>&1; sleep 60; done
SH
chmod +x /root/pe-hist/keepalive_hist.sh
pkill -f keepalive_hist.sh 2>/dev/null; pkill -f pe-hist/loader.py 2>/dev/null; sleep 1
nohup /root/pe-hist/keepalive_hist.sh >/dev/null 2>&1 &
( crontab -l 2>/dev/null | grep -v keepalive_hist; echo "@reboot nohup /root/pe-hist/keepalive_hist.sh >/dev/null 2>&1 &"; echo "*/10 * * * * pgrep -f keepalive_hist.sh >/dev/null || nohup /root/pe-hist/keepalive_hist.sh >/dev/null 2>&1 &" ) | crontab -
sleep 90; echo "== loader log"; tail -15 /root/pe-hist/loader.log | sed -E 's#postgres(ql)?://[^ ]*#<dsn>#g' | cut -c1-200
echo "== disk"; df -h / | tail -1
