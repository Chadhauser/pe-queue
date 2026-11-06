#!/bin/bash
set -o pipefail
# 499_atp_climb (Finder 2026-11-06, queue item 230, Finder's own, source c, the reverse of jobs/499_ch_atp_drop.sh): ATP runner climbing from the Challenger tour, at the last pre-off print. Read only. The number 499 is reused: 450-499 are all taken.
# TAPE, ENTRY, MATCH, RETIREMENTS as jobs/499_old_fav.sh: T-20 to T-2, worse of the print and the next within 120 s, one tick, <= 50, 2%, £10 risk, to the result, last-traded prints so an upper bound; unique match on both names, tournament start -2 to +21 days; a line must also clear +£0.15 with retirements removed.
# RULE, fixed before any price was read: CLIMB = ATP runner in their first played match of the tournament whose previous match was on the Challenger tour, in a tournament starting 7 to 21 days before this one, and whose opponent's previous match was not on the Challenger tour in the 21 days. Bands on the runner's print <1.5, 1.5-2, 2-3. Back and lay. 6 lines. Control = other ATP runners in their first match, neither runner with a Challenger match in the 21 days, cannot pass.
# Team events and season finals are out as the tournament being bet. Walkovers are not played matches. ATP qualifying is not in the table, so a qualifier's rounds there are not seen. A latest date holding both Challenger and other rows is MIXED, out of both groups. In status() and label(), ATP7 here means the flagged tour, Challenger.
# DIAGNOSTIC, cannot pass: NEAR = the same with a 5 or 6 day gap, shown apart and kept out of control.
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
TEAM=re.compile(r"davis cup|atp cup|united cup|laver cup|olympic|finals",re.I)
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
def status(hist,cur):
    """hist = sorted [(date,is_tour_atp)] of played matches. Reads only the latest date before cur.
    OTHER: no ATP tour match in 21 days. ATP7: latest date all ATP tour, 7-21 days. NEAR: same, 5-6 days. LATE: same, under 5. MIXED: latest date holds ATP tour and other rows."""
    i=bisect.bisect_left(hist,(cur,False))
    if i==0: return 'OTHER'
    d=hist[i-1][0]; gap=(cur-d).days
    if gap>21: return 'OTHER'
    k=[a for x,a in hist[:i] if x==d]
    if not any(k): return 'OTHER'
    if not all(k): return 'MIXED'
    return 'ATP7' if gap>=7 else 'NEAR' if gap>=5 else 'LATE'
def label(me,opp):
    """Group of a first-match runner, from the two statuses. None = in neither group."""
    if opp!='OTHER': return None
    return {'ATP7':'CLIMB','NEAR':'NEAR','OTHER':'CTRL'}.get(me)
