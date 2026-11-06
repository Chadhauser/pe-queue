#!/bin/bash
set -o pipefail
# 499_tennis_upset_next (Finder 2026-11-06, queue item 236, Finder's own, source a, from jobs/499_return_from_ret.sh): tennis runner who has just won as an outsider, at the last pre-off print of the next round. Read only. The number 499 is reused: 450-499 are all taken.
# TAPE, ENTRY, MATCH as jobs/499_return_from_ret.sh: T-20 to T-2, worse of the print and the next within 120 s, one tick, <= 50, 2%, £10 risk, to the result, last-traded prints so an upper bound; unique match on both names, tournament start -2 to +21 days; a line must also clear +£0.15 with retirements removed.
# RULE, fixed before any price of this match type was scored: UPSET = runner whose previous played match in the SAME tournament they won, with their own entry print there >= 2.5; opponent not in that state. Previous round must be strictly earlier by round rank and carry a print on the tape, else no label. Round-robin rows out of both ends, as a loss can precede a next match and rank ties are ambiguous. Team events and season finals out. Bands on this match's print <1.5, 1.5-2, 2-3. Back and lay. ALL, ATP, WTA, CHALLENGER. 24 lines. Control = runner whose previous win there was at a print < 2.0, opponent not UPSET, cannot pass. 2.0 to under 2.5 is neither.
# ENGINE CHECK: rebuilds item 215's YOUNG <2 back line, n 1,901 +0.169 t 1.04 h1 +0.178 h2 +0.160. A mismatch means the port drifted or the data moved, and is printed.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_800_000_000,1_800_000_000))  # this job only
import sys,re,time,datetime as dt,unicodedata,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,line,back_settle,lay_settle
pd.set_option('display.width',240); pd.set_option('display.max_rows',150); pd.set_option('display.max_columns',30)
T0=time.time(); BUDGET=2100
RANK={'1':0,'R128':5,'R64':6,'R32':7,'R16':8,'QF':9,'SF':10,'BR':10.5,'F':11,'RR':4,'Quarterfinals':9}
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
def band(p): return '<1.5' if p<1.5 else '1.5-2' if p<2 else '2-3' if p<3 else None
def young(ax,bx,gap=6.0):
    if ax is None or bx is None or ax!=ax or bx!=bx: return None
    return 'a' if bx-ax>=gap else 'b' if ax-bx>=gap else None
def zdiff(a,b):
    a=np.asarray(a,float); b=np.asarray(b,float)
    return (a.mean()-b.mean())/np.sqrt(a.var(ddof=1)/len(a)+b.var(ddof=1)/len(b))
def prev_rank(ranks,cur):
    """ranks: this player's played round ranks in the tournament. Latest strictly earlier, None if none or a tie for it or round-robin is involved."""
    if cur==RANK['RR'] or cur==99: return None
    e=[r for r in ranks if r<cur]
    if not e: return None
    m=max(e)
    if m==RANK['RR'] or e.count(m)>1 or m==99: return None
    return m
def prior_state(pw):
    """pw: this player's print in the previous match, which they won; None if unknown."""
    if pw is None: return None
    return 'UP' if pw>=2.5 else 'FAV' if pw<2.0 else None
def label(me,opp):
    if opp=='UP': return None
    return {'UP':'UPSET','FAV':'CTRL'}.get(me)
