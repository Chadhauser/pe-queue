#!/bin/bash
# 091: M1 PHONE ALERTS — the Weekend Card manual trade, delivered to Peter's phone through the same web-push channel as the goal
# signal (push_subscriptions / pywebpush / vapid.env, see 090). He asked: "add to goal signal otherwise i dont know how".
# Watches the football ladder recorder (liq_goal_depth, MO market, offset 0 = goal reopen). For a goal 10'-75', not the 3rd+ of
# the match, in a Weekend Card game (parsed from /root/pe-report/weekend.txt) OR any market with £500k+ matched: at +60s reads the
# scorer's best LAY price; if 1.30-2.50 pushes "M1 ENTRY — LAY <team> @ <px>, £10, exit at <min+10>' or next goal". Then pushes
# "M1 EXIT — BACK <team> now @ <px>" at +10 min or the next goal/suspension, whichever first. Everything logged in m1_alerts.
# Max 6 entries/day. Installs a cron keepalive and sends an "M1 TEST" push immediately so Peter can confirm the channel.
mkdir -p /root/pe-push && cat > /root/pe-push/m1_alert.py <<'PYFILE'
import os, re, sys, json, time, datetime, psycopg2, psycopg2.extras
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
from pywebpush import webpush, WebPushException
for line in open('/root/pe-push/vapid.env'):
    if '=' in line and not line.startswith('#'):
        k,v=line.strip().split('=',1); os.environ.setdefault(k,v)
PRIV=os.environ["VAPID_PRIVATE"]; SUB=os.environ.get("VAPID_SUB","mailto:pe@edwardsbros.co.uk")
TOKEN="Y995gYX453GTN6emk1pHtFTTu788BHXM"; STAKE=10; LO,HI=1.30,2.50; MIN_LO,MIN_HI=10,75; HOLD=600; BIG=500000; MAXDAY=6
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
cur.execute("""CREATE TABLE IF NOT EXISTS m1_alerts (id SERIAL PRIMARY KEY, market_id TEXT, goal_ts TIMESTAMPTZ, event_name TEXT, competition TEXT, team TEXT, sel TEXT,
  minute INT, goals INT, reason TEXT, entry_px NUMERIC, entry_sent TIMESTAMPTZ, exit_due TIMESTAMPTZ, exit_px NUMERIC, exit_sent TIMESTAMPTZ, exit_reason TEXT, recipients INT, UNIQUE (market_id, goal_ts))""")
def push(title,body,tag):
    cur.execute("SELECT id,endpoint,p256dh,auth FROM push_subscriptions WHERE active"); subs=cur.fetchall(); ok=0
    payload=json.dumps({'title':title,'body':body,'tag':tag,'url':f"/positions?k={TOKEN}"})
    for s in subs:
        try:
            webpush(subscription_info={'endpoint':s['endpoint'],'keys':{'p256dh':s['p256dh'],'auth':s['auth']}},data=payload,vapid_private_key=PRIV,vapid_claims={'sub':SUB}); ok+=1
        except WebPushException as e:
            code=getattr(e.response,'status_code',None)
            cur.execute("UPDATE push_subscriptions SET last_error=%s, active=(%s NOT IN (404,410)) WHERE id=%s",(str(e)[:200],code or 0,s['id']))
        except Exception as e: print("push err",repr(e)[:120],flush=True)
    print(f"PUSH {title} | {body} -> {ok}/{len(subs)}",flush=True); return ok
if '--test' in sys.argv:
    n=push("M1 TEST","Weekend Card alerts are live. ENTRY/EXIT pushes will look like this. Reply 'got it' to Claude.","m1-test-"+str(int(time.time())))
    sys.exit(0 if n else 1)
def card_games():
    try: txt=open('/root/pe-report/weekend.txt').read()
    except Exception: return set()
    names=set()
    for ln in txt.split('\n'):
        m=re.match(r'^(Mon|Tue|Wed|Thu|Fri|Sat|Sun) \d\d:\d\d\s+[\d,]+\s+(.+?)\s{2,}',ln)
        if m: names.add(m.group(2).strip()[:40])
    return names
