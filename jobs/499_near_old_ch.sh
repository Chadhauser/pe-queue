#!/bin/bash
set -o pipefail
# 499_near_old_ch (Finder 2026-11-06, queue item 224, Finder's own, source c, from jobs/499_old_fav.sh): Challenger favourite aged 30 to under 33, an age band item 222 pooled into its control and never read apart. Rule pushed before this band's prices were read. Read only. The number 499 is reused: 450-499 are all taken.
# TAPE, ENTRY, MATCH, RETIREMENTS as jobs/499_tennis_format.sh: T-20 to T-2, worse of the print and the next within 120 s, one tick, <= 50, 2%, £10 risk, to the result, last-traded prints so an upper bound; unique match on both names, tournament start -2 to +21 days; a line must also clear +£0.15 with retirements removed.
# RULE: NEAR = CHALLENGER favourite aged 30 to under 33 and at least 3 years older than the opponent. Bands <1.5, 1.5-2. Back and lay. 4 lines. Control = other Challenger favourites under 30 or not 3 years older, same band, cannot pass; favourites 33+ are left out, as item 222 read them.
# ENGINE CHECK: the job also rebuilds item 215's YOUNG <2 back line, which printed n 1,901 +0.169 t 1.04 h1 +0.178 h2 +0.160. A mismatch means the port drifted or the data moved, and is printed.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_800_000_000,1_800_000_000))  # this job only
import sys,re,time,unicodedata,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,line,back_settle,lay_settle
pd.set_option('display.width',240); pd.set_option('display.max_rows',150); pd.set_option('display.max_columns',30)
T0=time.time(); BUDGET=2100
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
def band(p): return '<1.5' if p<1.5 else '1.5-2' if p<2 else None
def near(af,ao):
    """Favourite 30 to under 33 and at least 3 years older than the opponent. Missing age: False."""
    if af is None or ao is None or af!=af or ao!=ao: return False
    return 30<=af<33 and af-ao>=3
def young(ax,bx,gap=6.0):
    if ax is None or bx is None or ax!=ax or bx!=bx: return None
    return 'a' if bx-ax>=gap else 'b' if ax-bx>=gap else None
def zdiff(a,b):
    a=np.asarray(a,float); b=np.asarray(b,float)
    return (a.mean()-b.mean())/np.sqrt(a.var(ddof=1)/len(a)+b.var(ddof=1)/len(b))
# known answers, worked by hand
assert near(30.,27.) and near(32.99,20.) and not near(33.,20.) and not near(29.99,20.) and not near(30.,27.01) and not near(27.,30.) and not near(None,30.) and not near(31.,float('nan'))
assert band(1.49)=='<1.5' and band(1.5)=='1.5-2' and band(1.99)=='1.5-2' and band(2.0) is None
assert entry([100.,1170.,1250.],[2.,3.,4.],1300.)==(3.0,4.0) and entry([1250.],[2.],1300.) is None
assert abs(value('B',(2.0,1.9),True)-8.722)<1e-9 and value('B',(2.0,1.9),False)==-10.0 and abs(value('L',(2.0,2.2),False)-10/1.22*0.98)<1e-9 and value('L',(2.0,2.2),True)==-10.0 and value('B',(51.0,None),True) is None
assert walkover('W/O') and retired('6-1 3-2 RET') and not retired('6-1 6-2')
assert abs(zdiff([0,1]*50,[0,1]*50))<1e-9 and zdiff([0,1]*50,[0,0,0,1]*50)>2
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
rc=psycopg2.connect(creds.pg_railway(),sslmode='require')
TR=pd.read_sql("""SELECT tourney_date,winner_norm,loser_norm,score,tour,round,winner_age::float8 winner_age,loser_age::float8 loser_age FROM tennis_results_2026""",rc); rc.close()
TR['tour']=TR.tour.astype(str).str.upper()
print(f"results {len(TR)}, {TR.tourney_date.min()}..{TR.tourney_date.max()}; tours {TR.tour.value_counts().to_dict()}",flush=True)
print("share with both ages, by tour:",TR.assign(b=TR.winner_age.notna()&TR.loser_age.notna()).groupby('tour').b.mean().round(3).to_dict(),flush=True)
ix=defaultdict(list); nw=0
for r in TR.itertuples():
    if walkover(r.score): nw+=1; continue
    w,l=fold(r.winner_norm),fold(r.loser_norm)
    ix[frozenset((w,l))].append(dict(date=r.tourney_date,w=w,l=l,score=r.score,tour=r.tour,aw=r.winner_age,al=r.loser_age))
