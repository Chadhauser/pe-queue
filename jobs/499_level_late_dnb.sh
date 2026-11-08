#!/bin/bash
set -o pipefail
# 499_level_late_dnb (Finder 2026-11-08, queue item 449, new; built from jobs/499_ht_state_lines.sh; rule pushed in 978c358 before any DNB price was read).
# Draw No Bet late in a level game (0-0 or 1-1): back or lay the pre-off favourite and outsider at a real DNB print, held to the official result.
# Settlement: bf_hist_result DRAW_NO_BET holds one WINNER on every market and drawn games are missing (Betfair voids them), so settling on it would drop every void.
# This job settles on the official MATCH_ODDS winner instead: a draw pays 0 on back and lay; checks DNB winner = MO winner on non-drawn games, at least 99%, or stops.
# Read only, no tables written. Prints only, so a pass is an upper bound and earns a real-touch read on liq_sample, not a stake.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line
from lib_official import bk,ly,fill,first_in,last_in,secs,checks,group
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',230); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',300)
WINDOWS=(75,90,100)          # minutes after the first in-play MO print
LOOK=180                     # MO last-print look-back, seconds, no forward fill past it
def dnb_back(p,outcome):
    """outcome: 'W' runner won, 'L' runner lost, 'D' draw (void, 0)."""
    if outcome=='D': return 0.0
    return bk(p,outcome=='W')
def dnb_lay(p,outcome):
    if outcome=='D': return 0.0
    return ly(p,outcome=='W')
def state_ok(st,entry,seen):
    """seen: dict line -> first ts the Over printed at 1.05 or under. S00: no OU0.5 Over before entry. S11: OU1.5 Over 3+ min before entry, no OU2.5 Over before entry."""
    s05,s15,s25=seen.get(0.5),seen.get(1.5),seen.get(2.5)
    if st=='S00': return s05 is None or s05>=entry
    if st=='S11': return (s15 is not None and s15<=entry-180) and (s25 is None or s25>=entry)
    return False
def draw_shortest(h,a,d): return d is not None and h is not None and a is not None and d<h and d<a
def band(p): return 'STRONG' if p<1.6 else 'NEAR'
# known answers, worked by hand
# back DNB 2.0 -> 1.99: wins 9.9*0.98=9.702; loses -10; draw 0. lay 2.0 -> 2.02: stake 10/1.02, runner loses -> +9.6078; runner wins -> -10; draw 0.
assert abs(dnb_back(2.0,'W')-9.702)<1e-9 and dnb_back(2.0,'L')==-10.0 and dnb_back(2.0,'D')==0.0
assert abs(dnb_lay(2.0,'L')-10/1.02*0.98)<1e-9 and dnb_lay(2.0,'W')==-10.0 and dnb_lay(2.0,'D')==0.0
assert state_ok('S00',100,{}) and state_ok('S00',100,{0.5:100}) and not state_ok('S00',100,{0.5:99})
assert state_ok('S11',1000,{0.5:10,1.5:820}) and not state_ok('S11',1000,{0.5:10,1.5:821}) and not state_ok('S11',1000,{1.5:10,2.5:999}) and state_ok('S11',1000,{1.5:10,2.5:1000}) and not state_ok('S11',1000,{0.5:10})
assert draw_shortest(3.0,4.0,2.0) and not draw_shortest(2.0,4.0,2.0) and not draw_shortest(None,4.0,2.0) and not draw_shortest(3.0,4.0,None)
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
drawn_with_dnb=sum(1 for e in DNWIN if MOWIN.get(e)=='The Draw')
print(f"official MO events {len(MOWIN)}, DNB events {len(DNWIN)}, non-drawn with both {len(both)}, DNB winner = MO winner {agree:.4f}; drawn MO games holding a DNB winner {drawn_with_dnb}",flush=True)
if agree<0.99: print("STOP: DNB and MO official winners agree on under 99%"); sys.exit(1)
C=Counter(); rows=[]
def months():
    for y,ms in ((2023,range(3,13)),(2024,range(1,11)),(2026,range(4,11))):
        for m in ms:
            # fix after the first run's MemoryError on 2026-08: three blocks a month by market_time, a game sits in one block, logic unchanged
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
    S=pd.read_sql("""SELECT event_id,market_type mt,min(ts) t1 FROM bf_hist_other WHERE sport='Soccer' AND market_type IN ('OVER_UNDER_05','OVER_UNDER_15','OVER_UNDER_25')
                     AND sel LIKE 'Over%%' AND inplay AND ltp<=1.05 AND market_time>=%s AND market_time<%s
                     AND ts>=market_time-interval '30 minutes' AND ts<=market_time+interval '3 hours' GROUP BY 1,2""",con,params=(lo,hi))
    LN={'OVER_UNDER_05':0.5,'OVER_UNDER_15':1.5,'OVER_UNDER_25':2.5}
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
        fav,dog=(hn,an) if P[hn]<=P[an] else (an,hn)
        if e not in DG: C['no in-play DNB prints']+=1; continue
        dg=DG[e]; dmk=sorted(dg.market_id.unique())[0]; dg=dg[dg.market_id==dmk]
        MI={s_:(g.tt.values,g.ltp.values) for s_,g in ip.groupby('sel')}
        res=MOWIN[e]; seen=SEEN.get(e,{})
        for role,nm in (('FAV',fav),('DOG',dog)):
            y=dg[dg.sel==nm]
            if y.empty: C[f'{role} DNB sel not named as MO']+=1; continue
            tt=y.tt.values; px=y.ltp.values
            outcome='D' if res=='The Draw' else ('W' if res==nm else 'L')
            for W in WINDOWS:
                i=first_in(tt,ip0+W*60,ip0+W*60+180)
                if i is None: C[f'W{W} no DNB print']+=1; continue
                ent=float(tt[i]); last={}
                for s_ in (hn,an,'The Draw'):
                    if s_ not in MI: last[s_]=None; continue
                    j=last_in(MI[s_][0],ent-LOOK,ent); last[s_]=None if j is None else float(MI[s_][1][j])
                if not draw_shortest(last[hn],last[an],last['The Draw']): C[f'W{W} draw not shortest or MO print missing']+=1; continue
                st='S00' if state_ok('S00',ent,seen) else ('S11' if state_ok('S11',ent,seen) else None)
                if st is None: C[f'W{W} not 0-0 or 1-1']+=1; continue
                pb=fill(tt,px,i,'B'); pl=fill(tt,px,i,'L')
                if pl>50: C['price over 50']+=1; continue
                vb=dnb_back(pb,outcome); vl=dnb_lay(pl,outcome)
                rows.append(dict(e=e,ev=ev,ip0=ip0,W=W,st=st,role=role,band=band(P[fav]),px=float(px[i]),vb=vb,vl=vl,out=outcome))
    print(lo,"games",ng,"DNB in-play prints",len(D),"trades",len(rows),f"{time.time()-T0:.0f}s",flush=True); del M,D,S,DG,x; import gc; gc.collect()
