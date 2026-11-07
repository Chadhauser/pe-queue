#!/bin/bash
set -o pipefail
# 499_equaliser_stress (Finder 2026-11-07, item 430 stress of the one numeric pass in jobs/499_equaliser_side.sh: FIRST LAY ALL n 1,683 +0.664 t 3.52; its largest win 98 is a lay near 1.11, which a post-equaliser price cannot be, so the clock is suspect). Copied from 499_equaliser_side, queue item 430, Finder's own, source a): AFTER A SECOND-HALF EQUALISER TO 1-1, back or lay the equaliser, the side that scored first, or the Draw. 450-499 are all taken, so 499 is reused with a new slug.
# Data: local DB (creds.pg_local): af_price_map x af_fixtures x af_events x bf_hist_price MO. Read only. Style and fill rules from jobs/499_draw_22_late.sh.
# SIGNAL: the game's second goal makes it 1-1 at af minute E; t = E+3 (guard against the tape clock). E 46-80 = the item; E 10-40 = CONTROL (cannot pass). A third goal at or before t = no signal.
# FILL: first real MO print of that runner in tape minutes t+1..t+3, never forward-filled (none = no trade, counted). Back at one tick under the print, lay at one tick over. Prices 1.01-50 only.
# EXIT: held to the af FT score; never dropped on its result. £10 back stake, £10 lay liability, 2% on profit. One bet a game per line.
# DROPPED FOR DATA: goal events that do not add up to the FT score; first print outside -5..+20 min of the af kick-off. Counted.
# STRESS: L (t=E+L) 3, 6, 10; PRICED = FIRST's entry print at least 1.25 x its last print in af minutes E-6..E-1 (the leader must have drifted on the goal); 3 ticks adverse; without the 1% largest wins; by price band; CLOCK = median FIRST price by tape minute minus E.
# HALVES: season 2024 v 2025. Bar: n>=300, n>=150 per half, both halves > 0, t>=3.5, mean >= +0.15 per £10.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
sys.path.insert(0,'/root/pe-queue/runner'); import creds
pd.set_option('display.width',240); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',40)
T0=time.time()
LD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    v=lo
    while v<hi-1e-9: LD.append(round(v,2)); v+=st
LD.append(1000.0); LD=np.array(LD)
def ix(p): return int(np.searchsorted(LD,round(float(p),2)-1e-9))
def dn(p,k=1): return float(LD[max(ix(p)-k,0)])
def up(p,k=1): return float(LD[min(ix(p)+k,len(LD)-1)])
def net(x): return x*0.98 if x>0 else x
def back_settle(a,won): return net(10*(a-1) if won else -10.0)
def lay_settle(a,won): return -10.0 if won else net(10/(a-1))
def first_print(arr,lo,hi):
    for m in range(max(lo,0),min(hi,len(arr))):
        if not np.isnan(arr[m]): return m
    return None
def eq_signal(gl):
    """gl sorted [(minute,'h'|'a')]. If goals 1 and 2 are by different sides, return (E, first scorer, equaliser), else None."""
    if len(gl)<2 or gl[0][1]==gl[1][1]: return None
    return gl[1][0],gl[0][1],gl[1][1]
def tstat(x):
    x=np.asarray(x,dtype=float); s=x.std(ddof=1) if len(x)>1 else 0
    return float(x.mean()/(s/len(x)**0.5)) if s>0 else 0.0
