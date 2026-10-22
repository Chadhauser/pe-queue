#!/bin/bash
# 130: CLOSING-LINE-VALUE PAPER BOT — the one copy-the-pros survivor (121: lay when Betfair is 20%+ shorter than Pinnacle:
# +52/+59 per £100 both halves, n 152). Live version: every 5 min, for every football match kicking off in the next 12 minutes
# that we can match between Betfair (MO catalogue, GB+IE+world) and API-Football (Pinnacle = bookmaker 4, "Match Winner"):
# record Betfair best back/lay vs Pinnacle H/D/A into clv_tape (ALL matches, so every band gets live data), and open a paper
# lay (£10 reference) in clv_paper when bf_lay/pinnacle - 1 <= -0.20 (plus the -0.10..-0.20 band flagged 'watch'). Settlement:
# nightly 05:40 from API-Football fixture results (same ids). Verdict after 30 settled trades in the -20% band -> £2 live.
mkdir -p /root/pe-clv && cat > /root/pe-clv/clv_bot.py <<'PYFILE'
import os, re, sys, time, json, datetime, unicodedata, requests, psycopg2, psycopg2.extras
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
sys.path.insert(0,'/root/pe-queue/runner'); import creds
APP_KEY,USER,PW=creds.betfair()
AF=None
for p in ('/root/pe-logger/.env','/root/pe-bot/.env'):
    if os.path.exists(p):
        m=re.search(r'^(?:API_?FOOTBALL_KEY|APIFOOTBALL_KEY|RAPIDAPI_KEY)=(.+)$',open(p).read(),re.M)
        if m: AF=m.group(1).strip().strip('"\''); break
if not AF: sys.exit("no API-Football key found in /root/pe-logger/.env")
AFH={"x-apisports-key":AF}
TOK=None; TOK_T=0
def login():
    global TOK,TOK_T
    r=requests.post("https://identitysso.betfair.com/api/login",data={"username":USER,"password":PW},headers={"X-Application":APP_KEY,"Accept":"application/json"},timeout=15).json()
    if r.get('status')!='SUCCESS': raise SystemExit("LOGIN FAILED: "+str(r))
    TOK=r['token']; TOK_T=time.time()
