#!/bin/bash
set -o pipefail
# 487 (Finder 2026-11-04, queue item 32): RACING PLACE MARKET IN-PLAY on ip_tape. PILOT: the tape rolls at about 6 days, so race-level lines cannot reach n 300.
# STALE FRAMES: ip_tape replays old books (total_matched falls, prices jump back). A frame is dropped when its total_matched is below the running max of earlier frames. Past data only, so a live bot could do the same.
# SNAPSHOT: status OPEN, secs_since_start > 0. The tape has no in-play flag, so the first frame may be just before the off when the off is late (said in the report).
# RESULT: placed = ltp <= 1.05 on the runner's last clean frame, any status. KNOWN only if the placed count fits the field (<=7: 2, 8-15: 3, 16+: 3 or 4) and the WIN winner from racing_results, where present, is among the placed. Only WORST (unknown = -£10) can pass; KNOWN is a diagnostic.
# FILL: BACK = worse of this frame's and the next clean frame's back_px, less one tick, back_sz >= £10 on the entry frame. LAY = worse lay_px, plus one tick, entry lay_px < 100 (980 is a junk order, not a market), lay_sz >= the stake. TOUCH column = entry frame only, no latency, diagnostic.
# TRADES: (A) every runner at the first clean frame, back and lay, by price band and field; (B) place favourite at the first frame; (C) WIN favourite drifts >= 15/30/50% in-play: first clean PLACE frame after the WIN trigger, within 60 s, lay it to place; the back mirror as a diagnostic; control = lay the WIN favourite to place at the first frame.
# (D) the same first-frame trades on tight books only (lay/back <= 1.25), with a calibration table, implied v placed, as the independent check on the result labels. Number clash: another lane took 487 first (487_racing_inplay_hist); this file could not be renamed unattended.
# COST: 2% commission, £10 risk. Halves: date median of market_start. t = per trade; t_c = clustered by race (sum per race).
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,warnings,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
from functools import lru_cache
warnings.filterwarnings('ignore')
pd.set_option('display.width',230); pd.set_option('display.max_rows',120); pd.set_option('display.max_columns',30)
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
LAD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    x=lo
    while x<hi-1e-9: LAD.append(round(x,2)); x+=st
LAD.append(1000.0); LADA=np.array(LAD)
@lru_cache(maxsize=None)
def dn(p): return float(LADA[max(int(np.searchsorted(LADA,round(p,2)-1e-9))-1,0)])
@lru_cache(maxsize=None)
def up(p): return float(LADA[min(int(np.searchsorted(LADA,round(p,2)-1e-9))+1,len(LADA)-1)])
def back_pnl(p,won):
    a=dn(p)
    if a<=1.01: return None
    return 10*(a-1)*0.98 if won else -10.0
def lay_pnl(p,won):
    a=up(p); return -10.0 if won else 10/(a-1)*0.98
def clean_mask(tm):
    """True where total_matched is not below the running max of earlier frames."""
    tm=np.asarray(tm,dtype=float); keep=np.ones(len(tm),bool); mx=-np.inf
    for i,v in enumerate(tm):
        if np.isnan(v): keep[i]=False; continue
        if v<mx: keep[i]=False
        else: mx=v
    return keep
def allowed(field): return {2} if field<=7 else {3} if field<=15 else {3,4}
def label(placed,field,winner):
    """placed: set of runners; returns placed if the count fits the field and the known winner is in it, else None."""
    if len(placed) not in allowed(field): return None
    if winner is not None and winner not in placed: return None
    return placed
def drift_at(series,x):
    """series: (frame position, back_px) in time order. First later point at or above off*(1+x)."""
    off=series[0][1]
    for i,(_,b) in enumerate(series[1:],1):
        if b>=off*(1+x)-1e-9: return i
    return None
