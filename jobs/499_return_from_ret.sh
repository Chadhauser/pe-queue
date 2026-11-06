#!/bin/bash
set -o pipefail
# 499_return_from_ret (Finder 2026-11-06, queue item 232, Finder's own, source d, from jobs/499_ch_atp_drop.sh): tennis runner back after retiring hurt from their previous match, at the last pre-off print. Read only. The number 499 is reused: 450-499 are all taken.
# TAPE, ENTRY, MATCH as jobs/499_old_fav.sh: T-20 to T-2, worse of the print and the next within 120 s, one tick, <= 50, 2%, £10 risk, to the result, last-traded prints so an upper bound; unique match on both names, tournament start -2 to +21 days; a line must also clear +£0.15 with retirements removed.
# RULE, fixed before any price was read: BACK_HURT = runner in their first played match of a tournament whose previous match, in a tournament starting 5 to 30 days before, they lost with RET in the score; opponent not in the same state. Bands on the runner's print <1.5, 1.5-2, 2-3. Back and lay. ALL, ATP, WTA, CHALLENGER. 24 lines. Control = other runners in their first match, previous match 5 to 30 days before and not lost by retirement, opponent not BACK_HURT, cannot pass.
# Team events and season finals are out as the tournament being bet, and count in a player's history. Walkovers are not played matches, so a withdrawal between the two matches is not seen. A previous match under 5 days before is out of both groups, as dates are coarse. Absences over 30 days are out of both, as item 210 and others read long lay-offs apart.
# RETIREMENTS AGAIN IN THIS MATCH are the point of the test on the lay side, so x_ret shows the line without them and the bar still asks +£0.15 there.
# ENGINE CHECK: rebuilds item 215's YOUNG <2 back line, n 1,901 +0.169 t 1.04 h1 +0.178 h2 +0.160. A mismatch means the port drifted or the data moved, and is printed.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_800_000_000,1_800_000_000))  # this job only
import sys,re,time,bisect,datetime as dt,unicodedata,warnings,psycopg2,pandas as pd,numpy as np
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
def hurt(score): return 'RET' in str(score).upper()
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
def status(hist,cur):
    """hist = sorted [(date,lost_by_retirement)]. Reads only the latest date before cur. HURT, FIT, LATE (under 5 days), NONE (no match in 30 days)."""
    i=bisect.bisect_left(hist,(cur,False))
    if i==0: return 'NONE'
    d=hist[i-1][0]; gap=(cur-d).days
    if gap>30: return 'NONE'
    if gap<5: return 'LATE'
    return 'HURT' if any(a for x,a in hist[:i] if x==d) else 'FIT'
def label(me,opp):
    if opp=='HURT': return None
    return {'HURT':'BACK_HURT','FIT':'CTRL'}.get(me)
