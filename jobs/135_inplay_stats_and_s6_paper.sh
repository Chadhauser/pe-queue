#!/bin/bash
# 135: IN-PLAY STATS TAPE + S6 PAPER (Peter 22 Oct: "see the course of travel of games using xG and shots on goal, put the price
# in and then exit"). SofaScore unofficial feed (same endpoints as sofascore_live.py, no key): every 60s all live football, per
# game every ~2 min: minute, score, xG, shots, shots on target, possession, dangerous attacks, corners -> ip_stats. Matched to our
# Betfair MO ladder (liq_sample, same day, team-name similarity) so price and stats sit on one timeline.
# S6 PAPER BOT in the same loop, Peter's S6 rule verbatim: 20-35', 0-0, one side xG >= 0.6 ahead with 4+ shots and 2+ on target,
# draw lay price 3.00-4.50 -> paper LAY THE DRAW £10; exit = first goal (draw price at +60s from liq_goal_depth, else next
# sample); stop = 65' at the draw back price. -> s6_paper. Also logs the dominant side so Psychoff's "back the next goal" can be
# scored from the same rows. Verdict after 40 paper trades.
mkdir -p /root/pe-stats && cat > /root/pe-stats/stats_recorder.py <<'PYFILE'
import re, sys, time, datetime, unicodedata, requests, psycopg2, psycopg2.extras
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
H={"User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36","Accept":"application/json","Referer":"https://www.sofascore.com/","Origin":"https://www.sofascore.com"}
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("""CREATE TABLE IF NOT EXISTS ip_stats (ts TIMESTAMPTZ DEFAULT now(), sofa_id BIGINT, event_name TEXT, league TEXT, market_id TEXT, minute INT, hs INT, "as" INT,
  h_xg NUMERIC, a_xg NUMERIC, h_shots INT, a_shots INT, h_sot INT, a_sot INT, h_poss NUMERIC, a_poss NUMERIC, h_dang INT, a_dang INT, h_corn INT, a_corn INT);
CREATE INDEX IF NOT EXISTS ip_stats_ev ON ip_stats (sofa_id, ts);
CREATE TABLE IF NOT EXISTS s6_paper (id SERIAL PRIMARY KEY, ts TIMESTAMPTZ DEFAULT now(), sofa_id BIGINT, market_id TEXT, event_name TEXT, league TEXT, entry_min INT, dominant TEXT,
  h_xg NUMERIC, a_xg NUMERIC, h_sot INT, a_sot INT, draw_lay NUMERIC, exit_min INT, exit_px NUMERIC, exit_reason TEXT, pnl_per_10 NUMERIC, UNIQUE (sofa_id));
CREATE TABLE IF NOT EXISTS stats_heartbeat (id INT PRIMARY KEY, last_seen TIMESTAMPTZ, live INT, matched INT, http_status INT)""")
def get(url):
    r=requests.get(url,headers=H,timeout=12); return r.status_code,(r.json() if r.status_code==200 else None)