con.close(); print("counts",dict(sorted(C.items())),flush=True)
T=pd.DataFrame(rows)
if T.empty: print("\n== SURVIVORS\nnone (no trades)"); sys.exit(0)
T['vb']=T.vb.astype(float); med=T.ip0.median(); T['h']=np.where(T.ip0<=med,1,2)
print(f"\nhalves split at {pd.to_datetime(med,unit='s')}; trades {len(T)}, games {T.e.nunique()}")
print("by state, window, role: n, median price, won, drew, implied (1/price)\n",T.groupby(['st','W','role']).agg(n=('px','size'),px=('px','median'),won=('out',lambda s:(s=='W').mean()),drew=('out',lambda s:(s=='D').mean()),imp=('px',lambda s:(1/s).mean())).round(3).to_string())
def row(nm,x,col):
    x=x.dropna(subset=[col]); v=x[col].astype(float).values
    if len(v)<2: return dict(line=nm,n=len(v))
    d=line(v,x.h.values); nd=x[x.out!='D']
    return dict(line=nm,n=d['n'],games=x.e.nunique(),per10=round(d['per10'],3),t=round(d['t'],2),h1=round(d['h1'],3),h2=round(d['h2'],3),n1=d['n1'],n2=d['n2'],
                no_top=round(np.delete(v,v.argmax()).mean(),3),won_nd=round((nd.out=='W').mean(),3) if len(nd) else np.nan,imp=round((1/x.px).mean(),3),PASS=d['PASS'])
o=[]
for st in ('S00','S11'):
    for W in WINDOWS:
        for role in ('FAV','DOG'):
            x=T[(T.st==st)&(T.W==W)&(T.role==role)]
            if x.empty: continue
            for col,sd in (('vb','back'),('vl','lay')):
                o.append(row(f'{st} W{W} {role} {sd} ALL',x,col))
                for b_ in ('STRONG','NEAR'): o.append(row(f'{st} W{W} {role} {sd} {b_}',x[x.band==b_],col))
O=pd.DataFrame(o); O=O[O.n>=2]
print(f"\n== ITEM 449, {len(O)} scored lines, top 15 by t")
print(O.sort_values('t',ascending=False).head(15).to_string(index=False))
print("\n-- bottom 6 by t\n",O.sort_values('t').head(6).to_string(index=False))
c=[]
for st in ('S00','S11'):
    for role in ('FAV','DOG'):
        for col,sd in (('vb','back'),('vl','lay')): c.append(row(f'POOLED {st} all W {role} {sd}',T[(T.st==st)&(T.role==role)],col))
print("\n-- pooled over windows, not scored (correlated, up to 3 entries a game)\n",pd.DataFrame(c).to_string(index=False))
P_=O[O.PASS==True]
print("\n== SURVIVORS"); print(P_.to_string(index=False) if len(P_) else "none",flush=True); print(f"total {time.time()-T0:.0f}s")
PY
