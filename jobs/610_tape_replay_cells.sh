#!/bin/bash
# 610 (Mon 16 Nov 2026, 15:45). Replay the bot's exact rule on the recorded ladder (stream_ticks, 2 Nov onward: archive files 2-10 Nov + table
# from 11 Nov). Rule as in bookie_v2.py: passed cell by sport, market type and implied-probability band; pre-off, within 120 s of the off; best
# back < best lay, both sizes >= £10, lay <= 20, spread <= 3 ticks; taker: BACK at best back, LAY at best lay; £2; settle WINNER/LOSER from
# Betfair (listMarketBook on the closed market); 2% commission on winnings. First qualifying tick per market+selection. Runs in the
# background; writes reports/tape_replay.md.
cat > /root/pe-sports/team/tape_replay.py <<'PY'
import sys, os, csv, io, glob, subprocess, datetime, statistics, requests, psycopg2
sys.path.insert(0,'/root/pe-queue/runner'); import creds
csv.field_size_limit(10**7)
STAKE=2.0; COMM=0.02; MIN_SIZE=10.0; MAX_PRICE=20.0; MAX_SPREAD=3; WIN=120
LADDER=[(2,0.01),(3,0.02),(4,0.05),(6,0.1),(10,0.2),(20,0.5),(30,1),(50,2),(100,5),(1000,10)]
def tick(p):
    for hi,t in LADDER:
        if p<hi: return t
    return 10
def nticks(a,b):
    n=0; p=a
    while p<b-1e-9 and n<50: p=round(p+tick(p),2); n+=1
    return n
SPORT={'football':'Soccer','tennis':'Tennis','racing':'Horse Racing','greyhounds':'Greyhound Racing'}
MT={'MO':'MATCH_ODDS','BTTS':'BOTH_TEAMS_TO_SCORE','CS':'CORRECT_SCORE','DNB':'DRAW_NO_BET','DC':'DOUBLE_CHANCE','HT_MO':'HALF_TIME','HTFT':'HALF_TIME_FULL_TIME',
    'HT_CS':'HALF_TIME_SCORE','FH05':'FIRST_HALF_GOALS_05','FH15':'FIRST_HALF_GOALS_15','FH25':'FIRST_HALF_GOALS_25','OU05':'OVER_UNDER_05','OU15':'OVER_UNDER_15',
    'OU25':'OVER_UNDER_25','OU35':'OVER_UNDER_35','OU45':'OVER_UNDER_45','OU55':'OVER_UNDER_55','WIN':'WIN','CSH':'CLEAN_SHEET','FGS':'FIRST_GOAL_SCORER'}
con=psycopg2.connect(creds.pg_local(),sslmode='disable'); c=con.cursor(); c.execute("SET statement_timeout='3600s'")
c.execute("SELECT sport, market_type, band_lo, band_hi, side FROM fair_price_passed"); CELLS=[(s,m,float(a),float(b),sd) for s,m,a,b,sd in c.fetchall()]
def cell(sport,mt,p):
    for s,m,a,b,sd in CELLS:
        if s==sport and m==mt and a<=p<b: return (s,m,a,b,sd)
bets={}   # (market,sel_id) -> dict
def consider(r):
    # r: dict with market_id, sport, mkt, sel_id, sel, back_px, back_sz, lay_px, lay_sz, inplay, secs_to_off, ts
    try:
        if str(r['inplay']).lower() in ('t','true','1'): return
        s2o=float(r['secs_to_off']); 
        if not (0<=s2o<=WIN): return
        key=(r['market_id'],str(r['sel_id']))
        if key in bets: return
        bb=float(r['back_px']); bl=float(r['lay_px']); bs=float(r['back_sz']); ls=float(r['lay_sz'])
    except Exception: return
    if bl<=bb or bs<MIN_SIZE or ls<MIN_SIZE or bl>MAX_PRICE or nticks(bb,bl)>MAX_SPREAD: return
    sport=SPORT.get(r['sport'],r['sport']); mt=MT.get(r['mkt'],r['mkt']); p=2.0/(bb+bl)
    cl=cell(sport,mt,p)
    if not cl: return
    side=cl[4]; price=bb if side=='BACK' else bl
    bets[key]=dict(market=r['market_id'],sel_id=str(r['sel_id']),sel=r.get('sel'),sport=sport,mt=mt,cell=cl,side=side,price=price,ts=str(r['ts'])[:19])