def api(ep,payload):
    if TOK is None or time.time()-TOK_T>3000: login()
    r=requests.post(f"https://api.betfair.com/exchange/betting/rest/v1.0/{ep}/",json=payload,headers={"X-Authentication":TOK,"X-Application":APP_KEY,"Content-Type":"application/json","Accept":"application/json"},timeout=20)
    r.raise_for_status(); return r.json()
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("""CREATE TABLE IF NOT EXISTS clv_tape (ts TIMESTAMPTZ DEFAULT now(), market_id TEXT, fixture_id BIGINT, event_name TEXT, competition TEXT, ko TIMESTAMPTZ, mins_to_ko INT,
  side TEXT, bf_back NUMERIC, bf_lay NUMERIC, pin NUMERIC, edge NUMERIC, total_matched NUMERIC, UNIQUE (market_id, side));
CREATE TABLE IF NOT EXISTS clv_paper (id SERIAL PRIMARY KEY, ts TIMESTAMPTZ DEFAULT now(), market_id TEXT, fixture_id BIGINT, event_name TEXT, competition TEXT, ko TIMESTAMPTZ, side TEXT, action TEXT,
  bf_lay NUMERIC, pin NUMERIC, edge NUMERIC, band TEXT, result TEXT, pnl_per_10 NUMERIC, settled_at TIMESTAMPTZ, UNIQUE (market_id, side));
CREATE TABLE IF NOT EXISTS clv_heartbeat (id INT PRIMARY KEY, last_seen TIMESTAMPTZ, matched_today INT, calls_today INT)""")
def norm(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
    s=re.sub(r"\b(fc|cf|afc|sc|ac|as|ss|us|sv|vfb|vfl|tsg|fk|nk|sk|bk|if|club|de|the|athletic|atletico|sporting|real|cd|ud|sd|rcd|women|u21|u19|u23|ii|b)\b"," ",s)
    s=re.sub(r"[^a-z0-9 ]"," ",s); return set(w for w in s.split() if len(w)>2)
def sim(a,b):
    A,B=norm(a),norm(b)
    return len(A&B)/max(1,len(A|B))
fixtures={}; fx_day=None; calls=0
def load_fixtures():
    global fixtures,fx_day,calls
    today=datetime.date.today()
    if fx_day==today and fixtures: return
    fixtures={}
    for d in (today,today+datetime.timedelta(days=1)):
        r=requests.get("https://v3.football.api-sports.io/fixtures",params={"date":d.isoformat()},headers=AFH,timeout=30).json(); calls+=1
        for f in r.get('response',[]):
            try: ko=datetime.datetime.fromisoformat(f['fixture']['date'].replace('Z','+00:00'))
            except Exception: continue
            fixtures[f['fixture']['id']]={'home':f['teams']['home']['name'],'away':f['teams']['away']['name'],'ko':ko,'league':f['league']['name']}
    fx_day=today; print("fixtures loaded",len(fixtures),flush=True)
def pinnacle(fid):
    global calls
    r=requests.get("https://v3.football.api-sports.io/odds",params={"fixture":fid,"bookmaker":4,"bet":1},headers=AFH,timeout=30).json(); calls+=1
    for b in r.get('response',[]):
        for bk in b.get('bookmakers',[]):
            for bet in bk.get('bets',[]):
                if bet.get('id')==1:
                    v={x['value']:float(x['odd']) for x in bet.get('values',[])}
                    if all(k in v for k in ('Home','Draw','Away')): return v
    return None
done=set(); last_hb=0
while True:
    try:
        load_fixtures(); now=datetime.datetime.now(datetime.timezone.utc)
        cat=api('listMarketCatalogue',{"filter":{"eventTypeIds":["1"],"marketTypeCodes":["MATCH_ODDS"],"marketStartTime":{"from":(now+datetime.timedelta(minutes=3)).isoformat(),"to":(now+datetime.timedelta(minutes=12)).isoformat()}},
                "marketProjection":["EVENT","COMPETITION","RUNNER_DESCRIPTION","MARKET_START_TIME"],"maxResults":200,"sort":"MAXIMUM_TRADED"})
        for m in cat:
            mid=m['marketId']
            if mid in done: continue
            ev=m['event']['name']; ko=datetime.datetime.fromisoformat(m['marketStartTime'].replace('Z','+00:00'))
            if ' v ' not in ev: done.add(mid); continue
            home,away=[x.strip() for x in ev.split(' v ',1)]
            # match to a fixture within 30 min of KO by team-name similarity
            best=None;bs=0
            for fid,f in fixtures.items():
                if abs((f['ko']-ko).total_seconds())>1800: continue
                s=sim(home,f['home'])+sim(away,f['away'])
                if s>bs: bs=s; best=fid
            if best is None or bs<1.0: done.add(mid); continue
            pin=pinnacle(best)
            if not pin: done.add(mid); continue
            mb=api('listMarketBook',{"marketIds":[mid],"priceProjection":{"priceData":["EX_BEST_OFFERS"]}})[0]
            names={r['selectionId']:r['runnerName'] for r in m['runners']}
            tm=mb.get('totalMatched') or 0; mins=int((ko-now).total_seconds()/60)
            for r in mb.get('runners',[]):
                nm=names.get(r['selectionId'],''); side='D' if nm.lower() in ('the draw','draw') else ('H' if sim(nm,home)>=sim(nm,away) else 'A')
                ex=r.get('ex',{}); b=ex.get('availableToBack',[]); l=ex.get('availableToLay',[])
                if not b or not l: continue
                pp=pin['Home' if side=='H' else 'Draw' if side=='D' else 'Away']; edge=l[0]['price']/pp-1
                cur.execute("INSERT INTO clv_tape (market_id,fixture_id,event_name,competition,ko,mins_to_ko,side,bf_back,bf_lay,pin,edge,total_matched) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) ON CONFLICT DO NOTHING",
                            (mid,best,ev,(m.get('competition') or {}).get('name',''),ko,mins,side,b[0]['price'],l[0]['price'],pp,round(edge,4),tm))
                band='lay-20' if edge<=-0.20 else ('watch-10' if edge<=-0.10 else ('back+6' if edge>=0.06 else None))
                if band:
                    cur.execute("INSERT INTO clv_paper (market_id,fixture_id,event_name,competition,ko,side,action,bf_lay,pin,edge,band) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) ON CONFLICT DO NOTHING",
                                (mid,best,ev,(m.get('competition') or {}).get('name',''),ko,side,'LAY' if band!='back+6' else 'BACK',l[0]['price'] if band!='back+6' else b[0]['price'],pp,round(edge,4),band))
                    print(f"PAPER {band} {ev} {side} bf {l[0]['price'] if band!='back+6' else b[0]['price']} pin {pp} edge {edge:+.1%}",flush=True)
            done.add(mid)
        if time.time()-last_hb>60:
            cur.execute("INSERT INTO clv_heartbeat VALUES (1,now(),%s,%s) ON CONFLICT (id) DO UPDATE SET last_seen=now(), matched_today=EXCLUDED.matched_today, calls_today=EXCLUDED.calls_today",(len(done),calls)); last_hb=time.time()
        time.sleep(300)
    except Exception as e:
        print("loop",repr(e)[:200],flush=True); time.sleep(60)
        try: con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
        except Exception: pass
PYFILE
cat > /root/pe-clv/settle.py <<'PYFILE'
import os, re, sys, requests, psycopg2
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
AF=None
for p in ('/root/pe-logger/.env','/root/pe-bot/.env'):
    if os.path.exists(p):
        m=re.search(r'^(?:API_?FOOTBALL_KEY|APIFOOTBALL_KEY|RAPIDAPI_KEY)=(.+)$',open(p).read(),re.M)
        if m: AF=m.group(1).strip().strip('"\''); break
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("SELECT id, fixture_id, side, action, bf_lay FROM clv_paper WHERE result IS NULL AND ko < now()-interval '3 hours'")
for id_,fid,side,action,px in cur.fetchall():
    r=requests.get("https://v3.football.api-sports.io/fixtures",params={"id":fid},headers={"x-apisports-key":AF},timeout=30).json()
    try:
        f=r['response'][0]; st=f['fixture']['status']['short']
        if st not in ('FT','AET','PEN'): continue
        hg,ag=f['goals']['home'],f['goals']['away']; res='H' if hg>ag else 'A' if hg<ag else 'D'
    except Exception: continue
    won=(res==side); px=float(px)
    pnl=( (px-1)*10*0.98 if won else -10.0 ) if action=='BACK' else ( -(px-1)*10 if won else 10*0.98 )
    cur.execute("UPDATE clv_paper SET result=%s, pnl_per_10=%s, settled_at=now() WHERE id=%s",(res,round(pnl,2),id_))
cur.execute("SELECT band, count(*), count(*) FILTER (WHERE result IS NOT NULL) settled, round(sum(pnl_per_10)::numeric,2) FROM clv_paper GROUP BY 1 ORDER BY 1"); print("CLV paper:",cur.fetchall())
PYFILE
python3 -m py_compile /root/pe-clv/clv_bot.py /root/pe-clv/settle.py || exit 1
cat > /root/pe-clv/keepalive.sh <<'SH'
#!/bin/bash
pgrep -f clv_bot.py >/dev/null || (cd /root/pe-clv && nohup python3 clv_bot.py >> clv.log 2>&1 &)
SH
chmod +x /root/pe-clv/keepalive.sh
( crontab -l 2>/dev/null | grep -v pe-clv ; echo "* * * * * /root/pe-clv/keepalive.sh" ; echo "40 5 * * * cd /root/pe-clv && python3 settle.py >> clv.log 2>&1" ) | crontab -
/root/pe-clv/keepalive.sh; sleep 60; pgrep -af clv_bot.py; tail -5 /root/pe-clv/clv.log
