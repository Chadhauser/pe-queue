#!/bin/bash
# 546 (Tue 10 Nov 2026). RESTING-ORDER REPLAY ON THE STREAM TAPE — the test the old BASIC data cannot do (one price a minute, no book),
# but the stream tape can: stream_ticks holds best back/lay with sizes every tick since late October (65M rows, local).
# For every passed cell (sport, market type, probability band, side): walk each pre-off market in the last hour before the off; every
# 5 minutes per runner, if the runner's normalised probability sits in the cell, rest the bot's quote (one tick inside the spread, on the
# right side of fair) and watch the next 10 minutes of the book: BACK at P is filled when best back later >= P+1 tick, LAY at L when
# best lay later <= L-1 tick (one tick adverse, as the bot scores itself). Settle on the market's result. Report per cell: quotes, fills,
# fill rate, settled n, £ per £100 after 2% commission, and the ADVERSE move 10 min after a fill (how far the price went against us).
# Control: the same quotes on runners NOT in any passed cell, random side — the adverse-selection baseline.
# Result: the market's result from the tape's own close (the winner trades to <=1.10 while every other runner is >=5.0 at the last
# print) and, where that is not clear, Betfair listMarketBook for the market if it still answers; markets with neither are not settled
# and counted as such. Writes fair_price_replay; verifier_cells drops a cell whose replay (n>=30) is negative, so the bot never quotes it.
set -o pipefail
export PYTHONDONTWRITEBYTECODE=1
cd /root/pe-sports/team && cat > replay_fills.py <<'PYFILE'
import sys, math, json, time, datetime, numpy as np, pandas as pd, psycopg2, psycopg2.extras, requests
sys.path.insert(0,'/root/pe-queue/runner'); import creds
COMM=0.02; STAKE=2.0; STEP=300; HOLD=600; MIN_SIZE=10.0; MAX_SPREAD=3; MAX_PRICE=20.0
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
MT={'MO':'MATCH_ODDS','MO_PRE':'MATCH_ODDS','OU25':'OVER_UNDER_25','OU15':'OVER_UNDER_15','OU35':'OVER_UNDER_35','WIN':'WIN','PLACE':'PLACE'}
SPORT={'football':'Soccer','soccer':'Soccer','racing':'Horse Racing','tennis':'Tennis'}
con=psycopg2.connect(creds.pg_local(),sslmode='disable'); cur=con.cursor(); cur.execute("SET statement_timeout=0; SET work_mem='256MB'")
cur.execute("SELECT sport, market_type, band_lo, band_hi, side, fair_factor FROM fair_price_passed"); cells=cur.fetchall()
C={}
for sp,mt,lo,hi,side,f in cells: C.setdefault((sp,mt),[]).append((float(lo),float(hi),side,float(f)))
print("passed cells:",len(cells),"types:",sorted(C),flush=True)
def cell_for(sp,mt,p):
    for lo,hi,side,f in C.get((sp,mt),[]):
        if lo<=p<hi: return side,f
    return None,None
# Betfair for unclear results
APP,USER,PW=creds.betfair(); SSO=None
def bf_results(mids):
    global SSO
    out={}
    try:
        if SSO is None:
            r=requests.post("https://identitysso.betfair.com/api/login",data={"username":USER,"password":PW},headers={"X-Application":APP,"Accept":"application/json"},timeout=20).json(); SSO=r.get('token')
        for i in range(0,len(mids),40):
            r=requests.post("https://api.betfair.com/exchange/betting/rest/v1.0/listMarketBook/",json={"marketIds":mids[i:i+40]},headers={"X-Application":APP,"X-Authentication":SSO,"Content-Type":"application/json"},timeout=25)
            if r.status_code!=200: continue
            for b in r.json():
                if b.get('status')=='CLOSED': out[b['marketId']]={str(x['selectionId']):x.get('status') for x in b.get('runners',[])}
    except Exception as e: print("bf_results",repr(e)[:100],flush=True)
    return out
# universe: pre-off markets of the passed types with at least 30 min of pre-off tape
cur.execute("""SELECT market_id, sport, mkt, min(ts_recv), max(ts_recv) FROM stream_ticks
               WHERE NOT inplay AND secs_to_off BETWEEN 0 AND 3600 GROUP BY 1,2,3 HAVING max(ts_recv)-min(ts_recv) > interval '30 minutes'""")
