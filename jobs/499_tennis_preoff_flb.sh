#!/bin/bash
set -o pipefail
# 499_tennis_preoff_flb (Finder 2026-11-05, queue item 173; from jobs/499_tennis_fav_trouble.sh): tennis pre-off price band by tour, and the favourite's line move, held to the real result. Rule pushed before prices were read (commit 8773b44).
# TAPE: bf_hist_other Tennis singles MATCH_ODDS, last-traded prints only, so a pass is an upper bound. TRUTH: tennis_results_2026 (Railway, this one table read), unique match on both names, tournament start -2 to +21 days. Walkovers void.
# ENTRY: last non-in-play print T-20 to T-2 by market_time; the worse of it and that runner's next non-in-play print within 120 s; one tick adverse; over 50 not traded. Never forward-filled.
# BAND lines: 8 bands x ATP, WTA, ALL x back, lay; one bet per match per line, first runner by name if both share a band. MOVE lines: favourite at entry, P0 last print T-240 to T-120, log(entry print/P0) <= -0.05 SHORT, >= +0.05 DRIFT, else FLAT.
# ITEM 176 (same night, rule pushed before this read): CHALLENGER added as a fourth tour, 22 more lines; the other 66 are unchanged. Diagnostic added: markets sharing one results row.
# COST: 2% on profit, £10 risk. Halves by median date. RETIREMENTS stand as results; a line must also clear +£0.15 with every RET match removed (x_ret), as the Betfair retirement rule is from memory, not checked on this box.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(3_500_000_000,3_500_000_000))  # this job only
import sys,re,time,math,unicodedata,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,line,back_settle,lay_settle
pd.set_option('display.width',230); pd.set_option('display.max_rows',120); pd.set_option('display.max_columns',30)
T0=time.time(); BUDGET=2400
BANDS=((1.01,1.2,'<1.2'),(1.2,1.4,'1.2-1.4'),(1.4,1.7,'1.4-1.7'),(1.7,2.2,'1.7-2.2'),(2.2,3,'2.2-3'),(3,5,'3-5'),(5,10,'5-10'),(10,50.0001,'10-50'))
def fold(s): return re.sub(r"[^a-z]","",unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower())
def walkover(score): return bool(re.search(r"W/O|WO|WALK",str(score).upper()))
def retired(score): return bool(re.search(r"RET|ABD|ABN|DEF",str(score).upper()))
def band(p):
    for lo,hi,lab in BANDS:
        if lo<=p<hi: return lab
    return None
def entry(ts,p,mt):
    """ts seconds, p prices, in time order, all non-in-play. (print, next print within 120 s or None), or None. Window T-20 to T-2 of market time mt."""
    k=None
    for i in range(len(ts)):
        if mt-1200<=ts[i]<=mt-120: k=i
    if k is None: return None
    nx=float(p[k+1]) if k+1<len(ts) and ts[k+1]-ts[k]<=120 else None
    return float(p[k]),nx
def p0_of(ts,p,mt):
    """Last print T-240 to T-120, or None."""
    k=None
    for i in range(len(ts)):
        if mt-14400<=ts[i]<=mt-7200: k=i
    return None if k is None else float(p[k])
def move(e,p0):
    x=math.log(e/p0)
    return 'SHORT' if x<=-0.05 else 'DRIFT' if x>=0.05 else 'FLAT'
def value(side,e,won):
    """e=(print,next or None). Worse of the two for the side, one tick adverse. None at the bottom of the ladder or over 50."""
    if e[0]>50: return None
    if side=='B':
        x=min(e[0],e[1]) if e[1] is not None else e[0]; a=step(x,-1)
        return None if a<=1.01 else back_settle(a,won)
    x=max(e[0],e[1]) if e[1] is not None else e[0]; a=step(x,1)
    return lay_settle(a,won)
