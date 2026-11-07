#!/bin/bash
set -o pipefail
# 499_tennis_error_close (Finder 2026-11-07, queue item 359, Finder's own, source d; from jobs/499_tennis_own_error.sh and jobs/499_tennis_left_close.sh): a player's own price error at Pinnacle closes, ATP, scored on dates outside the tape. Rule pushed before any close was read. Read only. Closes are a proxy, so no line can pass the bar.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_500_000_000,1_500_000_000))  # this job only
import sys,re,time,unicodedata,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,line,back_settle,lay_settle
pd.set_option('display.width',240); pd.set_option('display.max_columns',30)
T0=time.time()
def fold(s): return re.sub(r"[^a-z]","",unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower())
def key_short(s):
    w=str(s).strip().split()
    if len(w)<2: return None
    return fold(' '.join(w[:-1])),fold(w[-1])[:1]
def fair(pa,pb): return (1/pa)/(1/pa+1/pb)
def bk(x,won):
    a=step(x,-1); return np.nan if a<=1.01 else back_settle(a,won)
def ly(x,won): return lay_settle(step(x,1),won)
def zdiff(a,b):
    a=np.asarray(a,float); b=np.asarray(b,float)
    return (a.mean()-b.mean())/np.sqrt(a.var(ddof=1)/len(a)+b.var(ddof=1)/len(b))
def unseen(d): return d<pd.Timestamp('2024-08-31') or d>pd.Timestamp('2026-03-31')
def zof(h,minn): return None if h[2]<minn or h[1]<=0 else h[0]/h[1]**0.5
def walk(rows,minn):
    """rows: (day,a,b,fair_a,a_won). (z of a, z of b) from EARLIER dates only."""
    H=defaultdict(lambda:[0.,0.,0]); out=[None]*len(rows); o=sorted(range(len(rows)),key=lambda i:rows[i][0]); i=0
    while i<len(o):
        j=i
        while j<len(o) and rows[o[j]][0]==rows[o[i]][0]: j+=1
        for q in o[i:j]:
            d,a,b,f,w=rows[q]; out[q]=(zof(H[a],minn),zof(H[b],minn))
        for q in o[i:j]:
            d,a,b,f,w=rows[q]
            for k,ff,ww in ((a,f,w),(b,1-f,1-w)):
                H[k][0]+=ww-ff; H[k][1]+=ff*(1-ff); H[k][2]+=1
        i=j
    return out
def label(z,zo):
    if z is None: return None
    if z>=1.5: return None if (zo is not None and zo>=1.5) else 'HIGH'
    if z<=-1.5: return None if (zo is not None and zo<=-1.5) else 'LOW'
    return 'CTRL' if abs(z)<=0.5 else None
# known answers, worked by hand
_w=walk([(i,'A','B',0.5,1) for i in range(20)]+[(20,'A','B',0.5,1),(20,'A','C',0.5,0)],20)
assert _w[19]==(None,None) and abs(_w[20][0]-10/5**0.5)<1e-9 and abs(_w[20][1]+10/5**0.5)<1e-9 and abs(_w[21][0]-10/5**0.5)<1e-9 and _w[21][1] is None
assert label(4.5,None)=='HIGH' and label(4.5,1.5) is None and label(-1.5,0.)=='LOW' and label(0.5,3.)=='CTRL' and label(1.,0.) is None
assert key_short('De Minaur A.')==('deminaur','a') and key_short('Nadal') is None and abs(fair(1.5,3.0)-2/3)<1e-9
assert unseen(pd.Timestamp('2024-08-30')) and not unseen(pd.Timestamp('2024-08-31')) and unseen(pd.Timestamp('2026-04-01'))
assert abs(bk(2.0,True)-10*.99*.98)<1e-9 and bk(2.0,False)==-10.0 and ly(2.0,True)==-10.0 and abs(ly(2.0,False)-10/1.02*.98)<1e-9
assert zdiff([0,1]*50,[0,0,0,1]*50)>2 and abs(zdiff([0,1]*50,[0,1]*50))<1e-9
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
c=psycopg2.connect(creds.pg_railway(),sslmode='require')
M=pd.read_sql("SELECT tour,date,winner,loser,psw::float8 psw,psl::float8 psl,score FROM tennis_matches",c); c.close()
M['d']=pd.to_datetime(M.date,errors='coerce'); M['tour']=M.tour.astype(str).str.upper()
print(f"rows {len(M)}, {M.d.min()} to {M.d.max()}, tours {M.tour.value_counts().to_dict()}, {time.time()-T0:.0f}s",flush=True)
SK=Counter(); G=[]
for r in M[M.d.notna()&(M.tour=='ATP')].itertuples():
    if re.search(r"W/O|WO|WALK",str(r.score).upper()): SK['walkover']+=1; continue
    w,l=key_short(r.winner),key_short(r.loser)
    if not (w and l): SK['bad name']+=1; continue
    if not (r.psw>1 and r.psl>1): SK['no close']+=1; continue
    SK['used']+=1; G.append((r.d,w,l,r.psw,r.psl))
print("counts",dict(SK),flush=True)
W=walk([(g[0],g[1],g[2],fair(g[3],g[4]),1) for g in G],20)
rows=[]
for g,(zw,zl) in zip(G,W):
    d,w,l,pw,pl=g; fw=fair(pw,pl)
    if not unseen(d): continue
    for who,z,zo,p,fr,won in ((w,zw,zl,pw,fw,True),(l,zl,zw,pl,1-fw,False)):
        lab=label(z,zo)
        if lab: rows.append((lab,d,p,won,float(won)-fr,bk(p,won),ly(p,won)))
A=pd.DataFrame(rows,columns='st d px won err vb vl'.split()); A['won']=A.won.astype(bool)
print("labels",A.st.value_counts().to_dict(),f"dates {A.d.min()} to {A.d.max()}; by year {A.d.dt.year.value_counts().sort_index().to_dict()}",flush=True)
K=A[A.st=='CTRL']
print("\n== TEST, direction fixed by item 353: HIGH z <= -2 against control; LOW z >= 2 against control")
for st,fn,txt in (('HIGH',lambda z:z<=-2,'lay'),('LOW',lambda z:z>=2,'back')):
    o=A[A.st==st]; z=zdiff(o.err,K.err); c_='vl' if st=='HIGH' else 'vb'; x=o[o[c_].notna()]; ll=line(x[c_].values,np.where(x.d<x.d.median(),1,2))
    print(f"  {st}: n {len(o)} won {o.won.mean():.3f} implied {(1/o.px).mean():.3f} err {o.err.mean():+.4f} v control n {len(K)} err {K.err.mean():+.4f}; z {z:.2f}: {'SUPPORTED' if fn(z) else 'NOT SUPPORTED'}; {txt} at the close, one tick, 2%: n {ll['n']} {ll['per10']:+.3f} t {ll['t']:.2f} h1 {ll['h1']:+.3f} h2 {ll['h2']:+.3f}")
print("\n== SURVIVORS: none can pass at closes; forward test only if the z test is supported")
print(f"total {time.time()-T0:.0f}s")
PY