print(f"walkovers out {nw} | {time.time()-T0:.0f}s",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
cur.execute("SELECT DISTINCT market_id FROM bf_hist_other WHERE sport='Tennis' AND market_type='MATCH_ODDS'")
MID=sorted(r[0] for r in cur.fetchall() if r[0].startswith('MATCH_ODDS|') and '/' not in r[0]); print(f"singles markets {len(MID)} | {time.time()-T0:.0f}s",flush=True)
SK=Counter(); rows=[]; seen=set(); yrows=[]
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
        seen.add((pair,h['date'])); SK['matched']+=1
        w,l=h['w'],h['l']; ew=entry(run[names[w]].ts.values,run[names[w]].ltp.values,mt); el=entry(run[names[l]].ts.values,run[names[l]].ltp.values,mt)
        if ew is None or el is None: SK['no entry print on both']+=1; continue
        SK['scored']+=1; ret=retired(h['score']); T=h['tour']; pw,pl=ew[0],el[0]
        y=young(h['aw'],h['al'])
        if y:   # engine check, item 215 YOUNG <2 back
            k=w if y=='a' else l; p=pw if k==w else pl
            if p<2:
                v=value('B',ew if k==w else el,k==w)
                if v is not None: yrows.append((day,v))
        if pw==pl: SK['equal prints, no bet']+=1; continue
        fav_w=pw<pl; pf,po=(pw,pl) if fav_w else (pl,pw); b=band(pf)
        if not b: continue
        af,ao=(h['aw'],h['al']) if fav_w else (h['al'],h['aw'])
        if af!=af or ao!=ao or af is None or ao is None: SK['favourite in band, age missing']+=1; continue
        if T!='CHALLENGER': continue
        if af>=33: SK['33 or over, read by item 222, out']+=1; continue
        st='NEAR' if near(af,ao) else 'CTRL'; SK[f'in band {st}']+=1
        e=ew if fav_w else el; fair=(1/pf)/(1/pf+1/po)
        for side in 'BL':
            v=value(side,e,fav_w)
            if v is None: SK['no bet at the ladder ends']+=1; continue
            rows.append((st,b,side,T,day,mk,ret,fav_w,pf,fair,w if fav_w else l,v))
    print(f"  {min(c_+800,len(MID))}/{len(MID)}, rows {len(rows)} | {time.time()-T0:.0f}s",flush=True)
con.close(); print("counts:",dict(sorted(SK.items())),flush=True)
Y=pd.DataFrame(yrows,columns=['day','v'])
if len(Y):
    wh=pd.to_datetime(Y.day).astype('int64').values; yl=line(Y.v.values,np.where(wh<np.median(wh),1,2))
    print(f"ENGINE CHECK, item 215 YOUNG <2 back, was n 1901 +0.169 t 1.04 h1 +0.178 h2 +0.160; now n {yl['n']} {yl['per10']:+.3f} t {yl['t']:.2f} h1 {yl['h1']:+.3f} h2 {yl['h2']:+.3f}",flush=True)
R=pd.DataFrame(rows,columns='st band side tour day m ret won px fair fav v'.split())
if R.empty or not (R.st=='NEAR').any(): print("ERROR: no NEAR rows, no verdict"); sys.exit(1)
assert not R.duplicated(['st','band','side','m']).any(),"more than one bet per match per line"
R['when']=pd.to_datetime(R.day).astype('int64'); print(f"dates {R.day.min()}..{R.day.max()}; markets {R.m.nunique()}; tours in NEAR {R[R.st=='NEAR'].tour.value_counts().to_dict()}",flush=True)
def tab(x,**k):
    md=np.median(x.when.values); hh=np.where(x.when.values<md,1,2); l=line(x.v.values,hh); xr=x[~x.ret].v
    top=x.fav.value_counts(normalize=True).head(3).sum()
    return dict(**k,n=l['n'],per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2'],n1=l['n1'],n2=l['n2'],x_ret=xr.mean() if len(xr) else np.nan,won=x.won.mean(),implied=(1/x.px).mean(),players=x.fav.nunique(),top3=top,PASS=bool(l['PASS'] and len(xr)>0 and xr.mean()>=0.15))
out=[]
for (st,b,side),x in R.groupby(['st','band','side']):
    for cut,xx in (('CHALLENGER',x),):
        if len(xx): out.append(tab(xx,st=st,band=b,side=side,cut=cut))
S=pd.DataFrame(out).sort_values('t',ascending=False)
A=S[S.st=='NEAR']; C=S[S.st=='CTRL'].drop(columns='PASS')
print(f"\n== ITEM 224, {len(A)} lines of a possible 4, by t\n",A.round(3).to_string(index=False))
print("\n-- control, other favourites, cannot pass\n",C.round(3).to_string(index=False))
print("\n== NEAR v control, won minus overround-free print, back rows, both bands")
for cut in ('CHALLENGER',):
    x=R[(R.side=='B')&((R.tour==cut)|(cut=='ALL'))]; o=x[x.st=='NEAR']; c=x[x.st=='CTRL']
    if len(o)>1 and len(c)>1:
        print(f"  {cut}: NEAR n {len(o)} err {(o.won-o.fair).mean():+.4f} v CTRL n {len(c)} err {(c.won-c.fair).mean():+.4f}; z {zdiff(o.won-o.fair,c.won-c.fair):.2f}")
print("\ntop NEAR favourites, back rows:",R[(R.st=='NEAR')&(R.side=='B')].fav.value_counts().head(8).to_dict())
W=A[A.PASS]; print(f"\n== SURVIVORS: {len(W)} of {len(A)}\n",W.round(3).to_string(index=False) if len(W) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