# known answers, worked by hand
assert band(1.19)=='<1.2' and band(1.2)=='1.2-1.4' and band(2.2)=='2.2-3' and band(50.0)=='10-50' and band(51.0) is None
assert entry([0.,100.,110.],[2.,3.,4.],1300.)==(4.0,None)            # window 100..1180, 110 is its last print, nothing after
assert entry([100.,1170.,1250.],[2.,3.,4.],1300.)==(3.0,4.0)         # next print 80 s later counts though it is past T-2
assert entry([100.,1170.,1400.],[2.,3.,4.],1300.)==(3.0,None)        # next print 230 s later is not used
assert entry([1250.],[2.],1300.) is None                             # inside T-2: no entry
assert p0_of([700.,8000.],[2.,3.],15000.)==2.0 and p0_of([14000.],[2.],15000.) is None   # window is 600..7800
assert move(2.0,2.2)=='SHORT' and move(2.2,2.0)=='DRIFT' and move(2.0,2.05)=='FLAT'    # log(2/2.2)=-0.095, log(2/2.05)=-0.025
# back 2.0 next 1.9: worse is 1.9, fills 1.89: wins 10x0.89x0.98=8.722. lay 2.0 next 2.2: worse is 2.2, fills 2.22: stake 10/1.22, wins 8.03279 after 2%.
assert abs(value('B',(2.0,1.9),True)-8.722)<1e-9 and value('B',(2.0,1.9),False)==-10.0
assert abs(value('L',(2.0,2.2),False)-10/1.22*0.98)<1e-9 and value('L',(2.0,2.2),True)==-10.0
assert value('B',(1.02,None),True) is None and value('B',(51.0,None),True) is None and value('L',(51.0,None),False) is None
assert walkover('W/O') and not walkover('6-1 3-2 RET') and retired('6-1 3-2 RET') and not retired('6-1 6-2') and fold('Jiří Lehečka')=='jirilehecka'
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
rc=psycopg2.connect(creds.pg_railway(),sslmode='require'); TR=pd.read_sql("SELECT tourney_date,winner_norm,loser_norm,score,tour FROM tennis_results_2026 WHERE tourney_date>='2024-08-01'",rc); rc.close()
TR['tour']=TR.tour.astype(str).str.upper(); print("tours",TR.tour.value_counts().to_dict(),flush=True)
ix=defaultdict(list)
for r in TR.itertuples(): ix[frozenset((fold(r.winner_norm),fold(r.loser_norm)))].append((r.tourney_date,fold(r.winner_norm),r.score,r.tour))
print(f"results {len(TR)}, {TR.tourney_date.min()}..{TR.tourney_date.max()} | {time.time()-T0:.0f}s",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
cur.execute("SELECT DISTINCT market_id FROM bf_hist_other WHERE sport='Tennis' AND market_type='MATCH_ODDS'")
MID=sorted(r[0] for r in cur.fetchall() if r[0].startswith('MATCH_ODDS|') and '/' not in r[0])
print(f"singles markets {len(MID)} | {time.time()-T0:.0f}s",flush=True)
SK=Counter(); rows=[]; HITKEY=Counter()
for c_ in range(0,len(MID),800):
    if time.time()-T0>BUDGET: SK['chunks not pulled, budget']+=1; continue
    cur.execute("""SELECT market_id,extract(epoch from market_time)::float8,market_time,sel,extract(epoch from ts)::float8,ltp::float8 FROM bf_hist_other
                   WHERE sport='Tennis' AND market_id=ANY(%s) AND market_type='MATCH_ODDS' AND NOT inplay AND ltp>=1.01 AND ltp<=1000 AND ts>=market_time-interval '245 minutes'""",(MID[c_:c_+800],))
    d=pd.DataFrame(cur.fetchall(),columns='mid mts mt sel ts ltp'.split())
    if d.empty: continue
    d=d.drop_duplicates(['mid','sel','ts']).sort_values(['mid','ts'],kind='stable')
    for mk,g in d.groupby('mid',sort=False):
        SK['market']+=1; run={s:x for s,x in g.groupby('sel',sort=False)}
        if len(run)!=2: SK['not two runners with prints']+=1; continue
        names={fold(s):s for s in run}; day=pd.Timestamp(g.mt.iloc[0]).date(); mt=float(g.mts.iloc[0])
        hits=[h for h in ix.get(frozenset(names),[]) if -2<=(day-h[0]).days<=21]
        if len(hits)!=1: SK['no unique results match']+=1; continue
        if walkover(hits[0][2]): SK['walkover, void']+=1; continue
        win=names[hits[0][1]]; ret=retired(hits[0][2]); tour=hits[0][3]; E={}; P0={}; HITKEY[(frozenset(names),hits[0][0])]+=1
        for s in sorted(run):
            x=run[s]; e=entry(x.ts.values,x.ltp.values,mt)
            if e is not None: E[s]=e; P0[s]=p0_of(x.ts.values,x.ltp.values,mt)
        if not E: SK['no entry print T-20 to T-2']+=1; continue
        SK['scored']+=1; SK['scored, retirement']+=ret
        seen=set()
        for s,e in E.items():
            b=band(e[0])
            if b is None: SK['runner over 50']+=1; continue
            if b in seen: SK['both runners in one band, second skipped']+=1; continue
            seen.add(b)
            for side in 'BL': rows.append(('BAND',b,tour,side,day,mk,value(side,e,s==win),ret,s==win,e[0]))
        if len(E)==2 and E[list(E)[0]][0]!=E[list(E)[1]][0]:
            f=min(E,key=lambda k:E[k][0])
            if P0[f] is None: SK['favourite no print T-240 to T-120']+=1
            else:
                m=move(E[f][0],P0[f])
                for side in 'BL': rows.append(('MOVE',m,tour,side,day,mk,value(side,E[f],f==win),ret,f==win,E[f][0]))
        else: SK['no clear favourite']+=1
    print(f"  {min(c_+800,len(MID))}/{len(MID)}, rows {len(rows)} | {time.time()-T0:.0f}s",flush=True)
con.close(); print("counts:",dict(sorted(SK.items())),flush=True)
print(f"results rows matched by more than one market: {sum(1 for v in HITKEY.values() if v>1)} of {len(HITKEY)}; extra markets {sum(v-1 for v in HITKEY.values())}",flush=True)
R=pd.DataFrame(rows,columns='kind key tour side day m v ret won px'.split())
if R.empty: print("ERROR: no entries, no verdict"); sys.exit(1)
nb=R.v.isna().sum(); R=R.dropna(subset=['v']); R['v']=R.v.astype(float); R['when']=pd.to_datetime(R.day).astype('int64')
print(f"dates {R.day.min()}..{R.day.max()}; matches {R.m.nunique()}; no bet at the bottom of the ladder {nb}; retirements {R.drop_duplicates('m').ret.mean():.3f} of matches",flush=True)
out=[]
for (kind,key,side),A in R.groupby(['kind','key','side']):
    for tour in ('ATP','WTA','CHALLENGER','ALL'):
        x=A if tour=='ALL' else A[A.tour==tour]
        if not len(x): continue
        md=np.median(x.when.values); l=line(x.v.values,np.where(x.when.values<md,1,2)); xr=x[~x.ret].v
        ok=bool(l['PASS'] and len(xr)>0 and xr.mean()>=0.15)
        out.append(dict(kind=kind,key=key,tour=tour,side=side,n=l['n'],per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2'],n1=l['n1'],n2=l['n2'],x_ret=xr.mean() if len(xr) else np.nan,won=x.won.mean(),implied=(1/x.px).mean(),maxwin=l['maxwin'],PASS=ok))
S=pd.DataFrame(out).sort_values('t',ascending=False); print(f"\n== ALL {len(S)} LINES, per £10, by t\n",S.round(3).to_string(index=False))
W=S[S.PASS]; print(f"\n== SURVIVORS: {len(W)} of {len(S)}\n",W.round(3).to_string(index=False) if len(W) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
