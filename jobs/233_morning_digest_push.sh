#!/bin/bash
# 233: MORNING DIGEST TO PETER'S PHONE. His laptop (the only route for Claude to read Postgres) is off, so the server pushes the
# numbers itself: stream health, every paper book, the xG recorder, and the headline verdicts from last night's 226-230, as 3-4 web
# pushes (the only alert channel he uses). Also stored in digest_log so it is readable later. Installed as a daily 06:45 cron.
mkdir -p /root/pe-push && cat > /root/pe-push/digest.py <<'PYFILE'
import os, sys, json, re, datetime, psycopg2, psycopg2.extras
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
from pywebpush import webpush, WebPushException
for line in open('/root/pe-push/vapid.env'):
    if '=' in line and not line.startswith('#'):
        k,v=line.strip().split('=',1); os.environ.setdefault(k,v)
PRIV=os.environ["VAPID_PRIVATE"]; SUB=os.environ.get("VAPID_SUB","mailto:pe@edwardsbros.co.uk"); TOKEN="Y995gYX453GTN6emk1pHtFTTu788BHXM"
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
cur.execute("CREATE TABLE IF NOT EXISTS digest_log (ts TIMESTAMPTZ DEFAULT now(), part INT, body TEXT)")
def q(sql,args=()):
    try: cur.execute(sql,args); return cur.fetchall()
    except Exception as e: con.rollback() if not con.autocommit else None; return [{'err':str(e)[:80]}]
def one(sql,args=()):
    r=q(sql,args); return r[0] if r else {}
def push(title,body,tag):
    subs=q("SELECT id,endpoint,p256dh,auth FROM push_subscriptions WHERE active"); ok=0
    payload=json.dumps({'title':title,'body':body[:1800],'tag':tag,'url':f"/positions?k={TOKEN}"})
    for s in subs:
        try: webpush(subscription_info={'endpoint':s['endpoint'],'keys':{'p256dh':s['p256dh'],'auth':s['auth']}},data=payload,vapid_private_key=PRIV,vapid_claims={'sub':SUB}); ok+=1
        except Exception as e: print("push err",repr(e)[:100],flush=True)
    return ok
L=[]
h=one("SELECT * FROM stream_heartbeat"); L.append(f"STREAM {h.get('conn_state','?')[:12]} mkts {h.get('markets')} ticks/min {h.get('ticks_last_min')} lat {h.get('median_latency_ms')}ms last {str(h.get('last_seen'))[11:16]}")
e=one("SELECT * FROM espn_heartbeat"); L.append(f"ESPN live {e.get('live')} matched {e.get('matched')} last {str(e.get('last_seen'))[11:16]}")
s=one("SELECT * FROM stats_heartbeat"); L.append(f"xG feed remaining {s.get('http_status')} last {str(s.get('last_seen'))[11:16]}")
x=one("SELECT count(*) n, count(pnl_per_10) st, coalesce(sum(pnl_per_10),0) p FROM xg_paper"); L.append(f"xG paper: {x.get('n')} trades, {x.get('st')} settled, £{float(x.get('p') or 0):+.2f}")
lo=one("SELECT count(*) n, count(pnl_per_10) st, coalesce(sum(pnl_per_10),0) p, count(*) FILTER (WHERE pnl_per_10>0) w FROM late_over_paper WHERE goal_src='espn'"); L.append(f"Late lay-Over paper: {lo.get('n')} trades, {lo.get('st')} settled, {lo.get('w')} won, £{float(lo.get('p') or 0):+.2f}")
ld=one("SELECT count(*) n, count(pnl_per_10) st, coalesce(sum(pnl_per_10),0) p FROM ltd_inplay_paper"); L.append(f"LTD lower-league paper: {ld.get('n')}/{ld.get('st')} settled £{float(ld.get('p') or 0):+.2f}")
c=q("SELECT rule, count(*) n, count(pnl_per_10) st, coalesce(sum(pnl_per_10),0) p FROM cricket_fav_paper GROUP BY rule")
for r in c: L.append(f"Cricket {r['rule'][:14]}: {r['n']}/{r['st']} settled £{float(r['p'] or 0):+.2f}")
mm=one("SELECT count(*) n, coalesce(sum(pnl_per_10),0) p FROM racing_mm_stream WHERE exit_reason IS NOT NULL"); mt=one("SELECT count(*) n, coalesce(sum(pnl_per_10),0) p FROM racing_mm_paper WHERE exit_reason IS NOT NULL")
L.append(f"Racing MM stream {mm.get('n')} rounds £{float(mm.get('p') or 0):+.2f} | tape {mt.get('n')} rounds £{float(mt.get('p') or 0):+.2f}")
part1="\n".join(L)
# verdict lines from last night's jobs
def tail(job,pat,n=6):
    r=one("SELECT status, log FROM job_results WHERE job LIKE %s ORDER BY started DESC LIMIT 1",(job+'%',))
    if not r or not r.get('log'): return f"{job}: no result yet"
    lines=[l for l in r['log'].splitlines() if re.search(pat,l)]
    return f"{job} [{r['status']}]: "+" | ".join(l.strip()[:110] for l in lines[:n])
V=[tail('228_playbook',r'^S\d|S8 |S9|S18|lay draw at KO|lay home',8), tail('229_cross',r'events on both|followed within|lag seconds|riskless|LOWER lay',6), tail('230_tennis',r'qualifying entries|p_settle:|p_hedge:|favourite still won',5), tail('227_opp',r'share of total|OPPORTUNITY MAP|Typical late',4)]
part2="\n".join(V)
for i,(t,b) in enumerate([("PE morning 1/2 — live books",part1),("PE morning 2/2 — overnight verdicts",part2)],1):
    cur.execute("INSERT INTO digest_log (part, body) VALUES (%s,%s)",(i,b)); n=push(t,b,f"digest{i}"); print(f"pushed part {i} to {n} devices\n{b}\n")
PYFILE
python3 -m py_compile /root/pe-push/digest.py || exit 1
python3 /root/pe-push/digest.py
( crontab -l 2>/dev/null | grep -v "pe-push/digest.py" ; echo "45 6 * * * cd /root/pe-push && python3 digest.py >> digest.log 2>&1" ) | crontab -
echo "daily 06:45 digest installed"