# known answers, worked by hand
D=lambda n:dt.date(2025,6,30)-dt.timedelta(days=n); CUR=D(0)
assert status([],CUR)=='NONE' and status([(D(31),True)],CUR)=='NONE' and status([(D(30),True)],CUR)=='HURT' and status([(D(5),True)],CUR)=='HURT' and status([(D(4),True)],CUR)=='LATE'
assert status([(D(10),False)],CUR)=='FIT' and status([(D(14),True),(D(7),False)],CUR)=='FIT' and status([(D(14),False),(D(7),True)],CUR)=='HURT'
assert status(sorted([(D(10),False),(D(10),True)]),CUR)=='HURT'             # won early that week, then retired in a later round
assert status([(D(10),False),(D(0),True),(D(-3),True)],CUR)=='FIT'          # this week and later are ignored
assert label('HURT','FIT')=='BACK_HURT' and label('HURT','NONE')=='BACK_HURT' and label('HURT','HURT') is None and label('FIT','FIT')=='CTRL' and label('FIT','HURT') is None and label('NONE','FIT') is None and label('LATE','FIT') is None
assert hurt('6-1 3-2 RET') and hurt('6-1 3-2 Ret') and not hurt('6-1 6-2') and not hurt('W/O') and not hurt('6-1 ABD')
assert band(1.49)=='<1.5' and band(1.5)=='1.5-2' and band(2.0)=='2-3' and band(3.0) is None
assert TEAM.search('Davis Cup WG2 R1: BAR vs INA') and TEAM.search('WTA Finals') and TEAM.search('Billie Jean King Cup') and TEAM.search('BJK Cup G2 RR: ISR vs BIH') and TEAM.search('BJK Cup Playoffs: JPN vs UKR') and not TEAM.search('Wimbledon')
assert entry([100.,1170.,1250.],[2.,3.,4.],1300.)==(3.0,4.0) and entry([1250.],[2.],1300.) is None
assert abs(value('B',(2.0,1.9),True)-8.722)<1e-9 and value('B',(2.0,1.9),False)==-10.0 and abs(value('L',(2.0,2.2),False)-10/1.22*0.98)<1e-9 and value('L',(2.0,2.2),True)==-10.0 and value('B',(51.0,None),True) is None
assert walkover('W/O') and retired('6-1 3-2 RET') and not retired('6-1 6-2')
assert abs(zdiff([0,1]*50,[0,1]*50))<1e-9 and zdiff([0,1]*50,[0,0,0,1]*50)>2
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
rc=psycopg2.connect(creds.pg_railway(),sslmode='require')
TR=pd.read_sql("""SELECT tourney_name,tourney_date,winner_norm,loser_norm,score,tour,round,winner_age::float8 winner_age,loser_age::float8 loser_age FROM tennis_results_2026""",rc); rc.close()
TR['tour']=TR.tour.astype(str).str.upper(); TR['w']=TR.winner_norm.map(fold); TR['l']=TR.loser_norm.map(fold); TR['wo']=TR.score.map(walkover); TR['hurt']=TR.score.map(hurt)
print(f"results {len(TR)}, {TR.tourney_date.min()}..{TR.tourney_date.max()}; tours {TR.tour.value_counts().to_dict()}; RET rows by tour {TR[TR.hurt].tour.value_counts().to_dict()}; walkovers {TR.wo.sum()}",flush=True)
P=TR[~TR.wo]; hist=defaultdict(set)
for r in P.itertuples():
    hist[r.w].add((r.tourney_date,False)); hist[r.l].add((r.tourney_date,bool(r.hurt)))
hist={k:sorted(v) for k,v in hist.items()}
B=P[~P.tourney_name.str.contains(TEAM)]; first={}
for r in B.itertuples():
    q=RANK.get(r.round,99)
    for x in (r.w,r.l):
        k=(r.tour,r.tourney_name,r.tourney_date,x); first[k]=min(first.get(k,99),q)
print("unknown rounds in bet tournaments:",sorted(set(B['round'])-set(RANK)),flush=True)
ix=defaultdict(list); LAB=Counter()
for r in P.itertuples():
    h=dict(date=r.tourney_date,w=r.w,l=r.l,score=r.score,tour=r.tour,aw=r.winner_age,al=r.loser_age,lw=None,ll=None)
    if not TEAM.search(r.tourney_name):
        q=RANK.get(r.round,99); sw=status(hist[r.w],r.tourney_date); sl=status(hist[r.l],r.tourney_date)
        if first[(r.tour,r.tourney_name,r.tourney_date,r.w)]==q: h['lw']=label(sw,sl); LAB[(r.tour,h['lw'])]+=1
        if first[(r.tour,r.tourney_name,r.tourney_date,r.l)]==q: h['ll']=label(sl,sw); LAB[(r.tour,h['ll'])]+=1
    ix[frozenset((r.w,r.l))].append(h)
print("census, all dates, before any price:",{f"{k[0]} {k[1]}":v for k,v in sorted(LAB.items(),key=str) if k[1]},f"| {time.time()-T0:.0f}s",flush=True)
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
        SK['scored']+=1; ret=retired(h['score']); pw,pl=ew[0],el[0]
        y=young(h['aw'],h['al'])
        if y:   # engine check, item 215 YOUNG <2 back
            k=w if y=='a' else l; p=pw if k==w else pl
            if p<2:
                v=value('B',ew if k==w else el,k==w)
                if v is not None: yrows.append((day,v))
        for who,lab,e,p,po,won in ((w,h['lw'],ew,pw,pl,True),(l,h['ll'],el,pl,pw,False)):
            if not lab: continue
            b=band(p)
            if not b: SK[f'{lab} outside the bands']+=1; continue
            SK[f'in band {lab}']+=1; fair=(1/p)/(1/p+1/po)
            for side in 'BL':
                v=value(side,e,won)
                if v is None: SK['no bet at the ladder ends']+=1; continue
                rows.append((lab,b,side,h['tour'],day,mk,who,ret,won,p,fair,v))
    print(f"  {min(c_+800,len(MID))}/{len(MID)}, rows {len(rows)} | {time.time()-T0:.0f}s",flush=True)
