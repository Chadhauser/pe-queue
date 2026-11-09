#!/bin/bash
# 538 (Mon 9 Nov 2026). BOOKIE v2 — the bot the one job describes, in the right order this time.
# v1.1 quoted both sides of every market, in-play included, and its first settled line was -£260 on 1,436 Betfair fills (-9p per £2):
# a two-sided maker is filled by the people who know the price is about to move. Stopped here.
# v2 rules, enforced in code:
#   1. NO QUOTE WITHOUT A PASSED CELL. The Verifier alone writes fair_price_passed (verifier_cells.py, every 30 min) from the fair-price
#      map: n_is>=300, n_oos>=100, the market's error has the SAME SIGN in both halves, |error| >= 1 point of probability in-sample and
#      0.5 out. The bot reads that table and nothing else. Empty table = bot quotes nothing and says so.
#   2. ONE SIDE ONLY, the side the cell says: market too long -> BACK; too short -> LAY. Never both.
#   3. PRE-OFF ONLY (the map is built on closing prices): markets kicking off in the next 60 minutes, read straight from Betfair
#      (listMarketCatalogue + listMarketBook every 20 s, selection ids, no name matching), until the in-play map has its own verdict.
#   4. MAKER inside the spread and on the right side of fair: a BACK quote must sit at or above the fair price, a LAY at or below it;
#      both sides of the book >= £10, spread <= 3 ticks, price <= 20, market matched >= £2,000. £2. One quote per runner per 5 min, 10-min life.
#   5. Paper fill one tick adverse (BACK at P fills when best back later >= P+1 tick; LAY at L when best lay later <= L-1 tick).
#      Settlement on the official runner status (CLOSED), 2% commission on net wins. version='v2', exchange='betfair'.
# Reported: settled £ per £100 only. Fills are not news.
set -o pipefail
export PYTHONDONTWRITEBYTECODE=1
echo "== stop the two-sided legs (v1.1) =="
pkill -f 'bookie_paper.py'; pkill -f 'bookie_xx.py'; rm -f /root/pe-sports/bookie/.ready
( crontab -l 2>/dev/null | grep -v 'pe-sports/bookie/run_bookie.sh\|pe-sports/bookie/run_bookie_xx.sh' ) | crontab -
echo "v1.1 Betfair, Matchbook and Smarkets legs stopped (keepalives removed); their rows stay for the record"
echo "== Verifier: passed cells table =="
cd /root/pe-sports/team && cat > verifier_cells.py <<'PY'
# verifier_cells (538): the ONLY writer of fair_price_passed. A cell passes when the market's error (actual rate - implied) has the same sign
# in both halves of the data, is at least 1 point in-sample and 0.5 out, with n_is>=300 and n_oos>=100. The bot quotes only these.
import sys, datetime, psycopg2
sys.path.insert(0,'/root/pe-queue/runner'); import creds
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; c=con.cursor()
c.execute("""CREATE TABLE IF NOT EXISTS fair_price_passed (market_type TEXT, band_lo NUMERIC, band_hi NUMERIC, side TEXT, fair_factor NUMERIC,
  n_is INT, n_oos INT, edge_is NUMERIC, edge_oos NUMERIC, source TEXT, passed_at TIMESTAMPTZ DEFAULT now(), PRIMARY KEY (market_type, band_lo, source))""")
c.execute("""SELECT market_type, band_lo, band_hi, fair_factor, n_is, n_oos, rate_is-p_mean_is AS e_is, rate_oos-p_mean_oos AS e_oos FROM fair_price_calib
             WHERE n_is>=300 AND n_oos>=100 AND rate_oos IS NOT NULL""")
rows=c.fetchall(); c.execute("DELETE FROM fair_price_passed WHERE source='H1'"); n=0
for mt,lo,hi,f,nis,noos,eis,eoos in rows:
    if eis is None or eoos is None: continue
    if (eis>0)==(eoos>0) and abs(eis)>=0.01 and abs(eoos)>=0.005:
        side='BACK' if eis>0 else 'LAY'   # market under-rates the runner -> back it; over-rates -> lay it
        c.execute("INSERT INTO fair_price_passed (market_type,band_lo,band_hi,side,fair_factor,n_is,n_oos,edge_is,edge_oos,source) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,'H1')",(mt,lo,hi,side,f,nis,noos,round(float(eis),4),round(float(eoos),4))); n+=1