# known answers, worked by hand: back 3.0 -> 2.98, wins 10*1.98*.98 = 19.404, loses -10. Lay 3.0 -> 3.05, wins 10/2.05*.98 = 4.780488, loses -10.
assert dn(3.0)==2.98 and up(3.0)==3.05 and up(2.0)==2.02 and dn(2.0)==1.99 and up(1.99)==2.0
assert abs(back_settle(2.98,True)-19.404)<1e-9 and back_settle(2.98,False)==-10.0
assert abs(lay_settle(3.05,False)-4.780488)<1e-6 and lay_settle(3.05,True)==-10.0
assert eq_signal([(20,'h'),(60,'a'),(70,'h')])==(60,'h','a') and eq_signal([(20,'h'),(60,'h')]) is None and eq_signal([(20,'h')]) is None
A_=np.full(131,np.nan); A_[66]=2.5
assert first_print(A_,64,67)==66 and first_print(A_,64,66) is None
assert abs(tstat([1,3])-2.0)<1e-9
print("known-answer checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'"); cur.execute("SET statement_timeout='2400s'")
G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.league,f.season,f.kickoff,f.hg,f.ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL""",con)
G=G.drop_duplicates('event_id')
print(f"mapped FT games {len(G):,}, seasons {sorted(G.season.unique())}",flush=True)
EV=pd.read_sql("SELECT fixture_id,coalesce(minute,0) mn,is_home FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal')",con,params=(list(map(int,G.fixture_id)),))
goals=defaultdict(list)
for r in EV.itertuples(): goals[r.fixture_id].append((int(r.mn),'h' if r.is_home else 'a'))
for k in goals: goals[k].sort(key=lambda z:z[0])
SEL={'h':'HOME','a':'AWAY'}
rows=[]; cnt=defaultdict(int); clock=defaultdict(list)
for i in range(0,len(G),1000):
    sub=G.iloc[i:i+1000]
    P=pd.read_sql("SELECT event_id,minute,m,sel,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt='MO' AND sel IN ('HOME','AWAY','DRAW') AND minute BETWEEN 0 AND 130 AND ltp>=1.01 AND ltp<1000",con,params=(list(sub.event_id),))
    P=P.sort_values('m').drop_duplicates(['event_id','sel','minute'])
    byev={e:x for e,x in P.groupby('event_id')}
    for g in sub.itertuples():
        x=byev.get(g.event_id)
        if x is None: cnt['no MO prints']+=1; continue
        gl=goals.get(g.fixture_id,[]); hg,ag=int(g.hg),int(g.ag)
        if sum(s=='h' for _,s in gl)!=hg or sum(s=='a' for _,s in gl)!=ag: cnt['goal events do not match FT']+=1; continue
        arr={}
        for s_,y in x.groupby('sel'):
            a=np.full(131,np.nan); a[y.minute.values]=y.ltp.values; arr[s_]=a
        if 'HOME' not in arr or 'AWAY' not in arr or 'DRAW' not in arr: cnt['a runner missing']+=1; continue
        h0=first_print(arr['HOME'],0,3); a0=first_print(arr['AWAY'],0,3)
        if h0 is None or a0 is None: cnt['no pre-off/first print at minute 0-2']+=1; continue
        fm=x[x.sel.isin(['HOME','AWAY'])].m.min()
        lag=(pd.to_datetime(fm,utc=True)-pd.to_datetime(g.kickoff,utc=True)).total_seconds()/60
        if not -5<=lag<=20: cnt['first print outside kick-off window']+=1; continue
        cnt['games used']+=1
        sg=eq_signal(gl)
        if sg is None: continue
        E,first,eq=sg
        grp='ITEM' if 46<=E<=80 else ('CONTROL' if 10<=E<=40 else None)
        if grp is None: continue
        favside='h' if arr['HOME'][h0]<=arr['AWAY'][a0] else 'a'
        res='h' if hg>ag else ('a' if ag>hg else 'd')
        fa=arr[SEL[first]]
        if grp=='ITEM' and (len(gl)==2 or gl[2][0]>E+12):
            for o in range(-6,13):
                if 0<=E+o<131 and not np.isnan(fa[E+o]): clock[o].append(fa[E+o])
        pre=[fa[m] for m in range(max(E-6,0),E) if not np.isnan(fa[m])]
        for L in (3,6,10):
            t=E+L
            if len(gl)>2 and gl[2][0]<=t: cnt[f'{grp} L{L} third goal by t']+=1; continue
            cnt[f'{grp} L{L} signals']+=1
            sel=SEL[first]; ent=first_print(fa,t+1,t+4)
            if ent is None: cnt[f'{grp} L{L} no print']+=1; continue
            p=float(fa[ent])
            if p>50: continue
            won=(res==first); priced=bool(pre) and p>=1.25*pre[-1]
            rows.append(dict(grp=grp,L=L,event_id=g.event_id,season=int(g.season),E=E,p=p,won=won,v=lay_settle(up(p),won),v3=lay_settle(up(p,3),won),priced=priced,haspre=bool(pre),eqfav=('FAV' if eq==favside else 'DOG')))
    print(f"  {min(i+1000,len(G))}/{len(G)} {time.time()-T0:.0f}s",flush=True)
R=pd.DataFrame(rows); assert not R.duplicated(['grp','L','event_id']).any()
print("\ncounts:",dict(cnt))
print("\n== CLOCK: median price of the side that scored first, by tape minute minus af minute of the equaliser (E 46-80, no third goal within 12 min)")
print(" ".join(f"{o:+d}:{np.median(clock[o]):.2f}(n{len(clock[o])})" for o in sorted(clock)))
def line(d,c='v'):
    a=d[d.season==2024][c]; b=d[d.season==2025][c]; v=d[c]
    r=dict(n=len(v),px=d.p.median(),won=d.won.mean(),imp=(1/d.p).mean(),per10=v.mean(),t=tstat(v),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,max_win=v.max() if len(v) else np.nan)
    r['PASS']=bool(r['n']>=300 and r['n1']>=150 and r['n2']>=150 and r['t']>=3.5 and r['h1']>0 and r['h2']>0 and r['per10']>=0.15); return r
o=[]
for (grp,L),d in R.groupby(['grp','L']):
    o.append(dict(grp=grp,L=L,cut='ALL',ex='1 tick',**line(d)))
    o.append(dict(grp=grp,L=L,cut='ALL',ex='3 ticks',**line(d,'v3')))
    o.append(dict(grp=grp,L=L,cut='PRICED',ex='1 tick',**line(d[d.priced])))
    o.append(dict(grp=grp,L=L,cut='PRICED',ex='3 ticks',**line(d[d.priced],'v3')))
    o.append(dict(grp=grp,L=L,cut='NOT_PRICED',ex='1 tick',**line(d[d.haspre&~d.priced])))
    o.append(dict(grp=grp,L=L,cut='p>=2',ex='1 tick',**line(d[d.p>=2])))
    q=d.v.quantile(0.99); o.append(dict(grp=grp,L=L,cut='less top 1%',ex='1 tick',**line(d[d.v<q])))
T=pd.DataFrame(o)
print("\n== FIRST LAY stress lines\n",T.round(3).to_string(index=False))
B=R[(R.grp=='ITEM')&(R.L==3)].copy(); B['pb']=pd.cut(B.p,[1,1.5,2,3,4,6,10,50])
u=[]
for kk,d in B.groupby('pb',observed=True): u.append(dict(band=str(kk),**line(d)))
print("\n-- ITEM L3 by entry price\n",pd.DataFrame(u).drop(columns=['PASS']).round(3).to_string(index=False))
W=T[T.PASS&(T.grp=='ITEM')]
print(f"\n== SURVIVORS: {len(W)} of {int((T.grp=='ITEM').sum())} ITEM stress lines (one bet a game per line; lines share games)")
print(W.round(3).to_string(index=False) if len(W) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
