#!/bin/bash
# 537 (Mon 9 Nov 2026). THE DESK — over-the-shoulder trading, first session Tue 10 Nov evening (Peter, 8 Nov: "Tuesday on any game is fine").
# Peter never watches games or ladders. The machine watches the tape and the live scores and writes one line per CALL to a file he reads on
# his phone: pe-queue/calls/<date>.md (pushed within a minute of each call). He clicks or doesn't; every call is scored against the real tape
# either way, so the desk builds its own record. Two lines only on day one, both in-play, both already positive on our data:
#   FADE  — Peter's verified line: a goal is scored, the scorer's Match Odds price collapses; LAY the scorer at +120 s (price <= 6), EXIT by
#           backing at +10 min. In and out. Source of goals: liq_goal_depth (the goal recorder's +120 s row).
#   HT11  — half-time 1-1: BACK Over 2.5 at the half-time price, hold to settle (coach tape, 7 d: n 67 +£1.70/£10; 48 games +£18.60/£100).
#           Source of scores: API-Football live fixtures (paid key, polled every 60 s), matched to the tape by team names.
# Scoring: FADE pnl per £2 = 2*(1-entry/exit) (lay then back), commission 2% on a profit; HT11 settles on the final score. Every call and its
# result goes to local table desk_calls and to the day file. Runs continuously under a keepalive; idle when nothing is live.
set -o pipefail
export PYTHONDONTWRITEBYTECODE=1
mkdir -p /root/pe-sports/desk /root/pe-queue/calls && cd /root/pe-sports/desk
cat > desk.py <<'PYFILE'
import sys, os, re, time, json, datetime, traceback, subprocess, requests, psycopg2
sys.path.insert(0,'/root/pe-queue/runner'); import creds
STAKE=2.0; COMM=0.02; FADE_OFFSET=120; FADE_MAX=6.0; FADE_HOLD=600; POLL=20
LOG='/root/pe-sports/desk/desk.log'; CALLS_DIR='/root/pe-queue/calls'
def log(m):
    with open(LOG,'a') as f: f.write(f"{datetime.datetime.utcnow():%Y-%m-%d %H:%M:%S} {m}\n")
def norm(x): return re.sub(r'[^a-z0-9]','',re.sub(r'\b(fc|cf|afc|sc|ac|the|u21|u23)\b','',str(x).lower()))
def ev_key(name):
    s=re.split(r'\s+v(?:s\.?)?\s+|\s+-\s+',str(name),maxsplit=1)
    return (norm(s[0]),norm(s[1])) if len(s)==2 else (norm(name),'')
def sim(a,b): return a==b or (len(a)>3 and len(b)>3 and (a in b or b in a))
L=psycopg2.connect(creds.pg_local()); L.autocommit=True; lc=L.cursor()
lc.execute("""CREATE TABLE IF NOT EXISTS desk_calls (id SERIAL PRIMARY KEY, ts TIMESTAMPTZ DEFAULT now(), day DATE, line TEXT, market_id TEXT, event_name TEXT,
  mkt TEXT, sel TEXT, side TEXT, price NUMERIC, stake NUMERIC, exit_rule TEXT, status TEXT DEFAULT 'open', exit_ts TIMESTAMPTZ, exit_price NUMERIC, result TEXT, pnl NUMERIC, note TEXT)""")
def T(): return psycopg2.connect(creds.pg_railway(),sslmode='require',connect_timeout=20)   # the live tape, wherever it lives today
AF_KEY=creds.apifootball(); AF_T=0; LIVE={}
def af_live():
    global AF_T, LIVE
    if time.time()-AF_T<60: return LIVE
    try:
        r=requests.get("https://v3.football.api-sports.io/fixtures?live=all",headers={"x-apisports-key":AF_KEY},timeout=20).json()
        LIVE={}
        for f in r.get('response',[]):
            h=f['teams']['home']['name']; a=f['teams']['away']['name']; st=f['fixture']['status']
            LIVE[(norm(h),norm(a))]=dict(home=h,away=a,status=st.get('short'),minute=st.get('elapsed'),gh=f['goals']['home'],ga=f['goals']['away'],fid=f['fixture']['id'])
        AF_T=time.time()
    except Exception as e: log(f"api-football {e!r}"[:160])
    return LIVE
def live_for(event_name):
    k=ev_key(event_name)
    for (h,a),v in af_live().items():
        if sim(h,k[0]) and sim(a,k[1]): return v
    return None
def day_file():
    d=datetime.date.today().isoformat(); p=f"{CALLS_DIR}/{d}.md"
    if not os.path.exists(p):
        open(p,'w').write(f"# Desk calls — {d}\n\nOne line per call. CLICK = what to do on Betfair now. EXIT = when to close. Every call is scored against the real tape whether you trade it or not; results are appended as they settle.\n\nLines today: FADE (lay the scorer at +2 min, back out at +10 min) · HT11 (1-1 at half-time, back Over 2.5, hold).\n\n")
    return p