def band(p): return '<1.5' if p<1.5 else '1.5-2' if p<2 else '2-3' if p<3 else '3-5' if p<5 else '5-10' if p<10 else '10+'
# known answers, worked by hand
assert abs(back_pnl(3.0,True)-10*1.98*0.98)<1e-9 and back_pnl(3.0,False)==-10.0 and back_pnl(1.02,True) is None   # 3.0 fills 2.98; 1.02 fills 1.01, nothing to win
assert abs(lay_pnl(3.0,False)-10/2.05*0.98)<1e-9 and lay_pnl(3.0,True)==-10.0                                      # 3.0 fills 3.05
assert clean_mask([10,12,11,12,13,12.5]).tolist()==[True,True,False,True,True,False]                               # 11 and 12.5 are replays; an equal 12 stays
assert clean_mask([10,float('nan'),11]).tolist()==[True,False,True]
assert label({'a','b'},7,'a')=={'a','b'} and label({'a','b'},8,'a') is None and label({'a','b','c'},9,'z') is None and label({'a','b','c'},16,None)=={'a','b','c'}
assert drift_at([(0,2.0),(1,2.5),(2,2.6)],0.30)==2 and drift_at([(0,2.0),(1,2.5)],0.25)==1 and drift_at([(0,2.0),(1,2.5)],0.30) is None
assert band(1.49)=='<1.5' and band(2.0)=='2-3' and band(10.0)=='10+'
print("known-answer checks: OK",flush=True)

con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
t0=time.time(); frames=[]
day=pd.Timestamp('2026-10-25',tz='UTC'); end=pd.Timestamp.now(tz='UTC')+pd.Timedelta(days=1)
while day<end:
    d=pd.read_sql("""SELECT ts,market_id,market_type mt,event_name,market_start,status,secs_since_start ss,sel_id,sel_name,ltp::float ltp,back_px::float bp,back_sz::float bs,lay_px::float lp,lay_sz::float ls,total_matched::float tm FROM ip_tape
       WHERE sport='horse_racing' AND market_type IN ('PLACE','WIN') AND ts>=%s AND ts<%s""",con,params=(day,day+pd.Timedelta(days=1)))
    if len(d): frames.append(d)
    print(f"  {day.date()} rows {len(d)} | {int(time.time()-t0)}s",flush=True)
    day+=pd.Timedelta(days=1)
if not frames: print("ERROR: no racing rows pulled, so no verdict"); sys.exit(1)
A=pd.concat(frames,ignore_index=True)
Pm=A[A.mt=='PLACE'].drop_duplicates('market_id')[['market_id','event_name','market_start']]
Wm=A[A.mt=='WIN'].drop_duplicates('market_id')[['market_id','event_name','market_start']]
pair=Pm.merge(Wm,on=['event_name','market_start'],suffixes=('','_w'))
print(f"rows {len(A)} | place markets {len(Pm)} | win markets {len(Wm)} | paired {len(pair)} | {A.ts.min()} .. {A.ts.max()}",flush=True)
rr=pd.read_sql("SELECT market_id,selection_id,won FROM racing_results WHERE market_id=ANY(%s) AND won IS TRUE",con,params=(pair.market_id_w.tolist(),))
WIN=rr.groupby('market_id').selection_id.agg(list).to_dict()
print(f"racing_results winners for {len(WIN)} of {len(pair)} paired races",flush=True)
def clean(g):
    f=g.groupby('ts',sort=True).tm.max().reset_index(); f['keep']=clean_mask(f.tm.values); return f
