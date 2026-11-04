#!/bin/bash
set -o pipefail
# 490 (Finder 2026-11-04, queue item 19, second of that number): TICK LEAD-LAG, MO DRAW v OU25 UNDER at 0-0 in-play, stream_ticks. PILOT: table rolls at about 3 days.
# PAIRING: MO and OU25 market ids share an event_name in liq_sample.
# 0-0 PROXY: stream_ticks has no score. From the first OPEN in-play tick until the first non-OPEN tick in either market, or a draw back price jump >= 25% between ticks. Betfair suspends on goals, so this is 0-0 or close to it; past data only. Entries start 60 s after the first OPEN tick. Red-card and VAR suspensions end the phase early, which only loses sample.
# SIGNAL at an Under tick, time t: SHORT = Under back_px at least 2 ticks shorter than the standing book at t-10 s (book at most 60 s old); DRIFT = at least 2 ticks longer. Draw touch, both sides, the same at t and t-10 s. Variant "both" also needs Under lay_px to move at least 1 tick the same way, to exclude a pulled order.
# TRADE: SHORT backs the draw at its standing back_px, one tick adverse, back_sz >= £10. DRIFT lays at lay_px, one tick adverse, lay_sz >= the stake. Exit at the standing opposite touch at +30 s / +60 s, one tick adverse. If the book is not OPEN then (a goal in the hold), exit at the next OPEN tick, never dropped; no later OPEN tick = the last valid book, counted. 60 s cooldown per game per line. LAG2 = entry book 2 s after the signal, diagnostic. CTRL = same trades every 300 s of the phase, no signal: what friction alone costs.
# COST: 2% commission, £10 risk. Halves: median game by start. t per trade, t_c clustered by game. FIRST = first signal per game. move = draw mid change over the hold, %.
# 403 (watchman fix of 490): the known-answer block assigned a test array to DB, overwriting the bot_core connection string, so psycopg2.connect(DB,...) raised TypeError; test variable renamed DBK, nothing else changed.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,warnings,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
warnings.filterwarnings('ignore')
pd.set_option('display.width',230); pd.set_option('display.max_rows',120); pd.set_option('display.max_columns',30)
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
LAD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    x=lo
    while x<hi-1e-9: LAD.append(round(x,2)); x+=st
LAD.append(1000.0); LAD=np.array(LAD)
def idx(p): return np.searchsorted(LAD,np.round(p,2)-1e-9)
def dn(p): return float(LAD[max(int(idx(p))-1,0)])
def up(p): return float(LAD[min(int(idx(p))+1,len(LAD)-1)])
def comm(x): return x*0.98 if x>0 else x
def back_trade(bp0,lp1):
    if bp0<=1.01: return None
    return comm(10*(dn(bp0)/up(lp1)-1))
def lay_trade(lp0,bp1):
    a=up(lp0); c=max(1.01,dn(bp1)); return comm(10/(a-1)*(1-a/c))
def phase(t,st,b):
    """(start, end) of the 0-0 proxy for one market's ticks in time order; end is the first non-OPEN tick or back jump >= 25% after the first OPEN tick."""
    op=np.flatnonzero(st)
    if len(op)==0: return None
    a=op[0]; end=np.inf
    for i in range(a+1,len(t)):
        if not st[i]: end=t[i]; break
        if np.isfinite(b[i]) and np.isfinite(b[i-1]) and b[i]>=b[i-1]*1.25: end=t[i]; break
    return t[a],end
def signals(ut,ub,ul,dt,db,dl,dok,t0,t1,sign,both):
    """Under ticks in (t0+60, t1) where the Under moved >= 2 ticks over 10 s in direction sign (-1 shorter, +1 longer) and the draw touch is unchanged. Cooled to 60 s."""
    ui=idx(ub); li=idx(ul); out=[]; last=-np.inf
    for i in range(len(ut)):
        t=ut[i]
        if t<=t0+60 or t>=t1 or t-last<60: continue
        r=np.searchsorted(ut,t-10,'right')-1
        if r<0 or t-ut[r]>60: continue
        if sign*(int(ui[i])-int(ui[r]))<2: continue
        if both and sign*(int(li[i])-int(li[r]))<1: continue
        a=np.searchsorted(dt,t,'right')-1; c=np.searchsorted(dt,t-10,'right')-1
        if a<0 or c<0 or not (dok[a] and dok[c]) or db[a]!=db[c] or dl[a]!=dl[c]: continue
        out.append(float(t)); last=t
    return out
