#!/bin/bash
set -o pipefail
# 499_atp_climb_close (Finder 2026-11-06, queue item 231, Finder's own, source c, from jobs/499_atp_climb.sh, jobs/499_home_atp_close.sh): ATP runner climbing from the Challenger tour, at Pinnacle closes, on dates outside the tape window. Rule pushed before any odds were read. Read only. The number 499 is reused: 450-499 are all taken.
# TABLES tennis_matches (Railway, results with Pinnacle closes), tennis_results_2026 (Railway, tours and rounds). Join as jobs/499_home_atp_close.sh: tour, both players (folded surname + first initial), tournament start -21 to +2 days from the match; a unique match only. CLIMB, control and the 7-21 day rule as jobs/499_atp_climb.sh, team events and season finals out.
# DATES: outside 31 Aug 2024 to 31 Mar 2026, and from 15 Feb 2021, as Challenger rows start 24 Jan 2021 and a 21-day look-back needs them.
# TEST, fixed first: CLIMB won minus de-vigged fair, close under 3.0, sits above the control's by z >= 2. Item 230 gave +0.0410 v -0.0015, z 1.12, so the direction is set by that. Control can hold both runners of a match, so its error is near zero by construction. Back at the close shown, one tick, 2%, £10; lays flatter at a Pinnacle close (as item 74), so read err and z. Closes are a proxy, so no line here can pass the bar: support only earns a forward test.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_500_000_000,1_500_000_000))  # this job only
import sys,re,time,bisect,datetime as dt,unicodedata,warnings,psycopg2,pandas as pd,numpy as np
from collections import defaultdict,Counter
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,back_settle,lay_settle,line
pd.set_option('display.width',220); pd.set_option('display.max_rows',60); pd.set_option('display.max_columns',30)
T0=time.time()
RANK={'1':0,'R128':5,'R64':6,'R32':7,'R16':8,'QF':9,'SF':10,'BR':10.5,'F':11,'RR':4,'Quarterfinals':9}
TEAM=re.compile(r"davis cup|atp cup|united cup|laver cup|olympic|finals",re.I)
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
def ly(x,won): return lay_settle(step(x,1),won)
def zdiff(a,b):
    a=np.asarray(a,float); b=np.asarray(b,float)
    return (a.mean()-b.mean())/np.sqrt(a.var(ddof=1)/len(a)+b.var(ddof=1)/len(b))
def band(p): return '<1.5' if p<1.5 else '1.5-2' if p<2 else '2-3' if p<3 else None
def status(hist,cur):
    """hist = sorted [(date,is_challenger)] of played matches. Latest date before cur only. As jobs/499_atp_climb.sh, where ATP7 means the flagged tour."""
    i=bisect.bisect_left(hist,(cur,False))
    if i==0: return 'OTHER'
    d=hist[i-1][0]; gap=(cur-d).days
    if gap>21: return 'OTHER'
    k=[a for x,a in hist[:i] if x==d]
    if not any(k): return 'OTHER'
    if not all(k): return 'MIXED'
    return 'ATP7' if gap>=7 else 'NEAR' if gap>=5 else 'LATE'
def label(me,opp):
    if opp!='OTHER': return None
    return {'ATP7':'CLIMB','OTHER':'CTRL'}.get(me)
def seen_dates(d):
    """True on a date the tape test did not use and the look-back covers."""
    return pd.Timestamp('2021-02-15')<=d and (d<pd.Timestamp('2024-08-31') or d>pd.Timestamp('2026-03-31'))
# known answers, worked by hand
D=lambda n:dt.date(2023,6,30)-dt.timedelta(days=n); CUR=D(0)
assert status([],CUR)=='OTHER' and status([(D(7),True)],CUR)=='ATP7' and status([(D(21),True)],CUR)=='ATP7' and status([(D(22),True)],CUR)=='OTHER' and status([(D(6),True)],CUR)=='NEAR' and status([(D(4),True)],CUR)=='LATE' and status([(D(10),False)],CUR)=='OTHER' and status([(D(14),True),(D(7),False)],CUR)=='OTHER' and status(sorted([(D(10),True),(D(10),False)]),CUR)=='MIXED'
assert label('ATP7','OTHER')=='CLIMB' and label('OTHER','OTHER')=='CTRL' and label('NEAR','OTHER') is None and label('OTHER','ATP7') is None and label('ATP7','ATP7') is None
assert seen_dates(pd.Timestamp('2023-01-01')) and seen_dates(pd.Timestamp('2026-04-01')) and not seen_dates(pd.Timestamp('2024-08-31')) and not seen_dates(pd.Timestamp('2026-03-31')) and not seen_dates(pd.Timestamp('2021-02-14'))
assert key_short('De Minaur A.')==key_full('Alex De Minaur')==('deminaur','a') and key_short('Nadal') is None
assert abs(fair(1.5,3.0)-2/3)<1e-9 and band(1.49)=='<1.5' and band(2.99)=='2-3' and band(3.0) is None
assert abs(bk(2.0,True)-10*.99*.98)<1e-9 and bk(2.0,False)==-10.0 and np.isnan(bk(1.02,True)) and abs(ly(2.0,False)-10/1.02*.98)<1e-9 and ly(2.0,True)==-10.0
assert zdiff([0,1]*50,[0,0,0,1]*50)>2 and abs(zdiff([0,1]*50,[0,1]*50))<1e-9
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
c=psycopg2.connect(creds.pg_railway(),sslmode='require')
M=pd.read_sql("SELECT tour,date,winner,loser,psw::float8 psw,psl::float8 psl,score FROM tennis_matches",c)
T=pd.read_sql("SELECT tour,tourney_name,tourney_date,winner_name,loser_name,winner_norm,loser_norm,round,score FROM tennis_results_2026 WHERE upper(tour) IN ('ATP','CHALLENGER')",c); c.close()
M['d']=pd.to_datetime(M.date,errors='coerce'); M['tour']=M.tour.astype(str).str.upper(); T['tour']=T.tour.astype(str).str.upper()
T=T[~T.score.astype(str).str.upper().str.contains(r"W/O|WO|WALK")]; T['w']=T.winner_norm.map(fold); T['l']=T.loser_norm.map(fold)
print(f"tennis_matches rows {len(M)}, {M.d.min()} to {M.d.max()}, tours {M.tour.value_counts().to_dict()}; result rows {len(T)}",flush=True)
hist=defaultdict(set)
for r in T.itertuples():
    for x in (r.w,r.l): hist[x].add((r.tourney_date,r.tour=='CHALLENGER'))
