#!/bin/bash
# 282: (a) DAILY SHELF — one row per line per day in table shelf_daily (line, trades, settled, won, pnl per £10, since-live-key),
#     written 06:40 so a morning or Friday read is a single query. (b) Grader output collapsed to the nearest-minute cell only.
set -e
cat > /root/pe-push/shelf_daily.py <<'PY'
import sys,psycopg2,datetime; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require'); c.autocommit=True; k=c.cursor()
k.execute("CREATE TABLE IF NOT EXISTS shelf_daily (d DATE, line TEXT, trades INT, settled INT, won INT, pnl NUMERIC, note TEXT, PRIMARY KEY (d,line))")
LIVE="'2026-10-27 09:37'"
Q={ 'late_over_paper':f"SELECT count(*),count(pnl_per_10),count(*) FILTER (WHERE pnl_per_10>0),round(sum(pnl_per_10),2) FROM late_over_paper WHERE entry_ts>{LIVE}",
    'xg_paper':f"SELECT count(*),count(pnl_per_10),count(*) FILTER (WHERE pnl_per_10>0),round(sum(pnl_per_10),2) FROM xg_paper WHERE entry_ts>{LIVE}",
    's9_paper':f"SELECT count(*),count(pnl_per_10),count(*) FILTER (WHERE pnl_per_10>0),round(sum(pnl_per_10),2) FROM s9_paper WHERE entry_ts>{LIVE} AND coalesce(exit_reason,'') NOT LIKE 'VOID%'",
    'ltd_probe':f"SELECT count(*),count(pnl_per_10),count(*) FILTER (WHERE pnl_per_10>0),round(sum(pnl_per_10),2) FROM ltd_inplay_paper WHERE entry_ts>{LIVE}",
    'cricket_fav':"SELECT count(*),count(*) FILTER (WHERE exit_ts IS NOT NULL),0,NULL FROM cricket_fav_paper",
    'user_trades':"SELECT count(*),count(live_pnl_hedge10),count(*) FILTER (WHERE live_pnl_hedge10>0),round(sum(live_pnl_hedge10),2) FROM user_trades"}
for line,sql in Q.items():
    try: k.execute(sql); n,s,w,p=k.fetchone()
    except Exception as e: c.rollback(); n,s,w,p=None,None,None,None; print(line,"ERR",str(e)[:80])
    k.execute("INSERT INTO shelf_daily VALUES (current_date,%s,%s,%s,%s,%s,'since live key') ON CONFLICT (d,line) DO UPDATE SET trades=EXCLUDED.trades, settled=EXCLUDED.settled, won=EXCLUDED.won, pnl=EXCLUDED.pnl",(line,n,s,w,p))
k.execute("""SELECT book, count(*), count(*) FILTER (WHERE exit_reason='CAPTURED'), round(sum(pnl_per_10)*10/CASE book WHEN '50through' THEN 50 WHEN '200through' THEN 200 ELSE 10 END,2) FROM racing_mm_stream WHERE exit_reason IS NOT NULL GROUP BY 1""")
for book,n,cap,p in k.fetchall():
    k.execute("INSERT INTO shelf_daily VALUES (current_date,%s,%s,%s,%s,%s,'per £10 equiv') ON CONFLICT (d,line) DO UPDATE SET trades=EXCLUDED.trades, settled=EXCLUDED.settled, won=EXCLUDED.won, pnl=EXCLUDED.pnl",('mm_'+book,n,n,cap,p))
k.execute("SELECT line, trades, settled, won, pnl FROM shelf_daily WHERE d=current_date ORDER BY line"); [print(r) for r in k.fetchall()]
PY
python3 -m py_compile /root/pe-push/shelf_daily.py && python3 /root/pe-push/shelf_daily.py
( crontab -l 2>/dev/null | grep -v "pe-push/shelf_daily.py" ; echo "40 6 * * * python3 /root/pe-push/shelf_daily.py >> /root/pe-push/shelf_daily.log 2>&1" ) | crontab -
python3 - <<'PY'
p='/root/pe-user/grade.py'; s=open(p).read()
old="AND band=%s AND minute BETWEEN %s AND %s AND n>=50 ORDER BY fam, exit\"\"\",(fams,selkey,side,b,m5-5,m5+5))"
new="AND band=%s AND minute=%s AND n>=50 ORDER BY fam, exit\"\"\",(fams,selkey,side,b,m5))"
assert old in s; s=s.replace(old,new,1); open(p,'w').write(s); print("grader: nearest-minute cell only")
PY
python3 -m py_compile /root/pe-user/grade.py && python3 /root/pe-user/grade.py regrade | head -8