# known answers, worked by hand
D=lambda n:dt.date(2025,6,30)-dt.timedelta(days=n); CUR=D(0)
assert status([],CUR)=='OTHER'
assert status([(D(7),True)],CUR)=='ATP7' and status([(D(21),True)],CUR)=='ATP7' and status([(D(22),True)],CUR)=='OTHER'
assert status([(D(6),True)],CUR)=='NEAR' and status([(D(5),True)],CUR)=='NEAR' and status([(D(4),True)],CUR)=='LATE'
assert status([(D(10),False)],CUR)=='OTHER'                          # Challenger or team event last
assert status([(D(14),True),(D(7),False)],CUR)=='OTHER'              # only the latest date counts
assert status([(D(14),False),(D(7),True)],CUR)=='ATP7'
assert status(sorted([(D(10),True),(D(10),False)]),CUR)=='MIXED'
assert status([(D(10),True),(D(0),True),(D(-3),True)],CUR)=='ATP7'   # the current week and later are ignored
assert label('ATP7','OTHER')=='CLIMB' and label('ATP7','ATP7') is None and label('NEAR','OTHER')=='NEAR' and label('OTHER','OTHER')=='CTRL' and label('OTHER','ATP7') is None and label('OTHER','NEAR') is None and label('MIXED','OTHER') is None and label('LATE','OTHER') is None
assert band(1.49)=='<1.5' and band(1.5)=='1.5-2' and band(1.99)=='1.5-2' and band(2.0)=='2-3' and band(2.99)=='2-3' and band(3.0) is None
assert TEAM.search('Davis Cup WG2 R1: BAR vs INA') and TEAM.search('Paris Olympics') and TEAM.search('United Cup') and not TEAM.search('Delray Beach') and TEAM.search('ATP Finals') and TEAM.search('NextGen Finals')
assert entry([100.,1170.,1250.],[2.,3.,4.],1300.)==(3.0,4.0) and entry([1250.],[2.],1300.) is None
assert abs(value('B',(2.0,1.9),True)-8.722)<1e-9 and value('B',(2.0,1.9),False)==-10.0 and abs(value('L',(2.0,2.2),False)-10/1.22*0.98)<1e-9 and value('L',(2.0,2.2),True)==-10.0 and value('B',(51.0,None),True) is None
assert walkover('W/O') and retired('6-1 3-2 RET') and not retired('6-1 6-2')
assert abs(zdiff([0,1]*50,[0,1]*50))<1e-9 and zdiff([0,1]*50,[0,0,0,1]*50)>2
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
rc=psycopg2.connect(creds.pg_railway(),sslmode='require')
TR=pd.read_sql("""SELECT tourney_name,tourney_date,winner_norm,loser_norm,score,tour,round,winner_age::float8 winner_age,loser_age::float8 loser_age FROM tennis_results_2026""",rc); rc.close()
TR['tour']=TR.tour.astype(str).str.upper(); TR['w']=TR.winner_norm.map(fold); TR['l']=TR.loser_norm.map(fold); TR['wo']=TR.score.map(walkover)
TR['tourATP']=TR.tour=='CHALLENGER'
print(f"results {len(TR)}, {TR.tourney_date.min()}..{TR.tourney_date.max()}; tours {TR.tour.value_counts().to_dict()}; ATP rows that are team or finals {((TR.tour=='ATP')&TR.tourney_name.str.contains(TEAM)).sum()}; walkovers {TR.wo.sum()}",flush=True)
P=TR[~TR.wo]; hist=defaultdict(set)
for r in P.itertuples():
    for x in (r.w,r.l): hist[x].add((r.tourney_date,bool(r.tourATP)))
hist={k:sorted(v) for k,v in hist.items()}
first={}   # (tournament,date,player) -> lowest round rank played
for r in P[(P.tour=='ATP')&~P.tourney_name.str.contains(TEAM)].itertuples():
    q=RANK.get(r.round,99)
    for x in (r.w,r.l):
        k=(r.tourney_name,r.tourney_date,x); first[k]=min(first.get(k,99),q)
print("unknown ATP rounds:",sorted(set(P[P.tour=='ATP']['round'])-set(RANK)),flush=True)
ix=defaultdict(list); CENS=Counter(); GAP=Counter()
for r in P.itertuples():
    h=dict(date=r.tourney_date,w=r.w,l=r.l,score=r.score,tour=r.tour,aw=r.winner_age,al=r.loser_age,lw=None,ll=None)
    if r.tour=='ATP' and not TEAM.search(r.tourney_name):
        q=RANK.get(r.round,99); sw=status(hist[r.w],r.tourney_date); sl=status(hist[r.l],r.tourney_date)
        if first[(r.tourney_name,r.tourney_date,r.w)]==q: h['lw']=label(sw,sl); CENS[('first',sw,sl)]+=1
        if first[(r.tourney_name,r.tourney_date,r.l)]==q: h['ll']=label(sl,sw); CENS[('first',sl,sw)]+=1
    ix[frozenset((r.w,r.l))].append(h)
LAB=Counter();
for v in ix.values():
    for h in v:
        for k in ('lw','ll'):
            if h[k]: LAB[h[k]]+=1
