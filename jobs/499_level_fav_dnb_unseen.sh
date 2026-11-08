#!/bin/bash
set -o pipefail
# 499_level_fav_dnb_unseen (Finder 2026-11-08, queue item 450, Finder's own, source c, from item 449; built from jobs/499_level_late_dnb.sh, rule fixed in the queue before this job read a price).
# Back the pre-off favourite's Draw No Bet at a level score with goals (LEVEL_G, G = 2 or 4 goals seen) late, one entry per game, on months no read has used: Jan and Feb 2023 (Soccer 2023-01 and 2023-02 read DONE on the loader 8 Nov; item 449 read Mar 2023 on).
# LEVEL_G: OU(G-0.5) Over printed at 1.05 or under 3+ min before entry, OU(G+0.5) Over not before entry, and the MO draw shortest at entry (MO last print within 180 s, no forward fill past it).
# Entry: the favourite's first DNB print from 75 to 103 min after the first in-play MO print at which LEVEL_G holds; one per game. Back at the worse of the print and the next within 120 s, one tick adverse, GBP 10, 2%.
# Settlement on the official MATCH_ODDS winner, a draw pays 0 (DNB official results omit drawn games); checks DNB winner = MO winner on non-drawn games, at least 99%, or stops.
# Read only, no tables written. Prints only, so a pass is an upper bound.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line
from lib_official import bk,ly,fill,first_in,last_in,secs,checks,group
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',230); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',300)
LO_MIN,HI_MIN=75,103
LOOK=180
MONTHS=((2023,range(1,3)),)
def dnb_back(p,outcome):
    """outcome: 'W' runner won, 'L' runner lost, 'D' draw (void, 0)."""
    if outcome=='D': return 0.0
    return bk(p,outcome=='W')
def dnb_lay(p,outcome):
    if outcome=='D': return 0.0
    return ly(p,outcome=='W')
def level_g(G,entry,seen):
    """seen: dict line -> first ts the Over printed at 1.05 or under. G goals seen 3+ min before entry, goal G+1 not before entry."""
    lo,hi=seen.get(G-0.5),seen.get(G+0.5)
    return (lo is not None and lo<=entry-180) and (hi is None or hi>=entry)
def state(entry,seen):
    for G in (2,4):
        if level_g(G,entry,seen): return G
    return None
def draw_shortest(h,a,d): return d is not None and h is not None and a is not None and d<h and d<a
def band(p): return 'STRONG' if p<1.6 else 'NEAR'
# known answers, worked by hand
# back DNB 2.0 -> 1.99: wins 9.9*0.98=9.702; loses -10; draw 0. lay 2.0 -> 2.02: stake 10/1.02, runner loses -> +9.6078; runner wins -> -10; draw 0.
assert abs(dnb_back(2.0,'W')-9.702)<1e-9 and dnb_back(2.0,'L')==-10.0 and dnb_back(2.0,'D')==0.0
assert abs(dnb_lay(2.0,'L')-10/1.02*0.98)<1e-9 and dnb_lay(2.0,'W')==-10.0 and dnb_lay(2.0,'D')==0.0
assert state(1000,{0.5:10,1.5:820})==2 and state(1000,{0.5:10,1.5:821}) is None and state(1000,{1.5:10,2.5:999}) is None and state(1000,{1.5:10,2.5:1000})==2
assert state(1000,{0.5:10}) is None and state(1000,{}) is None and state(1000,{1.5:5,2.5:6,3.5:7})==4 and state(1000,{1.5:5,2.5:6,3.5:7,4.5:900}) is None
assert state(1000,{1.5:5,2.5:6}) is None    # three goals seen: not level, G odd
assert draw_shortest(3.0,4.0,2.0) and not draw_shortest(2.0,4.0,2.0) and not draw_shortest(None,4.0,2.0)
assert band(1.59)=='STRONG' and band(1.6)=='NEAR'
t=np.array([0.,100.,200.]); assert last_in(t,20,150)==1 and last_in(t,150,190) is None
print("checks: OK",flush=True); T0=time.time()
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
R=pd.read_sql("SELECT market_id,event_id,market_type,sel,status FROM bf_hist_result WHERE sport='Soccer' AND market_type IN ('MATCH_ODDS','DRAW_NO_BET')",con)
MO=R[R.market_type=='MATCH_ODDS']; w=MO[MO.status=='WINNER'].groupby('market_id').size(); okm=set(w[w==1].index)
MOW=MO[MO.market_id.isin(okm)&(MO.status=='WINNER')].sort_values('market_id').drop_duplicates('event_id')
MOWIN=dict(zip(MOW.event_id,MOW.sel))
DN=R[(R.market_type=='DRAW_NO_BET')&(R.status=='WINNER')].sort_values('market_id').drop_duplicates('event_id'); DNWIN=dict(zip(DN.event_id,DN.sel)); del R,MO,MOW,DN
both=[e for e in DNWIN if e in MOWIN and MOWIN[e]!='The Draw']; agree=np.mean([DNWIN[e]==MOWIN[e] for e in both]) if both else 0
print(f"official MO events {len(MOWIN)}, DNB events {len(DNWIN)}, non-drawn with both {len(both)}, DNB winner = MO winner {agree:.4f}",flush=True)
if agree<0.99: print("STOP: DNB and MO official winners agree on under 99%"); sys.exit(1)
LN={'OVER_UNDER_15':1.5,'OVER_UNDER_25':2.5,'OVER_UNDER_35':3.5,'OVER_UNDER_45':4.5,'OVER_UNDER_05':0.5}
C=Counter(); rows=[]
def months():
    for y,ms in MONTHS:
        for m in ms:
            a=pd.Timestamp(y,m,1); b=a+pd.offsets.MonthBegin(1)
            for s,e in ((a,a+pd.Timedelta(days=10)),(a+pd.Timedelta(days=10),a+pd.Timedelta(days=20)),(a+pd.Timedelta(days=20),b)): yield str(s.date()),str(e.date())
