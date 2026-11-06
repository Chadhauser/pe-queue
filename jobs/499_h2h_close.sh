#!/bin/bash
set -o pipefail
# 499_h2h_close (Finder 2026-11-06, queue item 324, Finder's own, source d, from jobs/499_tennis_load_close.sh, jobs/499_tennis_h2h_hour.sh): tennis head-to-head sweep priced 3-6 at Pinnacle closes, dates outside the tape. Rule pushed before any close was read. Read only. Closes are a proxy, so no line can pass the bar: support earns the unseen tape months.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_500_000_000,1_500_000_000))  # this job only
import sys,re,time,datetime as dt,unicodedata,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,line,back_settle,lay_settle
pd.set_option('display.width',240); pd.set_option('display.max_columns',30)
T0=time.time()
RANK={'1':0,'R128':5,'R64':6,'R32':7,'R16':8,'QF':9,'SF':10,'BR':10.5,'F':11,'RR':4,'Quarterfinals':9}
TEAM=re.compile(r"davis cup|atp cup|united cup|laver cup|billie jean|bjk|fed cup|hopman|olympic|finals",re.I)
def fold(s): return re.sub(r"[^a-z]","",unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower())
def key_short(s):
    w=str(s).strip().split()
    if len(w)<2: return None
    return fold(' '.join(w[:-1])),fold(w[-1])[:1]
def key_full(s):
    w=str(s).strip().split()
    if len(w)<2: return None
    return fold(' '.join(w[1:])),fold(w[0])[:1]
def fair(pa,pb): return (1/pa)/(1/pa+1/pb)
def bk(x,won):
    a=step(x,-1); return np.nan if a<=1.01 else back_settle(a,won)
def zdiff(a,b):
    a=np.asarray(a,float); b=np.asarray(b,float)
    return (a.mean()-b.mean())/np.sqrt(a.var(ddof=1)/len(a)+b.var(ddof=1)/len(b))
def band(p): return '2-3' if 2<=p<3 else '3-6' if 3<=p<6 else None
def unseen(d): return d<pd.Timestamp('2024-08-31') or d>pd.Timestamp('2026-03-31')
def sweep_state(meets,date):
    """meets: (date,round rank,winner), one tour, walkovers out. Last two strictly before date."""
    m=sorted([z for z in meets if z[0]<date],key=lambda z:(z[0],z[1]))
    if len(m)<2: return None
    a,b=m[-2][2],m[-1][2]
    return ('SWEEP',a) if a==b else ('SPLIT',None)
# known answers, worked by hand
D=pd.Timestamp
mm=[(D('2024-01-01'),5,'x'),(D('2025-01-01'),5,'y'),(D('2025-06-01'),7,'y'),(D('2026-01-01'),7,'x')]
assert sweep_state(mm,D('2025-12-01'))==('SWEEP','y') and sweep_state(mm,D('2026-02-01'))==('SPLIT',None) and sweep_state(mm,D('2026-01-01'))==('SWEEP','y') and sweep_state(mm,D('2025-01-01')) is None
assert key_short('De Minaur A.')==key_full('Alex De Minaur')==('deminaur','a') and key_short('Nadal') is None
assert abs(fair(1.5,3.0)-2/3)<1e-9 and band(1.99) is None and band(2.0)=='2-3' and band(3.0)=='3-6' and band(5.99)=='3-6' and band(6.0) is None
assert unseen(D('2024-08-30')) and unseen(D('2026-04-01')) and not unseen(D('2024-08-31')) and not unseen(D('2026-03-31'))
assert abs(bk(2.0,True)-10*.99*.98)<1e-9 and bk(2.0,False)==-10.0 and np.isnan(bk(1.02,True))
assert zdiff([0,1]*50,[0,0,0,1]*50)>2 and abs(zdiff([0,1]*50,[0,1]*50))<1e-9
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
c=psycopg2.connect(creds.pg_railway(),sslmode='require')
M=pd.read_sql("SELECT tour,date,winner,loser,psw::float8 psw,psl::float8 psl,score FROM tennis_matches",c)
T=pd.read_sql("SELECT tour,tourney_name,tourney_date,winner_name,loser_name,round,score FROM tennis_results_2026",c); c.close()
M['d']=pd.to_datetime(M.date,errors='coerce'); M['tour']=M.tour.astype(str).str.upper(); T['tour']=T.tour.astype(str).str.upper(); T['td']=pd.to_datetime(T.tourney_date)
T=T[~T.score.astype(str).str.upper().str.contains(r"W/O|WO|WALK")]
print(f"tennis_matches rows {len(M)}, {M.d.min()} to {M.d.max()}, by tour {M.tour.value_counts().to_dict()}; result rows {len(T)}, by tour {T.groupby('tour').td.min().to_dict()}",flush=True)
meets=defaultdict(list); ix=defaultdict(list)
for r in T.itertuples():
    a,b=key_full(r.winner_name),key_full(r.loser_name)
    if not (a and b): continue
    q=RANK.get(r.round,99); pr=(r.tour,frozenset((a,b)))
    meets[pr].append((r.td,q,a))
    ix[pr].append(dict(team=bool(TEAM.search(r.tourney_name)),date=r.td,w=a,l=b))
