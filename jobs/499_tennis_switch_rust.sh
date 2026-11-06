#!/bin/bash
set -o pipefail
# 499_tennis_switch_rust (Finder 2026-11-06, queue item 211, Finder's own, source c): surface switch and rust at the last pre-off print. Rule pushed before any price was read. The number 499 is reused: 450-499 are all taken.
# STATE walk of tennis_results_2026 (Railway, this table read only, as jobs/499_tennis_elo.sh), walkovers out, in tournament date then round order; only earlier matches count. Dates are tournament starts, so gaps are coarse.
# TAPE, ENTRY, MATCH, RETIREMENTS as jobs/499_tennis_elo.sh: T-20 to T-2, worse of the print and the next within 120 s, one tick, <= 50, 2%, £10 risk, last-traded prints so an upper bound; unique match on both names, tournament start -2 to +21 days; a line must also clear +£0.15 with retirements removed.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))  # this job only
import sys,re,time,unicodedata,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,line,back_settle,lay_settle
pd.set_option('display.width',230); pd.set_option('display.max_rows',120); pd.set_option('display.max_columns',30)
T0=time.time(); BUDGET=2100
RANK={'Q1':0,'Q2':1,'Q3':2,'Q4':2.5,'ER':3,'RR':4,'R128':5,'R64':6,'R32':7,'R16':8,'QF':9,'SF':10,'BR':10.5,'F':11,
      '1st Round':5,'2nd Round':6,'3rd Round':7,'4th Round':8,'Round Robin':4,'Quarterfinals':9,'Semifinals':10,'The Final':11}
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
def states(pa,pb,surf,day):
    """pa,pb: (last surface,last tournament date as ordinal) or None. Returns the set of (state, 'a' or 'b') for this match."""
    out=set()
    if not str(surf).strip(): return out
    def sw(x): return x is not None and x[0]!=surf and 0<=day-x[1]<=21
    def same(x): return x is not None and x[0]==surf
    def rust(x): return x is not None and 28<=day-x[1]<=180
    def fresh(x): return x is not None and 0<=day-x[1]<=14
    if sw(pa) and same(pb): out.add(('SWITCH','a'))
    if sw(pb) and same(pa): out.add(('SWITCH','b'))
    if rust(pa) and fresh(pb): out.add(('RUST','a'))
    if rust(pb) and fresh(pa): out.add(('RUST','b'))
    return out
# known answers, worked by hand
assert states(('Clay',100),('Grass',100),'Grass',110)=={('SWITCH','a')}          # a from clay 10 days back; b already on grass
assert states(('Clay',100),('Clay',100),'Grass',110)==set()                       # both switching: no state
assert states(('Clay',80),('Grass',100),'Grass',110)=={('RUST','a')}              # a's clay is 30 days back: not a switch, is rust, b is fresh
assert states(('Clay',89),('Grass',100),'Grass',110)=={('SWITCH','a')}            # exactly 21 days: switch; 21 is not rust
assert states(('Clay',82),('Grass',96),'Grass',110)=={('RUST','a')} and states(('Clay',82),('Grass',95),'Grass',110)==set()   # 28 days rust; b 14 days fresh, 15 not
assert states(('Clay',100),('Grass',100),'',110)==set()                           # this match's surface blank: no state
assert states(None,('Grass',100),'Grass',110)==set()                             # a has no history: no state
assert states(('Grass',-200),('Grass',100),'Grass',110)==set()                    # 310 days: past 180, not rust
assert entry([100.,1170.,1250.],[2.,3.,4.],1300.)==(3.0,4.0) and entry([1250.],[2.],1300.) is None
assert abs(value('B',(2.0,1.9),True)-8.722)<1e-9 and value('B',(2.0,1.9),False)==-10.0 and abs(value('L',(2.0,2.2),False)-10/1.22*0.98)<1e-9 and value('L',(2.0,2.2),True)==-10.0 and value('B',(51.0,None),True) is None
assert walkover('W/O') and retired('6-1 3-2 RET') and not retired('6-1 6-2')
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
rc=psycopg2.connect(creds.pg_railway(),sslmode='require')
TR=pd.read_sql("SELECT tourney_date,winner_norm,loser_norm,score,tour,surface,round,match_num FROM tennis_results_2026",rc); rc.close()
TR['tour']=TR.tour.astype(str).str.upper(); TR['rk']=TR['round'].map(RANK).fillna(4)
TR=TR.sort_values(['tourney_date','rk','match_num'],kind='stable'); last={}; ix=defaultdict(list); nw=0
for r in TR.itertuples():
    if walkover(r.score): nw+=1; continue
    w,l=fold(r.winner_norm),fold(r.loser_norm); day=pd.Timestamp(r.tourney_date).toordinal()
    ix[frozenset((w,l))].append((r.tourney_date,w,l,r.score,r.tour,r.surface,states(last.get(w),last.get(l),r.surface,day)))
    if str(r.surface).strip(): last[w]=(r.surface,day); last[l]=(r.surface,day)   # a blank surface (451 rows) is no information: never recorded, so it cannot make a false switch
