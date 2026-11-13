#!/bin/bash
# 562 (Fri 13 Nov 2026, re-queue of 558 behind the 13 Nov orders; the one replay Peter allowed). CEO order 4: before the maker (bookie) idea is dropped, replay resting orders (a) IN-PLAY in the ten
# minutes after a goal, on the Betfair in-play tape (liq_sample, every few seconds, best back/lay + sizes), and (b) on MATCHBOOK and
# SMARKETS (xx_tape) pre-off and in-play. Same mechanics as 546: quote one tick inside the spread, fill when the touch crosses our price
# (one tick adverse), measure what happens next. These are TRADES (unwound at the touch 10 minutes later), so no result mapping is needed:
# £ per £100 = capture minus pick-off, plus the adverse move. Control = random side. Output reports/replay_inplay_xx_<date>.md.
set -o pipefail
export PYTHONDONTWRITEBYTECODE=1
cd /root/pe-sports/team && cat > replay_inplay_xx.py <<'PYFILE'
import sys, math, datetime, numpy as np, pandas as pd, psycopg2
sys.path.insert(0,'/root/pe-queue/runner'); import creds
STAKE=2.0; COMM=0.02; HOLD=600; MIN_SIZE=10.0; MAX_SPREAD=3; MAX_PRICE=20.0
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
def trade_pnl(side,entry,exit_):   # maker entry at `entry`, unwound by taking the touch at `exit_`; £ per £2 stake
    if side=='BACK': g=STAKE*(entry/exit_-1)     # backed high, laid lower = profit
    else: g=STAKE*(1-entry/exit_)                # laid low, backed higher = profit
    return g*(1-COMM) if g>0 else g
con=psycopg2.connect(creds.pg_local(),sslmode='disable'); cur=con.cursor(); cur.execute("SET statement_timeout=0; SET work_mem='128MB'")
rng=np.random.default_rng(5); lines=[]
def replay_window(rows,offsets,label_prefix):
    """rows: list of (ts, sel, bb, bs, bl, ls) for one market window. Quote at each offset (seconds from window start) on every runner,
    both sides as a maker; fill when touch crosses; unwind at +HOLD at the touch. Returns list of (label, side, filled, pnl, adverse)."""
    out=[]
    if not rows: return out
    df=pd.DataFrame(rows,columns=['ts','sel','bb','bs','bl','ls']).dropna(subset=['bb','bl']);
    for c in ('bb','bs','bl','ls'): df[c]=pd.to_numeric(df[c],errors='coerce')
    t0=df.ts.min()
    for off in offsets:
        snap_t=t0+pd.Timedelta(seconds=off); snap=df[df.ts<=snap_t].sort_values('ts').groupby('sel').tail(1)
        fut=df[(df.ts>snap_t)&(df.ts<=snap_t+pd.Timedelta(seconds=HOLD))]
        for _,r in snap.iterrows():
            bb,bl,bs,ls=float(r.bb),float(r.bl),float(r.bs or 0),float(r.ls or 0)
            if bl<=bb or bs<MIN_SIZE or ls<MIN_SIZE or bl>MAX_PRICE or nticks(bb,bl)>MAX_SPREAD: continue
            nt=nticks(bb,bl); fr=fut[fut.sel==r.sel]
            if fr.empty: continue
            for side in ('BACK','LAY'):
                q=(tick_up(bb) if nt>=2 else bb) if side=='BACK' else (tick_down(bl) if nt>=2 else bl)
                hit=fr[fr.bb>=tick_up(q)] if side=='BACK' else fr[fr.bl<=tick_down(q)]
                filled=len(hit)>0; pnl=None; adv=None
                if filled:
                    last=fr.iloc[-1]; ex=float(last.bl) if side=='BACK' else float(last.bb)   # unwind by taking the touch
                    pnl=trade_pnl(side,q,ex); mid2=(float(last.bb)+float(last.bl))/2; adv=(q/mid2-1) if side=='BACK' else (mid2/q-1)
                out.append((f"{label_prefix} +{off}s",side,filled,pnl,adv))
    return out
def summarise(name,res):
    if not res: lines.append(f"| {name} | 0 | | | | | |"); return
    R=pd.DataFrame(res,columns=['label','side','filled','pnl','adv'])
    for (lab,side),g in R.groupby(['label','side']):
        f=g[g.filled]; per=(f.pnl.sum()/(len(f)*STAKE)*100) if len(f) else None
        lines.append(f"| {lab} {side} | {len(g)} | {len(f)} | {len(f)/len(g):.0%} | {f.pnl.sum():+.2f} | {'n/a' if per is None else f'{per:+.2f}'} | {'n/a' if not f.adv.notna().any() else f'{f.adv.mean():+.2%}'} |")
    # control: random side at random offset
    f=R[R.filled]; ctrl=f.pnl.values*np.where(rng.random(len(f))<0.5,1,-1) if len(f) else np.array([])
    lines.append(f"| {name} CONTROL (random side) | {len(R)} | {len(f)} | {len(f)/max(1,len(R)):.0%} | {ctrl.sum():+.2f} | {'n/a' if not len(f) else f'{ctrl.sum()/(len(f)*STAKE)*100:+.2f}'} | |")
