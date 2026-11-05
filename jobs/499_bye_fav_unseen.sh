#!/bin/bash
set -o pipefail
# 499_bye_fav_unseen (Finder 2026-11-05, queue item 109): the bye favourite lead from jobs/499_tennis_prev_load.sh, on dates that test did not see. Read only.
# TABLE: tennis_matches (Railway, the one history table not local), results with Pinnacle closes. Dates outside 31 Aug 2024 to 31 Mar 2026, the tape window of job 499_tennis_prev_load.
# BYE: 2nd Round match where one player has no 1st Round row in that tour x year x tournament, the opponent has one, and the event has 1st Round rows. CONTROL: other 2nd Round matches where both played a 1st Round.
# FAVOURITE: the shorter Pinnacle close. Equal prices: not used. Fair = de-vigged by proportion. Walkovers and missing odds excluded, counted.
# TEST, fixed before odds are read: BYE won minus fair is below the control's, z <= -2 on the difference. Also shown: back and lay at the close, one tick adverse, 2%, £10. Closes are a proxy (item 75: lays at Pinnacle closes collect its margin), so no line here can pass the bar: support only earns a forward test.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,warnings,psycopg2,pandas as pd,numpy as np
warnings.filterwarnings('ignore')
pd.set_option('display.width',220); pd.set_option('display.max_rows',60); pd.set_option('display.max_columns',30)
sys.path.insert(0,'/root/pe-queue/runner'); import creds
T0=time.time()
LD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    v=lo
    while v<hi-1e-9: LD.append(round(v,2)); v+=st
LD.append(1000.0); LD=np.array(LD)
def rung_dn(p): return float(LD[max(int(np.searchsorted(LD,round(float(p),2)+1e-9,side='right'))-2,0)])   # rung at or under p, then one down
def rung_up(p): return float(LD[min(int(np.searchsorted(LD,round(float(p),2)-1e-9,side='left'))+1,len(LD)-1)])  # rung at or over p, then one up
def back(p,w):
    a=rung_dn(p)
    if a<=1.01: return np.nan
    return 10*(a-1)*0.98 if w else -10.0
def lay(p,w):
    a=rung_up(p); return -10.0 if w else 10/(a-1)*0.98
def fair(pf,po): return (1/pf)/(1/pf+1/po)
def tstat(x):
    x=np.asarray(x,dtype=float); x=x[np.isfinite(x)]
    if len(x)<2: return 0.0
    s=x.std(ddof=1); return float(x.mean()/(s/len(x)**0.5)) if s>0 else 0.0
def zdiff(a,b):
    a=np.asarray(a,float); b=np.asarray(b,float)
    return (a.mean()-b.mean())/np.sqrt(a.var(ddof=1)/len(a)+b.var(ddof=1)/len(b))
def classify(p1,o1,has_r1):
    """2nd Round: p1 and o1 say whether each player has a 1st Round row. Returns the bye player's index (0, 1), 'both' if both played, or None."""
    if not has_r1: return None
    if p1 and o1: return 'both'
    if p1 and not o1: return 1
    if o1 and not p1: return 0
    return None
