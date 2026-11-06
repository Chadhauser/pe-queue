#!/bin/bash
set -o pipefail
# 499_tennis_h2h_hour (Finder 2026-11-06, queue items 321, 322, Finder's own, sources c, d, from jobs/499_tennis_load.sh): tennis head-to-head sweep priced over 2.0, and tennis by scheduled UTC hour, at the last pre-off print. Rules pushed in the queue before any price. Read only. Prints only, so a pass is an upper bound and earns a real-touch check.
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
def young(ax,bx,gap=6.0):
    if ax is None or bx is None or ax!=ax or bx!=bx: return None
    return 'a' if bx-ax>=gap else 'b' if ax-bx>=gap else None
def band321(p): return '2-3' if 2<=p<3 else '3-6' if 3<=p<6 else None
def sweep_state(meets,tour,date):
    """meets: (date,round rank,winner), played, walkovers already out. Last two of the same tour strictly before date. ('SWEEP',x) if x won both, ('SPLIT',None) if each won one, None if under two."""
    m=sorted([z for z in meets if z[3]==tour and z[0]<date],key=lambda z:(z[0],z[1]))
    if len(m)<2: return None
    a,b=m[-2][2],m[-1][2]
    return ('SWEEP',a) if a==b else ('SPLIT',None)
def hour_block(mt):
    h=int(mt//3600)%24
    return '00-05' if h<6 else '06-11' if h<12 else '12-17' if h<18 else '18-23'
def role(pa,pb):
    """Favourite of two entry prints: 'a', 'b', or None on a tie."""
    return 'a' if pa<pb else 'b' if pb<pa else None
# known answers, worked by hand
D=dt.date
mm=[(D(2024,1,1),5,'x','ATP'),(D(2025,1,1),5,'y','ATP'),(D(2025,6,1),7,'y','ATP'),(D(2025,7,1),7,'x','CHALLENGER'),(D(2026,1,1),7,'x','ATP')]
assert sweep_state(mm,'ATP',D(2025,12,1))==('SWEEP','y')          # y won the last two ATP before the date; the Challenger is ignored
assert sweep_state(mm,'ATP',D(2026,2,1))==('SPLIT',None)          # y then x
assert sweep_state(mm,'ATP',D(2026,1,1))==('SWEEP','y')           # strictly before: this tournament's start date is out
assert sweep_state(mm,'ATP',D(2025,1,1)) is None                  # one meeting only
assert sweep_state(mm,'CHALLENGER',D(2026,2,1)) is None
assert sweep_state([(D(2025,1,1),4,'x','ATP'),(D(2025,1,1),11,'y','ATP')],'ATP',D(2025,3,1))==('SPLIT',None)   # same week, round order decides
assert band321(1.99) is None and band321(2.0)=='2-3' and band321(2.99)=='2-3' and band321(3.0)=='3-6' and band321(5.99)=='3-6' and band321(6.0) is None
assert hour_block(1700000000.)=='18-23'    # 2023-11-14 22:13:20 UTC
assert hour_block(1699920000.)=='00-05' and hour_block(1699920000.+5*3600+3599)=='00-05' and hour_block(1699920000.+6*3600)=='06-11' and hour_block(1699920000.+12*3600)=='12-17' and hour_block(1699920000.+18*3600)=='18-23'   # 2023-11-14 00:00 UTC
assert role(1.5,2.5)=='a' and role(2.5,1.5)=='b' and role(2.0,2.0) is None
assert entry([100.,1170.,1250.],[2.,3.,4.],1300.)==(3.0,4.0) and entry([1250.],[2.],1300.) is None
assert abs(value('B',(2.0,1.9),True)-8.722)<1e-9 and value('B',(2.0,1.9),False)==-10.0 and abs(value('L',(2.0,2.2),False)-10/1.22*0.98)<1e-9 and value('L',(2.0,2.2),True)==-10.0 and value('B',(51.0,None),True) is None
assert TEAM.search('WTA Finals') and not TEAM.search('Wimbledon') and walkover('W/O') and retired('6-1 3-2 RET') and not retired('6-1 6-2')
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
rc=psycopg2.connect(creds.pg_railway(),sslmode='require')
TR=pd.read_sql("""SELECT tourney_name,tourney_date,tourney_level,best_of,surface,minutes::float8 minutes,winner_norm,loser_norm,score,tour,round,winner_age::float8 winner_age,loser_age::float8 loser_age FROM tennis_results_2026""",rc); rc.close()
TR['tour']=TR.tour.astype(str).str.upper(); TR['w']=TR.winner_norm.map(fold); TR['l']=TR.loser_norm.map(fold); TR['wo']=TR.score.map(walkover)
print(f"results {len(TR)}, {TR.tourney_date.min()}..{TR.tourney_date.max()}; tours {TR.tour.value_counts().to_dict()}; walkovers {TR.wo.sum()}",flush=True)
P=TR[~TR.wo]; ix=defaultdict(list); meets=defaultdict(list)
for r in P.itertuples():
    q=RANK.get(r.round,99); key=(r.tour,r.tourney_name,r.tourney_date); tm=bool(TEAM.search(r.tourney_name)); pr=frozenset((r.w,r.l))
    meets[pr].append((r.tourney_date,q,r.w,r.tour))
    ix[pr].append(dict(key=key,team=tm,q=q,date=r.tourney_date,w=r.w,l=r.l,score=r.score,tour=r.tour,aw=r.winner_age,al=r.loser_age))
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
cur.execute("SELECT data_type FROM information_schema.columns WHERE table_name='bf_hist_other' AND column_name='market_time'"); print("market_time type:",cur.fetchone()[0],flush=True)
cur.execute("SELECT DISTINCT market_id FROM bf_hist_other WHERE sport='Tennis' AND market_type='MATCH_ODDS'")
MID=sorted(r[0] for r in cur.fetchall() if r[0].startswith('MATCH_ODDS|') and '/' not in r[0]); print(f"singles markets {len(MID)} | {time.time()-T0:.0f}s",flush=True)
SK=Counter(); M=[]; seen=set(); yrows=[]
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
        if y:
            k=w if y=='a' else l; pk=ew[0] if k==w else el[0]
            if pk<2:
                v=value('B',ew if k==w else el,k==w)
                if v is not None: yrows.append((day,v))
        if h['team']: continue
        M.append((h,day,mk,ew,el,mt))
    print(f"  {min(c_+800,len(MID))}/{len(MID)}, scored {len(M)} | {time.time()-T0:.0f}s",flush=True)
con.close(); print("counts:",dict(sorted(SK.items())),flush=True)
LB=Counter(); rows=[]
for h,day,mk,ew,el,mt in M:
    w,l=h['w'],h['l']; ret=retired(h['score'])
    # 321
    s=sweep_state(meets[frozenset((w,l))],h['tour'],h['date'])
    if s:
        LB[(321,s[0])]+=1
        who=[s[1]] if s[0]=='SWEEP' else [w,l]
        for x in who:
            won=x==w; e=ew if won else el; b_=band321(e[0])
            if not b_: continue
            for side in 'BL':
                v=value(side,e,won)
                if v is not None: rows.append((321,s[0],b_,side,h['tour'],day,mk,x,ret,won,e[0],v))
    # 322
    hb=hour_block(mt); f=role(ew[0],el[0])
    if f:
        LB[(322,hb)]+=1
        fav,dog=(w,l) if f=='a' else (l,w)
        for x,rl in ((fav,'FAV'),(dog,'DOG')):
            won=x==w; e=ew if won else el
            for side in 'BL':
                v=value(side,e,won)
                if v is not None: rows.append((322,hb,rl,side,h['tour'],day,mk,x,ret,won,e[0],v))
print("labels:",{f"{k[0]} {k[1]}":v for k,v in sorted(LB.items())},flush=True)
Y=pd.DataFrame(yrows,columns=['day','v'])
if len(Y):
    wh=pd.to_datetime(Y.day).astype('int64').values; yl=line(Y.v.values,np.where(wh<np.median(wh),1,2))
    print(f"ENGINE CHECK, item 215 YOUNG <2 back, was n 1901 +0.169 t 1.04 h1 +0.178 h2 +0.160; now n {yl['n']} {yl['per10']:+.3f} t {yl['t']:.2f} h1 {yl['h1']:+.3f} h2 {yl['h2']:+.3f}",flush=True)
R=pd.DataFrame(rows,columns='it st band side tour day m who ret won px v'.split())
if R.empty: print("ERROR: no rows, no verdict"); sys.exit(1)
assert not R.duplicated(['it','st','band','side','m','who']).any(),"more than one bet per runner per line"
R['when']=pd.to_datetime(R.day).astype('int64'); print(f"dates {R.day.min()}..{R.day.max()}; markets {R.m.nunique()}; tours {R[R['it']==322].drop_duplicates('m').tour.value_counts().to_dict()}",flush=True)
def tab(x,ret_bar,**k):
    md=np.median(x.when.values); hh=np.where(x.when.values<md,1,2); l=line(x.v.values,hh); xr=x[~x.ret].v; vv=x.v.values
    ok=bool(l['PASS']) and (not ret_bar or (len(xr)>0 and xr.mean()>=0.15))
    return dict(**k,n=l['n'],per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2'],n1=l['n1'],n2=l['n2'],x_ret=xr.mean() if len(xr) else np.nan,no_top=np.delete(vv,vv.argmax()).mean() if len(vv)>1 else np.nan,won=x.won.mean(),implied=(1/x.px).mean(),games=x.m.nunique(),PASS=ok)
tot_lines=tot_pass=0
# 321
out=[]
for (st,b,side),x in R[R['it']==321].groupby(['st','band','side']):
    for cut,xx in (('ALL',x),('ATP',x[x.tour=='ATP']),('WTA',x[x.tour=='WTA']),('CHALLENGER',x[x.tour=='CHALLENGER'])):
        if len(xx)>1: out.append(tab(xx,True,st=st,band=b,side=side,cut=cut))
S=pd.DataFrame(out).sort_values('t',ascending=False); A=S[S.st=='SWEEP']; tot_lines+=len(A)
print(f"\n== ITEM 321, SWEEP: {len(A)} lines\n",A.round(3).to_string(index=False))
print("\n-- control SPLIT, ALL, cannot pass\n",S[(S.st=='SPLIT')&(S['cut']=='ALL')].drop(columns='PASS').round(3).to_string(index=False))
W=A[A.PASS]; tot_pass+=len(W); print(f"\n== SURVIVORS 321: {len(W)} of {len(A)}\n",W.round(3).to_string(index=False) if len(W) else "none",flush=True)
# 322
out=[]
for (st,b,side),x in R[R['it']==322].groupby(['st','band','side']):
    for cut,xx in (('ALL',x),('CHALLENGER',x[x.tour=='CHALLENGER'])):
        if len(xx)>1: out.append(tab(xx,False,hours=st,role=b,side=side,cut=cut))
A=pd.DataFrame(out).sort_values('t',ascending=False); tot_lines+=len(A)
print(f"\n== ITEM 322: {len(A)} lines\n",A.round(3).to_string(index=False))
W=A[A.PASS]; tot_pass+=len(W); print(f"\n== SURVIVORS 322: {len(W)} of {len(A)}\n",W.round(3).to_string(index=False) if len(W) else "none",flush=True)
print(f"\nALL ITEMS: {tot_pass} of {tot_lines} scored lines pass; total {time.time()-T0:.0f}s")
PY