hdr=["| cell | quotes | fills | fill rate | £ | £ per £100 | adverse move at unwind |","|---|---|---|---|---|---|---|"]
# ---- (a) Betfair in-play, ten minutes after a goal
cur.execute("select distinct market_id, goal_ts, mkt from liq_goal_depth where offset_s=60 and goal_ts>now()-interval '21 days'"); goals=cur.fetchall()
print("goals with tape:",len(goals),flush=True); resA={'MO':[],'OU25':[]}
for i,(mid,gts,mkt) in enumerate(goals):
    cur.execute("select ts, sel, back_px, back_sz, lay_px, lay_sz from liq_sample where market_id=%s and ts between %s and %s order by ts",(mid,gts,gts+datetime.timedelta(seconds=HOLD+300)))
    rows=cur.fetchall()
    if len(rows)<20: continue
    resA.setdefault(mkt,[]).extend(replay_window(rows,(60,120,300),f"Betfair in-play {mkt} after goal"))
    if i%200==0: print(f"  {i}/{len(goals)}",flush=True)
lines+=["## (a) Betfair in-play: rest one tick inside the spread after a goal, unwind at the touch 10 min later","",*hdr]
for mkt,res in resA.items(): summarise(f"Betfair in-play {mkt}",res)
# ---- (b) Matchbook / Smarkets: pre-off last hour and in-play, by exchange
cur.execute("""select exchange, market_id, min(ts), max(ts), bool_or(inplay) from xx_tape where ts>now()-interval '21 days' and (sport ilike '%foot%' or sport ilike '%socc%')
               group by 1,2 having count(*)>200 order by 1,2"""); mk=cur.fetchall(); print("xx markets:",len(mk),flush=True)
resB={}
for i,(ex,mid,a,b,ip) in enumerate(mk):
    cur.execute("select ts, sel_name, back_px, back_sz, lay_px, lay_sz, inplay, start_ts from xx_tape where exchange=%s and market_id=%s order by ts",(ex,mid)); rows=cur.fetchall()
    pre=[(r[0],r[1],r[2],r[3],r[4],r[5]) for r in rows if not r[6] and r[7] is not None and 0<=(r[7]-r[0]).total_seconds()<=3600]
    inp=[(r[0],r[1],r[2],r[3],r[4],r[5]) for r in rows if r[6]]
    if len(pre)>50:
        for k in range(0,len(pre),max(1,len(pre)//6)):   # several quote times through the pre-off hour
            resB.setdefault((ex,'pre-off'),[]).extend(replay_window(pre[k:],(0,),f"{ex} pre-off"))
    if len(inp)>50:
        for k in range(0,len(inp),max(1,len(inp)//8)):
            resB.setdefault((ex,'in-play'),[]).extend(replay_window(inp[k:],(0,),f"{ex} in-play"))
    if i%300==0: print(f"  {i}/{len(mk)}",flush=True)
lines+=["","## (b) Matchbook and Smarkets: rest one tick inside the spread, unwind at the touch 10 min later","",*hdr]
for (ex,ph),res in sorted(resB.items()): summarise(f"{ex} {ph}",res)
out=f"/root/pe-queue/reports/replay_inplay_xx_{datetime.date.today()}.md"
open(out,'w').write(f"# Resting-order replay — in-play after goals (Betfair) and Matchbook/Smarkets — {datetime.date.today()} (job 558)\n\nTrades, not bets: a maker quote one tick inside the spread, filled when the touch crosses it (one tick adverse), unwound by taking the touch 10 minutes later; 2% commission on a profit; £2. Goals from liq_goal_depth (21 days); cross-exchange tape xx_tape (21 days).\n\n"+"\n".join(lines)+"\n")
print("\n".join(lines))
PYFILE
python3 -m py_compile replay_inplay_xx.py && echo compiles && timeout 7000 python3 replay_inplay_xx.py 2>&1 | tail -40
cd /root/pe-queue && git add reports/replay_inplay_xx_*.md && git commit -q -m "558: resting-order replay in-play after goals and on Matchbook/Smarkets" && git pull -q --rebase && git push -q && echo pushed
echo "562 done"
