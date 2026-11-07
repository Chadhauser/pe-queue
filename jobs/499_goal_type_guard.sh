#!/bin/bash
set -o pipefail
# 499_goal_type_guard (Finder 2026-11-07, queue item 433, first part): jobs/499_goal_type.sh (item 179) unchanged except a PRICED-IN GUARD split. MOVED = the entry print has moved at least 20% from the leg's last print in af minutes c-6..c-1, the way the goal should move it (SCORER and OVER25 shorter, ratio <= 0.8; OTHER and DRAW longer, ratio >= 1.25); UNMOVED = it has not; no pre-goal print = neither. A lead whose profit sits only in UNMOVED is a clock artefact (items 430-432).
# DATA af_events, af_fixtures, af_price_map, bf_hist_price (MO, OU25), seasons 2024 and 2025. One entry per game per line. is_home on a goal row names the team credited with it, own goals included (checked 5 Nov on games with one goal: own goal 457 v 12, penalty 1,250 v 22).
# ENTRY E5 c+5..c+7, E10 c+10..c+12; af minute 1-39 or 46-80 for E5, 1-34 or 46-80 for E10, so an entry never crosses the break. Worse of the print and the next within 2, one tick adverse. No print: no trade, never a forward fill. No trade if a second goal has come by the entry minute.
# EXIT settle, or first print 10+ minutes on; no print, or the third goal by that print on Over 2.5: settled at the result. 2% commission, £10 risk. Halves by season.
# BAR standard, and a pass must hold on both E5 and E10. Games whose goal rows disagree with the final score are out, and counted. The CLOCK section prints where the price jump sits against the af minute, as a late tape clock would make an entry look ahead.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import defaultdict,Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,tstat
import lib_cand,lib_inplay; lib_cand._checks(); lib_inplay.checks()
from lib_inplay import *
pd.set_option('display.width',250); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',40)
T0=time.time()
TYPE={'Normal Goal':'NORMAL','Penalty':'PEN','Own Goal':'OG'}
def ok_minute(c,lag):
    """lag 5 (E5) or 10 (E10). Latest first-half minute leaves the whole window, c+lag..c+lag+2, at tape 46 or before."""
    return 1<=c<=44-lag or 46<=c<=80
def first_goal(rows):
    """rows (minute, extra, is_home, type). Sorted by clock: (first, second minute or None). 45+2 sorts before 46."""
    r=sorted(rows,key=lambda x:(x[0],x[1]))
    return r[0],(r[1][0] if len(r)>1 else None)
def consistent(rows,hg,ag): return sum(1 for r in rows if r[2])==hg and sum(1 for r in rows if not r[2])==ag
def third_minute(rows):
    r=sorted(rows,key=lambda x:(x[0],x[1])); return r[2][0] if len(r)>2 else None
def favourite(h,a,c):
    """HOME, AWAY or None, from the earliest pair of prints before the goal at c."""
    for m in range(0,c):
        if h[m]==h[m] and a[m]==a[m] and h[m]!=a[m]: return 'HOME' if h[m]<a[m] else 'AWAY'
    return None
