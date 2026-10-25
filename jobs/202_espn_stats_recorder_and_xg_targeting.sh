#!/bin/bash
# 202: STATS FEED, TWO-TIER. (1) ESPN's keyless site API (probe 201: shots, shots on target, possession, corners, goals per side for
# ~27 leagues, one call per league) becomes the always-on in-play stats tape -> espn_stats, matched to the Betfair market with the same
# name matcher the API-Football recorder uses. No quota, every 60 s. (2) API-Football is reserved for xG only, and only where the xG
# cells can fire: matched market, minute >= 18, total goals <= 2. That is a fraction of the calls the recorder was making, so the daily
# quota should last the day instead of dying mid-afternoon. Both followed by heartbeat checks.
set -e
mkdir -p /root/pe-stats && cat > /root/pe-stats/espn_recorder.py <<'PYFILE'
import re, sys, time, datetime, unicodedata, requests, psycopg2
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
H={"User-Agent":"Mozilla/5.0"}
LEAGUES=["eng.1","eng.2","eng.3","eng.4","esp.1","esp.2","ita.1","ita.2","ger.1","ger.2","fra.1","fra.2","ned.1","por.1","sco.1","bel.1","tur.1","usa.1","bra.1","arg.1","jpn.1","aus.1",
         "uefa.champions","uefa.europa","uefa.europa.conf","fin.1","swe.1","nor.1","den.1","aut.1","sui.1","gre.1","mex.1","chn.1","kor.1","pol.1","cze.1","rus.1","irl.1","wal.1"]