print(f"results {len(TR)}, walkovers out {nw}, {TR.tourney_date.min()}..{TR.tourney_date.max()}, surfaces {TR.surface.value_counts().to_dict()} | {time.time()-T0:.0f}s",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
cur.execute("SELECT DISTINCT market_id FROM bf_hist_other WHERE sport='Tennis' AND market_type='MATCH_ODDS'")
MID=sorted(r[0] for r in cur.fetchall() if r[0].startswith('MATCH_ODDS|') and '/' not in r[0]); print(f"singles markets {len(MID)} | {time.time()-T0:.0f}s",flush=True)
SK=Counter(); rows=[]; seen=set()
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
        hits=[h for h in ix.get(pair,[]) if -2<=(day-h[0]).days<=21]
        if len(hits)!=1: SK['no unique results match or walkover']+=1; continue
        hd,w,l,score,tour,surf,st=hits[0]
        if (pair,hd) in seen: SK['second market on one result row, skipped']+=1; continue
        seen.add((pair,hd)); SK['matched']+=1
        if not st: continue
        ret=retired(score)
        for state,who in st:
            k=w if who=='a' else l; won=k==w; e=entry(run[names[k]].ts.values,run[names[k]].ltp.values,mt)
            if e is None: SK['no entry print']+=1; continue
            SK['scored '+state]+=1
            for side in 'BL':
                v=value(side,e,won)
                if v is None: SK['no bet at the ladder ends']+=1; continue
                rows.append((state,side,tour,surf,day,mk,ret,won,e[0],v))
    print(f"  {min(c_+800,len(MID))}/{len(MID)}, rows {len(rows)} | {time.time()-T0:.0f}s",flush=True)
con.close(); print("counts:",dict(sorted(SK.items())),flush=True)
R=pd.DataFrame(rows,columns='state side tour surf day m ret won px v'.split())
if R.empty: print("ERROR: no entries, no verdict"); sys.exit(1)
R['when']=pd.to_datetime(R.day).astype('int64'); print(f"dates {R.day.min()}..{R.day.max()}; markets {R.m.nunique()}",flush=True)
def tab(x,**k):
    md=np.median(x.when.values); l=line(x.v.values,np.where(x.when.values<md,1,2)); xr=x[~x.ret].v
    return dict(**k,n=l['n'],per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2'],n1=l['n1'],n2=l['n2'],x_ret=xr.mean() if len(xr) else np.nan,won=x.won.mean(),implied=(1/x.px).mean(),maxwin=l['maxwin'],PASS=bool(l['PASS'] and len(xr)>0 and xr.mean()>=0.15))
out=[]
for (st,side),A in R.groupby(['state','side']):
    out.append(tab(A,state=st,side=side,cut='ALL'))
    for t_ in ('ATP','WTA','CHALLENGER'):
        x=A[A.tour==t_]
        if len(x): out.append(tab(x,state=st,side=side,cut=t_))
    if st=='SWITCH':
        for s_ in ('Clay','Grass','Hard'):
            x=A[A.surf==s_]
            if len(x): out.append(tab(x,state=st,side=side,cut='INTO '+s_))
S=pd.DataFrame(out).sort_values('t',ascending=False); print(f"\n== ALL {len(S)} LINES, per £10, by t\n",S.round(3).to_string(index=False))
W=S[S.PASS]; print(f"\n== SURVIVORS: {len(W)} of {len(S)}\n",W.round(3).to_string(index=False) if len(W) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
