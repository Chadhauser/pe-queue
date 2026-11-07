#!/bin/bash
set -o pipefail
# 499_tennis_own_error (Finder 2026-11-07, queue item 353, Finder's own, source d; engine from jobs/499_tennis_upset_next.sh): a player's own price error, walked forward. Rule pushed in the queue before any price. Read only, no tables written. Last-traded prints, so a pass is an upper bound.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_800_000_000,1_800_000_000))  # this job only
import sys,re,time,unicodedata,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,line,back_settle,lay_settle
pd.set_option('display.width',240); pd.set_option('display.max_rows',150); pd.set_option('display.max_columns',30)
T0=time.time(); BUDGET=2100
TEAM=re.compile(r"davis cup|atp cup|united cup|laver cup|billie jean|bjk|fed cup|hopman|olympic|finals",re.I)
def fold(s): return re.sub(r"[^a-z]","",unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower())
def walkover(score): return bool(re.search(r"W/O|WO|WALK",str(score).upper()))
def retired(score): return bool(re.search(r"RET|ABD|ABN|DEF",str(score).upper()))
def entry(ts,p,mt):
    k=None
    for i in range(len(ts)):
        if mt-1200<=ts[i]<=mt-120: k=i
    if k is None: return None
    nx=float(p[k+1]) if k+1<len(ts) and ts[k+1]-ts[k]<=120 else None
    return float(p[k]),nx
def value(side,e,won):
    if e[0]>50: return None
    if side=='B':
        x=min(e[0],e[1]) if e[1] is not None else e[0]; a=step(x,-1)
        return None if a<=1.01 else back_settle(a,won)
    x=max(e[0],e[1]) if e[1] is not None else e[0]; a=step(x,1)
    return lay_settle(a,won)
def zof(h,minn):
    """h: [sum of won-fair, sum of fair(1-fair), n]. None under minn matches."""
    return None if h[2]<minn or h[1]<=0 else h[0]/h[1]**0.5
def walk(rows,minn):
    """rows: (day,a,b,fair_a,a_won). Returns (z of a, z of b) per row from EARLIER dates only, so a same-day match is never history."""
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
_r=[(i,'A','B',0.5,1) for i in range(20)]+[(20,'A','B',0.5,1),(20,'A','C',0.5,0)]
_w=walk(_r,20)
assert _w[0]==(None,None) and _w[19]==(None,None)                       # match 20 has 19 earlier
assert abs(_w[20][0]-10/5**0.5)<1e-9 and abs(_w[20][1]+10/5**0.5)<1e-9  # 20 wins at 0.5: error 10, variance 5, z 4.472; B -4.472
assert abs(_w[21][0]-10/5**0.5)<1e-9 and _w[21][1] is None              # same day: the 20th-day match does not count, C has no history
assert label(4.5,None)=='HIGH' and label(4.5,1.5) is None and label(4.5,1.49)=='HIGH' and label(-1.5,0.)=='LOW' and label(-2,-2) is None and label(0.5,3.)=='CTRL' and label(1.,0.) is None and label(None,0.) is None
assert entry([100.,1170.,1250.],[2.,3.,4.],1300.)==(3.0,4.0) and entry([1250.],[2.],1300.) is None
assert abs(value('B',(2.0,1.9),True)-8.722)<1e-9 and value('B',(2.0,1.9),False)==-10.0 and abs(value('L',(2.0,2.2),False)-10/1.22*0.98)<1e-9 and value('L',(2.0,2.2),True)==-10.0 and value('B',(51.0,None),True) is None
assert walkover('W/O') and retired('6-1 3-2 RET') and not retired('6-1 6-2')
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
rc=psycopg2.connect(creds.pg_railway(),sslmode='require')
TR=pd.read_sql("""SELECT tourney_name,tourney_date,winner_norm,loser_norm,score,tour FROM tennis_results_2026 WHERE tourney_date>='2024-06-01'""",rc); rc.close()
TR['tour']=TR.tour.astype(str).str.upper(); TR['w']=TR.winner_norm.map(fold); TR['l']=TR.loser_norm.map(fold); TR['wo']=TR.score.map(walkover)
print(f"results {len(TR)}, {TR.tourney_date.min()}..{TR.tourney_date.max()}; tours {TR.tour.value_counts().to_dict()}; walkovers {TR.wo.sum()} | {time.time()-T0:.0f}s",flush=True)
ix=defaultdict(list)
for r in TR[~TR.wo].itertuples():
    ix[frozenset((r.w,r.l))].append(dict(date=r.tourney_date,w=r.w,l=r.l,score=r.score,tour=r.tour,team=bool(TEAM.search(r.tourney_name))))
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
cur.execute("SELECT DISTINCT market_id FROM bf_hist_other WHERE sport='Tennis' AND market_type='MATCH_ODDS'")
MID=sorted(r[0] for r in cur.fetchall() if r[0].startswith('MATCH_ODDS|') and '/' not in r[0]); print(f"singles markets {len(MID)} | {time.time()-T0:.0f}s",flush=True)
SK=Counter(); M=[]; seen=set()
for c_ in range(0,len(MID),800):
    if time.time()-T0>BUDGET: SK['chunks not pulled, budget']+=1; continue
    cur.execute("""SELECT market_id,extract(epoch from market_time)::float8,market_time,sel,extract(epoch from ts)::float8,ltp::float8 FROM bf_hist_other
                   WHERE sport='Tennis' AND market_id=ANY(%s) AND market_type='MATCH_ODDS' AND NOT inplay AND ltp>=1.01 AND ltp<=1000 AND ts>=market_time-interval '25 minutes'""",(MID[c_:c_+800],))
    d=pd.DataFrame(cur.fetchall(),columns='mid mts mt sel ts ltp'.split())
    if d.empty: continue
    d=d.drop_duplicates(['mid','sel','ts']).sort_values(['mid','ts'],kind='stable')
    for mk,g in d.groupby('mid',sort=False):
        SK['market']+=1; run={s:x for s,x in g.groupby('sel',sort=False)}
        if len(run)!=2: SK['not two runners with prints']+=1; continue
        names={fold(s):s for s in run}; day=pd.Timestamp(g.mt.iloc[0]).date(); mt=float(g.mts.iloc[0]); pair=frozenset(names)
        hits=[h for h in ix.get(pair,[]) if -2<=(day-h['date']).days<=21]
        if len(hits)!=1: SK['no unique results match or walkover']+=1; continue
        h=hits[0]
        if (pair,h['date']) in seen: SK['second market on one result row, skipped']+=1; continue
        seen.add((pair,h['date']))
        if h['team']: SK['team event']+=1; continue
        w,l=h['w'],h['l']; ew=entry(run[names[w]].ts.values,run[names[w]].ltp.values,mt); el=entry(run[names[l]].ts.values,run[names[l]].ltp.values,mt)
        if ew is None or el is None: SK['no entry print on both']+=1; continue
        SK['scored']+=1; M.append((day,w,l,ew,el,h['tour'],retired(h['score']),mk))
    print(f"  {min(c_+800,len(MID))}/{len(MID)}, scored {len(M)} | {time.time()-T0:.0f}s",flush=True)