def side_name(ev,sel):
    parts=re.split(r'\s+v\s+|\s+vs\s+',ev,maxsplit=1,flags=re.I)
    s=(sel or '').upper()
    if s in ('HOME','1') and len(parts)==2: return parts[0]
    if s in ('AWAY','2') and len(parts)==2: return parts[1]
    return sel
print("m1 alerter up; card games:",sorted(card_games()),flush=True)
pending={}; last_card=0; CARD=set()
while True:
    try:
        now=datetime.datetime.now(datetime.timezone.utc)
        if time.time()-last_card>300: CARD=card_games(); last_card=time.time()
        # 1. new MO goal reopens in the last 3 minutes
        cur.execute("""SELECT market_id, event_name, competition, goal_ts, minute, sel, min(pre_ltp) pre, min(ltp) post, max(total_matched) tm
                       FROM liq_goal_depth WHERE mkt='MO' AND offset_s=0 AND goal_ts>now()-interval '3 minutes' GROUP BY 1,2,3,4,5,6""")
        byg={}
        for r in cur.fetchall(): byg.setdefault((r['market_id'],r['goal_ts']),[]).append(r)
        for (mid,gts),rows in byg.items():
            if (mid,gts) in pending: continue
            cur.execute("SELECT 1 FROM m1_alerts WHERE market_id=%s AND goal_ts=%s",(mid,gts))
            if cur.fetchone(): continue
            ev=rows[0]['event_name']; comp=rows[0]['competition']; minute=rows[0]['minute']; tm=max((r['tm'] or 0) for r in rows)
            why='card' if ev[:40].strip() in CARD else ('big' if tm>=BIG else None)
            # scorer = non-draw selection that shortened most
            teams=[r for r in rows if (r['sel'] or '').upper() not in ('DRAW','THE DRAW','X') and r['pre'] and r['post']]
            if not teams: continue
            sc=min(teams,key=lambda r: float(r['post'])/float(r['pre']))
            if float(sc['post'])/float(sc['pre'])>0.97: why=None; note='no shortener (red card / VAR?)'
            cur.execute("SELECT count(DISTINCT goal_ts) n FROM liq_goal_depth WHERE event_name=%s AND mkt='MO' AND offset_s=0 AND goal_ts<=%s AND goal_ts>now()-interval '3 hours'",(ev,gts))
            goals=cur.fetchone()['n'] or 1
            cur.execute("SELECT count(*) n FROM m1_alerts WHERE entry_sent::date=current_date"); today=cur.fetchone()['n']
            skip=None
            if why is None: skip='not card/£500k or no clear scorer'
            elif goals>2: skip=f'goal {goals} of match'
            elif minute is None or not (MIN_LO<=minute<=MIN_HI): skip=f'minute {minute}'
            elif today>=MAXDAY: skip='daily cap'
            if skip:
                cur.execute("INSERT INTO m1_alerts (market_id,goal_ts,event_name,competition,team,sel,minute,goals,reason) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s) ON CONFLICT DO NOTHING",(mid,gts,ev,comp,side_name(ev,sc['sel']),sc['sel'],minute,goals,'SKIP: '+skip))
                print("skip",ev,skip,flush=True); continue
            pending[(mid,gts)]={'ev':ev,'comp':comp,'sel':sc['sel'],'team':side_name(ev,sc['sel']),'minute':minute,'goals':goals,'why':why,'due':gts+datetime.timedelta(seconds=60)}
        # 2. entries due (+60s): read the scorer's lay price now
        for key,p in list(pending.items()):
            if now<p['due']: continue
            mid,gts=key
            cur.execute("SELECT lay_px, back_px, ltp FROM liq_goal_depth WHERE market_id=%s AND goal_ts=%s AND sel=%s AND offset_s>0 AND lay_px IS NOT NULL ORDER BY ts DESC LIMIT 1",(mid,gts,p['sel']))
            r=cur.fetchone()
            if not r:
                cur.execute("SELECT lay_px, back_px, ltp FROM liq_sample WHERE market_id=%s AND sel=%s AND lay_px IS NOT NULL AND ts>%s ORDER BY ts DESC LIMIT 1",(mid,p['sel'],gts))
                r=cur.fetchone()
            if not r:
                if (now-p['due']).total_seconds()<30: continue
                px=None
            else: px=float(r['lay_px'])
            del pending[key]
            if px is None or not (LO<=px<=HI):
                cur.execute("INSERT INTO m1_alerts (market_id,goal_ts,event_name,competition,team,sel,minute,goals,reason,entry_px) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) ON CONFLICT DO NOTHING",(mid,gts,p['ev'],p['comp'],p['team'],p['sel'],p['minute'],p['goals'],f"SKIP: lay price {px} outside {LO}-{HI}",px))
                print("skip price",p['ev'],px,flush=True); continue
            exit_min=(p['minute'] or 0)+10
            n=push(f"M1 ENTRY — {p['ev']}",f"{p['minute']}' {p['team']} scored. LAY {p['team']} @ {px:.2f}, £{STAKE}. Exit at {exit_min}' or next goal.",f"m1e-{mid}-{int(gts.timestamp())}")
            cur.execute("INSERT INTO m1_alerts (market_id,goal_ts,event_name,competition,team,sel,minute,goals,reason,entry_px,entry_sent,exit_due,recipients) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,now(),%s,%s) ON CONFLICT DO NOTHING",
                        (mid,gts,p['ev'],p['comp'],p['team'],p['sel'],p['minute'],p['goals'],p['why'],px,gts+datetime.timedelta(seconds=60+HOLD),n))
        # 3. exits: +10 min, or a new goal/suspension on the market first
        cur.execute("SELECT * FROM m1_alerts WHERE entry_sent IS NOT NULL AND exit_sent IS NULL")
        for t in cur.fetchall():
            cur.execute("SELECT 1 FROM liq_goal_depth WHERE market_id=%s AND offset_s=0 AND goal_ts>%s LIMIT 1",(t['market_id'],t['entry_sent'])); newg=cur.fetchone() is not None
            if not newg and now<t['exit_due']: continue
            cur.execute("SELECT back_px FROM liq_sample WHERE market_id=%s AND sel=%s AND back_px IS NOT NULL ORDER BY ts DESC LIMIT 1",(t['market_id'],t['sel'])); r=cur.fetchone()
            bp=float(r['back_px']) if r else None
            push(f"M1 EXIT — {t['event_name']}",f"BACK {t['team']} now"+(f" @ {bp:.2f}" if bp else "")+(" — new goal/suspension" if newg else " — 10 minutes up")+". Record: entry "+f"{float(t['entry_px']):.2f}"+(f" exit {bp:.2f}" if bp else ""),f"m1x-{t['id']}")
            cur.execute("UPDATE m1_alerts SET exit_sent=now(), exit_px=%s, exit_reason=%s WHERE id=%s",(bp,'GOAL' if newg else 'CLOCK',t['id']))
        time.sleep(5)
    except Exception as e:
        print("loop error",repr(e)[:200],flush=True); time.sleep(10)
        try: con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        except Exception: pass
