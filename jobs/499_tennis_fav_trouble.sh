#!/bin/bash
set -o pipefail
# 499_tennis_fav_trouble (Finder 2026-11-05, queue item 171; from jobs/482, jobs/499_tennis_late_outsider.sh): T2 and T3 of item 27 on the BASIC tape, rule as written in the queue before prices were read (commit 0820fac).
# TAPE: bf_hist_other Tennis singles MATCH_ODDS, last-traded prints only, so a pass is an upper bound. TRUTH: tennis_results_2026 (Railway, this one read), unique match on both names, tournament start -2 to +21 days. Walkovers void.
# FAVOURITE: the shorter last pre-off print, 1.30-2.00. T2: first in-play print above 2.00 and at most 15. T3: first in-play print >= 1.20 x either of the two prints before it, that print at most 15, with pre-move price = that print.
# ENTRY: next print, never the trigger's own, one tick adverse; no next print = no trade, counted. EXIT: T2 holds to the result. T3 first later print at or under the pre-move price within 40 minutes, one tick adverse, else the result.
# 2% commission, £10 risk, one entry per match per rule. Halves by median market date.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(3_500_000_000,3_500_000_000))  # this job only
import sys,re,time,unicodedata,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,line,back_settle,lay_settle,back_hedge,lay_hedge
pd.set_option('display.width',230); pd.set_option('display.max_rows',80); pd.set_option('display.max_columns',30)
T0=time.time(); BUDGET=2400
def fold(s): return re.sub(r"[^a-z]","",unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower())
def walkover(score): return bool(re.search(r"W/O|WO|WALK",str(score).upper()))
def t2_entry(p):
    """Index of the entry print: the print after the first one above 2.00 and at most 15. 'nofill' if none. None if never triggered."""
    for i in range(len(p)):
        if 2.0<p[i]<=15: return i+1 if i+1<len(p) else 'nofill'
    return None
def t3_entry(p):
    """(entry index, pre-move price) or (None,None) or ('nofill',pre)."""
    for i in range(1,len(p)):
        for j in (i-1,i-2):
            if j>=0 and p[j]<=15 and p[i]>=1.2*p[j]-1e-9:
                return (i+1 if i+1<len(p) else 'nofill'),float(p[j])
    return None,None
def t3_exit(ts,p,k,pre,hor=2400.0):
    """First print after the entry at or under pre within hor seconds, else None (hold to the result)."""
    for i in range(k+1,len(p)):
        if ts[i]-ts[k]>hor: return None
        if p[i]<=pre+1e-9: return i
    return None
def value(side,x,won,q=None):
    """Entry print x, one tick adverse. q is the exit print, else settled at the result. None: no bet at the bottom of the ladder."""
    if side=='B':
        a=step(x,-1)
        if a<=1.01: return None
        return back_hedge(a,q) if q is not None else back_settle(a,won)
    a=step(x,1)
    return lay_hedge(a,q) if q is not None else lay_settle(a,won)
