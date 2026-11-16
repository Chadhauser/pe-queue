#!/bin/bash
# 613 (Mon 16 Nov 2026, 16:15). Peter: "do all of it". One comparison on the recorded ladder (stream_ticks, 2 Nov onward), same matches,
# same passed cells, 2% commission, £2, settled from Betfair (results cached in tape_results so older markets stay settleable):
#  M1 TAKE      first tick within 120 s of the off that meets the bot's rule, take the price (today's bot)
#  M2 TAKE+VAL  as M1 but only if the taken price beats fair (implied x fair_factor) by m (1%, 2%)
#  M3 MOMENT    first tick in the last 60 min where the taken price beats fair by m (bet when the price is wrong, not at a set time)
#  M4 POST      at the first tick 10-60 min before the off, post our own price m better than fair; filled only if the market later trades
#               through it before the off (last traded price reaches it); unfilled = no bet
#  M5 BEST EXCH M1 but at the best of Betfair / Smarkets / Matchbook at that moment, if xx_tape can be matched to the Betfair market
# Background; writes reports/execution_methods.md.
cat > /root/pe-sports/team/execution_methods.py <<'PY'
import sys, os, csv, glob, subprocess, datetime, requests, psycopg2
sys.path.insert(0,'/root/pe-queue/runner'); import creds
csv.field_size_limit(10**7)
STAKE=2.0; COMM=0.02; MIN_SIZE=10.0; MAX_PRICE=20.0; MAX_SPREAD=3
LADDER=[(2,0.01),(3,0.02),(4,0.05),(6,0.1),(10,0.2),(20,0.5),(30,1),(50,2),(100,5),(1000,10)]
def tick(p):
    for hi,t in LADDER:
        if p<hi: return t
    return 10
def up(p): return round(min(1000,p+tick(p)),2)
def down(p): return round(max(1.01,p-tick(p-1e-9)),2)
def snap_up(x):   # smallest valid price >= x
    p=1.01
    while p<x-1e-9 and p<1000: p=up(p)
    return p
def snap_down(x):
    p=snap_up(x); return p if abs(p-x)<1e-9 else down(p)
def nticks(a,b):
    n=0; p=a
    while p<b-1e-9 and n<50: p=up(p); n+=1
    return n
SPORT={'football':'Soccer','tennis':'Tennis','racing':'Horse Racing'}
MT={'MO':'MATCH_ODDS','BTTS':'BOTH_TEAMS_TO_SCORE','CS':'CORRECT_SCORE','DNB':'DRAW_NO_BET','DC':'DOUBLE_CHANCE','HT_MO':'HALF_TIME','HTFT':'HALF_TIME_FULL_TIME',
    'HT_CS':'HALF_TIME_SCORE','FH05':'FIRST_HALF_GOALS_05','FH15':'FIRST_HALF_GOALS_15','FH25':'FIRST_HALF_GOALS_25','OU05':'OVER_UNDER_05','OU15':'OVER_UNDER_15',
    'OU25':'OVER_UNDER_25','OU35':'OVER_UNDER_35','OU45':'OVER_UNDER_45','OU55':'OVER_UNDER_55','WIN':'WIN','CSH':'CLEAN_SHEET','FGS':'FIRST_GOAL_SCORER'}
con=psycopg2.connect(creds.pg_local(),sslmode='disable'); con.autocommit=True; c=con.cursor(); c.execute("SET statement_timeout='5400s'")
c.execute("SELECT sport, market_type, band_lo, band_hi, side, fair_factor FROM fair_price_passed"); CELLS=[(s,m,float(a),float(b),sd,float(f)) for s,m,a,b,sd,f in c.fetchall()]
def cell(sport,mt,p):
    for x in CELLS:
        if x[0]==sport and x[1]==mt and x[2]<=p<x[3]: return x