hist={k:sorted(v) for k,v in hist.items()}
A=T[(T.tour=='ATP')&~T.tourney_name.str.contains(TEAM)]; first={}
for r in A.itertuples():
    q=RANK.get(r.round,99)
    for x in (r.w,r.l):
        k=(r.tourney_name,r.tourney_date,x); first[k]=min(first.get(k,99),q)
ix=defaultdict(list)
for r in A.itertuples():
    a,b=key_full(r.winner_name),key_full(r.loser_name)
    if not (a and b): continue
    q=RANK.get(r.round,99); sw=status(hist[r.w],r.tourney_date); sl=status(hist[r.l],r.tourney_date)
    lw=label(sw,sl) if first[(r.tourney_name,r.tourney_date,r.w)]==q else None
    ll=label(sl,sw) if first[(r.tourney_name,r.tourney_date,r.l)]==q else None
    ix[frozenset((a,b))].append((pd.Timestamp(r.tourney_date),a,lw,b,ll))
SK=Counter(); rows=[]
U=M[(M.tour=='ATP')&M.d.notna()]; U=U[U.d.map(seen_dates)]; SK['ATP rows on unseen dates']=len(U)
for r in U.itertuples():
    if re.search(r"W/O|WO|WALK",str(r.score).upper()): SK['walkover']+=1; continue
    if not (r.psw>1 and r.psl>1): SK['no close']+=1; continue
    w,l=key_short(r.winner),key_short(r.loser)
    if not (w and l): SK['bad name']+=1; continue
    hits=[h for h in ix.get(frozenset((w,l)),[]) if -21<=(h[0]-r.d).days<=2]
    if len(hits)!=1: SK['no unique match, or a team event or finals']+=1; continue
    h=hits[0]; lab={h[1]:h[2],h[3]:h[4]}; SK['matched']+=1; fw=fair(r.psw,r.psl)
    for st,p,won,fr in ((lab.get(w),r.psw,True,fw),(lab.get(l),r.psl,False,1-fw)):
        if st and band(p): rows.append((st,band(p),r.d,p,won,float(won)-fr,bk(p,won),ly(p,won)))
print("counts:",dict(SK),flush=True)
R=pd.DataFrame(rows,columns='st band d px won err vb vl'.split())
if R.empty or not (R.st=='CLIMB').any(): print("ERROR: no CLIMB rows, no verdict"); sys.exit(1)
print(f"dates {R.d.min()} to {R.d.max()}; CLIMB by year {R[R.st=='CLIMB'].d.dt.year.value_counts().sort_index().to_dict()}",flush=True)
H=R[R.st=='CLIMB']; C=R[R.st=='CTRL']; z=zdiff(H.err,C.err)
print(f"\n== TEST: CLIMB n {len(H)} won {H.won.mean():.3f} err {H.err.mean():+.4f} v CTRL n {len(C)} err {C.err.mean():+.4f}; z {z:.2f}; bar z >= 2: {'SUPPORTED' if z>=2 else 'NOT SUPPORTED'}",flush=True)
out=[]
for (st,b),x in R.groupby(['st','band']):
    print(f"  {st} {b}: n {len(x)} err {x.err.mean():+.4f}"+("" if st=='CTRL' else f"; z v CTRL {zdiff(x.err,C[C.band==b].err):.2f}"))
    md=x.d.median(); hh=np.where(x.d<md,1,2)
    for side,col in (('back','vb'),('lay','vl')):
        k=x[col].notna().values; l=line(x[col].values[k],hh[k]); out.append(dict(st=st,band=b,side=side,n=l['n'],per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],won=x.won.mean(),implied=(1/x.px).mean()))
print("\n== closes, a proxy, by t\n",pd.DataFrame(out).sort_values('t',ascending=False).round(3).to_string(index=False))
print("\n== SURVIVORS: none can pass at closes; forward test only if the z test is supported")
print(f"total {time.time()-T0:.0f}s")
PY