for lo,hi in months():
    M=pd.read_sql("""SELECT event_id,max(event_name) OVER (PARTITION BY event_id) ev,market_id,sel,ts,ltp::float8 ltp,inplay FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS'
                     AND market_time>=%s AND market_time<%s AND ltp>=1.01 AND ltp<1000
                     AND ts>=market_time-interval '60 minutes' AND ts<=market_time+interval '3 hours'""",con,params=(lo,hi))
    if M.empty: print(lo,"no rows",flush=True); continue
    D=pd.read_sql("""SELECT event_id,market_id,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type='DRAW_NO_BET' AND inplay
                     AND market_time>=%s AND market_time<%s AND ltp>=1.01 AND ltp<1000
                     AND ts>=market_time+interval '60 minutes' AND ts<=market_time+interval '3 hours'""",con,params=(lo,hi))
    S=pd.read_sql("""SELECT event_id,market_type mt,min(ts) t1 FROM bf_hist_other WHERE sport='Soccer' AND market_type=ANY(%s)
                     AND sel LIKE 'Over%%' AND inplay AND ltp<=1.05 AND market_time>=%s AND market_time<%s
                     AND ts>=market_time-interval '30 minutes' AND ts<=market_time+interval '3 hours' GROUP BY 1,2""",con,params=(list(LN),lo,hi))
    SEEN={}
    for e,mt,t1 in zip(S.event_id,S.mt,secs(S.t1)): SEEN.setdefault(e,{})[LN[mt]]=float(t1)
    M['tt']=secs(M.ts); D['tt']=secs(D.ts)
    M=M.sort_values('tt',kind='stable'); D=D.sort_values('tt',kind='stable').drop_duplicates(['market_id','sel','tt'])
    DG={k:g for k,g in D.groupby('event_id',sort=False)}
    ng=0
    for e,x in M.groupby('event_id',sort=False):
        ng+=1; C['games']+=1; ev=x.ev.iloc[0]
        if not isinstance(ev,str) or ' v ' not in ev: C['no H v A']+=1; continue
        if group(ev): C['women or youth']+=1; continue
        mk=sorted(x.market_id.unique())[0]; x=x[x.market_id==mk]
        hn,an=[s.strip() for s in ev.split(' v ',1)]
        if e not in MOWIN: C['no official MO']+=1; continue
        ip=x[x.inplay]
        if ip.empty: C['no in-play MO']+=1; continue
        ip0=float(ip.tt.min()); pre=x[~x.inplay & (x.tt<ip0)]
        P={}
        for s_,g in pre.groupby('sel'): P[s_]=float(g.ltp.values[-1])
        if hn not in P or an not in P: C['no pre-off MO print for both sides']+=1; continue
        if P[hn]==P[an]: C['pre-off tie']+=1; continue
        fav,dog=(hn,an) if P[hn]<P[an] else (an,hn)
        if e not in DG: C['no in-play DNB prints']+=1; continue
        dg=DG[e]; dmk=sorted(dg.market_id.unique())[0]; dg=dg[dg.market_id==dmk]
        MI={s_:(g.tt.values,g.ltp.values) for s_,g in ip.groupby('sel')}
        res=MOWIN[e]; seen=SEEN.get(e,{})
        y=dg[dg.sel==fav]
        if y.empty: C['FAV DNB sel not named as MO']+=1; continue
        tt=y.tt.values; px=y.ltp.values
        outcome='D' if res=='The Draw' else ('W' if res==fav else 'L')
        a0=np.searchsorted(tt,ip0+LO_MIN*60,'left'); b0=np.searchsorted(tt,ip0+HI_MIN*60,'right')
        if a0>=b0: C['no FAV DNB print 75-103']+=1; continue
        hit=None
        for i in range(a0,b0):
            ent=float(tt[i]); G=state(ent,seen)
            if G is None: continue
            last={}
            for s_ in (hn,an,'The Draw'):
                if s_ not in MI: last[s_]=None; continue
                j=last_in(MI[s_][0],ent-LOOK,ent); last[s_]=None if j is None else float(MI[s_][1][j])
            if not draw_shortest(last[hn],last[an],last['The Draw']): continue
            hit=(i,G); break
        if hit is None: C['never LEVEL_G with draw shortest 75-103']+=1; continue
        i,G=hit; pb=fill(tt,px,i,'B'); pl=fill(tt,px,i,'L')
        if pl>50: C['price over 50']+=1; continue
        rows.append(dict(e=e,ev=ev,ip0=ip0,G=G,band=band(P[fav]),px=float(px[i]),ent=(float(tt[i])-ip0)/60,vb=dnb_back(pb,outcome),vl=dnb_lay(pl,outcome),out=outcome))
    print(lo,"games",ng,"DNB in-play prints",len(D),"trades",len(rows),f"{time.time()-T0:.0f}s",flush=True); del M,D,S,DG; import gc; gc.collect()