c.execute("SELECT market_type, band_lo, band_hi, side, n_is, edge_is, edge_oos FROM fair_price_passed ORDER BY 1,2")
print(f"{datetime.datetime.utcnow():%Y-%m-%d %H:%M} passed cells: {n}"); [print("  ",r) for r in c.fetchall()]
PY
python3 -m py_compile verifier_cells.py && python3 verifier_cells.py
( crontab -l 2>/dev/null | grep -v 'verifier_cells.py'; echo "*/30 * * * * /usr/bin/python3 /root/pe-sports/team/verifier_cells.py >> /root/pe-sports/team/verifier_cells.log 2>&1" ) | crontab -
echo "== bookie v2 =="
cd /root/pe-sports/bookie && cat > bookie_v2.py <<'PY'
# BOOKIE v2 (538, 9 Nov 2026) — one-sided, map-driven, pre-off, Betfair direct. See jobs/538 header for the rules. Nothing quotes without a passed cell.
import sys, time, datetime, traceback, requests, psycopg2
sys.path.insert(0,'/root/pe-liq'); sys.path.insert(0,'/root/pe-queue/runner')
try: import bf_chunk   # catalogue overflow guard (532)
except Exception: pass
import creds
STAKE=2.0; COMM=0.02; TTL=600; REQUOTE=300; MIN_MATCHED=2000.0; MIN_SIZE=10.0; MAX_PRICE=20.0; MAX_SPREAD=3; HORIZON_MIN=60; VERSION='v2'
LADDER=[(2,0.01),(3,0.02),(4,0.05),(6,0.1),(10,0.2),(20,0.5),(30,1),(50,2),(100,5),(1000,10)]
def tick(p):
    for lim,inc in LADDER:
        if p<lim: return inc
    return 10
def tick_down(p): return round(max(1.01,p-tick(p-1e-9)),2)
def tick_up(p): return round(min(1000,p+tick(p)),2)
def nticks(a,b):
    n=0; p=a
    while p<b-1e-9 and n<50: p=tick_up(p); n+=1
    return n
def log(m):
    with open('/root/pe-sports/bookie/bookie_v2.log','a') as f: f.write(f"{datetime.datetime.utcnow():%Y-%m-%d %H:%M:%S} {m}\n")
L=psycopg2.connect(creds.pg_local()); L.autocommit=True; lc=L.cursor()
lc.execute("ALTER TABLE bookie_paper ADD COLUMN IF NOT EXISTS exchange TEXT DEFAULT 'betfair'; ALTER TABLE bookie_paper ADD COLUMN IF NOT EXISTS bf_market_id TEXT; ALTER TABLE bookie_paper ADD COLUMN IF NOT EXISTS start_ts TIMESTAMPTZ; ALTER TABLE bookie_paper ADD COLUMN IF NOT EXISTS fair NUMERIC")
APP,USER,PW=creds.betfair(); SSO=None; SSO_T=0
def login():
    global SSO,SSO_T
    r=requests.post("https://identitysso.betfair.com/api/login",data={"username":USER,"password":PW},headers={"X-Application":APP,"Accept":"application/json"},timeout=20).json()
    if r.get('status')=='SUCCESS': SSO=r['token']; SSO_T=time.time(); return True
    log(f"login failed {r.get('error')}"); return False
def api(ep,body):
    if SSO is None or time.time()-SSO_T>3*3600:
        if not login(): return []
    r=requests.post(f"https://api.betfair.com/exchange/betting/rest/v1.0/{ep}/",json=body,headers={"X-Application":APP,"X-Authentication":SSO,"Content-Type":"application/json"},timeout=25)
    if r.status_code!=200: log(f"{ep} {r.status_code} {r.text[:120]}"); return []
    return r.json()
def cells():
    lc.execute("SELECT market_type, band_lo, band_hi, side, fair_factor FROM fair_price_passed"); C={}
    for mt,lo,hi,side,f in lc.fetchall(): C.setdefault(mt,[]).append((float(lo),float(hi),side,float(f)))
    return C
def cell_for(C,mt,p):
    for lo,hi,side,f in C.get(mt,[]):
        if lo<=p<hi: return side,f
    return None,None
