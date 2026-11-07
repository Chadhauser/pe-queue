#!/bin/bash
# 531: the Smarkets/Matchbook leg quoted NOTHING in 24 h (no rows, empty log). Cause: xx_tape stamps each runner with its own ts, so the
# "latest snapshot" join on an exact ts kept one runner per market and every book failed the two-runner test. Now: latest row per
# runner in the last 90 s. Also maps Smarkets "Full-time result" -> MO and "Half-time result" -> HT_MO (Matchbook uses "Match Odds").
set -o pipefail
cd /root/pe-sports/bookie && cp bookie_xx.py bookie_xx.py.bak_531
cat > bookie_xx.py <<'PYFILE'
# BOOKIE PAPER BOT — SMARKETS / MATCHBOOK LEGS (THE ONE JOB step 2b, 6 Nov 2026: "resting-order bot across Betfair, Matchbook and Smarkets").
# Same maker-only rules as bookie_paper.py (Betfair), applied to the cross-exchange tape xx_tape (Railway): quote one tick inside the
# spread (or join the touch) on every runner of every two-sided football book, £2 nominal, one quote pair per runner per 5 min, 10-min life.
# Snapshot: latest row per runner in the last 90 s (xx_tape stamps each runner separately, so a join on an exact ts kept one runner per market and quoted nothing for 24 h — 531).
# Fill (one tick adverse): BACK at P fills when a later sample on THAT exchange shows back_px >= P+1 tick; LAY at L when lay_px <= L-1 tick.
# Settlement: the Betfair official result for the same game — the event is matched to a Betfair market on the tape (liq_sample) by
# normalised event name + market type + kick-off day, runner ids via liq_runners, result via listMarketBook. Rows carry exchange and
# version='v1'; the Verifier reports per exchange. Commission: Smarkets 2%, Matchbook 2% (paper assumption, stated).
import sys, time, datetime, traceback, re, requests, psycopg2
sys.path.insert(0,'/root/pe-queue/runner'); import creds
STAKE=2.0; COMM={'smarkets':0.02,'matchbook':0.02}; TTL=600; REQUOTE=300; BATCH=40; MAX_PRICE=20.0; MAX_SPREAD_TICKS=3; MIN_SIZE=10.0; VERSION='v1.1'
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
def norm(x): return re.sub(r'[^a-z0-9]','',re.sub(r'\b(fc|cf|afc|sc|ac|the)\b','',str(x).lower()))
def ev_key(name):
    s=re.split(r'\s+v(?:s\.?)?\s+|\s+-\s+',str(name),maxsplit=1)
    return (norm(s[0]),norm(s[1])) if len(s)==2 else (norm(name),'')
MKT={'match odds':'MO','full-time result':'MO','full time result':'MO','half-time result':'HT_MO','over/under 2.5 goals':'OU25','over/under 1.5 goals':'OU15','over/under 3.5 goals':'OU35','over/under 0.5 goals':'OU05','over/under 4.5 goals':'OU45','both teams to score':'BTTS','draw no bet':'DNB','half time':'HT_MO'}
def mkt_code(market_name):
    m=str(market_name).lower().strip()
    for k,v in MKT.items():
        if k in m: return v
    return None
def log(m):
    with open('/root/pe-sports/bookie/bookie_xx.log','a') as f: f.write(f"{datetime.datetime.utcnow():%Y-%m-%d %H:%M:%S} {m}\n")
L=psycopg2.connect(creds.pg_local(),sslmode='prefer'); L.autocommit=True; lc=L.cursor()
lc.execute("ALTER TABLE bookie_paper ADD COLUMN IF NOT EXISTS exchange TEXT DEFAULT 'betfair'; ALTER TABLE bookie_paper ADD COLUMN IF NOT EXISTS bf_market_id TEXT")
lc.execute("CREATE INDEX IF NOT EXISTS bookie_paper_exch ON bookie_paper (exchange, status)")
APP,USER,PW=creds.betfair(); SSO=None; SSO_T=0
def login():
    global SSO,SSO_T
    r=requests.post("https://identitysso.betfair.com/api/login",data={"username":USER,"password":PW},headers={"X-Application":APP,"Accept":"application/json"},timeout=20).json()
    if r.get('status')=='SUCCESS': SSO=r['token']; SSO_T=time.time(); return True
    log(f"login failed {r.get('error')}"); return False