def norm(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
    s=re.sub(r"\b(fc|cf|afc|sc|ac|as|ss|us|sv|vfb|vfl|tsg|fk|nk|sk|bk|if|club|de|the|athletic|atletico|sporting|real|cd|ud|sd|rcd|u21|u19|u23|women|ii)\b"," ",s)
    return set(w for w in re.sub(r"[^a-z0-9 ]"," ",s).split() if len(w)>2)
def sim(a,b): A,B=norm(a),norm(b); return len(A&B)/max(1,len(A|B))
def parse_stats(d):
    r=dict(h_xg=None,a_xg=None,h_shots=0,a_shots=0,h_sot=0,a_sot=0,h_poss=None,a_poss=None,h_dang=0,a_dang=0,h_corn=0,a_corn=0)
    def f(v):
        try: return float(str(v).replace('%','').strip() or 0)
        except Exception: return 0.0
    for p in d.get('statistics',[]):
        if p.get('period')!='ALL': continue
        for g in p.get('groups',[]):
            for it in g.get('statisticsItems',[]):
                n=it.get('name','').lower(); h=f(it.get('home',0)); a=f(it.get('away',0))
                if 'expected goals' in n or n=='xg': r['h_xg'],r['a_xg']=h,a
                elif 'shots on target' in n: r['h_sot'],r['a_sot']=int(h),int(a)
                elif n in ('total shots','shots'): r['h_shots'],r['a_shots']=int(h),int(a)
                elif 'possession' in n: r['h_poss'],r['a_poss']=h,a
                elif 'dangerous attack' in n: r['h_dang'],r['a_dang']=int(h),int(a)
                elif 'corner' in n: r['h_corn'],r['a_corn']=int(h),int(a)
    return r
last_poll={}; mkt_cache={}; last_mkt=0; open_tr={}
def bf_markets():
    global mkt_cache,last_mkt
    if time.time()-last_mkt<120: return mkt_cache
    cur.execute("SELECT DISTINCT market_id, event_name FROM liq_sample WHERE mkt='MO' AND ts>now()-interval '3 hours'"); mkt_cache=cur.fetchall(); last_mkt=time.time(); return mkt_cache
def draw_px(mid,col='lay_px'):
    cur.execute(f"SELECT {col} FROM liq_sample WHERE market_id=%s AND mkt='MO' AND upper(sel) IN ('THE DRAW','DRAW') AND {col} IS NOT NULL ORDER BY ts DESC LIMIT 1",(mid,)); r=cur.fetchone(); return float(r[0]) if r else None
while True:
    try:
        st,data=get("https://api.sofascore.com/api/v1/sport/football/events/live"); live=(data or {}).get('events',[]); matched=0
        for e in live:
            sid=e.get('id'); minute=(e.get('time') or {}).get('played');
            if not sid or minute is None: continue
            if sid in last_poll and time.time()-last_poll[sid]<110: continue
            home=(e.get('homeTeam') or {}).get('name',''); away=(e.get('awayTeam') or {}).get('name',''); lg=((e.get('tournament') or {}).get('uniqueTournament') or {}).get('name') or (e.get('tournament') or {}).get('name','')
            hs=(e.get('homeScore') or {}).get('current',0); as_=(e.get('awayScore') or {}).get('current',0)
            s2,sd=get(f"https://api.sofascore.com/api/v1/event/{sid}/statistics"); last_poll[sid]=time.time(); time.sleep(0.7)
            if not sd: continue
            s=parse_stats(sd); ev=f"{home} v {away}"
            # Betfair market match
            mid=None; bs=0
            for m,en in bf_markets():
                if ' v ' not in en: continue
                h2,a2=en.split(' v ',1); sc=sim(home,h2)+sim(away,a2)
                if sc>bs: bs=sc; mid=m
            if bs<1.0: mid=None
            else: matched+=1
            cur.execute('INSERT INTO ip_stats (sofa_id,event_name,league,market_id,minute,hs,"as",h_xg,a_xg,h_shots,a_shots,h_sot,a_sot,h_poss,a_poss,h_dang,a_dang,h_corn,a_corn) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)',
                        (sid,ev,lg,mid,int(minute),hs,as_,s['h_xg'],s['a_xg'],s['h_shots'],s['a_shots'],s['h_sot'],s['a_sot'],s['h_poss'],s['a_poss'],s['h_dang'],s['a_dang'],s['h_corn'],s['a_corn']))
            # ---- S6 paper: manage open
            if sid in open_tr:
                t=open_tr[sid]
                if hs+as_>0 or minute>=65:
                    px=draw_px(mid,'lay_px' if hs+as_>0 else 'back_px') if mid else None
                    if hs+as_>0 and mid:
                        cur.execute("SELECT lay_px FROM liq_goal_depth WHERE market_id=%s AND mkt='MO' AND upper(sel) IN ('THE DRAW','DRAW') AND offset_s=60 AND goal_ts>%s ORDER BY goal_ts LIMIT 1",(mid,t['ts'])); r=cur.fetchone()
                        if r and r[0]: px=float(r[0])
                    if px:
                        pnl=(1-t['px']/px)*10; pnl=pnl*0.98 if pnl>0 else pnl
                        cur.execute("UPDATE s6_paper SET exit_min=%s, exit_px=%s, exit_reason=%s, pnl_per_10=%s WHERE sofa_id=%s",(int(minute),px,'GOAL' if hs+as_>0 else 'STOP65',round(pnl,2),sid))
                        print(f"S6 EXIT {ev} {t['px']}->{px} {'GOAL' if hs+as_>0 else 'STOP65'} {pnl:+.2f}",flush=True); del open_tr[sid]
                continue
            # ---- S6 entry
            if mid and 20<=minute<=35 and hs==0 and as_==0 and s['h_xg'] is not None:
                dom=None
                if s['h_xg']-s['a_xg']>=0.6 and s['h_shots']>=4 and s['h_sot']>=2: dom='HOME'
                elif s['a_xg']-s['h_xg']>=0.6 and s['a_shots']>=4 and s['a_sot']>=2: dom='AWAY'
                if dom:
                    dl=draw_px(mid,'lay_px')
                    if dl and 3.0<=dl<=4.5:
                        cur.execute("INSERT INTO s6_paper (sofa_id,market_id,event_name,league,entry_min,dominant,h_xg,a_xg,h_sot,a_sot,draw_lay) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) ON CONFLICT DO NOTHING",
                                    (sid,mid,ev,lg,int(minute),dom,s['h_xg'],s['a_xg'],s['h_sot'],s['a_sot'],dl))
                        if cur.rowcount: open_tr[sid]={'px':dl,'ts':datetime.datetime.now(datetime.timezone.utc)}; print(f"S6 ENTRY {ev} {minute}' {dom} xG {s['h_xg']}-{s['a_xg']} lay draw {dl}",flush=True)
        cur.execute("INSERT INTO stats_heartbeat VALUES (1,now(),%s,%s,%s) ON CONFLICT (id) DO UPDATE SET last_seen=now(), live=EXCLUDED.live, matched=EXCLUDED.matched, http_status=EXCLUDED.http_status",(len(live),matched,st))
        time.sleep(60)
    except Exception as ex:
        print("loop",repr(ex)[:200],flush=True); time.sleep(30)
        try: con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
        except Exception: pass
PYFILE
python3 -m py_compile /root/pe-stats/stats_recorder.py || exit 1
cat > /root/pe-stats/keepalive.sh <<'SH'
#!/bin/bash
pgrep -f stats_recorder.py >/dev/null || (cd /root/pe-stats && nohup python3 stats_recorder.py >> stats.log 2>&1 &)
SH
chmod +x /root/pe-stats/keepalive.sh
( crontab -l 2>/dev/null | grep -v pe-stats ; echo "* * * * * /root/pe-stats/keepalive.sh" ) | crontab -
/root/pe-stats/keepalive.sh; sleep 90; pgrep -af stats_recorder.py; tail -5 /root/pe-stats/stats.log
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require').cursor(); c.execute("SELECT * FROM stats_heartbeat"); print("heartbeat (live, matched, sofascore http status):",c.fetchall())
c.execute("SELECT count(*), count(DISTINCT sofa_id), count(*) FILTER (WHERE market_id IS NOT NULL) FROM ip_stats"); print("ip_stats rows, games, matched-to-Betfair rows:",c.fetchone())
PY