COLS=['ts_recv','pt','latency_ms','market_id','sport','mkt','sel_id','sel','back_px','back_sz','lay_px','lay_sz','back2_px','lay2_px','ltp','tv','inplay','status','secs_to_off']
files=sorted(glob.glob('/root/pe-archive/stream_ticks/*.csv.zst'))
for f in files:
    n=0
    p=subprocess.Popen(['zstdcat',f],stdout=subprocess.PIPE,text=True,errors='replace')
    rd=csv.reader(p.stdout); hdr=next(rd)
    idx={h:i for i,h in enumerate(hdr)}
    for row in rd:
        n+=1
        try: r={k:row[idx[k]] for k in ('market_id','sport','mkt','sel_id','sel','back_px','back_sz','lay_px','lay_sz','inplay','secs_to_off')}; r['ts']=row[idx['ts_recv']]
        except Exception: continue
        if r['secs_to_off'] in ('','\\N'): continue
        consider(r)
    p.wait(); print(f"{os.path.basename(f)}: {n} rows, bets so far {len(bets)}",flush=True)
cur=con.cursor(name='st'); cur.itersize=200000
cur.execute("SELECT ts_recv, market_id, sport, mkt, sel_id, sel, back_px, back_sz, lay_px, lay_sz, inplay, secs_to_off FROM stream_ticks WHERE secs_to_off BETWEEN 0 AND %s ORDER BY ts_recv",(WIN,))
n=0
for t,m,sp,mk,sid,sel,bb,bs,bl,ls,ip,s2o in cur:
    n+=1; consider(dict(ts=t,market_id=m,sport=sp,mkt=mk,sel_id=sid,sel=sel,back_px=bb,back_sz=bs,lay_px=bl,lay_sz=ls,inplay=ip,secs_to_off=s2o))
print(f"table: {n} rows in the window, bets {len(bets)}",flush=True)
# settle from Betfair
APP,U,P=creds.betfair()
tok=requests.post("https://identitysso.betfair.com/api/login",data={"username":U,"password":P},headers={"X-Application":APP,"Accept":"application/json"},timeout=20).json().get('token')
H={"X-Application":APP,"X-Authentication":tok,"Content-Type":"application/json"}
mids=sorted({b['market'] for b in bets.values()}); status={}
for i in range(0,len(mids),40):
    try:
        r=requests.post("https://api.betfair.com/exchange/betting/rest/v1.0/listMarketBook/",headers=H,json={"marketIds":mids[i:i+40]},timeout=30).json()
        for b in r if isinstance(r,list) else []:
            for ru in b.get('runners',[]): status[(b['marketId'],str(ru['selectionId']))]=ru.get('status')
    except Exception as e: print("listMarketBook error",str(e)[:80])
rows=[]
for k,b in bets.items():
    s=status.get(k)
    if s not in ('WINNER','LOSER'): continue
    won=s=='WINNER'; pr=b['price']
    g=((pr-1)*STAKE if won else -STAKE) if b['side']=='BACK' else (-(pr-1)*STAKE if won else STAKE)
    b['pnl']=g*(1-COMM) if g>0 else g; rows.append(b)
rows.sort(key=lambda b:b['ts'])
def line(lbl,rs):
    if not rs: return f"| {lbl} | 0 | | | | |"
    pn=[r['pnl'] for r in rs]; h=len(pn)//2; stk=STAKE*len(pn)
    return f"| {lbl} | {len(pn)} | £{sum(pn):+.2f} | £{sum(pn)/stk*100:+.1f} | £{sum(pn[:h]):+.2f} | £{sum(pn[h:]):+.2f} |"
out=[f"# Tape replay of the passed cells — {datetime.datetime.utcnow():%F %H:%M} UTC","",
     f"Ladder recorded {files[0][-18:-8] if files else '?'} to today. Candidate bets {len(bets)}, settled from Betfair {len(rows)} (the rest: Betfair no longer returns a result for that market).","",
     "| cell | bets | profit after 2% | per £100 staked | first half | second half |","|---|---|---|---|---|---|", line("ALL CELLS", rows)]
for cl in sorted({r['cell'] for r in rows}):
    out.append(line(f"{cl[0]} {cl[1]} {cl[2]:.2f}-{cl[3]:.2f} {cl[4]}", [r for r in rows if r['cell']==cl]))
for sp in sorted({r['sport'] for r in rows}): out.append(line(f"sport: {sp}", [r for r in rows if r['sport']==sp]))
open('/root/pe-queue/reports/tape_replay.md','w').write("\n".join(out)+"\n"); print("\n".join(out))
PY
python3 -m py_compile /root/pe-sports/team/tape_replay.py && echo compiles || exit 1
cd /root/pe-sports/team && nohup bash -c 'nice -n 10 python3 tape_replay.py > tape_replay.log 2>&1; cd /root/pe-queue && git add reports/tape_replay.md && git commit -qm "tape replay of the passed cells" && git pull -q --no-rebase --no-edit && git push -q' >/dev/null 2>&1 &
sleep 60; tail -3 /root/pe-sports/team/tape_replay.log
echo "610 done (replay running in the background)"