def bf_post(ep,body):
    if SSO is None or time.time()-SSO_T>3*3600:
        if not login(): return []
    r=requests.post(f"https://api.betfair.com/exchange/betting/rest/v1.0/{ep}/",json=body,headers={"X-Application":APP,"X-Authentication":SSO,"Content-Type":"application/json"},timeout=25)
    if r.status_code!=200: log(f"{ep} {r.status_code} {r.text[:120]}"); return []
    return r.json()
def rconn(): return psycopg2.connect(creds.pg_railway(),sslmode='require',connect_timeout=20)
R=None; last_quote={}; bfmap={}; bfmap_t=0
while True:
    try:
        if R is None or R.closed: R=rconn()
        rc=R.cursor(); rc.execute("SET statement_timeout='40s'")
        rc.execute("""SELECT DISTINCT ON (exchange, market_id, sel_name) exchange, market_id, ts, event_name, market_name, start_ts, sel_name, ltp, back_px, lay_px, back_sz, lay_sz
                      FROM xx_tape WHERE ts>now()-interval '90 seconds' AND (sport ILIKE '%foot%' OR sport ILIKE '%socc%') ORDER BY exchange, market_id, sel_name, ts DESC""")
        rows=rc.fetchall(); R.commit(); by={}
        for ex,mid,ts,ev,mn,st,sel,ltp,bp,lp,bsz,lsz in rows: by.setdefault((ex,mid),[]).append((ts,ev,mn,st,sel,float(ltp or 0),float(bp or 0),float(lp or 0),float(bsz or 0),float(lsz or 0)))
        now=time.time()
        # fills (maker only), per exchange
        lc.execute("select id, exchange, market_id, sel, side, price from bookie_paper where status='open' and exchange<>'betfair'"); filled=0
        for oid,ex,mid,sel,side,price in lc.fetchall():
            for ts,ev,mn,st,s,ltp,bp,lp,bsz,lsz in by.get((ex,mid),[]):
                if s!=sel: continue
                price=float(price)
                if side=='BACK' and bp>=tick_up(price): lc.execute("update bookie_paper set status='filled', fill_ts=%s, fill_price=%s, fill_kind='maker' where id=%s",(ts,price,oid)); filled+=1
                elif side=='LAY' and lp>0 and lp<=tick_down(price): lc.execute("update bookie_paper set status='filled', fill_ts=%s, fill_price=%s, fill_kind='maker' where id=%s",(ts,price,oid)); filled+=1
        lc.execute("update bookie_paper set status='expired' where status='open' and exchange<>'betfair' and ts<now()-interval '%s seconds'"%TTL)
        lc.execute("select exchange, market_id, sel, side from bookie_paper where status='open' and exchange<>'betfair'"); have={t for t in lc.fetchall()}
        quoted=0
        for (ex,mid),rs in by.items():
            if len(rs)<2 or mkt_code(rs[0][2]) is None: continue
            for ts,ev,mn,st,sel,ltp,bp,lp,bsz,lsz in rs:
                if bp<=1 or lp<=1 or lp<=bp or bsz<MIN_SIZE or lsz<MIN_SIZE or lp>MAX_PRICE: continue
                key=(ex,mid,sel)
                if now-last_quote.get(key,0)<REQUOTE: continue
                nt=nticks(bp,lp)
                if nt>MAX_SPREAD_TICKS: continue
                qb,ql=(tick_up(bp),tick_down(lp)) if nt>=2 else (bp,lp)
                if ql<qb: continue
                for side,px in (('BACK',qb),('LAY',ql)):
                    if (ex,mid,sel,side) in have: continue
                    lc.execute("insert into bookie_paper (ts,market_id,event_name,mkt,sel,side,price,mkt_back,mkt_lay,stake,status,version,exchange,start_ts) values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,'open',%s,%s,%s)",(ts,mid,ev,mkt_code(mn),sel,side,px,bp,lp,STAKE,VERSION,ex,st)); quoted+=1
                last_quote[key]=now
        # settlement: map to the Betfair market of the same game, then official result
        lc.execute("select distinct exchange, market_id, event_name, mkt, start_ts from bookie_paper where status='filled' and exchange<>'betfair' and ts<now()-interval '120 minutes'"); due=[d for d in lc.fetchall() if (d[0],d[1]) not in by][:BATCH]
        settled=0
        if due:
            if now-bfmap_t>600:
                rc.execute("select distinct market_id, event_name, mkt, min(ts)::date from liq_sample where ts>now()-interval '3 days' group by 1,2,3"); R.commit()
                bfmap={}
                for bmid,bev,bmkt,d in rc.fetchall(): bfmap.setdefault((ev_key(bev),bmkt),[]).append((bmid,d))
                bfmap_t=now
            targets={}
            for ex,mid,ev,mkt,st in due:
                cands=bfmap.get((ev_key(ev),mkt),[])
                if st is not None: cands=[c for c in cands if abs((c[1]-st.date()).days)<=1] or cands
                if cands: targets[(ex,mid)]=cands[0][0]
                else: lc.execute("update bookie_paper set status='unsettleable', settled_ts=now() where exchange=%s and market_id=%s and status='filled' and ts<now()-interval '10 hours'",(ex,mid))
            bmids=list({v for v in targets.values()})
            books={b['marketId']:b for b in (bf_post('listMarketBook',{"marketIds":bmids}) if bmids else [])}
            for (ex,mid),bmid in targets.items():
                b=books.get(bmid)
                if not b or b.get('status')!='CLOSED': continue
                win={str(r['selectionId']):r.get('status') for r in b.get('runners',[])}
                lc.execute("select sel_id, name from liq_runners where market_id=%s",(bmid,)); cat_=lc.fetchall()
                if not cat_:
                    for m in bf_post('listMarketCatalogue',{"filter":{"marketIds":[bmid]},"marketProjection":["RUNNER_DESCRIPTION"],"maxResults":1}):
                        for r in m.get('runners',[]): lc.execute("insert into liq_runners values (%s,%s,%s) on conflict do nothing",(bmid,r['selectionId'],r.get('runnerName','')))
                    lc.execute("select sel_id, name from liq_runners where market_id=%s",(bmid,)); cat_=lc.fetchall()
                nm={norm(n):str(i) for i,n in cat_}
                lc.execute("select id, sel, side, fill_price, stake from bookie_paper where exchange=%s and market_id=%s and status='filled'",(ex,mid))
                for oid,sel,side,fp,stk in lc.fetchall():
                    k=norm(sel); sid=nm.get(k) or next((v for kk,v in nm.items() if k and (k in kk or kk in k)),None); st_=win.get(sid) if sid else None
                    if st_ not in ('WINNER','LOSER'): lc.execute("update bookie_paper set status='unsettleable', settled_ts=now(), bf_market_id=%s where id=%s",(bmid,oid)); continue
                    fp=float(fp); stk=float(stk); won=1 if st_=='WINNER' else 0; c=COMM.get(ex,0.02)
                    gross=((fp-1)*stk if won else -stk) if side=='BACK' else (-(fp-1)*stk if won else stk)
                    pnl=gross*(1-c) if gross>0 else gross
                    lc.execute("update bookie_paper set status='settled', won=%s, pnl=%s, settled_ts=now(), bf_market_id=%s where id=%s",(won,round(pnl,4),bmid,oid)); settled+=1
        if quoted or filled or settled: log(f"books {len(by)} quoted {quoted} filled {filled} settled {settled}")
    except Exception:
        log(traceback.format_exc()[-600:])
        try: R.close()
        except Exception: pass
        R=None; time.sleep(20)
    time.sleep(20)
PYFILE
python3 -m py_compile bookie_xx.py || { cp bookie_xx.py.bak_531 bookie_xx.py; echo "compile failed, restored"; exit 1; }
pkill -f bookie_xx.py; sleep 120; pgrep -f bookie_xx.py >/dev/null && echo "xx leg up" || echo "XX LEG DOWN"; tail -4 bookie_xx.log
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
k=psycopg2.connect(creds.pg_local()).cursor(); k.execute("select exchange,status,count(*) from bookie_paper where version='v1.1' group by 1,2 order by 1,2"); print(k.fetchall())
PY
