#!/bin/bash
# 144: CRICKET FAVOURITE PAPER BOT — the Factory's confirmed survivors (23 Oct, 2 ticks required): back the 1.0-1.3 favourite when it
# drifts to 1.5x its off price (+60 per £100 both halves, n 430) ; lay the 1.0-1.3 favourite at the off, green at +20% (+3.7/+1.9,
# n 1,464). Live paper on our own feed to confirm before any stake: every 30s, cricket MATCH_ODDS markets from 10 min before the
# off: record the favourite's price; SP = last price before in-play; in-play, E fires when LTP >= 1.5x SP on two consecutive samples
# (paper BACK £10 at the second), F opens a paper LAY £10 at SP for every qualifying fav and greens when LTP >= 1.2x SP two
# consecutive (hedge at the second), else settles. Settlement nightly 05:55 from CLOSED market runner status. 30 settled E trades
# and 60 F trades before a verdict; £2 live if both halves of the live book are positive.
mkdir -p /root/pe-cricket && cat > /root/pe-cricket/fav_paper.py <<'PYFILE'
import sys, time, datetime, requests, psycopg2
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
sys.path.insert(0,'/root/pe-queue/runner'); import creds
APP_KEY,USER,PW=creds.betfair(); TOK=None; TOK_T=0
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
cur.execute("""CREATE TABLE IF NOT EXISTS cricket_fav_tape (ts TIMESTAMPTZ DEFAULT now(), market_id TEXT, event_name TEXT, competition TEXT, start_time TIMESTAMPTZ, inplay BOOLEAN, sel_id BIGINT, sel_name TEXT, ltp NUMERIC, back_px NUMERIC, lay_px NUMERIC, total_matched NUMERIC);
CREATE INDEX IF NOT EXISTS cricket_fav_tape_m ON cricket_fav_tape (market_id, ts);
CREATE TABLE IF NOT EXISTS cricket_fav_paper (id SERIAL PRIMARY KEY, ts TIMESTAMPTZ DEFAULT now(), market_id TEXT, event_name TEXT, competition TEXT, sel_id BIGINT, sel_name TEXT, rule TEXT, sp NUMERIC,
  entry_px NUMERIC, exit_px NUMERIC, exit_reason TEXT, result TEXT, pnl_per_10 NUMERIC, settled_at TIMESTAMPTZ, UNIQUE (market_id, rule));
CREATE TABLE IF NOT EXISTS cricket_heartbeat (id INT PRIMARY KEY, last_seen TIMESTAMPTZ, tracked INT)""")
state={}   # mid -> dict(fav, sp, names, inplay_seen, path[], e_open, f_open, start, ev, comp)
def hb(n):
    cur.execute("INSERT INTO cricket_heartbeat VALUES (1,now(),%s) ON CONFLICT (id) DO UPDATE SET last_seen=now(), tracked=EXCLUDED.tracked",(n,))
last_cat=0
while True:
    try:
        now=datetime.datetime.now(datetime.timezone.utc)
        if time.time()-last_cat>120:
            cat=api('listMarketCatalogue',{"filter":{"eventTypeIds":["4"],"marketTypeCodes":["MATCH_ODDS"],"marketStartTime":{"from":(now-datetime.timedelta(hours=9)).isoformat(),"to":(now+datetime.timedelta(minutes=10)).isoformat()}},
                    "marketProjection":["EVENT","COMPETITION","RUNNER_DESCRIPTION","MARKET_START_TIME"],"maxResults":60})
            for m in cat:
                if m['marketId'] not in state:
                    state[m['marketId']]=dict(names={r['selectionId']:r['runnerName'] for r in m['runners']},ev=m['event']['name'],comp=(m.get('competition') or {}).get('name',''),
                                              start=datetime.datetime.fromisoformat(m['marketStartTime'].replace('Z','+00:00')),fav=None,sp=None,inplay_seen=False,path=[],e_open=False,f_open=None,done=False)
            last_cat=time.time()
        live=[mid for mid,s in state.items() if not s['done']]
        for i in range(0,len(live),10):
            for b in api('listMarketBook',{"marketIds":live[i:i+10],"priceProjection":{"priceData":["EX_BEST_OFFERS"]}}):
                mid=b['marketId']; s=state[mid]; st=b.get('status'); inplay=bool(b.get('inplay'))
                if st=='CLOSED': s['done']=True; continue
                rs=[r for r in b.get('runners',[]) if r.get('status')=='ACTIVE' and r.get('lastPriceTraded')]
                if len(rs)<2: continue
                fav=min(rs,key=lambda r:r['lastPriceTraded']);
                for r in rs:
                    ex=r.get('ex',{}); bk=ex.get('availableToBack',[]); ly=ex.get('availableToLay',[])
                    cur.execute("INSERT INTO cricket_fav_tape (market_id,event_name,competition,start_time,inplay,sel_id,sel_name,ltp,back_px,lay_px,total_matched) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",
                                (mid,s['ev'],s['comp'],s['start'],inplay,r['selectionId'],s['names'].get(r['selectionId'],''),r['lastPriceTraded'],bk[0]['price'] if bk else None,ly[0]['price'] if ly else None,b.get('totalMatched')))
                if not inplay:
                    s['fav']=fav['selectionId']; s['sp']=float(fav['lastPriceTraded']); continue
                if s['sp'] is None or s['fav'] is None: continue
                if not s['inplay_seen']:
                    s['inplay_seen']=True
                    if 1.0<s['sp']<=1.3:   # F: paper lay fav at SP
                        cur.execute("INSERT INTO cricket_fav_paper (market_id,event_name,competition,sel_id,sel_name,rule,sp,entry_px) VALUES (%s,%s,%s,%s,%s,'F lay fav at SP green +20pct',%s,%s) ON CONFLICT DO NOTHING",(mid,s['ev'],s['comp'],s['fav'],s['names'].get(s['fav'],''),s['sp'],s['sp']))
                        s['f_open']=True; print(f"F LAY {s['ev']} fav {s['names'].get(s['fav'])} @ {s['sp']}",flush=True)
                fr=[r for r in rs if r['selectionId']==s['fav']]
                if not fr: continue
                p=float(fr[0]['lastPriceTraded']); s['path'].append(p); path=s['path']
                if len(path)>=2:
                    if s['f_open'] and path[-1]>=1.2*s['sp'] and path[-2]>=1.2*s['sp']:
                        x=path[-1]; pnl=(1-s['sp']/x)*10*0.98
                        cur.execute("UPDATE cricket_fav_paper SET exit_px=%s, exit_reason='GREEN', pnl_per_10=%s, settled_at=now(), result='HEDGED' WHERE market_id=%s AND rule LIKE 'F %%'",(x,round(pnl,2),mid)); s['f_open']=False; print(f"F GREEN {s['ev']} {s['sp']}->{x} {pnl:+.2f}",flush=True)
                    if (not s['e_open']) and 1.0<s['sp']<=1.3 and path[-1]>=1.5*s['sp'] and path[-2]>=1.5*s['sp']:
                        cur.execute("INSERT INTO cricket_fav_paper (market_id,event_name,competition,sel_id,sel_name,rule,sp,entry_px) VALUES (%s,%s,%s,%s,%s,'E back fav at 1.5x SP confirmed',%s,%s) ON CONFLICT DO NOTHING",(mid,s['ev'],s['comp'],s['fav'],s['names'].get(s['fav'],''),s['sp'],path[-1]))
                        s['e_open']=True; print(f"E BACK {s['ev']} fav {s['names'].get(s['fav'])} SP {s['sp']} @ {path[-1]}",flush=True)
        hb(len(live)); time.sleep(30)
    except Exception as e:
        print("loop",repr(e)[:200],flush=True); time.sleep(60)
        try: con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
        except Exception: pass