SK=defaultdict(int); st=defaultdict(int); rows=[]; lab_ok=lab_bad=0; wchk=[0,0]; opens=[]; cal=[]; calw=[]; kept=[]
Wg=dict(tuple(A[A.mt=='WIN'].groupby('market_id',sort=False))); Pg=dict(tuple(A[A.mt=='PLACE'].groupby('market_id',sort=False)))
for r in pair.itertuples():
    mid=r.market_id; g=Pg[mid]; f=clean(g); st['place frames']+=len(f); st['place stale']+=int((~f.keep).sum())
    ok=set(f[f.keep].ts)
    raw_open=g[(g.status=='OPEN')&(g.ss>0)].ts.nunique(); clean_open=g[(g.status=='OPEN')&(g.ss>0)&g.ts.isin(ok)].ts.nunique(); kept.append((raw_open,clean_open))
    g=g[g.ts.isin(ok)].sort_values('ts')
    if g.empty: SK['no clean frame']+=1; continue
    last=g.groupby('sel_id').tail(1); field=last.sel_id.nunique(); placed=set(last[last.ltp<=1.05].sel_id)
    wl=WIN.get(r.market_id_w); winner=wl[0] if wl and len(wl)==1 else None
    if winner is not None: wchk[0]+=1; wchk[1]+=int(winner in placed)
    res=label(placed,field,winner); known=res is not None; lab_ok+=int(known); lab_bad+=int(not known)
    o=g[(g.status=='OPEN')&(g.ss>0)]; tss=sorted(o.ts.unique())
    if len(tss)<2: SK['under 2 open frames']+=1; continue
    idx={t:i for i,t in enumerate(tss)}; bk={}
    for x in o.itertuples(): bk[(idx[x.ts],x.sel_id)]=x
    d0=pd.Timestamp(r.market_start).date(); fb='<=7' if field<=7 else '8+'
    def enter(i,sid,side):
        """Real touch at frame i, worse of frame i and i+1. Returns (fill, touch) or None."""
        e=bk.get((i,sid))
        if e is None: return None
        nx=bk.get((i+1,sid))
        if side=='B':
            if not (pd.notna(e.bp) and e.bp>1) or not (pd.notna(e.bs) and e.bs>=10): return None
            nb=nx.bp if nx is not None and pd.notna(nx.bp) and nx.bp>1 else e.bp
            return min(e.bp,nb),e.bp
        if not (pd.notna(e.lp) and 1<e.lp<100) or not (pd.notna(e.ls) and e.ls>=10/(e.lp-1)): return None
        nl=nx.lp if nx is not None and pd.notna(nx.lp) and nx.lp<1000 else e.lp
        return max(e.lp,nl),e.lp
    def add(line,sid,side,i,**k):
        q=enter(i,sid,side)
        if q is None: st[f'unfilled {line.split()[0]} {side}']+=1; return
        fill,touch=q; w=None if not known else (sid in res)
        fn=back_pnl if side=='B' else lay_pnl
        p=fn(fill,w) if w is not None else -10.0; t=fn(touch,w) if w is not None else -10.0
        if p is None or t is None: st['back under 1.02, no trade']+=1; return
        rows.append(dict(line=line,side=side,market=mid,sid=sid,day=d0,known=known,pnl=p,touch=t,**k))
    f0=o[o.ts==tss[0]]; opens.append(f0.assign(ratio=f0.lp/f0.bp))
    runners=[x for x in f0.itertuples() if pd.notna(x.bp) and x.bp>1]
    # (D) tight books only: a first frame quoted both sides within 25% is a live market; a wide one has already collapsed. Calibration checks the labels: implied v actual.
    for x in runners:
        if pd.notna(x.lp) and x.lp/x.bp<=1.25:
            if known: cal.append((band(x.bp),2/(x.bp+x.lp),int(x.sel_id in res)))
            for side in 'BL':
                add('D tight all',x.sel_id,side,0); add(f'D tight {band(x.bp)}',x.sel_id,side,0)
        elif known and pd.notna(x.lp): calw.append((band(x.bp),1/x.bp,int(x.sel_id in res)))
    for x in runners:
        for side in 'BL':
            add(f'A first {band(x.bp)}',x.sel_id,side,0)
            add(f'A first {band(x.bp)} f{fb}',x.sel_id,side,0)
            add('A first all',x.sel_id,side,0)
    if runners:
        pf=min(runners,key=lambda x:x.bp)
        for side in 'BL': add('B place fav first',pf.sel_id,side,0)
    # (C) WIN favourite drift. Only earlier WIN frames can set the trigger.
    wg=Wg[r.market_id_w]; wf=clean(wg); st['win frames']+=len(wf); st['win stale']+=int((~wf.keep).sum())
    wg=wg[wg.ts.isin(set(wf[wf.keep].ts))&(wg.status=='OPEN')&(wg.ss>0)&(wg.bp>1)].sort_values('ts')
    if wg.empty: SK['no win frames']+=1; continue
    w0=wg[wg.ts==wg.ts.iloc[0]]; fav=w0.loc[w0.bp.idxmin()].sel_id
    if fav not in set(o.sel_id): SK['win fav not in place tape']+=1; continue
    add('C ctrl win fav first',fav,'L',0)
    s=wg[wg.sel_id==fav]; ser=[(t,float(b)) for t,b in zip(s.ts,s.bp)]
    if s.ts.iloc[0]!=w0.ts.iloc[0]: continue
    for x_,lab in ((0.15,'15%'),(0.30,'30%'),(0.50,'50%')):
        i=drift_at(ser,x_)
        if i is None: continue
        st[f'drift signal {lab}']+=1; tg=ser[i][0]
        later=[t for t in tss if t>tg and (t-tg).total_seconds()<=60]
        if not later: st[f'drift no place frame in 60 s {lab}']+=1; continue
        add(f'C drift {lab}',fav,'L',idx[later[0]]); add(f'C drift {lab}',fav,'B',idx[later[0]])