cat={}; cat_t=0; last_quote={}; C={}; C_t=0
while True:
    try:
        now=time.time()
        if now-C_t>600: C=cells(); C_t=now; log(f"passed cells {sum(len(v) for v in C.values())} over types {sorted(C)}")
        if not C: time.sleep(60); continue
        if now-cat_t>300:   # universe: soccer markets of passed types kicking off in the next HORIZON_MIN
            t0=datetime.datetime.utcnow(); f={"eventTypeIds":["1"],"marketTypeCodes":sorted(C),"marketStartTime":{"from":t0.strftime('%Y-%m-%dT%H:%M:%SZ'),"to":(t0+datetime.timedelta(minutes=HORIZON_MIN)).strftime('%Y-%m-%dT%H:%M:%SZ')}}
            cat={m['marketId']:m for m in api('listMarketCatalogue',{"filter":f,"marketProjection":["EVENT","MARKET_START_TIME","MARKET_DESCRIPTION"],"maxResults":200})}
            cat_t=now
        mids=list(cat)
        books={}
        for i in range(0,len(mids),40):
            for b in api('listMarketBook',{"marketIds":mids[i:i+40],"priceProjection":{"priceData":["EX_BEST_OFFERS"]}}): books[b['marketId']]=b
        # fills one tick adverse on open v2 quotes
        lc.execute("SELECT id, market_id, sel, side, price FROM bookie_paper WHERE version=%s AND status='open'",(VERSION,)); filled=0
        for oid,mid,sel,side,price in lc.fetchall():
            b=books.get(mid)
            if not b: continue
            r=next((r for r in b.get('runners',[]) if str(r['selectionId'])==sel),None)
            if not r: continue
            bb=(r.get('ex',{}).get('availableToBack') or [{}])[0].get('price'); bl=(r.get('ex',{}).get('availableToLay') or [{}])[0].get('price'); price=float(price)
            if side=='BACK' and bb and bb>=tick_up(price): lc.execute("UPDATE bookie_paper SET status='filled', fill_ts=now(), fill_price=%s, fill_kind='maker' WHERE id=%s",(price,oid)); filled+=1
            elif side=='LAY' and bl and bl<=tick_down(price): lc.execute("UPDATE bookie_paper SET status='filled', fill_ts=now(), fill_price=%s, fill_kind='maker' WHERE id=%s",(price,oid)); filled+=1
        lc.execute("UPDATE bookie_paper SET status='expired' WHERE version=%s AND status='open' AND ts<now()-interval '%s seconds'"%("%s",TTL),(VERSION,))
        lc.execute("SELECT market_id, sel FROM bookie_paper WHERE version=%s AND status='open'",(VERSION,)); have={(a,b) for a,b in lc.fetchall()}
        quoted=0
        for mid,b in books.items():
            m=cat.get(mid); mt=(m.get('description') or {}).get('marketType') if m else None
            if not m or mt not in C or b.get('status')!='OPEN' or b.get('inplay') or float(b.get('totalMatched') or 0)<MIN_MATCHED: continue
            rs=b.get('runners',[]); px={}
            for r in rs:
                ex=r.get('ex',{}); bb=(ex.get('availableToBack') or [{}])[0]; bl=(ex.get('availableToLay') or [{}])[0]
                if bb.get('price') and bl.get('price'): px[str(r['selectionId'])]=(float(bb['price']),float(bb.get('size',0)),float(bl['price']),float(bl.get('size',0)),float(r.get('lastPriceTraded') or 0))
            if len(px)<2: continue
            mids_=[(bb+bl)/2 for bb,_,bl,_,_ in px.values()]; tot=sum(1/x for x in mids_ if x>1)
            if tot<=0: continue
            for sid,(bb,bsz,bl,lsz,ltp) in px.items():
                if bl<=bb or bsz<MIN_SIZE or lsz<MIN_SIZE or bl>MAX_PRICE or nticks(bb,bl)>MAX_SPREAD: continue
                p=(1/((bb+bl)/2))/tot; side,f=cell_for(C,mt,p)
                if side is None: continue
                fair=1/max(0.005,min(0.995,p*f))
                key=(mid,sid)
                if now-last_quote.get(key,0)<REQUOTE or key in have: continue
                nt=nticks(bb,bl); q=None
                if side=='BACK':
                    qb=tick_up(bb) if nt>=2 else bb
                    if qb>=fair and qb<bl: q=('BACK',qb)
                else:
                    ql=tick_down(bl) if nt>=2 else bl
                    if ql<=fair and ql>bb: q=('LAY',ql)
                if not q: continue
                lc.execute("INSERT INTO bookie_paper (ts,market_id,event_name,mkt,sel,side,price,fair,mkt_back,mkt_lay,stake,status,version,exchange,bf_market_id,start_ts) VALUES (now(),%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,'open',%s,'betfair',%s,%s)",
                           (mid,(m.get('event') or {}).get('name'),mt,sid,q[0],q[1],round(fair,3),bb,bl,STAKE,VERSION,mid,m.get('marketStartTime')))
                last_quote[key]=now; quoted+=1
        # settlement: filled v2 rows whose market is CLOSED
        lc.execute("SELECT DISTINCT market_id FROM bookie_paper WHERE version=%s AND status='filled'",(VERSION,)); due=[m for (m,) in lc.fetchall()][:40]; settled=0
        if due:
            for b in api('listMarketBook',{"marketIds":due}):
                if b.get('status')!='CLOSED': continue
                st={str(r['selectionId']):r.get('status') for r in b.get('runners',[])}
                lc.execute("SELECT id, sel, side, fill_price, stake FROM bookie_paper WHERE version=%s AND market_id=%s AND status='filled'",(VERSION,b['marketId']))
                for oid,sel,side,fp,stk in lc.fetchall():
                    s=st.get(sel)
                    if s not in ('WINNER','LOSER'): lc.execute("UPDATE bookie_paper SET status='unsettleable', settled_ts=now() WHERE id=%s",(oid,)); continue
                    fp=float(fp); stk=float(stk); won=1 if s=='WINNER' else 0
                    gross=((fp-1)*stk if won else -stk) if side=='BACK' else (-(fp-1)*stk if won else stk)
                    pnl=gross*(1-COMM) if gross>0 else gross
                    lc.execute("UPDATE bookie_paper SET status='settled', won=%s, pnl=%s, settled_ts=now() WHERE id=%s",(won,round(pnl,4),oid)); settled+=1
        lc.execute("SELECT count(*) FILTER (WHERE status='open'), count(*) FILTER (WHERE status IN ('filled','settled')) FROM bookie_paper WHERE version=%s",(VERSION,)); o,fl=lc.fetchone()
        lc.execute("INSERT INTO bookie_heartbeat VALUES (2,now(),%s,%s) ON CONFLICT (id) DO UPDATE SET last_seen=now(), open_orders=excluded.open_orders, fills=excluded.fills",(o,fl))
        if quoted or filled or settled: log(f"universe {len(cat)} books {len(books)} quoted {quoted} filled {filled} settled {settled} open {o}")
    except Exception:
        log(traceback.format_exc()[-500:]); time.sleep(30)
    time.sleep(20)