# known answers, worked by hand
assert prev_rank([7,8],9)==8 and prev_rank([8],8) is None and prev_rank([],9) is None and prev_rank([4],9) is None and prev_rank([7],4) is None and prev_rank([8,8],9) is None and prev_rank([7,9],8)==7
assert prior_state(None) is None and prior_state(2.5)=='UP' and prior_state(2.49) is None and prior_state(2.0) is None and prior_state(1.99)=='FAV'
assert label('UP','FAV')=='UPSET' and label('UP',None)=='UPSET' and label('UP','UP') is None and label('FAV','FAV')=='CTRL' and label('FAV','UP') is None and label(None,'FAV') is None
assert band(1.49)=='<1.5' and band(1.5)=='1.5-2' and band(2.0)=='2-3' and band(3.0) is None
assert entry([100.,1170.,1250.],[2.,3.,4.],1300.)==(3.0,4.0) and entry([1250.],[2.],1300.) is None
assert abs(value('B',(2.0,1.9),True)-8.722)<1e-9 and value('B',(2.0,1.9),False)==-10.0 and abs(value('L',(2.0,2.2),False)-10/1.22*0.98)<1e-9 and value('L',(2.0,2.2),True)==-10.0 and value('B',(51.0,None),True) is None
assert TEAM.search('Davis Cup WG2 R1: BAR vs INA') and TEAM.search('WTA Finals') and TEAM.search('BJK Cup Playoffs: JPN vs UKR') and not TEAM.search('Wimbledon')
assert walkover('W/O') and retired('6-1 3-2 RET') and not retired('6-1 6-2')
assert abs(zdiff([0,1]*50,[0,1]*50))<1e-9 and zdiff([0,1]*50,[0,0,0,1]*50)>2
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
rc=psycopg2.connect(creds.pg_railway(),sslmode='require')
TR=pd.read_sql("""SELECT tourney_name,tourney_date,winner_norm,loser_norm,score,tour,round,winner_age::float8 winner_age,loser_age::float8 loser_age FROM tennis_results_2026""",rc); rc.close()
TR['tour']=TR.tour.astype(str).str.upper(); TR['w']=TR.winner_norm.map(fold); TR['l']=TR.loser_norm.map(fold); TR['wo']=TR.score.map(walkover)
print(f"results {len(TR)}, {TR.tourney_date.min()}..{TR.tourney_date.max()}; tours {TR.tour.value_counts().to_dict()}; walkovers {TR.wo.sum()}",flush=True)
P=TR[~TR.wo]; ix=defaultdict(list); played=defaultdict(list); wonat=set()
for r in P.itertuples():
    q=RANK.get(r.round,99); key=(r.tour,r.tourney_name,r.tourney_date)
    if not TEAM.search(r.tourney_name):
        played[key+(r.w,)].append(q); played[key+(r.l,)].append(q); wonat.add(key+(r.w,q))
    ix[frozenset((r.w,r.l))].append(dict(key=key,team=bool(TEAM.search(r.tourney_name)),q=q,date=r.tourney_date,w=r.w,l=r.l,score=r.score,tour=r.tour,aw=r.winner_age,al=r.loser_age))