PYFILE
cat > /root/pe-cricket/settle.py <<'PYFILE'
import sys, requests, psycopg2
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
sys.path.insert(0,'/root/pe-queue/runner'); import creds
APP_KEY,USER,PW=creds.betfair()
r=requests.post("https://identitysso.betfair.com/api/login",data={"username":USER,"password":PW},headers={"X-Application":APP_KEY,"Accept":"application/json"},timeout=15).json(); TOK=r['token']
def api(ep,payload):
    r=requests.post(f"https://api.betfair.com/exchange/betting/rest/v1.0/{ep}/",json=payload,headers={"X-Authentication":TOK,"X-Application":APP_KEY,"Content-Type":"application/json","Accept":"application/json"},timeout=20); r.raise_for_status(); return r.json()
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("SELECT DISTINCT market_id FROM cricket_fav_paper WHERE result IS NULL"); mids=[x[0] for x in cur.fetchall()]
for i in range(0,len(mids),10):
    for b in api('listMarketBook',{"marketIds":mids[i:i+10]}):
        if b.get('status')!='CLOSED': continue
        for rr in b.get('runners',[]):
            st=rr.get('status')
            if st not in ('WINNER','LOSER'): continue
            # E: back at entry_px -> win (entry-1)*10*0.98 else -10 ; F (unhedged): lay at sp -> fav wins: -(sp-1)*10 else +9.8
            cur.execute("""UPDATE cricket_fav_paper SET result=%s, settled_at=now(),
                pnl_per_10=CASE WHEN rule LIKE 'E %%' THEN (CASE WHEN %s='WINNER' THEN (entry_px-1)*10*0.98 ELSE -10 END)
                                ELSE (CASE WHEN %s='WINNER' THEN -(sp-1)*10 ELSE 9.8 END) END
                WHERE market_id=%s AND sel_id=%s AND result IS NULL""",(st,st,st,b['marketId'],rr['selectionId']))
cur.execute("SELECT rule, count(*) n, count(pnl_per_10) settled, round(sum(pnl_per_10)::numeric,2) pnl FROM cricket_fav_paper GROUP BY 1"); print("CRICKET FAV paper:",cur.fetchall())
PYFILE
python3 -m py_compile /root/pe-cricket/fav_paper.py /root/pe-cricket/settle.py || exit 1
cat > /root/pe-cricket/keepalive.sh <<'SH'
#!/bin/bash
pgrep -f fav_paper.py >/dev/null || (cd /root/pe-cricket && nohup python3 fav_paper.py >> cricket.log 2>&1 &)
SH
chmod +x /root/pe-cricket/keepalive.sh
( crontab -l 2>/dev/null | grep -v pe-cricket ; echo "* * * * * /root/pe-cricket/keepalive.sh" ; echo "55 5 * * * cd /root/pe-cricket && python3 settle.py >> cricket.log 2>&1" ; echo "45 4 * * * cd /root/pe-cricket && python3 -c \"import sys,psycopg2;sys.path.insert(0,'/root/pe-bot');from bot_core import DB;c=psycopg2.connect(DB,sslmode='require');c.autocommit=True;c.cursor().execute(\\\"DELETE FROM cricket_fav_tape WHERE ts<now()-interval '14 days'\\\")\" >> cricket.log 2>&1" ) | crontab -
/root/pe-cricket/keepalive.sh; sleep 75; pgrep -af fav_paper.py; tail -5 /root/pe-cricket/cricket.log