PY
python3 -m py_compile bookie_v2.py && echo "bookie_v2 compiles"
cat > run_bookie_v2.sh <<'SH'
#!/bin/bash
cd /root/pe-sports/bookie && while true; do python3 bookie_v2.py >> bookie_v2.out 2>&1; sleep 15; done
SH
chmod +x run_bookie_v2.sh
( crontab -l 2>/dev/null | grep -v 'run_bookie_v2.sh'; echo "*/5 * * * * pgrep -f 'bookie_v2.py' >/dev/null || nohup /root/pe-sports/bookie/run_bookie_v2.sh >/dev/null 2>&1 &" ) | crontab -
nohup /root/pe-sports/bookie/run_bookie_v2.sh >/dev/null 2>&1 & disown
sleep 90; echo "v2 pids: $(pgrep -f bookie_v2.py | wc -l)"; tail -5 /root/pe-sports/bookie/bookie_v2.log; tail -3 /root/pe-sports/bookie/bookie_v2.out
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
c=psycopg2.connect(creds.pg_local()).cursor()
c.execute("select count(*) from fair_price_passed"); print("passed cells:",c.fetchone()[0])
c.execute("select status,count(*) from bookie_paper where version='v2' group by 1"); print("v2 rows by status:",c.fetchall())
PY
echo "== scoreboard: money and the bookie line count v2 only =="
cd /root/pe-sports/team && cp sports_team.py sports_team.py.bak_538 && sed -i "s/version='v1.1'/version='v2'/g; s/version=%s/version=%s/" sports_team.py && grep -c "version='v2'" sports_team.py && python3 -m py_compile sports_team.py && pkill -f 'sports_team.py'; sleep 2; nohup /root/pe-sports/team/run_team.sh >/dev/null 2>&1 & disown
echo "538 done — v1.1 stopped; v2 quotes only on passed cells, one side, pre-off; settled £ per £100 is the only number reported"