# known answers, worked by hand
assert rung_dn(2.0)==1.99 and rung_up(2.0)==2.02 and rung_dn(1.53)==1.52 and rung_up(2.03)==2.06 and rung_dn(2.03)==2.0  # 2.03 is off ladder: 2.02 at or under, one down 2.00; 2.04 at or over, one up 2.06
assert abs(back(2.0,True)-10*0.99*0.98)<1e-9 and back(2.0,False)==-10.0 and np.isnan(back(1.02,True))
assert abs(lay(2.0,False)-10/1.02*0.98)<1e-9 and lay(2.0,True)==-10.0
assert abs(fair(1.5,3.0)-2/3)<1e-9 and abs(fair(1.9,1.9)-0.5)<1e-9
assert classify(True,True,True)=='both' and classify(False,True,True)==0 and classify(True,False,True)==1 and classify(False,False,True) is None and classify(False,True,False) is None
assert abs(zdiff([0,1]*50,[0,1]*50))<1e-9 and zdiff([0,0,0,1]*50,[0,1]*50)<-2
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
c=psycopg2.connect(creds.pg_railway(),sslmode='require')
D=pd.read_sql("SELECT tour,year,tournament,date,round,winner,loser,psw::float8 psw,psl::float8 psl,score,lsets FROM tennis_matches",c); c.close()
print(f"rows {len(D)}, {D.date.min()} to {D.date.max()}; rounds {D['round'].value_counts().to_dict()}; tours {D.tour.value_counts().to_dict()}",flush=True)
D['d']=pd.to_datetime(D.date,errors='coerce')
K=['tour','year','tournament']; R1=D[D['round']=='1st Round']
played=set(zip(R1.tour,R1.year,R1.tournament,R1.winner))|set(zip(R1.tour,R1.year,R1.tournament,R1.loser)); ev=set(zip(R1.tour,R1.year,R1.tournament))
R2=D[(D['round']=='2nd Round')&((D.d<'2024-08-31')|(D.d>'2026-03-31'))].copy()
SK={'2nd round rows, unseen dates':len(R2)}; rows=[]
for r in R2.itertuples():
    k=(r.tour,r.year,r.tournament)
    if pd.isna(r.psw) or pd.isna(r.psl) or r.psw<=1 or r.psl<=1: SK['no close']=SK.get('no close',0)+1; continue
    if 'w/o' in str(r.score).lower() or 'walk' in str(r.score).lower(): SK['walkover']=SK.get('walkover',0)+1; continue
    if r.psw==r.psl: SK['equal prices']=SK.get('equal prices',0)+1; continue
    cl=classify(k+(r.winner,) in played,k+(r.loser,) in played,k in ev)
    if cl is None: SK['event or players without 1st Round rows']=SK.get('event or players without 1st Round rows',0)+1; continue
    wf=r.psw<r.psl; pf,po=(r.psw,r.psl) if wf else (r.psl,r.psw); F=fair(pf,po)
    if cl=='both': grp='CONTROL'
    else:
        byewinner=(cl==0); byefav=(byewinner==wf); grp='BYE_FAV' if byefav else 'BYE_DOG'
    rows.append((grp,r.tour,r.d,pf,F,wf,back(pf,wf),lay(pf,wf)))
print("counts:",SK,flush=True)
A=pd.DataFrame(rows,columns=['grp','tour','d','p','fair','won','B','L']); A['e']=A.won.astype(float)-A.fair
print(f"dates {A.d.min():%Y-%m-%d} to {A.d.max():%Y-%m-%d}, scored {len(A)}")
md=A.d.median(); out=[]
for (g,t),x in list(A.groupby(['grp','tour']))+[((g,'ALL'),x) for g,x in A.groupby('grp')]:
    h1=x[x.d<md]; h2=x[x.d>=md]
    out.append(dict(grp=g,tour=t,n=len(x),won=x.won.mean(),fair=x.fair.mean(),won_v_fair=x.e.mean(),h1=h1.e.mean(),h2=h2.e.mean(),back=x.B.mean(),t_back=tstat(x.B),lay=x.L.mean(),t_lay=tstat(x.L)))
print("\n== favourite in each group (BYE_DOG: the favourite is the opponent, who played)\n",pd.DataFrame(out).round(3).to_string(index=False))
b=A[A.grp=='BYE_FAV'].e.values; c_=A[A.grp=='CONTROL'].e.values; z=zdiff(b,c_)
print(f"\n== PRE-SET TEST: BYE_FAV won v fair {b.mean():+.4f} (n {len(b)}) v CONTROL {c_.mean():+.4f} (n {len(c_)}), diff {b.mean()-c_.mean():+.4f}, z {z:.2f}: {'SUPPORTED' if z<=-2 else 'NOT SUPPORTED'}")
print("\n== SURVIVORS\nnone possible: closes are a proxy, support only earns a forward test")
print(f"total {time.time()-T0:.0f}s")
PY