PYFILE
python3 -m py_compile /root/pe-push/m1_alert.py || exit 1
cat > /root/pe-push/m1_keepalive.sh <<'SH'
#!/bin/bash
exec 8>/root/pe-push/m1.lock; flock -n 8 || exit 0
cd /root/pe-push && python3 m1_alert.py >> /root/pe-push/m1.log 2>&1
SH
chmod +x /root/pe-push/m1_keepalive.sh
echo "== liq_goal_depth MO sel values (so the scorer logic is right) =="; python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require').cursor(); c.execute("SELECT sel, count(*) FROM liq_goal_depth WHERE mkt='MO' GROUP BY 1 ORDER BY 2 DESC LIMIT 8"); print(c.fetchall())
c.execute("SELECT count(*) FROM liq_sample WHERE ts>now()-interval '1 hour'"); print("liq_sample rows last hour",c.fetchone())
c.execute("SELECT count(*) FILTER (WHERE active), count(*) FROM push_subscriptions"); print("push subs active/total",c.fetchone())
PY
echo "== TEST PUSH =="; cd /root/pe-push && python3 m1_alert.py --test || echo "TEST PUSH FAILED (no active subscriptions or vapid error)"
( crontab -l 2>/dev/null | grep -v m1_keepalive ; echo "* * * * * /root/pe-push/m1_keepalive.sh" ) | crontab -
echo "CRON INSTALLED: M1 alerter"; sleep 20; tail -5 /root/pe-push/m1.log
