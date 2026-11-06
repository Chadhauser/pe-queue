#!/bin/bash
set -o pipefail
# 499_tennis_load (Finder 2026-11-06, queue items 304-308, Finder's own, sources c, d, from jobs/499_tennis_upset_next.sh): fatigue, tournament load, first match after a title, surface switch, best of five, at the last pre-off print. Rules pushed in the queue (7a00dd3) before any price. Read only. Prints only, so a pass is an upper bound and earns a real-touch check.
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
def prev_rank(ranks,cur):
    """Latest strictly earlier round, None if none, a tie, or round-robin is involved."""
    if cur==RANK['RR'] or cur==99: return None
    e=[r for r in ranks if r<cur]
    if not e: return None
    m=max(e)
    if m==RANK['RR'] or e.count(m)>1 or m==99: return None
    return m
def good_min(m): return m is not None and m==m and 20<=m<=400
def gap_state(a,b,big,even):
    """a, b minutes. Returns who is heavier by big or more ('a','b'), 'even' within even, else None."""
    d=a-b
    return 'a' if d>=big else 'b' if -d>=big else 'even' if abs(d)<=even else None
def is_first(ranks,cur): return cur!=99 and cur!=RANK['RR'] and RANK['RR'] not in ranks and 99 not in ranks and min(ranks)==cur and ranks.count(cur)==1
def latest_key(evs,d,key,tour,lo,hi,same_tour):
    """evs: (start date, key) sorted by date; key[0] is the tour. Key of the most recent other tournament starting lo to hi days before d, else None."""
    best=None
    for d0,k in evs:
        if k==key or (same_tour and k[0]!=tour): continue
        if lo<=(d-d0).days<=hi: best=k
    return best
def hours(a,b): return (a-b)/3600.0
# known answers, worked by hand
assert prev_rank([7,8],9)==8 and prev_rank([8],8) is None and prev_rank([],9) is None and prev_rank([4],9) is None and prev_rank([8,8],9) is None and prev_rank([7,9],8)==7
assert gap_state(150,100,45,15)=='a' and gap_state(100,145,45,15)=='b' and gap_state(100,144,45,15) is None and gap_state(100,115,45,15)=='even' and gap_state(115,100,45,15)=='even' and gap_state(116,100,45,15) is None
assert gap_state(300,210,90,20)=='a' and gap_state(300,211,90,20) is None
assert good_min(20) and good_min(400) and not good_min(19) and not good_min(401) and not good_min(None) and not good_min(float('nan'))
assert is_first([7,8],7) and not is_first([7,8],8) and not is_first([4,7],7) and not is_first([7,7],7)
D=dt.date; ev=[(D(2025,1,1),('ATP','A')),(D(2025,1,8),('ATP','B')),(D(2025,1,8),('CHALLENGER','C'))]
assert latest_key(ev,D(2025,1,15),('ATP','Z'),'ATP',5,16,True)==('ATP','B') and latest_key(ev,D(2025,1,15),('ATP','Z'),'ATP',5,16,False)==('CHALLENGER','C') and latest_key(ev,D(2025,1,10),('ATP','Z'),'ATP',5,16,True)==('ATP','A') and latest_key(ev,D(2025,3,1),('ATP','Z'),'ATP',5,16,True) is None and latest_key(ev,D(2025,1,15),('ATP','B'),'ATP',5,16,True)==('ATP','A')
assert hours(90000.,0.)==25.0
assert band(1.49)=='<1.5' and band(1.5)=='1.5-2' and band(2.0)=='2-3' and band(3.0) is None
assert entry([100.,1170.,1250.],[2.,3.,4.],1300.)==(3.0,4.0) and entry([1250.],[2.],1300.) is None
assert abs(value('B',(2.0,1.9),True)-8.722)<1e-9 and value('B',(2.0,1.9),False)==-10.0 and abs(value('L',(2.0,2.2),False)-10/1.22*0.98)<1e-9 and value('L',(2.0,2.2),True)==-10.0 and value('B',(51.0,None),True) is None
assert TEAM.search('WTA Finals') and not TEAM.search('Wimbledon') and walkover('W/O') and retired('6-1 3-2 RET') and not retired('6-1 6-2')
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
rc=psycopg2.connect(creds.pg_railway(),sslmode='require')
TR=pd.read_sql("""SELECT tourney_name,tourney_date,tourney_level,best_of,surface,minutes::float8 minutes,winner_norm,loser_norm,score,tour,round,winner_age::float8 winner_age,loser_age::float8 loser_age FROM tennis_results_2026""",rc); rc.close()
TR['tour']=TR.tour.astype(str).str.upper(); TR['w']=TR.winner_norm.map(fold); TR['l']=TR.loser_norm.map(fold); TR['wo']=TR.score.map(walkover)
print(f"results {len(TR)}, {TR.tourney_date.min()}..{TR.tourney_date.max()}; tours {TR.tour.value_counts().to_dict()}; walkovers {TR.wo.sum()}; minutes null {TR.minutes.isna().sum()}; surfaces {TR.surface.value_counts().to_dict()}",flush=True)
P=TR[~TR.wo]; ix=defaultdict(list); played=defaultdict(list); MIN={}; trn=defaultdict(dict)
for r in P.itertuples():
    q=RANK.get(r.round,99); key=(r.tour,r.tourney_name,r.tourney_date); tm=bool(TEAM.search(r.tourney_name))
    if not tm:
        for x,won in ((r.w,True),(r.l,False)):
            played[key+(x,)].append(q)
            MIN[key+(x,q)]=r.minutes if good_min(r.minutes) else None
            t=trn[x].setdefault(key,dict(date=r.tourney_date,surface=r.surface,tour=r.tour,title=False,lostfinal=False,lostat=[],wonat=[]))
            (t['wonat'] if won else t['lostat']).append(q)
            if q==RANK['F']:
                if won: t['title']=True
                else: t['lostfinal']=True
    ix[frozenset((r.w,r.l))].append(dict(key=key,team=tm,q=q,date=r.tourney_date,w=r.w,l=r.l,score=r.score,tour=r.tour,aw=r.winner_age,al=r.loser_age,level=str(r.tourney_level),bo=r.best_of,surface=r.surface))
