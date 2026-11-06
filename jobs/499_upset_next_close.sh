#!/bin/bash
set -o pipefail
# 499_upset_next_close (Finder 2026-11-06, queue item 239, Finder's own, source a, from jobs/499_tennis_upset_next.sh, jobs/499_atp_climb_close.sh): tennis runner who just won as an outsider, priced under 2.0 in the next round, at Pinnacle closes, on dates outside the tape window. Rule pushed before any odds were read. Read only. The number 499 is reused: 450-499 are all taken.
# TABLES tennis_matches (Railway, results with Pinnacle closes), tennis_results_2026 (Railway, tournaments and rounds). Join as jobs/499_atp_climb_close.sh: tour, both players (folded surname + first initial), tournament start -21 to +2 days from the match; a unique match only. Team events and season finals out. Dates outside 31 Aug 2024 to 31 Mar 2026.
# STATES as jobs/499_tennis_upset_next.sh, on the runner's own close: UPSET = previous played match in the same tournament won at a close >= 2.5, opponent not in that state; CTRL = previous win at a close < 2.0, opponent not UPSET. Round-robin out at both ends.
# TEST, fixed first: this match's close under 2.0, UPSET won minus de-vigged fair sits above CTRL's by z >= 2. Item 236 gave <1.5 z 1.66, 1.5-2 z 1.11 on the tape, so that sets the direction. Closes are a proxy, so no line here can pass the bar: support only earns a forward test.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_500_000_000,1_500_000_000))  # this job only
import sys,re,time,unicodedata,warnings,psycopg2,pandas as pd,numpy as np
from collections import defaultdict,Counter
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,back_settle,line
pd.set_option('display.width',220); pd.set_option('display.max_rows',60); pd.set_option('display.max_columns',30)
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
def band(p): return '<1.5' if p<1.5 else '1.5-2' if p<2 else None
def prev_rank(ranks,cur):
    if cur==RANK['RR'] or cur==99: return None
    e=[r for r in ranks if r<cur]
    if not e: return None
    m=max(e)
    if m==RANK['RR'] or e.count(m)>1 or m==99: return None
    return m
def prior_state(pw):
    if pw is None: return None
    return 'UP' if pw>=2.5 else 'FAV' if pw<2.0 else None
def label(me,opp):
    if opp=='UP': return None
    return {'UP':'UPSET','FAV':'CTRL'}.get(me)
def unseen(d): return d<pd.Timestamp('2024-08-31') or d>pd.Timestamp('2026-03-31')
# known answers, worked by hand
assert prev_rank([7,8],9)==8 and prev_rank([8],8) is None and prev_rank([4],9) is None and prev_rank([7],4) is None and prev_rank([8,8],9) is None
assert prior_state(2.5)=='UP' and prior_state(2.49) is None and prior_state(1.99)=='FAV' and prior_state(None) is None
assert label('UP','FAV')=='UPSET' and label('UP','UP') is None and label('FAV',None)=='CTRL' and label('FAV','UP') is None and label(None,'FAV') is None
assert key_short('De Minaur A.')==key_full('Alex De Minaur')==('deminaur','a') and key_short('Nadal') is None
assert abs(fair(1.5,3.0)-2/3)<1e-9 and band(1.49)=='<1.5' and band(1.99)=='1.5-2' and band(2.0) is None
assert unseen(pd.Timestamp('2024-08-30')) and unseen(pd.Timestamp('2026-04-01')) and not unseen(pd.Timestamp('2024-08-31')) and not unseen(pd.Timestamp('2026-03-31'))
assert abs(bk(2.0,True)-10*.99*.98)<1e-9 and bk(2.0,False)==-10.0 and np.isnan(bk(1.02,True))
assert zdiff([0,1]*50,[0,0,0,1]*50)>2 and abs(zdiff([0,1]*50,[0,1]*50))<1e-9
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
c=psycopg2.connect(creds.pg_railway(),sslmode='require')
M=pd.read_sql("SELECT tour,date,winner,loser,psw::float8 psw,psl::float8 psl,score FROM tennis_matches",c)
T=pd.read_sql("SELECT tour,tourney_name,tourney_date,winner_name,loser_name,round,score FROM tennis_results_2026",c); c.close()
M['d']=pd.to_datetime(M.date,errors='coerce'); M['tour']=M.tour.astype(str).str.upper(); T['tour']=T.tour.astype(str).str.upper()
T=T[~T.score.astype(str).str.upper().str.contains(r"W/O|WO|WALK")&~T.tourney_name.str.contains(TEAM)]
print(f"tennis_matches rows {len(M)}, {M.d.min()} to {M.d.max()}, tours {M.tour.value_counts().to_dict()}; result rows {len(T)}",flush=True)
played=defaultdict(list); wonat=set(); ix=defaultdict(list)
for r in T.itertuples():
    a,b=key_full(r.winner_name),key_full(r.loser_name)
    if not (a and b): continue
    q=RANK.get(r.round,99); key=(r.tour,r.tourney_name,r.tourney_date)
    played[key+(a,)].append(q); played[key+(b,)].append(q); wonat.add(key+(a,q))
    ix[(r.tour,frozenset((a,b)))].append(dict(key=key,q=q,date=pd.Timestamp(r.tourney_date),w=a,l=b))