def exit_row(dt,dok,t):
    """Standing OPEN book at t, else the next OPEN tick; flag True if none and the last valid book is used; None if no valid book at all."""
    j=int(np.searchsorted(dt,t,'right'))-1
    if j>=0 and dok[j]: return j,False
    s=max(j+1,0); k=np.flatnonzero(dok[s:])
    if len(k): return s+int(k[0]),False
    v=np.flatnonzero(dok)
    return (int(v[-1]),True) if len(v) else None
def tstat(v): return v.mean()/(v.std(ddof=1)/np.sqrt(len(v))) if len(v)>1 and v.std(ddof=1)>0 else 0.0
# known answers, worked by hand
assert dn(2.0)==1.99 and up(2.0)==2.02 and dn(3.0)==2.98 and up(3.0)==3.05 and int(idx(2.0))-int(idx(1.98))==2
assert abs(back_trade(5.0,4.0)-1.912195)<1e-6 and abs(back_trade(2.0,2.02)+0.245098)<1e-6 and back_trade(1.01,1.5) is None   # as job 469
assert abs(lay_trade(5.0,6.0)-0.324101)<1e-6 and abs(lay_trade(2.0,1.5)-(10/1.02*(1-2.02/1.49)))<1e-9
assert phase(np.array([0.,1,2,3]),np.array([False,True,True,False]),np.array([3.,3,3,3]))==(1.0,3.0)     # first OPEN at 1, suspended at 3
assert phase(np.array([0.,1,2]),np.array([True,True,True]),np.array([3.,3,3.75]))==(0.0,2.0)              # jump of exactly 25% ends it
assert phase(np.array([0.,1]),np.array([True,True]),np.array([3.,3.74]))==(0.0,np.inf) and phase(np.array([0.]),np.array([False]),np.array([3.])) is None
U=np.array([95.,100,108]); B=np.array([2.0,2.0,1.96]); L=np.array([2.02,2.02,1.98]); DT=np.array([90.,107]); DBK=np.array([3.5,3.5]); DL=np.array([3.55,3.55]); OK=np.array([True,True])
assert signals(U,B,L,DT,DBK,DL,OK,0,1e9,-1,False)==[108.0]                                                 # book at 98 is the 95 tick, 2.00 v 1.96 = 4 ticks; 95 and 100 have no book at t-10
assert signals(U,B,L,DT,DBK,DL,OK,0,1e9,+1,False)==[]                                                      # wrong direction
assert signals(U,B,L,DT,np.array([3.5,3.55]),DL,OK,0,1e9,-1,False)==[]                                    # draw moved inside the 10 s
assert signals(U,B,L,DT,DBK,DL,OK,0,108,-1,False)==[]                                                      # at or after phase end
assert signals(U,B,np.array([2.02,2.02,2.02]),DT,DBK,DL,OK,0,1e9,-1,True)==[]                              # "both": lay side did not move
assert signals(U,B,np.array([2.02,2.02,2.00]),DT,DBK,DL,OK,0,1e9,-1,True)==[108.0]                         # 2.02 to 2.00 is one tick; 2.01 is not on the ladder
U2=np.array([95.,100,108,120,175]); B2=np.array([2.0,2.0,1.98,1.96,1.94])
assert signals(U2,B2,B2+0.02,np.array([90.]),np.array([3.5]),np.array([3.55]),np.array([True]),0,1e9,-1,False)==[108.0,175.0]   # 120 is inside the cooldown; 175 v the 120 book (1.96) = 2 ticks
X=np.array([0.,10,20,30])
assert exit_row(X,np.array([True,False,False,True]),5)==(0,False) and exit_row(X,np.array([True,False,False,True]),15)==(3,False)   # a goal in the hold exits at the next OPEN tick
assert exit_row(np.array([0.,10]),np.array([True,False]),15)==(0,True) and exit_row(np.array([0.]),np.array([False]),5) is None
print("known-answer checks: OK",flush=True)