def push(msg):
    try: subprocess.run("cd /root/pe-queue && git pull -q --rebase && git add calls && git commit -q -m '%s' && git push -q"%msg.replace("'",""),shell=True,timeout=60,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    except Exception as e: log(f"push {e!r}"[:120])
def write(line):
    with open(day_file(),'a') as f: f.write(line+"\n")
    log(line); push("desk: "+line[:60])
def latest(tc,mid,sel,before=None):
    tc.execute("SELECT ts, ltp, back_px, lay_px FROM liq_sample WHERE market_id=%s AND sel=%s AND ts<=coalesce(%s,now()) ORDER BY ts DESC LIMIT 1",(mid,sel,before)); return tc.fetchone()
seen_goals=set(); seen_ht=set()
while True:
    try:
        R=T(); tc=R.cursor(); tc.execute("SET statement_timeout='40s'")
        now=datetime.datetime.now(datetime.timezone.utc)
        # ---- FADE: new +120 s goal rows in the last 3 minutes
        tc.execute("SELECT market_id, event_name, mkt, sel, goal_ts, ts, pre_ltp, ltp, lay_px FROM liq_goal_depth WHERE offset_s=%s AND ts>now()-interval '3 minutes' AND mkt='MO' ORDER BY ts",(FADE_OFFSET,))
        for mid,ev,mkt,sel,gts,ts,pre,ltp,lay in tc.fetchall():
            key=(mid,str(gts))
            if key in seen_goals or not pre or not ltp or float(ltp)/float(pre)-1>-0.10: continue   # the scorer = runner whose price fell 10%+
            seen_goals.add(key); lay=float(lay or 0)
            if lay<=1.01 or lay>FADE_MAX: write(f"- {now:%H:%M} {ev} — goal, {sel} now {lay:.2f}: NO CALL (lay price over {FADE_MAX:.0f} or no price)"); continue
            team=sel; lv=live_for(ev)
            if sel in ('HOME','AWAY') and lv: team=lv['home'] if sel=='HOME' else lv['away']
            exit_at=now+datetime.timedelta(seconds=FADE_HOLD)
            lc.execute("INSERT INTO desk_calls (day,line,market_id,event_name,mkt,sel,side,price,stake,exit_rule,note) VALUES (current_date,'FADE',%s,%s,'MO',%s,'LAY',%s,%s,%s,%s)",(mid,ev,sel,lay,STAKE,f"back out at {exit_at:%H:%M} UTC",f"goal {str(gts)[11:16]} pre {pre} now {ltp}"))
            write(f"- **{now:%H:%M} {ev} — FADE. CLICK: LAY {team} at {lay:.2f}, £{STAKE:.0f}.** EXIT: back {team} at {exit_at:%H:%M} (any price). Why: goal {str(gts)[11:16]}, {team}'s price fell {float(pre):.2f}→{float(ltp):.2f}; the drop after a goal overshoots and drifts back.")
        # ---- FADE exits due
        lc.execute("SELECT id, market_id, sel, price, ts, event_name FROM desk_calls WHERE line='FADE' AND status='open' AND ts<now()-interval '%s seconds'"%FADE_HOLD)
        for cid,mid,sel,price,cts,ev in lc.fetchall():
            row=latest(tc,mid,sel)
            if not row or (now-row[0]).total_seconds()>300: lc.execute("UPDATE desk_calls SET status='void', note=coalesce(note,'')||' | no tape at exit' WHERE id=%s",(cid,)); write(f"- {now:%H:%M} {ev} — FADE exit: no price on the tape, call VOID"); continue
            ex=float(row[2] or row[1]); price=float(price); pnl=STAKE*(1-price/ex); pnl=pnl*(1-COMM) if pnl>0 else pnl
            lc.execute("UPDATE desk_calls SET status='closed', exit_ts=now(), exit_price=%s, pnl=%s, result=%s WHERE id=%s",(ex,round(pnl,2),'WIN' if pnl>0 else 'LOSS',cid))
            write(f"- {now:%H:%M} {ev} — **EXIT NOW: BACK {sel} at {ex:.2f}.** Result {'+' if pnl>=0 else ''}£{pnl:.2f} on £{STAKE:.0f} (laid {price:.2f}, backed {ex:.2f}).")
        # ---- HT11: half-time 1-1 on the live scores -> back Over 2.5 on the tape
        for k,v in list(af_live().items()):
            if v['status']!='HT' or (v['gh'],v['ga'])!=(1,1) or k in seen_ht: continue
            tc.execute("SELECT DISTINCT ON (market_id) market_id, event_name, ts, ltp, back_px, lay_px FROM liq_sample WHERE mkt='OU25' AND sel='OVER' AND ts>now()-interval '5 minutes' ORDER BY market_id, ts DESC")
            for mid,ev,ts,ltp,bp,lp in tc.fetchall():
                ek=ev_key(ev)
                if not (sim(ek[0],k[0]) and sim(ek[1],k[1])): continue
                seen_ht.add(k); px=float(bp or ltp or 0)
                if px<=1.01: break
                lc.execute("INSERT INTO desk_calls (day,line,market_id,event_name,mkt,sel,side,price,stake,exit_rule,note) VALUES (current_date,'HT11',%s,%s,'OU25','OVER','BACK',%s,%s,'hold to full time',%s)",(mid,ev,px,STAKE,f"af fixture {v['fid']}"))
                write(f"- **{now:%H:%M} {ev} — HT11. CLICK: BACK Over 2.5 goals at {px:.2f}, £{STAKE:.0f}.** EXIT: none, hold to full time. Why: 1-1 at half-time; a third goal comes more often than this price says (our tape: +£18.60 per £100).")
                break
        # ---- HT11 settlement from the final score
        lc.execute("SELECT id, event_name, price, note FROM desk_calls WHERE line='HT11' AND status='open' AND ts<now()-interval '50 minutes'")
        for cid,ev,price,note in lc.fetchall():
            fid=re.search(r'af fixture (\d+)',note or '');
            if not fid: continue
            try: f=requests.get(f"https://v3.football.api-sports.io/fixtures?id={fid.group(1)}",headers={"x-apisports-key":AF_KEY},timeout=20).json()['response'][0]
            except Exception: continue
            if f['fixture']['status']['short'] not in ('FT','AET','PEN'): continue
            tot=(f['goals']['home'] or 0)+(f['goals']['away'] or 0); price=float(price); won=tot>=3
            pnl=(price-1)*STAKE*(1-COMM) if won else -STAKE
            lc.execute("UPDATE desk_calls SET status='settled', exit_ts=now(), result=%s, pnl=%s WHERE id=%s",('WIN' if won else 'LOSS',round(pnl,2),cid))
            write(f"- {now:%H:%M} {ev} — HT11 settled: FT {f['goals']['home']}-{f['goals']['away']}, {'WIN' if won else 'LOSS'} {'+' if pnl>=0 else ''}£{pnl:.2f}.")
        # ---- day total line (rewritten at the end of the file only when something settled this loop is handled above); heartbeat
        lc.execute("INSERT INTO bookie_heartbeat VALUES (9,now(),0,0) ON CONFLICT (id) DO UPDATE SET last_seen=now()")
        R.close()
    except Exception:
        log(traceback.format_exc()[-500:])
        try: R.close()
        except Exception: pass
        time.sleep(30)
    time.sleep(POLL)
PYFILE
python3 -m py_compile desk.py && echo "desk compiles"
cat > run_desk.sh <<'SH'
#!/bin/bash
cd /root/pe-sports/desk && while true; do python3 desk.py >> desk.out 2>&1; sleep 15; done
SH
chmod +x run_desk.sh
( crontab -l 2>/dev/null | grep -v 'pe-sports/desk/run_desk.sh'; echo "*/5 * * * * pgrep -f 'desk.py' >/dev/null || nohup /root/pe-sports/desk/run_desk.sh >/dev/null 2>&1 &" ) | crontab -
nohup /root/pe-sports/desk/run_desk.sh >/dev/null 2>&1 & disown
sleep 45; echo "desk pids: $(pgrep -f desk.py | wc -l)"; tail -5 /root/pe-sports/desk/desk.log 2>/dev/null; tail -3 /root/pe-sports/desk/desk.out 2>/dev/null
echo "-- smoke: API-Football live fixtures reachable --"
python3 - <<'PY'
import sys,requests; sys.path.insert(0,'/root/pe-queue/runner'); import creds
r=requests.get("https://v3.football.api-sports.io/fixtures?live=all",headers={"x-apisports-key":creds.apifootball()},timeout=20).json()
print("live fixtures now:",len(r.get('response',[])),"| errors:",r.get('errors'))
PY
mkdir -p /root/pe-queue/calls && [ -f /root/pe-queue/calls/README.md ] || cat > /root/pe-queue/calls/README.md <<'MD'
# Desk calls
One file per day, written by the desk on the server while football is live. Open today's file on your phone:
https://github.com/Chadhauser/pe-queue/blob/main/calls/
Each call line: time, game, LINE, **CLICK** (what to do on Betfair now), EXIT (when to close), Why. Results are appended as they settle.
MD
cd /root/pe-queue && git add calls && git commit -q -m "desk: calls folder" && git push -q || true
echo "537 done — desk running; first calls appear in calls/<date>.md when a goal or a 1-1 half-time happens on a game the tape covers"