SK=Counter(); PR={}; G=[]; seen=set()
U=M[M.d.notna()]; U=U[U.d.map(unseen)]; SK['rows on unseen dates']=len(U)
for r in U.itertuples():
    if re.search(r"W/O|WO|WALK",str(r.score).upper()): SK['walkover']+=1; continue
    if not (r.psw>1 and r.psl>1): SK['no close']+=1; continue
    w,l=key_short(r.winner),key_short(r.loser)
    if not (w and l): SK['bad name']+=1; continue
    hits=[h for h in ix.get((r.tour,frozenset((w,l))),[]) if -21<=(h['date']-r.d).days<=2]
    if len(hits)!=1: SK['no unique match, or a team event or finals']+=1; continue
    h=hits[0]
    if h['w']!=w: SK['winner disagrees between tables']+=1; continue
    SK['matched']+=1; PR[h['key']+(w,h['q'])]=r.psw; PR[h['key']+(l,h['q'])]=r.psl; G.append((h,r))
def prior(h,x):
    q=prev_rank(played[h['key']+(x,)],h['q'])
    if q is None or h['key']+(x,q) not in wonat: return None
    return PR.get(h['key']+(x,q))
rows=[]
for h,r in G:
    w,l=h['w'],h['l']; sw=prior_state(prior(h,w)); sl=prior_state(prior(h,l)); fw=fair(r.psw,r.psl)
    for st,p,won,fr in ((label(sw,sl),r.psw,True,fw),(label(sl,sw),r.psl,False,1-fw)):
        if st: rows.append((st,band(p),r.tour,r.d,p,won,float(won)-fr,bk(p,won)))
print("counts:",dict(SK),flush=True)
A=pd.DataFrame(rows,columns='st band tour d px won err vb'.split())
if A.empty or not (A.st=='UPSET').any(): print("ERROR: no UPSET rows, no verdict"); sys.exit(1)
print(f"labels, any price: {A.groupby(['tour','st']).size().to_dict()}; UPSET by year {A[A.st=='UPSET'].d.dt.year.value_counts().sort_index().to_dict()}",flush=True)
R=A[A.band.notna()]; H=R[R.st=='UPSET']; C=R[R.st=='CTRL']; z=zdiff(H.err,C.err)
print(f"\n== TEST: close under 2.0, UPSET n {len(H)} won {H.won.mean():.3f} err {H.err.mean():+.4f} v CTRL n {len(C)} err {C.err.mean():+.4f}; z {z:.2f}; bar z >= 2: {'SUPPORTED' if z>=2 else 'NOT SUPPORTED'}",flush=True)
for b in ('<1.5','1.5-2'):
    o=H[H.band==b]; c_=C[C.band==b]
    if len(o)>1 and len(c_)>1: print(f"  band {b}: UPSET n {len(o)} err {o.err.mean():+.4f} v CTRL n {len(c_)} err {c_.err.mean():+.4f}; z {zdiff(o.err,c_.err):.2f}")
for t in sorted(R.tour.unique()):
    o=H[H.tour==t]; c_=C[C.tour==t]
    if len(o)>1 and len(c_)>1: print(f"  {t}: UPSET n {len(o)} err {o.err.mean():+.4f} v CTRL n {len(c_)} err {c_.err.mean():+.4f}; z {zdiff(o.err,c_.err):.2f}")
x=H[H.vb.notna()]; hh=np.where(x.d<x.d.median(),1,2); l=line(x.vb.values,hh); print(f"  back at the close shown, one tick, 2%: n {l['n']} {l['per10']:+.3f} t {l['t']:.2f} h1 {l['h1']:+.3f} h2 {l['h2']:+.3f}")
print("\n== SURVIVORS: none can pass at closes; forward test only if the z test is supported")
print(f"total {time.time()-T0:.0f}s")
PY