# known answers, worked by hand
assert t2_entry([1.6,1.9,2.2,2.5,2.1])==3 and t2_entry([1.6,1.9])is None and t2_entry([1.6,2.2])=='nofill' and t2_entry([1.5,16.0,2.1,2.2])==3   # 16 is too long, next trigger is 2.1
assert t3_entry([1.5,1.5,1.8,1.7])==(3,1.5) and t3_entry([1.5,1.6,1.8,1.7])==(3,1.5) and t3_entry([1.5,1.55,1.6])==(None,None)                       # two prints back counts
assert t3_entry([1.5,1.8])==('nofill',1.5) and t3_entry([16.,20.,24.])==(None,None)
_ts=np.array([0.,60.,120.,180.,3000.]); assert t3_exit(_ts,[1.8,1.7,1.6,1.5,1.4],1,1.5)==3 and t3_exit(_ts,[1.8,1.7,1.6,1.6,1.4],1,1.5) is None and t3_exit(_ts,[1.8,1.7],1,1.5) is None
assert abs(value('B',2.5,True)-10*(2.48-1)*.98)<1e-9 and value('B',2.5,False)==-10.0 and value('B',1.02,True) is None                                # 2.5 fills 2.48
assert value('L',2.5,True)==-10.0 and abs(value('L',2.5,False)-10/(2.52-1)*.98)<1e-9                                                                  # 2.5 fills 2.52
assert abs(value('B',2.0,True,1.5)-.98*10*(1.99/1.51-1))<1e-9 and abs(value('L',2.0,True,1.5)-10/(2.02-1)*(1-2.02/1.49))<1e-9                        # exits a tick adverse
assert walkover('W/O') and not walkover('6-1 3-2 RET') and fold('Jiří Lehečka')=='jirilehecka'
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
rc=psycopg2.connect(creds.pg_railway(),sslmode='require'); TR=pd.read_sql("SELECT tourney_date,winner_norm,loser_norm,score,tour FROM tennis_results_2026 WHERE tourney_date>='2024-08-01'",rc); rc.close()
ix=defaultdict(list)
for r in TR.itertuples(): ix[frozenset((fold(r.winner_norm),fold(r.loser_norm)))].append((r.tourney_date,fold(r.winner_norm),walkover(r.score),r.tour))
print(f"results {len(TR)}, {TR.tourney_date.min()}..{TR.tourney_date.max()} | {time.time()-T0:.0f}s",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
cur.execute("SELECT DISTINCT market_id FROM bf_hist_other WHERE sport='Tennis' AND market_type='MATCH_ODDS'")
MID=[r[0] for r in cur.fetchall() if r[0].startswith('MATCH_ODDS|') and '/' not in r[0]]; MID.sort()
print(f"singles MATCH_ODDS markets {len(MID)} | {time.time()-T0:.0f}s",flush=True)
SK=Counter(); rows=[]
for c_ in range(0,len(MID),800):
    if time.time()-T0>BUDGET: SK['chunks not pulled, budget']+=1; break
    cur.execute("""SELECT market_id,market_time,sel,extract(epoch from ts)::float8,ltp::float8,inplay FROM bf_hist_other WHERE sport='Tennis' AND market_id=ANY(%s) AND market_type='MATCH_ODDS' AND ltp>=1.01 AND ltp<=1000""",(MID[c_:c_+800],))
    d=pd.DataFrame(cur.fetchall(),columns='mid mt sel ts ltp ip'.split())
    if d.empty: continue
    d=d.drop_duplicates(['mid','sel','ts']).sort_values(['mid','ts'],kind='stable')
    for mk,g in d.groupby('mid',sort=False):
        SK['market']+=1; run={s:x for s,x in g.groupby('sel',sort=False)}
        if len(run)!=2: SK['not two runners with prints']+=1; continue
        names={fold(s):s for s in run}; day=pd.Timestamp(g.mt.iloc[0]).date()
        hits=[h for h in ix.get(frozenset(names),[]) if -2<=(day-h[0]).days<=21]
        if len(hits)!=1: SK['no unique results match']+=1; continue
        if hits[0][2]: SK['walkover, void']+=1; continue
        tw=names[hits[0][1]]; pre={}
        for s,x in run.items():
            y=x[~x.ip]
            if len(y): pre[s]=float(y.ltp.iloc[-1])
        if len(pre)!=2 or pre[list(pre)[0]]==pre[list(pre)[1]]: SK['no clear favourite before the off']+=1; continue
        fav=min(pre,key=pre.get); p0=pre[fav]
        if not 1.30<=p0<=2.00: SK['favourite outside 1.30-2.00']+=1; continue
        x=run[fav]; x=x[x.ip]; ts,p=x.ts.values,x.ltp.values.astype(float)
        if len(p)==0: SK['favourite no in-play print']+=1; continue
        SK['scored']+=1; won=fav==tw; bd='1.30-1.50' if p0<1.50 else '1.50-2.00'
        k=t2_entry(p)
        if k=='nofill': SK['T2 no next print']+=1
        elif k is not None:
            for side in 'BL': rows.append(('T2',bd,side,day,mk,value(side,float(p[k]),won),True,won,float(p[k])))
        k,pr=t3_entry(p)
        if k=='nofill': SK['T3 no next print']+=1
        elif k is not None:
            e=t3_exit(ts,p,k,pr); q=None if e is None else float(p[e])
            for side in 'BL': rows.append(('T3',bd,side,day,mk,value(side,float(p[k]),won,q),e is None,won,float(p[k])))
    print(f"  {min(c_+800,len(MID))}/{len(MID)}, rows {len(rows)} | {time.time()-T0:.0f}s",flush=True)
con.close(); print("counts:",dict(sorted(SK.items())),flush=True)
R=pd.DataFrame(rows,columns='rule bd side day m v settled won px'.split())
if R.empty: print("ERROR: no entries, no verdict"); sys.exit(1)
nb=R.v.isna().sum(); R=R.dropna(subset=['v']); R['v']=R.v.astype(float); R['when']=pd.to_datetime(R.day).astype('int64')
print(f"dates {R.day.min()}..{R.day.max()}; matches {R.m.nunique()}; no bet at the bottom of the ladder {nb}",flush=True)
out=[]
for rule,side,bd in [(a,b,c) for a in ('T2','T3') for b in 'BL' for c in ('1.30-1.50','1.50-2.00','ALL')]:
    x=R[(R.rule==rule)&(R.side==side)&((R.bd==bd)|(bd=='ALL'))]
    if not len(x): continue
    md=np.median(x.when.values); l=line(x.v.values,np.where(x.when.values<md,1,2))
    out.append(dict(rule=rule,side=side,band=bd,n=l['n'],matches=x.m.nunique(),per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2'],n1=l['n1'],n2=l['n2'],won=x.won.mean(),implied=(1/x.px).mean(),settled=x.settled.mean(),maxwin=l['maxwin'],PASS=l['PASS']))
S=pd.DataFrame(out).sort_values('t',ascending=False); print("\n== ALL LINES, per £10, by t\n",S.round(3).to_string(index=False))
W=S[S.PASS]; print(f"\n== SURVIVORS: {len(W)} of {len(S)}\n",W.round(3).to_string(index=False) if len(W) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