print("unknown rounds:",sorted(set(P['round'])-set(RANK)),f"| {time.time()-T0:.0f}s",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
cur.execute("SELECT DISTINCT market_id FROM bf_hist_other WHERE sport='Tennis' AND market_type='MATCH_ODDS'")
MID=sorted(r[0] for r in cur.fetchall() if r[0].startswith('MATCH_ODDS|') and '/' not in r[0]); print(f"singles markets {len(MID)} | {time.time()-T0:.0f}s",flush=True)
SK=Counter(); M=[]; seen=set(); yrows=[]; PR={}
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
        SK['scored']+=1
        y=young(h['aw'],h['al'])
        if y:   # engine check, item 215 YOUNG <2 back
            k=w if y=='a' else l; pk=ew[0] if k==w else el[0]
            if pk<2:
                v=value('B',ew if k==w else el,k==w)
                if v is not None: yrows.append((day,v))
        if h['team']: continue
        PR[h['key']+(w,h['q'])]=ew[0]; PR[h['key']+(l,h['q'])]=el[0]
        M.append((h,day,mk,ew,el))
    print(f"  {min(c_+800,len(MID))}/{len(MID)}, scored {len(M)} | {time.time()-T0:.0f}s",flush=True)
con.close(); print("counts:",dict(sorted(SK.items())),flush=True)
def prior(h,x):
    """Print of player x in their previous match of this tournament, None unless it was a win with a print."""
    q=prev_rank(played[h['key']+(x,)],h['q'])
    if q is None or h['key']+(x,q) not in wonat: return None
    return PR.get(h['key']+(x,q))
rows=[]; LAB=Counter()
for h,day,mk,ew,el in M:
    w,l=h['w'],h['l']; sw=prior_state(prior(h,w)); sl=prior_state(prior(h,l)); ret=retired(h['score']); pw,pl=ew[0],el[0]
    for who,lab,e,p,po,won in ((w,label(sw,sl),ew,pw,pl,True),(l,label(sl,sw),el,pl,pw,False)):
        if not lab: continue
        LAB[(h['tour'],lab)]+=1
        b=band(p)
        if not b: SK[f'{lab} outside the bands']+=1; continue
        fair=(1/p)/(1/p+1/po)
        for side in 'BL':
            v=value(side,e,won)
            if v is None: SK['no bet at the ladder ends']+=1; continue
            rows.append((lab,b,side,h['tour'],day,mk,who,ret,won,p,fair,v))
print("labels:",{f"{k[0]} {k[1]}":v for k,v in sorted(LAB.items())},{k:v for k,v in SK.items() if 'outside' in k},flush=True)
Y=pd.DataFrame(yrows,columns=['day','v'])
if len(Y):
    wh=pd.to_datetime(Y.day).astype('int64').values; yl=line(Y.v.values,np.where(wh<np.median(wh),1,2))
    print(f"ENGINE CHECK, item 215 YOUNG <2 back, was n 1901 +0.169 t 1.04 h1 +0.178 h2 +0.160; now n {yl['n']} {yl['per10']:+.3f} t {yl['t']:.2f} h1 {yl['h1']:+.3f} h2 {yl['h2']:+.3f}",flush=True)
R=pd.DataFrame(rows,columns='st band side tour day m who ret won px fair v'.split())
if R.empty or not (R.st=='UPSET').any(): print("ERROR: no UPSET rows, no verdict"); sys.exit(1)
assert not R.duplicated(['st','band','side','m','who']).any(),"more than one bet per runner per line"
assert not R[R.st=='UPSET'].duplicated(['band','side','m']).any(),"both runners of a match in UPSET"
R['when']=pd.to_datetime(R.day).astype('int64'); print(f"dates {R.day.min()}..{R.day.max()}; markets {R.m.nunique()}; back rows {R[R.side=='B'].groupby(['st','tour']).size().to_dict()}",flush=True)
def tab(x,**k):
    md=np.median(x.when.values); hh=np.where(x.when.values<md,1,2); l=line(x.v.values,hh); xr=x[~x.ret].v
    return dict(**k,n=l['n'],per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2'],n1=l['n1'],n2=l['n2'],x_ret=xr.mean() if len(xr) else np.nan,won=x.won.mean(),implied=(1/x.px).mean(),players=x.who.nunique(),PASS=bool(l['PASS'] and len(xr)>0 and xr.mean()>=0.15))
out=[]
for (st,b,side),x in R.groupby(['st','band','side']):
    for cut,xx in (('ALL',x),('ATP',x[x.tour=='ATP']),('WTA',x[x.tour=='WTA']),('CHALLENGER',x[x.tour=='CHALLENGER'])):
        if len(xx): out.append(tab(xx,st=st,band=b,side=side,cut=cut))
S=pd.DataFrame(out).sort_values('t',ascending=False); A=S[S.st=='UPSET']
print(f"\n== ITEM 236, {len(A)} lines of a possible 24, by t\n",A.round(3).to_string(index=False))
print("\n-- control, ALL, cannot pass\n",S[(S.st=='CTRL')&(S['cut']=='ALL')].drop(columns='PASS').round(3).to_string(index=False))
print("\n== won minus overround-free print v control, back rows")
for cut in ('ALL','ATP','WTA','CHALLENGER'):
    x=R[(R.side=='B')&((R.tour==cut)|(cut=='ALL'))]; o=x[x.st=='UPSET']; c=x[x.st=='CTRL']
    if len(o)>1 and len(c)>1: print(f"  {cut}: UPSET n {len(o)} err {(o.won-o.fair).mean():+.4f} v CTRL n {len(c)} err {(c.won-c.fair).mean():+.4f}; z {zdiff(o.won-o.fair,c.won-c.fair):.2f}")
for b in ('<1.5','1.5-2','2-3'):
    x=R[(R.side=='B')&(R.band==b)]; o=x[x.st=='UPSET']; c=x[x.st=='CTRL']
    if len(o)>1 and len(c)>1: print(f"  band {b}: UPSET n {len(o)} err {(o.won-o.fair).mean():+.4f} v CTRL n {len(c)} err {(c.won-c.fair).mean():+.4f}; z {zdiff(o.won-o.fair,c.won-c.fair):.2f}")
W=A[A.PASS]; print(f"\n== SURVIVORS: {len(W)} of {len(A)}\n",W.round(3).to_string(index=False) if len(W) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