mk=[(m,SPORT.get(str(sp).lower(),sp),MT.get(mt,mt),a,b) for m,sp,mt,a,b in cur.fetchall()]
mk=[x for x in mk if (x[1],x[2]) in C or True]   # keep all: the ones outside cells are the control
print("pre-off markets on the stream tape:",len(mk),flush=True)
quotes=[]; results={}; unclear=[]
for n_m,(mid,sp,mt,t0,t1) in enumerate(mk):
    cur.execute("SELECT ts_recv, sel_id, back_px, back_sz, lay_px, lay_sz, ltp FROM stream_ticks WHERE market_id=%s AND NOT inplay AND secs_to_off BETWEEN 0 AND 3600 ORDER BY ts_recv",(mid,))
    df=pd.DataFrame(cur.fetchall(),columns=['ts','sel','bb','bs','bl','ls','ltp'])
    if df.empty: continue
    for c in ('bb','bs','bl','ls','ltp'): df[c]=pd.to_numeric(df[c],errors='coerce')
    sels=sorted(df.sel.unique())
    if len(sels)<2: continue
    # result from the tape's close: last in-play/any print per runner
    cur.execute("SELECT DISTINCT ON (sel_id) sel_id, ltp FROM stream_ticks WHERE market_id=%s ORDER BY sel_id, ts_recv DESC",(mid,)); last={str(s):float(l) if l else None for s,l in cur.fetchall()}
    vals=sorted([v for v in last.values() if v]);
    if len(vals)>=2 and vals[0]<=1.10 and vals[1]>=5.0: results[mid]={s:('WINNER' if v==vals[0] else 'LOSER') for s,v in last.items() if v}
    else: unclear.append(mid)
    # 1-minute grid of the latest book per runner
    g=df.set_index('ts').groupby('sel').resample('60s').last().ffill().reset_index()
    times=sorted(g.ts.unique())
    for i,t in enumerate(times):
        if i%(STEP//60): continue
        snap=g[g.ts==t].dropna(subset=['bb','bl'])
        if len(snap)<len(sels): continue
        mids_=(snap.bb+snap.bl)/2; tot=(1/mids_[mids_>1]).sum()
        if tot<=0: continue
        fut=g[(g.ts>t)&(g.ts<=t+pd.Timedelta(seconds=HOLD))]
        for _,r in snap.iterrows():
            bb,bl,bs,ls=float(r.bb),float(r.bl),float(r.bs or 0),float(r.ls or 0)
            if bl<=bb or bs<MIN_SIZE or ls<MIN_SIZE or bl>MAX_PRICE or nticks(bb,bl)>MAX_SPREAD: continue
            p=(1/((bb+bl)/2))/tot; side,f=cell_for(sp,mt,p); incell=side is not None
            if not incell: side='BACK' if (hash((mid,str(r.sel),i))%2) else 'LAY'; f=1.0
            fair=1/max(0.005,min(0.995,p*f)); nt=nticks(bb,bl)
            if side=='BACK':
                q=tick_up(bb) if nt>=2 else bb
                if incell and not (q>=fair and q<bl): continue
            else:
                q=tick_down(bl) if nt>=2 else bl
                if incell and not (q<=fair and q>bb): continue
            fr=fut[fut.sel==r.sel]
            if side=='BACK': hit=fr[fr.bb>=tick_up(q)]
            else: hit=fr[fr.bl<=tick_down(q)]
            filled=len(hit)>0; adv=None
            if filled:
                tf=hit.ts.iloc[0]; after=fr[fr.ts>=tf+pd.Timedelta(seconds=HOLD)]
                if len(after):
                    m2=float((after.bb.iloc[0]+after.bl.iloc[0])/2); adv=(q/m2-1) if side=='BACK' else (m2/q-1)   # + = price moved against us after the fill
            quotes.append((mid,sp,mt,str(r.sel),incell,side,q,p,filled,adv,round(fair,3)))
    if n_m%200==0: print(f"  {n_m}/{len(mk)} markets, quotes {len(quotes)}",flush=True)
if unclear: results.update(bf_results(unclear[:2000]))
Q=pd.DataFrame(quotes,columns=['mid','sport','mt','sel','incell','side','q','p','filled','adv','fair'])
def settle(row):
    r=results.get(row.mid)
    if not r or r.get(row.sel) not in ('WINNER','LOSER'): return None
    won=r[row.sel]=='WINNER'
    gross=((row.q-1)*STAKE if won else -STAKE) if row.side=='BACK' else (-(row.q-1)*STAKE if won else STAKE)
    return gross*(1-COMM) if gross>0 else gross
Q['pnl']=Q.apply(lambda r: settle(r) if r.filled else None,axis=1)
print(f"quotes {len(Q)} | fills {int(Q.filled.sum())} | settled {int(Q.pnl.notna().sum())} | markets with a result {len(results)} of {len(mk)}",flush=True)
cur.execute("DROP TABLE IF EXISTS fair_price_replay; CREATE TABLE fair_price_replay (sport TEXT, market_type TEXT, band_lo NUMERIC, side TEXT, quotes INT, fills INT, fill_rate NUMERIC, settled INT, pnl NUMERIC, per100 NUMERIC, adverse_10m NUMERIC, built_at TIMESTAMPTZ DEFAULT now())")
rows=[]; lines=["| cell | quotes | fills | fill rate | settled | £ | £ per £100 | adverse move 10 min after fill |","|---|---|---|---|---|---|---|---|"]
def band_of(sp,mt,p):
    for lo,hi,side,f in C.get((sp,mt),[]):
        if lo<=p<hi: return lo
    return None
Q['band']=[band_of(s,m,p) if ic else None for s,m,p,ic in zip(Q.sport,Q.mt,Q.p,Q.incell)]
for (sp,mt,band,side),g in Q[Q.incell].groupby(['sport','mt','band','side']):
    fl=g[g.filled]; st=fl[fl.pnl.notna()]; per100=(st.pnl.sum()/(len(st)*STAKE)*100) if len(st) else None; adv=fl.adv.dropna().mean() if fl.adv.notna().any() else None
    rows.append((sp,mt,band,side,len(g),len(fl),len(fl)/len(g) if len(g) else 0,len(st),round(float(st.pnl.sum()),2) if len(st) else 0,round(per100,2) if per100 is not None else None,round(float(adv),4) if adv is not None else None))
    lines.append(f"| {sp} {mt} p{band:.2f} {side} | {len(g)} | {len(fl)} | {len(fl)/len(g):.1%} | {len(st)} | {st.pnl.sum():+.2f} | {'n/a' if per100 is None else f'{per100:+.2f}'} | {'n/a' if adv is None else f'{adv:+.2%}'} |")
ctrl=Q[~Q.incell]; fl=ctrl[ctrl.filled]; st=fl[fl.pnl.notna()]
lines.append(f"| CONTROL (runners in no cell, random side) | {len(ctrl)} | {len(fl)} | {len(fl)/max(1,len(ctrl)):.1%} | {len(st)} | {st.pnl.sum():+.2f} | {'n/a' if not len(st) else f'{st.pnl.sum()/(len(st)*STAKE)*100:+.2f}'} | {'n/a' if not fl.adv.notna().any() else f'{fl.adv.dropna().mean():+.2%}'} |")
if rows: psycopg2.extras.execute_values(cur,"INSERT INTO fair_price_replay (sport,market_type,band_lo,side,quotes,fills,fill_rate,settled,pnl,per100,adverse_10m) VALUES %s",rows)
con.commit()
hdr=[f"# Resting-order replay on the stream tape — {datetime.date.today()} (job 546)","",f"Pre-off markets replayed: {len(mk)} (tape {min(x[3] for x in mk):%d %b} to {max(x[4] for x in mk):%d %b}); markets with a result {len(results)}; quotes {len(Q)}, fills {int(Q.filled.sum())}, settled {int(Q.pnl.notna().sum())}. £2 a quote, one tick adverse, 2% commission. 'Adverse move' = how far the mid price went against the filled side 10 minutes later (positive = we were picked off).",""]
open(f"/root/pe-queue/reports/replay_fills_{datetime.date.today()}.md",'w').write("\n".join(hdr+lines)+"\n"); print("\n".join(lines))
PYFILE
python3 -m py_compile replay_fills.py && echo "replay compiles"
timeout 7000 python3 replay_fills.py 2>&1 | tail -60
echo "== verifier: drop cells the replay shows negative (n>=30) =="
python3 - <<'PY'
p='/root/pe-sports/team/verifier_cells.py'; s=open(p).read()
if 'fair_price_replay' not in s:
    s=s.replace('c.execute("SELECT sport, market_type, band_lo, band_hi, side, n_is, edge_is, edge_oos FROM fair_price_passed ORDER BY 1,2,3")',
    '''try:
    c.execute("""DELETE FROM fair_price_passed p USING fair_price_replay r WHERE r.sport=p.sport AND r.market_type=p.market_type AND r.band_lo=p.band_lo AND r.side=p.side AND r.settled>=30 AND r.per100<0"""); print("cells dropped by the replay (negative on real books):",c.rowcount)
except Exception as e: print("replay gate skipped:",str(e)[:80])
c.execute("SELECT sport, market_type, band_lo, band_hi, side, n_is, edge_is, edge_oos FROM fair_price_passed ORDER BY 1,2,3")''')
    open(p,'w').write(s); print("verifier gates on the replay")
PY
python3 -m py_compile /root/pe-sports/team/verifier_cells.py && python3 /root/pe-sports/team/verifier_cells.py
( crontab -l 2>/dev/null | grep -v 'replay_fills.py'; echo "40 4 * * * cd /root/pe-sports/team && timeout 7000 /usr/bin/python3 replay_fills.py >> replay_fills.log 2>&1" ) | crontab -
cd /root/pe-queue && git add reports/replay_fills_*.md && git commit -q -m "546: resting-order replay on the stream tape" && git pull -q --rebase && git push -q && echo "pushed"
echo "546 done"