con.close(); print("counts",dict(sorted(C.items())),flush=True)
T=pd.DataFrame(rows)
if T.empty: print("\n== SURVIVORS\nnone (no trades)"); sys.exit(0)
med=T.ip0.median(); T['h']=np.where(T.ip0<=med,1,2)
print(f"\nhalves split at {pd.to_datetime(med,unit='s')}; trades {len(T)}, games {T.e.nunique()}; entry median {T.ent.median():.1f} min after the first in-play print")
print("by G and band: n, median price, won, drew, implied\n",T.groupby(['G','band']).agg(n=('px','size'),px=('px','median'),won=('out',lambda s:(s=='W').mean()),drew=('out',lambda s:(s=='D').mean()),imp=('px',lambda s:(1/s).mean())).round(3).to_string())
def row(nm,x,col):
    x=x.dropna(subset=[col]); v=x[col].astype(float).values
    if len(v)<2: return dict(line=nm,n=len(v))
    d=line(v,x.h.values); nd=x[x.out!='D']
    return dict(line=nm,n=d['n'],games=x.e.nunique(),per10=round(d['per10'],3),t=round(d['t'],2),h1=round(d['h1'],3),h2=round(d['h2'],3),n1=d['n1'],n2=d['n2'],
                no_top=round(np.delete(v,v.argmax()).mean(),3),won_nd=round((nd.out=='W').mean(),3) if len(nd) else np.nan,imp=round((1/x.px).mean(),3),PASS=d['PASS'])
S0=row('ONE FAV back *',T,'vb')
o=[S0,row('ONE FAV lay (mirror, not scored)',T,'vl')]
for G in (2,4): o.append(row(f'G{G} FAV back',T[T.G==G],'vb'))
for b_ in ('STRONG','NEAR'): o.append(row(f'{b_} FAV back',T[T.band==b_],'vb'))
print("\n== ITEM 450, Jan-Feb 2023, scored ONE FAV back; the rest for reading\n",pd.DataFrame(o).to_string(index=False))
print("\n== SURVIVORS"); print(S0 if S0.get('PASS') else "none",flush=True); print(f"total {time.time()-T0:.0f}s")
PY