MS=(0.01,0.02)
B={}      # method -> key -> bet dict(price, side, cell, ts)
for k in ['M1']+[f'M2_{m}' for m in MS]+[f'M3_{m}' for m in MS]+[f'M4_{m}' for m in MS]: B[k]={}
POST={}   # (m,key) -> posted dict(price, side, cell, ts)
FIRST={}  # key -> first M1 tick info for M5
def feed(r):
    try:
        if str(r['inplay']).lower() in ('t','true','1'): return
        s2o=float(r['secs_to_off']); bb=float(r['back_px']); bl=float(r['lay_px']); bs=float(r['back_sz']); ls=float(r['lay_sz'])
    except Exception: return
    ltp=None
    try: ltp=float(r['ltp'])
    except Exception: pass
    key=(r['market_id'],str(r['sel_id'])); ts=str(r['ts'])[:19]
    # M4 fill check for posted orders
    for m in MS:
        o=POST.get((m,key))
        if o and key not in B[f'M4_{m}'] and ltp:
            if (o['side']=='BACK' and ltp>=o['price']) or (o['side']=='LAY' and ltp<=o['price']): B[f'M4_{m}'][key]=dict(o,ts=ts)
    if not (0<=s2o<=3600): return
    ok=not(bl<=bb or bs<MIN_SIZE or ls<MIN_SIZE or bl>MAX_PRICE or nticks(bb,bl)>MAX_SPREAD)
    if not ok: return
    sport=SPORT.get(r['sport'],r['sport']); mt=MT.get(r['mkt'],r['mkt']); mid=(bb+bl)/2; p=1/mid
    cl=cell(sport,mt,p)
    if not cl: return
    side=cl[4]; fair_p=p*cl[5]; take=bb if side=='BACK' else bl
    val=(fair_p*take-1) if side=='BACK' else (1-fair_p*take)
    bet=dict(market=r['market_id'],sel_id=str(r['sel_id']),cell=cl,side=side,price=take,ts=ts,sport=sport)
    if s2o<=120:
        if key not in B['M1']: B['M1'][key]=bet; FIRST[key]=dict(r=r,bet=bet)
        for m in MS:
            if val>=m and key not in B[f'M2_{m}']: B[f'M2_{m}'][key]=bet
    for m in MS:
        if val>=m and key not in B[f'M3_{m}']: B[f'M3_{m}'][key]=bet
        if 600<=s2o<=3600 and (m,key) not in POST:
            if side=='BACK': px=snap_up((1+m)/fair_p); px=max(px,up(bb))     # sit above the best back price, m better than fair
            else: px=snap_down((1-m)/fair_p); px=min(px,down(bl))
            if 1.01<px<=MAX_PRICE: POST[(m,key)]=dict(market=r['market_id'],sel_id=str(r['sel_id']),cell=cl,side=side,price=px,ts=ts,sport=sport)
n=0
for f in sorted(glob.glob('/root/pe-archive/stream_ticks/*.csv.zst')):
    p=subprocess.Popen(['zstdcat',f],stdout=subprocess.PIPE,text=True,errors='replace'); rd=csv.reader(p.stdout); hdr=next(rd); ix={h:i for i,h in enumerate(hdr)}
    for row in rd:
        n+=1
        try: r={k:row[ix[k]] for k in ('market_id','sport','mkt','sel_id','back_px','back_sz','lay_px','lay_sz','ltp','inplay','secs_to_off')}; r['ts']=row[ix['ts_recv']]
        except Exception: continue
        if r['secs_to_off'] in ('','\\N'): continue
        feed(r)
    p.wait(); print(os.path.basename(f), n, {k:len(v) for k,v in B.items()}, flush=True)
cur=con.cursor(name='st'); cur.itersize=200000
cur.execute("SELECT ts_recv, market_id, sport, mkt, sel_id, back_px, back_sz, lay_px, lay_sz, ltp, inplay, secs_to_off FROM stream_ticks WHERE secs_to_off BETWEEN 0 AND 3600 ORDER BY ts_recv")
for t,m,sp,mk,sid,bb,bs,bl,ls,lt,ip,s2o in cur:
    feed(dict(ts=t,market_id=m,sport=sp,mkt=mk,sel_id=sid,back_px=bb,back_sz=bs,lay_px=bl,lay_sz=ls,ltp=lt,inplay=ip,secs_to_off=s2o))
print("table done", {k:len(v) for k,v in B.items()}, flush=True)
# M5: best price across exchanges at the M1 moment, if xx_tape maps to the Betfair market
c2=con.cursor(); c2.execute("select column_name from information_schema.columns where table_name='xx_tape' order by ordinal_position"); xcols=[r[0] for r in c2.fetchall()]
m5_note=f"xx_tape columns: {xcols}"
B['M5']={}
link=next((k for k in ('bf_market_id','betfair_market_id') if k in xcols),None)
if link:
    pc=next((k for k in ('back_px','back') if k in xcols),None); lc=next((k for k in ('lay_px','lay') if k in xcols),None); selc=next((k for k in ('sel','runner','selection') if k in xcols),None)
    for key,v in FIRST.items():
        b=dict(v['bet']); r=v['r']
        try:
            c2.execute(f"select {pc},{lc} from xx_tape where {link}=%s and {selc}=%s and ts between %s::timestamptz - interval '60 seconds' and %s::timestamptz + interval '60 seconds'",(b['market'],r.get('sel') or '',b['ts'],b['ts']))
            for xb,xl in c2.fetchall():
                if b['side']=='BACK' and xb and float(xb)>b['price']: b['price']=float(xb)
                if b['side']=='LAY' and xl and float(xl)<b['price']: b['price']=float(xl)
        except Exception as e: con.rollback()
        B['M5'][key]=b