print("census, all ATP dates, before any price: first-match runners by group",dict(LAB),"| runner status",dict(Counter(k[1] for k in CENS.elements())),f"| {time.time()-T0:.0f}s",flush=True)
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
                rows.append((lab,b,side,day,mk,who,ret,won,p,fair,v))
    print(f"  {min(c_+800,len(MID))}/{len(MID)}, rows {len(rows)} | {time.time()-T0:.0f}s",flush=True)
con.close(); print("counts:",dict(sorted(SK.items())),flush=True)
Y=pd.DataFrame(yrows,columns=['day','v'])
if len(Y):
    wh=pd.to_datetime(Y.day).astype('int64').values; yl=line(Y.v.values,np.where(wh<np.median(wh),1,2))
    print(f"ENGINE CHECK, item 215 YOUNG <2 back, was n 1901 +0.169 t 1.04 h1 +0.178 h2 +0.160; now n {yl['n']} {yl['per10']:+.3f} t {yl['t']:.2f} h1 {yl['h1']:+.3f} h2 {yl['h2']:+.3f}",flush=True)
R=pd.DataFrame(rows,columns='st band side day m who ret won px fair v'.split())
if R.empty or not (R.st=='CLIMB').any(): print("ERROR: no CLIMB rows, no verdict"); sys.exit(1)
assert not R.duplicated(['st','band','side','m','who']).any(),"more than one bet per runner per line"
assert not R[R.st=='CLIMB'].duplicated(['band','side','m']).any(),"both runners of a match in CLIMB"
R['when']=pd.to_datetime(R.day).astype('int64'); print(f"dates {R.day.min()}..{R.day.max()}; markets {R.m.nunique()}; rows by group, back side {R[R.side=='B'].st.value_counts().to_dict()}",flush=True)
def tab(x,**k):
    md=np.median(x.when.values); hh=np.where(x.when.values<md,1,2); l=line(x.v.values,hh); xr=x[~x.ret].v
    top=x.who.value_counts(normalize=True).head(3).sum()
    return dict(**k,n=l['n'],per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2'],n1=l['n1'],n2=l['n2'],x_ret=xr.mean() if len(xr) else np.nan,won=x.won.mean(),implied=(1/x.px).mean(),players=x.who.nunique(),top3=top,PASS=bool(l['PASS'] and len(xr)>0 and xr.mean()>=0.15))
S=pd.DataFrame([tab(x,st=st,band=b,side=side) for (st,b,side),x in R.groupby(['st','band','side'])]).sort_values('t',ascending=False)
A=S[S.st=='CLIMB']
print(f"\n== ITEM 230, {len(A)} lines of a possible 6, by t\n",A.round(3).to_string(index=False))
print("\n-- NEAR, 5-6 day gap, diagnostic, cannot pass\n",S[S.st=='NEAR'].drop(columns='PASS').round(3).to_string(index=False))
print("\n-- control, cannot pass\n",S[S.st=='CTRL'].drop(columns='PASS').round(3).to_string(index=False))
print("\n== won minus overround-free print v control, back rows")
c=R[(R.side=='B')&(R.st=='CTRL')]
for st in ('CLIMB','NEAR'):
    o=R[(R.side=='B')&(R.st==st)]
    if len(o)>1:
        print(f"  {st} all bands: n {len(o)} err {(o.won-o.fair).mean():+.4f} v CTRL n {len(c)} err {(c.won-c.fair).mean():+.4f}; z {zdiff(o.won-o.fair,c.won-c.fair):.2f}")
        for b in ('<1.5','1.5-2','2-3'):
            ob=o[o.band==b]; cb=c[c.band==b]
            if len(ob)>1: print(f"    {b}: n {len(ob)} err {(ob.won-ob.fair).mean():+.4f} v CTRL n {len(cb)} err {(cb.won-cb.fair).mean():+.4f}; z {zdiff(ob.won-ob.fair,cb.won-cb.fair):.2f}")
print("\ntop CLIMB runners, back rows:",R[(R.st=='CLIMB')&(R.side=='B')].who.value_counts().head(8).to_dict())
W=A[A.PASS]; print(f"\n== SURVIVORS: {len(W)} of {len(A)}\n",W.round(3).to_string(index=False) if len(W) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