con.close(); print("counts:",dict(sorted(SK.items())),flush=True)
Y=pd.DataFrame(yrows,columns=['day','v'])
if len(Y):
    wh=pd.to_datetime(Y.day).astype('int64').values; yl=line(Y.v.values,np.where(wh<np.median(wh),1,2))
    print(f"ENGINE CHECK, item 215 YOUNG <2 back, was n 1901 +0.169 t 1.04 h1 +0.178 h2 +0.160; now n {yl['n']} {yl['per10']:+.3f} t {yl['t']:.2f} h1 {yl['h1']:+.3f} h2 {yl['h2']:+.3f}",flush=True)
R=pd.DataFrame(rows,columns='st band side tour day m who ret won px fair v'.split())
if R.empty or not (R.st=='BACK_HURT').any(): print("ERROR: no BACK_HURT rows, no verdict"); sys.exit(1)
assert not R.duplicated(['st','band','side','m','who']).any(),"more than one bet per runner per line"
assert not R[R.st=='BACK_HURT'].duplicated(['band','side','m']).any(),"both runners of a match in BACK_HURT"
R['when']=pd.to_datetime(R.day).astype('int64'); print(f"dates {R.day.min()}..{R.day.max()}; markets {R.m.nunique()}; back rows {R[R.side=='B'].groupby(['st','tour']).size().to_dict()}",flush=True)
def tab(x,**k):
    md=np.median(x.when.values); hh=np.where(x.when.values<md,1,2); l=line(x.v.values,hh); xr=x[~x.ret].v
    top=x.who.value_counts(normalize=True).head(3).sum()
    return dict(**k,n=l['n'],per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2'],n1=l['n1'],n2=l['n2'],x_ret=xr.mean() if len(xr) else np.nan,won=x.won.mean(),implied=(1/x.px).mean(),ret=x.ret.mean(),players=x.who.nunique(),top3=top,PASS=bool(l['PASS'] and len(xr)>0 and xr.mean()>=0.15))
out=[]
for (st,b,side),x in R.groupby(['st','band','side']):
    for cut,xx in (('ALL',x),('ATP',x[x.tour=='ATP']),('WTA',x[x.tour=='WTA']),('CHALLENGER',x[x.tour=='CHALLENGER'])):
        if len(xx): out.append(tab(xx,st=st,band=b,side=side,cut=cut))
S=pd.DataFrame(out).sort_values('t',ascending=False); A=S[S.st=='BACK_HURT']
print(f"\n== ITEM 232, {len(A)} lines of a possible 24, by t\n",A.round(3).to_string(index=False))
print("\n-- control, ALL, cannot pass\n",S[(S.st=='CTRL')&(S['cut']=='ALL')].drop(columns='PASS').round(3).to_string(index=False))
print("\n== won minus overround-free print v control, back rows")
for cut in ('ALL','ATP','WTA','CHALLENGER'):
    x=R[(R.side=='B')&((R.tour==cut)|(cut=='ALL'))]; o=x[x.st=='BACK_HURT']; c=x[x.st=='CTRL']
    if len(o)>1 and len(c)>1:
        print(f"  {cut}: BACK_HURT n {len(o)} err {(o.won-o.fair).mean():+.4f} ret {o.ret.mean():.3f} v CTRL n {len(c)} err {(c.won-c.fair).mean():+.4f} ret {c.ret.mean():.3f}; z {zdiff(o.won-o.fair,c.won-c.fair):.2f}")
W=A[A.PASS]; print(f"\n== SURVIVORS: {len(W)} of {len(A)}\n",W.round(3).to_string(index=False) if len(W) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