con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
cur.execute("SELECT min(ts_recv),max(ts_recv) FROM stream_ticks"); r0=cur.fetchone(); print("stream_ticks range:",r0[0],"..",r0[1],flush=True)
t00=time.time()
cur.execute("SELECT DISTINCT market_id,mkt,event_name FROM liq_sample WHERE ts>=%s AND mkt IN ('MO','OU25')",(r0[0]-pd.Timedelta(days=1),))
PM=pd.DataFrame(cur.fetchall(),columns=['mid','mkt','ev']); print(f"liq_sample market map {len(PM)} rows | {int(time.time()-t00)}s",flush=True)
pair=PM[PM.mkt=='MO'].merge(PM[PM.mkt=='OU25'],on='ev',suffixes=('_m','_o'))
pair=pair[~pair.mid_m.duplicated(keep=False)&~pair.mid_o.duplicated(keep=False)]
print("pairs",len(pair),flush=True)
if pair.empty: print("ERROR: no MO/OU25 pairs, so no verdict"); sys.exit(1)
parts=[]
for a in pd.date_range(pd.Timestamp(r0[0]).floor('6h'),pd.Timestamp(r0[1]),freq='6h'):
    cur.execute("""SELECT market_id,mkt,extract(epoch from ts_recv)::float8,status='OPEN',back_px::float8,back_sz::float8,lay_px::float8,lay_sz::float8,secs_to_off FROM stream_ticks
       WHERE ts_recv>=%s AND ts_recv<%s AND sport='football' AND inplay AND secs_to_off>-7500 AND ((mkt='MO' AND sel='The Draw') OR (mkt='OU25' AND sel='Under 2.5 Goals'))""",(a,a+pd.Timedelta(hours=6)))
    d=pd.DataFrame(cur.fetchall(),columns=['mid','mkt','t','op','bp','bs','lp','ls','sto']); parts.append(d)
    print(f"  chunk {a}: {len(d)} ticks ({int(time.time()-t00)}s)",flush=True)
T=pd.concat(parts,ignore_index=True); del parts
for c in ('bp','bs','lp','ls'): T[c]=pd.to_numeric(T[c],errors='coerce')
T=T[T.mid.isin(set(pair.mid_m)|set(pair.mid_o))].sort_values(['mid','t'],kind='stable')
print(f"ticks in paired markets {len(T)} | markets {T.mid.nunique()}",flush=True)
G={m:g for m,g in T.groupby('mid',sort=False)}
SK=defaultdict(int); rows=[]; ph=[]
def run(game,dt,db,dl,dbs,dls,dok,dsto,t,side,line,both,t1):
    for h in (30,60):
        for lag in (0,2):
            j=int(np.searchsorted(dt,t+lag,'right'))-1
            if j<0 or not dok[j]: SK[f'{side} no book at entry']+=1; continue
            if side=='B' and not dbs[j]>=10: SK['B size under £10']+=1; continue
            if side=='L' and not dls[j]>=10/(dl[j]-1): SK['L size under stake']+=1; continue
            e=exit_row(dt,dok,t+lag+h)
            if e is None: continue
            x,fl=e
            if x<j: x=j; fl=True
            p=back_trade(db[j],dl[x]) if side=='B' else lay_trade(dl[j],db[x])
            if p is None: SK['B under 1.02']+=1; continue
            m0=(db[j]+dl[j])/2; m1=(db[x]+dl[x])/2; el=-dsto[j]/60
            rows.append((line,side,both,h,lag,game,t,p,(m1/m0-1)*100,t+lag+h>=t1,fl,'<20' if el<20 else '20-45' if el<45 else '45-70' if el<70 else '70+','tight' if int(idx(dl[j]))-int(idx(db[j]))<=1 else 'wide'))
