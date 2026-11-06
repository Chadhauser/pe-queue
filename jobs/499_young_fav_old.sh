#!/bin/bash
set -o pipefail
# 499_young_fav_old (Finder 2026-11-06, queue item 220, Finder's own, source c): younger favourite under 2.0 at Pinnacle closes, on dates outside the tape window of jobs/499_tennis_format.sh. Rule pushed before any odds were read. Read only. The number 499 is reused: 450-499 are all taken.
# TABLES tennis_matches (Railway, results with Pinnacle closes), tennis_results_2026 (Railway, ages). Join: tour, both players (folded surname + first initial), tournament start -21 to +2 days from the match; a unique match only.
# TEST, fixed first: YOUNG (favourite >= 6 years younger) won minus de-vigged fair exceeds the control's (other matched favourites under 2.0) by z >= 2. Back and lay at the close shown, one tick, 2%, £10. Closes are a proxy (item 75), so no line here can pass the bar: support only earns a forward test.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_500_000_000,1_500_000_000))  # this job only
import sys,re,time,unicodedata,warnings,psycopg2,pandas as pd,numpy as np
from collections import defaultdict,Counter
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,back_settle,lay_settle,line
pd.set_option('display.width',220); pd.set_option('display.max_rows',60); pd.set_option('display.max_columns',30)
T0=time.time()
def fold(s): return re.sub(r"[^a-z]","",unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower())
def key_short(s):
    """'De Minaur A.' -> ('deminaur','a'). 'Auger-Aliassime F.' -> ('augeraliassime','f'). 'Ferreira Silva F.A.' -> ('ferreirasilva','f')."""
    w=str(s).strip().split()
    if len(w)<2: return None
    return fold(' '.join(w[:-1])),fold(w[-1])[:1]
def key_full(s):
    """'Alex De Minaur' -> ('deminaur','a')."""
    w=str(s).strip().split()
    if len(w)<2: return None
    return fold(' '.join(w[1:])),fold(w[0])[:1]
def fair(pf,po): return (1/pf)/(1/pf+1/po)
def young(af,ao,gap=6.0): return af==af and ao==ao and ao-af>=gap
def bk(x,won):
    a=step(x,-1); return np.nan if a<=1.01 else back_settle(a,won)
def ly(x,won): return lay_settle(step(x,1),won)
def zdiff(a,b):
    a=np.asarray(a,float); b=np.asarray(b,float)
    return (a.mean()-b.mean())/np.sqrt(a.var(ddof=1)/len(a)+b.var(ddof=1)/len(b))
# known answers, worked by hand
assert key_short('De Minaur A.')==key_full('Alex De Minaur')==('deminaur','a') and key_short('Auger-Aliassime F.')==('augeraliassime','f') and key_short('Nadal')is None and key_full('Nadal') is None
assert abs(fair(1.5,3.0)-2/3)<1e-9 and abs(fair(1.9,1.9)-0.5)<1e-9
assert young(20.,26.) and not young(20.,25.9) and not young(26.,20.) and not young(float('nan'),20.)
assert abs(bk(2.0,True)-10*.99*.98)<1e-9 and bk(2.0,False)==-10.0 and np.isnan(bk(1.02,True)) and abs(ly(2.0,False)-10/1.02*.98)<1e-9 and ly(2.0,True)==-10.0
assert abs(zdiff([0,1]*50,[0,1]*50))<1e-9 and zdiff([0,1]*50,[0,0,0,1]*50)>2
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
c=psycopg2.connect(creds.pg_railway(),sslmode='require')
M=pd.read_sql("SELECT tour,date,round,winner,loser,psw::float8 psw,psl::float8 psl,score FROM tennis_matches",c)
A=pd.read_sql("SELECT tour,tourney_date,winner_name,loser_name,winner_age::float8 wa,loser_age::float8 la FROM tennis_results_2026 WHERE tour IN ('ATP','WTA')",c); c.close()
M['d']=pd.to_datetime(M.date,errors='coerce'); M['tour']=M.tour.astype(str).str.upper(); A['tour']=A.tour.astype(str).str.upper()
print(f"tennis_matches rows {len(M)}, {M.d.min()} to {M.d.max()}, tours {M.tour.value_counts().to_dict()}; age rows {len(A)}, {A.tourney_date.min()} to {A.tourney_date.max()} | {time.time()-T0:.0f}s",flush=True)
ix=defaultdict(list)
for r in A.itertuples():
    a,b=key_full(r.winner_name),key_full(r.loser_name)
    if a and b: ix[(r.tour,frozenset((a,b)))].append((pd.Timestamp(r.tourney_date),a,r.wa,b,r.la))