print("skips:",dict(SK)); print("counts:",dict(st))
print(f"stale frames: place {st['place stale']}/{st['place frames']} = {st['place stale']/max(st['place frames'],1):.1%} | win {st['win stale']}/{st['win frames']} = {st['win stale']/max(st['win frames'],1):.1%}")
print(f"result labels: known {lab_ok}, unknown {lab_bad}; racing_results winner among inferred placed {wchk[1]}/{wchk[0]}",flush=True)
if opens:
    O=pd.concat(opens); print("first frame lay/back ratio median:",round(O.ratio.median(),3),"| share with lay<100:",round((O.lp<100).mean(),3),"| median secs since scheduled off:",O.ss.median())
K=pd.DataFrame(kept,columns=['raw','clean']); print(f"open frames per market: raw median {K.raw.median()}, clean median {K.clean.median()}; markets with >=2 open frames raw {(K.raw>=2).sum()}, clean {(K.clean>=2).sum()}; markets keeping under half {(K.clean<K.raw/2).sum()}")
for nm,c_ in (('TIGHT first frame (lay/back <= 1.25), implied = 1/mid',cal),('WIDE first frame, implied = 1/back',calw)):
    if c_:
        C=pd.DataFrame(c_,columns=['band','implied','placed']); print(f"calibration, known results, {nm}:\n",C.groupby('band').agg(n=('placed','size'),implied=('implied','mean'),placed=('placed','mean')).round(3).to_string())
for sp in ('tennis','horse_racing','basketball'):
    x=pd.read_sql("SELECT market_id,ts,max(total_matched)::float tm FROM ip_tape WHERE sport=%s AND ts>=now()-interval '2 days' AND status='OPEN' GROUP BY 1,2 ORDER BY 1,2",con,params=(sp,))
    if len(x):
        drop=sum((~clean_mask(v.values)).sum() for _,v in x.groupby('market_id').tm); print(f"stale frames last 2 days, {sp}: {drop}/{len(x)} = {drop/len(x):.1%}",flush=True)
R=pd.DataFrame(rows)
if R.empty: print("\n== SURVIVORS: 0\nnone"); sys.exit()
days=sorted(R.day.unique()); md=days[len(days)//2]; print(f"entries {len(R)} | races {R.market.nunique()} | days {days[0]}..{days[-1]} | second half from {md}",flush=True)
def tstat(v): return v.mean()/(v.std(ddof=1)/np.sqrt(len(v))) if len(v)>1 and v.std(ddof=1)>0 else 0.0
out=[]
for (ln,sd),d in R.groupby(['line','side']):
    v=d.pnl; a=d[d.day<md].pnl; b=d[d.day>=md].pnl; kn=d[d.known].pnl; c=d.groupby('market').pnl.sum()
    out.append(dict(line=ln,side=sd,n=len(v),races=d.market.nunique(),per10=v.mean(),t=tstat(v),t_c=tstat(c),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,touch=d.touch.mean(),known=kn.mean() if len(kn) else np.nan,n_known=len(kn),
        PASS=len(v)>=300 and len(a)>=150 and len(b)>=150 and tstat(v)>=3.5 and a.mean()>0 and b.mean()>0 and v.mean()>=0.15))
S=pd.DataFrame(out).sort_values('t',ascending=False)
print("\n== RESULTS per £10 (per10 and t count unknown results as -£10; touch and known are diagnostics, never eligible)\n",S.round(3).to_string(index=False))
W=S[S.PASS==True]; print(f"\n== SURVIVORS: {len(W)} of {len(S)} lines"); print(W.round(3).to_string(index=False) if len(W) else "none")
PY