for r in pair.itertuples():
    if r.mid_m not in G or r.mid_o not in G: SK['no ticks in one market']+=1; continue
    D=G[r.mid_m]; O=G[r.mid_o]
    dt=D.t.values; dst=D.op.values.astype(bool); db=D.bp.values; dl=D.lp.values; dbs=D.bs.values; dls=D.ls.values; dsto=D.sto.values
    dok=dst&np.isfinite(db)&np.isfinite(dl)&(db>1)&(dl>db)&(dl<1000)
    ut=O.t.values; ust=O.op.values.astype(bool); ub=O.bp.values; ul=O.lp.values
    p1=phase(dt,dst,db); p2=phase(ut,ust,ub)
    if p1 is None or p2 is None: SK['no OPEN ticks']+=1; continue
    t0=max(p1[0],p2[0]); t1=min(p1[1],p2[1]); ended=np.isfinite(t1)
    ph.append((min(t1,dt[-1])-t0,ended))
    if min(t1,dt[-1])<=t0+60: SK['phase under 60 s']+=1; continue
    v=ust&np.isfinite(ub)&np.isfinite(ul)&(ub>1)&(ul>ub)&(ul<1000)&(ut>=t0-60)&(ut<min(t1,dt[-1]))
    uu,bu,lu=ut[v],ub[v],ul[v]
    for both in (False,True):
        for sign,side,line in ((-1,'B','SHORT back draw'),(1,'L','DRIFT lay draw')):
            for t in signals(uu,bu,lu,dt,db,dl,dok,t0,min(t1,dt[-1]),sign,both):
                run(r.mid_m,dt,db,dl,dbs,dls,dok,dsto,t,side,line,both,t1)
    for t in np.arange(t0+60,min(t1,dt[-1]),300.0):
        run(r.mid_m,dt,db,dl,dbs,dls,dok,dsto,float(t),'B','CTRL back draw',False,t1); run(r.mid_m,dt,db,dl,dbs,dls,dok,dsto,float(t),'L','CTRL lay draw',False,t1)
print("skips:",dict(SK),flush=True)
P=pd.DataFrame(ph,columns=['secs','ended']); print(f"0-0 proxy: games {len(P)} | ended by a suspension or jump {P.ended.mean():.1%} | phase minutes quantiles 10/50/90: {(P.secs/60).quantile([.1,.5,.9]).round(1).tolist()}",flush=True)
R=pd.DataFrame(rows,columns=['line','side','both','h','lag','game','t','pnl','move','goal','noexit','el','sp'])
if R.empty: print("\n== SURVIVORS: 0\nnone"); sys.exit()
gs=R.groupby('game').t.min().sort_values(); mdt=gs.iloc[len(gs)//2]; first_half=set(gs[gs<mdt].index)
print(f"trades {len(R)} | games {R.game.nunique()} | split at {pd.Timestamp(mdt,unit='s')} | goal-in-hold {R.goal.mean():.1%} | no later OPEN tick {R.noexit.sum()}",flush=True)
def row(d,**k):
    v=d.pnl; a=d[d.game.isin(first_half)].pnl; b=d[~d.game.isin(first_half)].pnl; c=d.groupby('game').pnl.sum()
    return dict(**k,n=len(v),games=d.game.nunique(),per10=v.mean(),t=tstat(v),t_c=tstat(c),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,move=d.move.mean(),goal=d.goal.mean(),
        PASS=(not k['line'].startswith('CTRL')) and k['lag']==0 and len(v)>=300 and len(a)>=150 and len(b)>=150 and tstat(v)>=3.5 and a.mean()>0 and b.mean()>0 and v.mean()>=0.15)
out=[]
for (ln,sd,bo,h,lag),d in R.groupby(['line','side','both','h','lag']):
    k=dict(line=ln,both=bo,h=h,lag=lag,cut='-'); out.append(row(d,**k))
    if not ln.startswith('CTRL'):
        k2=dict(k); k2['cut']='FIRST'; out.append(row(d.sort_values('t').groupby('game').head(1),**k2))
        if lag==0:
            for dim in ('el','sp'):
                for val,dd in d.groupby(dim):
                    k3=dict(k); k3['cut']=f'{dim} {val}'; out.append(row(dd,**k3))
S=pd.DataFrame(out).sort_values('t',ascending=False)
print("\n== HEADLINE: all lines, cut -")
print(S[S.cut=='-'].round(3).to_string(index=False))
print("\n== TOP 15 by t, every cut, lag 0 and not control")
print(S[(S.lag==0)&(~S.line.str.startswith('CTRL'))].head(15).round(3).to_string(index=False))
W=S[S.PASS==True]; print(f"\n== SURVIVORS: {len(W)} of {len(S)} lines"); print(W.round(3).to_string(index=False) if len(W) else "none")
PY