TL={x:sorted(((v['date'],k) for k,v in d.items()),key=lambda z:z[0]) for x,d in trn.items()}
print("unknown rounds:",sorted(set(P['round'])-set(RANK)),f"| {time.time()-T0:.0f}s",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
cur.execute("SELECT DISTINCT market_id FROM bf_hist_other WHERE sport='Tennis' AND market_type='MATCH_ODDS'")
MID=sorted(r[0] for r in cur.fetchall() if r[0].startswith('MATCH_ODDS|') and '/' not in r[0]); print(f"singles markets {len(MID)} | {time.time()-T0:.0f}s",flush=True)
SK=Counter(); M=[]; seen=set(); yrows=[]; MT={}
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
        if not h['team']: MT[h['key']+(h['w'],h['q'])]=mt; MT[h['key']+(h['l'],h['q'])]=mt   # the market time, even with no entry print, dates the earlier match
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
def prev_info(h,x):
    q=prev_rank(played[h['key']+(x,)],h['q'])
    if q is None: return None,None
    return MIN.get(h['key']+(x,q)),MT.get(h['key']+(x,q))
def tot_min(h,x):
    """(count of earlier matches, total minutes), None if a round-robin or a missing minutes figure is among them."""
    r=[q for q in played[h['key']+(x,)] if q<h['q']]
    if RANK['RR'] in r or 99 in r or h['q']==RANK['RR'] or len(r)!=len(set(r)): return None
    mm=[MIN.get(h['key']+(x,q)) for q in r]
    if any(m is None for m in mm): return None
    return len(r),sum(mm)
def prior_t(h,x,lo,hi,same_tour=True):
    """Most recent other tournament of x starting lo to hi days before this one, or None."""
    best=latest_key(TL.get(x,[]),h['date'],h['key'],h['tour'],lo,hi,same_tour)
    return trn[x][best] if best else None
LB=Counter(); rows=[]
for h,day,mk,ew,el,mt in M:
    w,l=h['w'],h['l']; ret=retired(h['score']); lab=defaultdict(list)   # lab[who]=[(item,state)]
    # 304
    (mw,tw),(ml,tl)=prev_info(h,w),prev_info(h,l)
    if mw is not None and ml is not None and tw is not None and tl is not None and 12<=hours(mt,tw)<=36 and 12<=hours(mt,tl)<=36:
        s=gap_state(mw,ml,45,15)
        if s=='a': lab[w].append((304,'TIRED'))
        elif s=='b': lab[l].append((304,'TIRED'))
        elif s=='even': lab[w].append((304,'CTRL')); lab[l].append((304,'CTRL'))
    # 305
    a,b=tot_min(h,w),tot_min(h,l)
    if a and b and a[0]==b[0] and a[0]>=2:
        s=gap_state(a[1],b[1],90,20)
        if s=='a': lab[w].append((305,'HEAVY'))
        elif s=='b': lab[l].append((305,'HEAVY'))
        elif s=='even': lab[w].append((305,'CTRL')); lab[l].append((305,'CTRL'))
    # 306, 307: first match here
    fw,fl=is_first(played[h['key']+(w,)],h['q']),is_first(played[h['key']+(l,)],h['q'])
    pw=prior_t(h,w,5,16) if fw else None; pl=prior_t(h,l,5,16) if fl else None
    tw_,tl_=bool(pw and pw['title']),bool(pl and pl['title'])
    for who,p_,me,op in ((w,pw,tw_,tl_),(l,pl,tl_,tw_)):
        if not p_: continue
        if me and not op: lab[who].append((306,'TITLE'))
        elif p_['lostfinal']: lab[who].append((306,'CONTEXT_LOSTFINAL'))
        elif not p_['wonat'] and p_['lostat']: lab[who].append((306,'CTRL'))
    if fw and fl and str(h['surface']).lower() not in ('carpet','none','nan',''):
        sw=prior_t(h,w,1,28,False); sl=prior_t(h,l,1,28,False)
        if sw and sl and 'carpet' not in (str(sw['surface']).lower(),str(sl['surface']).lower()):
            ss=h['surface']; aw,al=sw['surface']==ss,sl['surface']==ss
            if not aw and al: lab[w].append((307,'SWITCH'))
            elif aw and not al: lab[l].append((307,'SWITCH'))
            elif aw and al: lab[w].append((307,'CTRL')); lab[l].append((307,'CTRL'))
    # 308
    if h['tour']=='ATP' and h['level']=='G' and h['bo']==5:
        lab[w].append((308,'BO5')); lab[l].append((308,'BO5'))
    elif h['tour']=='ATP' and h['level']=='M' and h['bo']==3:
        lab[w].append((308,'CTRL')); lab[l].append((308,'CTRL'))
    for who,ls in lab.items():
        won=who==w; e=ew if won else el; p=e[0]; b_=band(p)
        for it,st in ls:
            LB[(it,st)]+=1
            if not b_: continue
            early=h['q'] in (RANK['R128'],RANK['R64'])
            for side in 'BL':
                v=value(side,e,won)
                if v is None: continue
                rows.append((it,st,b_,side,h['tour'],day,mk,who,ret,won,p,early,v))
print("labels before bands:",{f"{k[0]} {k[1]}":v for k,v in sorted(LB.items())},flush=True)
Y=pd.DataFrame(yrows,columns=['day','v'])
if len(Y):
    wh=pd.to_datetime(Y.day).astype('int64').values; yl=line(Y.v.values,np.where(wh<np.median(wh),1,2))
    print(f"ENGINE CHECK, item 215 YOUNG <2 back, was n 1901 +0.169 t 1.04 h1 +0.178 h2 +0.160; now n {yl['n']} {yl['per10']:+.3f} t {yl['t']:.2f} h1 {yl['h1']:+.3f} h2 {yl['h2']:+.3f}",flush=True)
R=pd.DataFrame(rows,columns='it st band side tour day m who ret won px early v'.split())
if R.empty: print("ERROR: no rows, no verdict"); sys.exit(1)
assert not R.duplicated(['it','st','band','side','m','who']).any(),"more than one bet per runner per line"
R['when']=pd.to_datetime(R.day).astype('int64'); print(f"dates {R.day.min()}..{R.day.max()}; markets {R.m.nunique()}",flush=True)
def tab(x,**k):
    md=np.median(x.when.values); hh=np.where(x.when.values<md,1,2); l=line(x.v.values,hh); xr=x[~x.ret].v; vv=x.v.values
    return dict(**k,n=l['n'],per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2'],n1=l['n1'],n2=l['n2'],x_ret=xr.mean() if len(xr) else np.nan,no_top=np.delete(vv,vv.argmax()).mean() if len(vv)>1 else np.nan,won=x.won.mean(),implied=(1/x.px).mean(),players=x.who.nunique(),PASS=bool(l['PASS'] and len(xr)>0 and xr.mean()>=0.15))
SC={304:'TIRED',305:'HEAVY',306:'TITLE',307:'SWITCH',308:'BO5'}
tot_lines=0; tot_pass=0
for it,sc in SC.items():
    out=[]
    for (st,b,side),x in R[R['it']==it].groupby(['st','band','side']):
        if it==308: cuts=(('ALL',x),('R128_R64',x[x.early]))
        else: cuts=(('ALL',x),('ATP',x[x.tour=='ATP']),('WTA',x[x.tour=='WTA']),('CHALLENGER',x[x.tour=='CHALLENGER']))
        for cut,xx in cuts:
            if len(xx)>1: out.append(tab(xx,st=st,band=b,side=side,cut=cut))
    S=pd.DataFrame(out).sort_values('t',ascending=False); A=S[S.st==sc]; tot_lines+=len(A)
    print(f"\n== ITEM {it}, {sc}: {len(A)} lines, top 12 by t\n",A.head(12).round(3).to_string(index=False))
    print("\n-- worst 3\n",A.tail(3).round(3).to_string(index=False))
    print("\n-- control and context, ALL, cannot pass\n",S[(S.st!=sc)&(S['cut']=='ALL')].drop(columns='PASS').round(3).to_string(index=False))
    W=A[A.PASS]; tot_pass+=len(W); print(f"\n== SURVIVORS {it}: {len(W)} of {len(A)}\n",W.round(3).to_string(index=False) if len(W) else "none",flush=True)
print(f"\nALL ITEMS: {tot_pass} of {tot_lines} scored lines pass; total {time.time()-T0:.0f}s")
PY