else: m5_note+=" -> no Betfair market link in xx_tape, M5 not computed"
# settle: cache results in tape_results
c.execute("CREATE TABLE IF NOT EXISTS tape_results (market_id text, sel_id text, status text, PRIMARY KEY(market_id, sel_id))")
mids=sorted({b['market'] for d in B.values() for b in d.values()})
c.execute("select market_id from tape_results group by 1"); have={r[0] for r in c.fetchall()}
APP,U,P=creds.betfair()
tok=requests.post("https://identitysso.betfair.com/api/login",data={"username":U,"password":P},headers={"X-Application":APP,"Accept":"application/json"},timeout=20).json().get('token')
H={"X-Application":APP,"X-Authentication":tok,"Content-Type":"application/json"}
todo=[m for m in mids if m not in have]
for i in range(0,len(todo),40):
    try:
        r=requests.post("https://api.betfair.com/exchange/betting/rest/v1.0/listMarketBook/",headers=H,json={"marketIds":todo[i:i+40]},timeout=30).json()
        for b in r if isinstance(r,list) else []:
            if b.get('status')!='CLOSED': continue
            for ru in b.get('runners',[]):
                if ru.get('status') in ('WINNER','LOSER'): c.execute("INSERT INTO tape_results VALUES (%s,%s,%s) ON CONFLICT DO NOTHING",(b['marketId'],str(ru['selectionId']),ru['status']))
    except Exception as e: print("settle error",str(e)[:80])
c.execute("select market_id, sel_id, status from tape_results"); RES={(a,b):s for a,b,s in c.fetchall()}
def pnl(b,s):
    won=s=='WINNER'; pr=b['price']
    g=((pr-1)*STAKE if won else -STAKE) if b['side']=='BACK' else (-(pr-1)*STAKE if won else STAKE)
    return g*(1-COMM) if g>0 else g
NAMES={'M1':'Take the price, last 2 min (today)','M2_0.01':'Take, only if 1% better than fair','M2_0.02':'Take, only if 2% better than fair',
       'M3_0.01':'Take when 1% better than fair, any time in last hour','M3_0.02':'Take when 2% better than fair, any time in last hour',
       'M4_0.01':'Post our price 1% better than fair, 10-60 min out','M4_0.02':'Post our price 2% better than fair, 10-60 min out','M5':'Take, best of three exchanges'}
out=[f"# Execution methods on the recorded ladder — {datetime.datetime.utcnow():%F %H:%M} UTC","","Same matches, same passed cells, £2, 2% commission, settled from Betfair.","",
     "| method | bets | profit | per £100 | 1st half | 2nd half |","|---|---|---|---|---|---|"]
for k,d in B.items():
    rows=sorted([(b['ts'],pnl(b,RES[(b['market'],b['sel_id'])])) for kk,b in d.items() if (b['market'],b['sel_id']) in RES])
    if not rows: out.append(f"| {NAMES.get(k,k)} | 0 | | | | |"); continue
    pn=[x[1] for x in rows]; h=len(pn)//2
    out.append(f"| {NAMES.get(k,k)} | {len(pn)} | £{sum(pn):+.2f} | £{sum(pn)/(len(pn)*STAKE)*100:+.1f} | £{sum(pn[:h]):+.2f} | £{sum(pn[h:]):+.2f} |")
out+=["",f"Posted orders (M4): {sum(1 for k in POST if k[0]==0.01)} at 1%, {sum(1 for k in POST if k[0]==0.02)} at 2%; filled {len(B['M4_0.01'])} and {len(B['M4_0.02'])}.",m5_note,
      f"Markets with a Betfair result: {len({k[0] for k in RES})} of {len(mids)}."]
open('/root/pe-queue/reports/execution_methods.md','w').write("\n".join(out)+"\n"); print("\n".join(out))
PY
python3 -m py_compile /root/pe-sports/team/execution_methods.py && echo compiles || exit 1
cd /root/pe-sports/team && nohup bash -c 'nice -n 10 timeout 10800 python3 execution_methods.py > execution_methods.log 2>&1; cd /root/pe-queue && git add reports/execution_methods.md && git commit -qm "execution methods on the recorded ladder" && git pull -q --no-rebase --no-edit && git push -q' >/dev/null 2>&1 &
sleep 30; tail -2 /root/pe-sports/team/execution_methods.log
echo "613 done (running in the background)"