# known answers, worked by hand
assert ok_minute(39,5) and not ok_minute(40,5) and ok_minute(34,10) and not ok_minute(35,10) and ok_minute(46,5) and ok_minute(80,10) and not ok_minute(81,5) and not ok_minute(45,5) and not ok_minute(0,5)
_r=[(46,0,True,'NORMAL'),(45,2,False,'PEN'),(70,0,True,'OG')]
assert first_goal(_r)==((45,2,False,'PEN'),46) and first_goal(_r[:1])==((46,0,True,'NORMAL'),None) and third_minute(_r)==70 and third_minute(_r[:2]) is None
assert consistent(_r,2,1) and not consistent(_r,1,2)
_h=np.full(96,np.nan); _a=np.full(96,np.nan); _h[3]=2.0; _a[3]=3.0; _h[20]=1.5
assert favourite(_h,_a,10)=='HOME' and favourite(_a,_h,10)=='AWAY' and favourite(_h,_a,3) is None
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.season,f.hg,f.ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.season IN (2024,2025)""",con)
ids=list(map(int,G.fixture_id))
EV=pd.read_sql("SELECT fixture_id,coalesce(minute,0) AS minute,coalesce(extra,0) AS extra,is_home,detail FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal') AND is_home IS NOT NULL",con,params=(ids,))
GL=defaultdict(list)
for r in EV.itertuples(): GL[r.fixture_id].append((int(r.minute),int(r.extra),bool(r.is_home),TYPE[r.detail]))
SK=Counter(); X=[]
for r in G.itertuples():
    if r.hg+r.ag==0: SK['no goal']+=1; continue
    rows=GL.get(r.fixture_id,[])
    if not rows or not consistent(rows,r.hg,r.ag): SK['goal rows disagree with the score']+=1; continue
    f,sec=first_goal(rows); X.append((r.event_id,r.fixture_id,r.season,r.hg,r.ag,f[0],f[2],f[3],sec,third_minute(rows)))
X=pd.DataFrame(X,columns='event_id fixture_id season hg ag c is_home kind sec third'.split())
print("games",len(G),"counts",dict(SK),"first goals",X.kind.value_counts().to_dict(),flush=True)
EID=list(X.event_id.unique()); px=defaultdict(dict)
for i in range(0,len(EID),1000):
    P=pd.read_sql("SELECT event_id,minute,mkt,sel,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND ((mkt='MO') OR (mkt='OU25' AND sel='OVER')) AND minute BETWEEN 0 AND 95 AND ltp>=1.01 AND ltp<1000",con,params=(EID[i:i+1000],))
    for (e,mk,s),g in P.groupby(['event_id','mkt','sel'],sort=False):
        a=np.full(96,np.nan); a[g.minute.values]=g.ltp.values; px[e][(mk,s)]=a
    print(f"  prices {min(i+1000,len(EID))}/{len(EID)} | {time.time()-T0:.0f}s",flush=True)
con.close()
rows=[]; off=defaultdict(list); SK=Counter()
for r in X.itertuples():
    b=px.get(r.event_id)
    if not b or ('MO','HOME') not in b or ('MO','AWAY') not in b or ('MO','DRAW') not in b: SK['no MO prices']+=1; continue
    S='HOME' if r.is_home else 'AWAY'; O='AWAY' if r.is_home else 'HOME'; h=1 if r.season==2024 else 2
    hw,aw=r.hg>r.ag,r.ag>r.hg; sw,ow=(hw,aw) if r.is_home else (aw,hw); third=None if pd.isna(r.third) else int(r.third); sec=None if pd.isna(r.sec) else int(r.sec)
    # CLOCK: where is the largest move in the scorer's price, against the af minute?
    a=b[('MO',S)]; fm=[m for m in range(max(r.c-6,0),min(r.c+14,95)) if a[m]==a[m]]
    if len(fm)>=2:
        js=[(abs(np.log(a[fm[i+1]]/a[fm[i]])),fm[i+1]) for i in range(len(fm)-1)]
        off[r.kind].append(max(js)[1]-r.c)
    fv=favourite(b[('MO','HOME')],b[('MO','AWAY')],r.c)
    sp=['all','H1' if r.c<=44 else 'H2']
    if fv: sp.append('FAV_SCORED' if fv==S else 'DOG_SCORED')
    legs=[('SCORER',b[('MO',S)],sw,None),('OTHER',b[('MO',O)],ow,None),('DRAW',b[('MO','DRAW')],r.hg==r.ag,None)]
    if ('OU25','OVER') in b: legs.append(('OVER25',b[('OU25','OVER')],r.hg+r.ag>2.5,third))
    for ent,lag in (('E5',5),('E10',10)):
        if not ok_minute(r.c,lag): SK[f'{ent} minute out']+=1; continue
        for leg,arr,won,gm in legs:
            for side in 'BL':
                e=enter(arr,r.c+lag,r.c+lag+2,side)
                if e is None: SK[f'{ent} no print or no bet']+=1; continue
                d,fx=e
                pre=[arr[m] for m in range(max(r.c-6,0),r.c) if arr[m]==arr[m]]
                mv=None if not pre else (arr[d]<=0.8*pre[-1] if leg in ('SCORER','OVER25') else arr[d]>=1.25*pre[-1])
                sq=sp+([] if mv is None else ['MOVED' if mv else 'UNMOVED'])
                if sec is not None and sec<=d: SK[f'{ent} second goal by entry']+=1; continue
                for ex in ('settle','+10'):
                    v=settle(side,fx,won) if ex=='settle' else exit_later(side,fx,arr,d,won,10,gm)
                    for s in sq: rows.append((r.kind,leg,'BACK' if side=='B' else 'LAY',ent,ex,s,h,r.event_id,v))
print("trade counts",dict(SK),f"priced games {len(px)}",flush=True)
print("\n== CLOCK largest jump in the scorer's price, tape minute less af minute (no outcome is read)")
for k,v in off.items(): print(' ',k,'n',len(v),'pct10/50/90/97',np.percentile(v,[10,50,90,97]).round(1).tolist(),'share after +4',round(float(np.mean(np.array(v)>4)),3),'share after +9',round(float(np.mean(np.array(v)>9)),3))
T=pd.DataFrame(rows,columns='kind leg side ent exit split h g v'.split()); o=[]; KEY=['leg','side','ent','exit','split']
N={k:x.v.values for k,x in T[T.kind=='NORMAL'].groupby(KEY)}
for k,x in T.groupby(['kind']+KEY):
    d=line(x.v.values,x.h.values); nv=N.get(k[1:])
    # difference from the same line on open-play goals; Welch, on independent games
    dt=np.nan
    if k[0]!='NORMAL' and nv is not None and len(nv)>1 and len(x)>1: dt=(x.v.mean()-nv.mean())/np.sqrt(x.v.var(ddof=1)/len(x)+nv.var(ddof=1)/len(nv))
    o.append(dict(zip(['kind']+KEY,k))|dict(n=d['n'],games=x.g.nunique(),per10=round(d['per10'],3),t=round(d['t'],2),h1=round(d['h1'],3),h2=round(d['h2'],3),n1=d['n1'],n2=d['n2'],t_v_NORMAL=round(dt,2) if dt==dt else np.nan,maxwin=round(d['maxwin'],0),ex_top=round((x.v.sum()-d['maxwin'])/max(d['n']-1,1),3),PASS=d['PASS']))
L=pd.DataFrame(o); E=L[L.n>=300].sort_values('t',ascending=False)
# a pass on one entry needs its twin on the other entry
tw={(r.kind,r.leg,r.side,r.ent,r.exit,r.split):r.PASS for r in L.itertuples()}
L['BOTH']=[bool(r.PASS and tw.get((r.kind,r.leg,r.side,'E10' if r.ent=='E5' else 'E5',r.exit,r.split),False)) for r in L.itertuples()]
print(f"\nlines {len(L)}, at n>=300 {len(E)}, passing one entry {int(L.PASS.sum())}, passing both {int(L.BOTH.sum())}, {time.time()-T0:.0f}s")
C=['kind','leg','side','ent','exit','split','n','per10','t','h1','h2','maxwin','ex_top','PASS','BOTH']
print("\n== ITEM 179's lead family: PEN OTHER BACK, all v MOVED v UNMOVED"); print(L[(L.kind=='PEN')&(L.leg=='OTHER')&(L.side=='BACK')&L.split.isin(['all','MOVED','UNMOVED'])].sort_values(['ent','exit','split'])[C].to_string(index=False))
print("\n== item 179's top 10 'all' lines by t (n>=300), with the same line on MOVED and UNMOVED")
K=['kind','leg','side','ent','exit']; Lk=L.set_index(K+['split'])
for r in L[(L.split=='all')&(L.n>=300)].sort_values('t',ascending=False).head(10).itertuples():
    k=(r.kind,r.leg,r.side,r.ent,r.exit); m=Lk.loc[k+('MOVED',)] if k+('MOVED',) in Lk.index else None; u=Lk.loc[k+('UNMOVED',)] if k+('UNMOVED',) in Lk.index else None
    f=lambda z: 'none' if z is None else f"n {int(z.n)} {z.per10:+.3f} t {z.t:.2f} ex_top {z.ex_top:+.3f}"
    print(f"  {' '.join(map(str,k))}: all n {r.n} {r.per10:+.3f} t {r.t:.2f} | MOVED {f(m)} | UNMOVED {f(u)}")
U=L[L.split=='UNMOVED']; M=L[L.split=='MOVED']
print(f"\nmean per10 over every line: MOVED {M.per10.mean():+.3f} (lines {len(M)}), UNMOVED {U.per10.mean():+.3f} (lines {len(U)})")
S=L[(L.split=='MOVED')&L.BOTH]; print(f"\n== SURVIVORS (MOVED, passing on both E5 and E10): {len(S)}"); print(S[C].to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