SK=Counter(); rows=[]
U=M[(M.d<'2024-08-31')|(M.d>'2026-03-31')]; SK['rows on unseen dates']=len(U)
for r in U.itertuples():
    if re.search(r"W/O|WO|WALK",str(r.score).upper()): SK['walkover']+=1; continue
    if not (r.psw>1 and r.psl>1): SK['no close']+=1; continue
    if r.psw==r.psl: SK['equal closes']+=1; continue
    fw=r.psw<r.psl; pf,po=(r.psw,r.psl) if fw else (r.psl,r.psw)
    if pf>=2.0: SK['favourite 2.0 or over']+=1; continue
    w,l=key_short(r.winner),key_short(r.loser)
    if not (w and l): SK['bad name']+=1; continue
    hits=[h for h in ix.get((r.tour,frozenset((w,l))),[]) if -21<=(h[0]-r.d).days<=2]   # tournament start, 21 days before the match to 2 days after
    if len(hits)!=1: SK['no unique age match']+=1; continue
    h=hits[0]; ages={h[1]:h[2],h[3]:h[4]}; aw,al=ages.get(w),ages.get(l)
    if aw is None or al is None or aw!=aw or al!=al: SK['no age']+=1; continue
    af,ao=(aw,al) if fw else (al,aw); st='YOUNG' if young(af,ao) else 'CTRL'; SK['scored '+st]+=1
    won=bool(fw); rows.append((st,r.tour,r.d,pf,won,float(won)-fair(pf,po),bk(pf,won),ly(pf,won)))
print("counts:",dict(SK),flush=True)
R=pd.DataFrame(rows,columns='st tour d px won err vb vl'.split())
if R.empty or not (R.st=='YOUNG').any(): print("ERROR: no YOUNG rows, no verdict"); sys.exit(1)
print(f"dates {R.d.min()} to {R.d.max()}",flush=True)
Y=R[R.st=='YOUNG']; C=R[R.st=='CTRL']; z=zdiff(Y.err,C.err)
print(f"\n== TEST: YOUNG n {len(Y)} won {Y.won.mean():.3f} err {Y.err.mean():+.4f} v CTRL n {len(C)} won {C.won.mean():.3f} err {C.err.mean():+.4f}; z {z:.2f}; bar z >= 2: {'SUPPORTED' if z>=2 else 'NOT SUPPORTED'}",flush=True)
out=[]
for st,x in R.groupby('st'):
    for cut,xx in (('ALL',x),('ATP',x[x.tour=='ATP']),('WTA',x[x.tour=='WTA'])):
        if len(xx)==0: continue
        md=xx.d.median(); h=np.where(xx.d<md,1,2)
        for side,col in (('back','vb'),('lay','vl')):
            k=xx[col].notna().values; l=line(xx[col].values[k],h[k]); out.append(dict(state=st,cut=cut,side=side,n=l['n'],per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],won=xx.won.mean(),implied=(1/xx.px).mean()))
print("\n== closes, a proxy, by t\n",pd.DataFrame(out).sort_values('t',ascending=False).round(3).to_string(index=False))
print("\n== SURVIVORS: none can pass at closes; forward test only if the z test is supported")
print(f"total {time.time()-T0:.0f}s")
PY
