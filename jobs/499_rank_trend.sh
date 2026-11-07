#!/bin/bash
set -o pipefail
# 499_rank_trend (Finder 2026-11-07, queue item 376, Finder's own, source d, from jobs/499_tennis_left_close.sh): a tennis player rising or falling in the rankings, at Pinnacle closes. Rule pushed before any close was read. Read only. Closes are a proxy, so no line can pass the bar.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_500_000_000,1_500_000_000))  # this job only
import sys,re,time,unicodedata,warnings,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,line,back_settle,lay_settle
pd.set_option('display.width',240); pd.set_option('display.max_rows',80); pd.set_option('display.max_columns',30)
T0=time.time()
def fold(s): return re.sub(r"[^a-z]","",unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower())
def key_short(s):
    w=str(s).strip().split()
    return None if len(w)<2 else (fold(' '.join(w[:-1])),fold(w[-1])[:1])
def fair(pa,pb): return (1/pa)/(1/pa+1/pb)
def bk(x,won):
    a=step(x,-1); return np.nan if a<=1.01 else back_settle(a,won)
def ly(x,won): return lay_settle(step(x,1),won)
def zdiff(a,b):
    a=np.asarray(a,float); b=np.asarray(b,float)
    return (a.mean()-b.mean())/np.sqrt(a.var(ddof=1)/len(a)+b.var(ddof=1)/len(b))
def band(p): return '<1.5' if p<1.5 else '1.5-2' if p<2 else '2-3' if p<3 else '3-6' if p<6 else None
def state(now,then):
    """now, then ranks; None outside the rule."""
    if now is None or then is None or not (now==now and then==then) or now<=0 or then<=0 or now>300 or then>300: return None
    r=now/then
    return 'RISER' if r<=0.6 else 'FALLER' if r>=5/3 else 'STEADY' if 0.8<=r<=1.25 else None
def rank_then(hist,d,lo=120,hi=240):
    """hist sorted [(date,rank)]; latest rank 120-240 days before d, else None."""
    best=None
    for x,r in hist:
        g=(d-x).days
        if lo<=g<=hi: best=r
    return best
# known answers, worked by hand
assert state(60,100)=='RISER' and state(61,100) is None and state(100,60)=='FALLER' and state(99,60) is None and state(100,100)=='STEADY' and state(125,100)=='STEADY' and state(126,100) is None and state(301,100) is None and state(100,301) is None and state(float('nan'),100) is None
D=pd.Timestamp
assert rank_then([(D('2025-01-01'),50),(D('2025-03-01'),40),(D('2025-07-01'),30)],D('2025-08-01'))==40 and rank_then([(D('2025-07-01'),30)],D('2025-08-01')) is None
assert key_short('De Minaur A.')==('deminaur','a') and abs(fair(1.5,3.0)-2/3)<1e-9 and band(1.49)=='<1.5' and band(5.99)=='3-6' and band(6) is None
assert zdiff([0,1]*50,[0,0,0,1]*50)>2 and ly(2.0,True)==-10.0
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
c=psycopg2.connect(creds.pg_railway(),sslmode='require')
M=pd.read_sql("SELECT tour,date,winner,loser,wrank::float8 wr,lrank::float8 lr,psw::float8 psw,psl::float8 psl,score FROM tennis_matches",c); c.close()
M['d']=pd.to_datetime(M.date,errors='coerce'); M['tour']=M.tour.astype(str).str.upper(); M=M[M.d.notna()].sort_values('d')
print(f"rows {len(M)}, {M.d.min()} to {M.d.max()}, tours {M.tour.value_counts().to_dict()}, with close {int(((M.psw>1)&(M.psl>1)).sum())}, {time.time()-T0:.0f}s",flush=True)
H=defaultdict(list); rows=[]; n_wo=0
for r in M.itertuples():
    w,l=key_short(r.winner),key_short(r.loser)
    if not (w and l): continue
    wo=bool(re.search(r"W/O|WO|WALK",str(r.score).upper())); n_wo+=wo
    if not wo and r.psw>1 and r.psl>1:
        fw=fair(r.psw,r.psl)
        for who,now,won,p,fr in ((w,r.wr,True,r.psw,fw),(l,r.lr,False,r.psl,1-fw)):
            st=state(now,rank_then(H[(r.tour,who)],r.d)); b=band(p)
            if st and b: rows.append((r.tour,st,b,r.d,p,won,float(won)-fr,bk(p,won),ly(p,won)))
    for who,now in ((w,r.wr),(l,r.lr)):
        if now==now: H[(r.tour,who)].append((r.d,now))
A=pd.DataFrame(rows,columns='tour st band d px won err vb vl'.split()); A['won']=A.won.astype(bool)
print(f"walkovers skipped {n_wo}; rows {len(A)}, {A.st.value_counts().to_dict()}, {time.time()-T0:.0f}s",flush=True)
out=[]
for (tr,st,b),o in A[A.st!='STEADY'].groupby(['tour','st','band']):
    k=A[(A.tour==tr)&(A.st=='STEADY')&(A.band==b)]
    if len(o)<30 or len(k)<30: continue
    z=zdiff(o.err,k.err); sign=1 if st=='RISER' else -1
    v=(o.vb if st=='RISER' else o.vl).values; h=np.where(o.d<o.d.median(),1,2); ok=~np.isnan(v); ll=line(v[ok],h[ok])
    out.append(dict(tour=tr,st=st,band=b,n=len(o),won=o.won.mean(),imp=(1/o.px).mean(),err=o.err.mean(),ctrl=k.err.mean(),z=z,dirz=z*sign,side='back' if st=='RISER' else 'lay',per10=ll['per10'],t=ll['t'],h1=ll['h1'],h2=ll['h2'],SUPPORTED=bool(z*sign>=2)))
O=pd.DataFrame(out).sort_values('dirz',ascending=False)
print(f"\n== ITEM 376: {len(O)} lines, z in the rule's direction v STEADY; trade at the close, one tick, 2%\n",O.round(3).to_string(index=False))
S=O[O.SUPPORTED]; print(f"\n== SUPPORTED: {len(S)} of {len(O)}\n",S.round(3).to_string(index=False) if len(S) else "none")
print("\n== SURVIVORS: none can pass at closes; a tape test only for a supported line")
print(f"total {time.time()-T0:.0f}s")
PY