ALIAS={'utd':'united','man':'manchester','intl':'international','st':'saint','wolves':'wolverhampton','spurs':'tottenham','psg':'paris','inter':'internazionale','olympique':'','borussia':'','dynamo':'dinamo','sporting':'','deportivo':'','atl':'atletico'}
def norm(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
    s=re.sub(r"\b(fc|cf|afc|sc|ac|as|ss|us|sv|vfb|vfl|tsg|fk|nk|sk|bk|if|club|de|the|athletic|atletico|sporting|real|cd|ud|sd|rcd|u21|u19|u23|women|ii)\b"," ",s)
    s=' '.join(ALIAS.get(w,w) for w in re.sub(r"[^a-z0-9 ]"," ",s).split())
    return set(w for w in s.split() if len(w)>2)
def sim(a,b): A,B=norm(a),norm(b); return len(A&B)/max(1,len(A|B))
def connect():
    c=psycopg2.connect(DB,sslmode='require'); c.autocommit=True; return c
con=connect(); cur=con.cursor()
cur.execute("""CREATE TABLE IF NOT EXISTS espn_stats (ts TIMESTAMPTZ DEFAULT now(), espn_id BIGINT, league TEXT, event_name TEXT, market_id TEXT, clock TEXT, minute INT, period INT, hs INT, "as" INT,
  h_shots INT, a_shots INT, h_sot INT, a_sot INT, h_poss NUMERIC, a_poss NUMERIC, h_corn INT, a_corn INT, h_fouls INT, a_fouls INT);
CREATE INDEX IF NOT EXISTS espn_stats_ev ON espn_stats (espn_id, ts); CREATE INDEX IF NOT EXISTS espn_stats_mkt ON espn_stats (market_id, ts);
CREATE TABLE IF NOT EXISTS espn_heartbeat (id INT PRIMARY KEY, last_seen TIMESTAMPTZ, live INT, matched INT, leagues_ok INT)""")
mkt_cache=[]; last_mkt=0; match_cache={}
def bf_markets():
    global mkt_cache,last_mkt
    if time.time()-last_mkt<120: return mkt_cache
    cur.execute("SELECT market_id, max(event_name) FROM liq_sample WHERE mkt='MO' AND ts>now()-interval '6 hours' GROUP BY market_id"); mkt_cache=cur.fetchall(); last_mkt=time.time(); return mkt_cache
def match(eid,home,away):
    if eid in match_cache and match_cache[eid]: return match_cache[eid]
    mid=None; bs=0; b2=0
    for m,en in bf_markets():
        if not en or ' v ' not in en: continue
        h2,a2=en.split(' v ',1); sc=sim(home,h2)+sim(away,a2)
        if sc>bs: b2=bs; bs=sc; mid=m
        elif sc>b2: b2=sc
    if bs<0.8 or bs-b2<0.25: mid=None
    match_cache[eid]=mid; return mid
def stat(c,k):
    for s in c.get('statistics',[]):
        if s['name']==k:
            try: return float(s.get('displayValue'))
            except Exception: return None
    return None
def minute_of(status):
    clk=status.get('displayClock') or ''; m=re.match(r"(\d+)'",clk); mn=int(m.group(1)) if m else None
    per=status.get('period'); return mn,per
while True:
    try:
        live=0; matched=0; ok=0
        for lg in LEAGUES:
            try: r=requests.get(f"https://site.api.espn.com/apis/site/v2/sports/soccer/{lg}/scoreboard",headers=H,timeout=10)
            except Exception: continue
            if r.status_code!=200: continue
            ok+=1
            for e in r.json().get('events',[]):
                if e['status']['type']['state']!='in': continue
                live+=1; comp=e['competitions'][0]; cs=comp['competitors']
                h=next((c for c in cs if c.get('homeAway')=='home'),cs[0]); a=next((c for c in cs if c.get('homeAway')=='away'),cs[-1])
                hn,an=h['team']['displayName'],a['team']['displayName']; mid=match(e['id'],hn,an)
                if mid: matched+=1
                mn,per=minute_of(e['status'])
                def iv(x): return int(x) if x is not None else None
                cur.execute('INSERT INTO espn_stats (espn_id,league,event_name,market_id,clock,minute,period,hs,"as",h_shots,a_shots,h_sot,a_sot,h_poss,a_poss,h_corn,a_corn,h_fouls,a_fouls) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)',
                    (int(e['id']),lg,f"{hn} v {an}",mid,e['status'].get('displayClock'),mn,per,iv(float(h.get('score') or 0)),iv(float(a.get('score') or 0)),
                     iv(stat(h,'totalShots')),iv(stat(a,'totalShots')),iv(stat(h,'shotsOnTarget')),iv(stat(a,'shotsOnTarget')),stat(h,'possessionPct'),stat(a,'possessionPct'),
                     iv(stat(h,'wonCorners')),iv(stat(a,'wonCorners')),iv(stat(h,'foulsCommitted')),iv(stat(a,'foulsCommitted'))))
            time.sleep(0.2)
        cur.execute("INSERT INTO espn_heartbeat VALUES (1,now(),%s,%s,%s) ON CONFLICT (id) DO UPDATE SET last_seen=now(), live=EXCLUDED.live, matched=EXCLUDED.matched, leagues_ok=EXCLUDED.leagues_ok",(live,matched,ok))
        time.sleep(60)
    except Exception as ex:
        print("loop",repr(ex)[:200],flush=True); time.sleep(30)
        try: con=connect(); cur=con.cursor()
        except Exception: pass
PYFILE
python3 -m py_compile /root/pe-stats/espn_recorder.py
cat > /root/pe-stats/keepalive_espn.sh <<'SH'
#!/bin/bash
pgrep -f espn_recorder.py >/dev/null || (cd /root/pe-stats && nohup python3 espn_recorder.py >> espn.log 2>&1 &)
SH
chmod +x /root/pe-stats/keepalive_espn.sh
( crontab -l 2>/dev/null | grep -v keepalive_espn ; echo "* * * * * /root/pe-stats/keepalive_espn.sh" ) | crontab -
/root/pe-stats/keepalive_espn.sh
echo "== xG targeting patch on the API-Football recorder"
python3 - <<'PY'
p='/root/pe-stats/stats_recorder.py'; s=open(p).read()
anchor="            if not mid: continue                                   # unmatched games are never polled (budget)\n"
add="            if minute<18 or ((f['goals']['home'] or 0)+(f['goals']['away'] or 0))>2: continue   # xG only where the xG cells can fire (202)\n"
if add in s: print("already patched")
else:
    assert anchor in s, "anchor missing"; s=s.replace(anchor,anchor+add,1); open(p,'w').write(s); print("xG targeting patched")
PY
python3 -m py_compile /root/pe-stats/stats_recorder.py
pkill -f stats_recorder.py || true; sleep 3; /root/pe-stats/keepalive.sh 2>/dev/null || true
sleep 75
echo "== processes"; pgrep -af "espn_recorder|stats_recorder" | head
echo "== espn log"; tail -3 /root/pe-stats/espn.log
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require').cursor()
c.execute("SELECT * FROM espn_heartbeat"); print("espn heartbeat (live, matched, leagues_ok):",c.fetchall())
c.execute("SELECT league, event_name, market_id IS NOT NULL m, clock, hs, \"as\", h_shots, a_shots, h_sot, a_sot, h_poss FROM espn_stats ORDER BY ts DESC LIMIT 12")
for r in c.fetchall(): print("  ",r)
c.execute("SELECT * FROM stats_heartbeat"); print("api-football heartbeat:",c.fetchall())
PY