SK=Counter(); rows=[]; LB=Counter()
for r in M[M.d.notna()].itertuples():
    if re.search(r"W/O|WO|WALK",str(r.score).upper()): SK['walkover']+=1; continue
    w,l=key_short(r.winner),key_short(r.loser)
    if not (w and l): SK['bad name']+=1; continue
    pr=(r.tour,frozenset((w,l)))
    hits=[h for h in ix.get(pr,[]) if -21<=(h['date']-r.d).days<=2]
    if len(hits)!=1: SK['no unique match']+=1; continue
    h=hits[0]
    if h['team']: SK['team or finals']+=1; continue
    if h['w']!=w: SK['winner disagrees between tables']+=1; continue
    if not unseen(r.d): SK['inside the tape window, not scored']+=1; continue
    if not (r.psw>1 and r.psl>1): SK['no close']+=1; continue
    SK['matched']+=1
    s=sweep_state(meets[pr],h['date'])
    if not s: continue
    LB[s[0]]+=1
    fw=fair(r.psw,r.psl)
    for x in ([s[1]] if s[0]=='SWEEP' else [w,l]):
        won=x==w; p=r.psw if won else r.psl; b_=band(p)
        if b_: rows.append((s[0],b_,r.tour,r.d,p,won,float(won)-(fw if won else 1-fw),bk(p,won)))
print("counts:",dict(SK),"labels:",dict(LB),f"| {time.time()-T0:.0f}s",flush=True)
A=pd.DataFrame(rows,columns='st band tour d px won err vb'.split()); A['won']=A.won.astype(bool)
print(f"dates {A.d.min()} to {A.d.max()}; by year {A.d.dt.year.value_counts().sort_index().to_dict()}",flush=True)
def show(b,cut,o,c_,test):
    if len(o)<2 or len(c_)<2: print(f"  {b} {cut}: too few, n {len(o)} v control {len(c_)}"); return
    z=zdiff(o.err,c_.err); x=o[o.vb.notna()]; ll=line(x.vb.values,np.where(x.d<x.d.median(),1,2)); y=c_[c_.vb.notna()]
    print(f"  {b} {cut}: n {len(o)} won {o.won.mean():.3f} implied {(1/o.px).mean():.3f} err {o.err.mean():+.4f} v SPLIT n {len(c_)} err {c_.err.mean():+.4f}; z {z:.2f}{': '+('SUPPORTED' if z>=2 else 'NOT SUPPORTED') if test else ''}; back at the close, one tick, 2%: n {ll['n']} {ll['per10']:+.3f} t {ll['t']:.2f} h1 {ll['h1']:+.3f} h2 {ll['h2']:+.3f}; SPLIT back {y.vb.mean():+.3f}",flush=True)
print("\n== TESTS, SWEEP 3-6, z >= 2 upward against SPLIT")
S,C=A[(A.st=='SWEEP')&(A.band=='3-6')],A[(A.st=='SPLIT')&(A.band=='3-6')]
show('3-6','ALL',S,C,True)
for t_ in sorted(A.tour.unique()): show('3-6',t_,S[S.tour==t_],C[C.tour==t_],True)
print("\n== context, band 2-3, not tests")
S,C=A[(A.st=='SWEEP')&(A.band=='2-3')],A[(A.st=='SPLIT')&(A.band=='2-3')]
show('2-3','ALL',S,C,False)
for t_ in sorted(A.tour.unique()): show('2-3',t_,S[S.tour==t_],C[C.tour==t_],False)
print("\n== SURVIVORS: none can pass at closes; a supported z earns the unseen tape months")
print(f"total {time.time()-T0:.0f}s")
PY