con.close(); print("counts:",dict(sorted(SK.items())),flush=True)
assert len(M)>2000
W=walk([(m[0],m[1],m[2],(1/m[3][0])/(1/m[3][0]+1/m[4][0]),1) for m in M],20)
rows=[]; LAB=Counter()
for m,(zw,zl) in zip(M,W):
    day,w,l,ew,el,tour,ret,mk=m
    for who,z,zo,e,won in ((w,zw,zl,ew,True),(l,zl,zw,el,False)):
        lab=label(z,zo)
        if not lab: continue
        LAB[(tour,lab)]+=1
        for side in 'BL':
            v=value(side,e,won)
            if v is None: continue
            rows.append((lab,side,tour,day,mk,who,ret,won,e[0],v))
print("labels:",{f"{k[0]} {k[1]}":v for k,v in sorted(LAB.items())},flush=True)
R=pd.DataFrame(rows,columns='st side tour day m who ret won px v'.split())
assert not R.duplicated(['st','side','m','who']).any(),"more than one bet per runner per line"
assert not R[R.st.isin(['HIGH','LOW'])].duplicated(['st','side','m']).any(),"both runners of a match in one state"
R['when']=(pd.to_datetime(R.day)-pd.Timestamp('1970-01-01'))/pd.Timedelta(seconds=1)
assert abs((pd.Timestamp('2024-01-01')-pd.Timestamp('1970-01-01'))/pd.Timedelta(seconds=1)-1704067200)<1
def tab(x,**k):
    hh=np.where(x.when.values<np.median(x.when.values),1,2); l=line(x.v.values,hh); xr=x[~x.ret].v
    return dict(**k,n=l['n'],per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2'],n1=l['n1'],n2=l['n2'],x_ret=xr.mean() if len(xr) else np.nan,maxwin=l['maxwin'],won=x.won.mean(),imp=(1/x.px).mean(),players=x.who.nunique(),PASS=bool(l['PASS'] and len(xr)>0 and xr.mean()>=0.15))
out=[]
for (st,side),x in R.groupby(['st','side']):
    for cut,xx in (('ALL',x),('ATP',x[x.tour=='ATP']),('WTA',x[x.tour=='WTA']),('CHALLENGER',x[x.tour=='CHALLENGER'])):
        if len(xx)>=30: out.append(tab(xx,st=st,side=side,cut=cut))
S=pd.DataFrame(out).sort_values('t',ascending=False); A=S[S.st!='CTRL']
print(f"\n== ITEM 353, {len(A)} lines of a possible 16, by t\n",A.round(3).to_string(index=False))
print("\n-- control, cannot pass\n",S[S.st=='CTRL'].drop(columns='PASS').round(3).to_string(index=False))
for cut in ('ALL','ATP','WTA','CHALLENGER'):
    x=R[(R.side=='B')&((R.tour==cut)|(cut=='ALL'))]
    print(f"  won v implied {cut}: "+", ".join(f"{s} n {len(y)} {y.won.mean():.3f} v {(1/y.px).mean():.3f}" for s,y in x.groupby('st')))
W_=A[A.PASS]; print(f"\n== SURVIVORS: {len(W_)} of {len(A)}\n",W_.round(3).to_string(index=False) if len(W_) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
