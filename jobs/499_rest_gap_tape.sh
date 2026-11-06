#!/bin/bash
set -o pipefail
# 499_rest_gap_tape (Finder 2026-11-06, queue items 309-311, Finder's own, sources c, d, from jobs/499_flip_flow.sh; not jobs/499_rest_gap.sh, which is item 77 on af_fixtures): short rest v a rested side, second leg, derby by name, at the last print T-5 to T-2. Rules pushed in the queue (7a00dd3) before any price. Read only, no tables written. Prints only, so a pass is an upper bound.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,re,time,bisect,unicodedata,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line
from lib_official import bk,ly,fill,last_in,secs,checks,group,load_results
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',240); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',200)
H=3600.0; DAY=86400.0
STOP={'united','athletic','atletico','sporting','dynamo','rovers','wanderers','county','albion','deportivo','olympique','racing','union','rangers','internacional','independiente','academica','santa','saint','real','town','city','hotspur','sport','nacional','central','universidad','junior'}
def words(n): return {w for w in re.sub(r"[^a-z ]"," ",unicodedata.normalize('NFKD',n).encode('ascii','ignore').decode().lower()).split() if len(w)>=5 and w not in STOP}
def derby(a,b): return bool(words(a)&words(b))
def rest(times,t):
    """Hours since the team's last market at least 12 h before t, within 14 days. times sorted. None if none."""
    i=bisect.bisect_right(times,t-12*H)-1
    if i<0 or t-times[i]>14*24*H: return None
    return (t-times[i])/H
def rest_state(a,b):
    """a, b rest hours for home, away. TIRED_H, TIRED_A, BOTH, EVEN or None."""
    if a is None or b is None: return None
    if a<=84 and b>=144: return 'TIRED_H'
    if b<=84 and a>=144: return 'TIRED_A'
    if a<=84 and b<=84: return 'BOTH'
    if 120<=a<=240 and 120<=b<=240: return 'EVEN'
    return None
def first_leg(games,t):
    """games: sorted (time, market_id) of the reversed fixture. Latest 3 to 21 days before t, None if none."""
    best=None
    for x,m in games:
        if 3*DAY<=t-x<=21*DAY: best=m
    return best
# known answers, worked by hand
assert derby('Manchester United','Manchester City') and not derby('Real Madrid','Real Betis') and not derby('Leeds','Hull') and derby('Inter Milan','AC Milan')  # milan has 5 letters
assert derby('Sheffield Utd','Sheffield Wed') and not derby('Atletico Madrid','Atletico Bilbao') and derby('Atletico Madrid','Real Madrid') is True
T=[0.,100*H,300*H]
assert rest(T,110*H)==110.0 and rest(T,100*H+11*H)==111.0 and rest(T,100*H+12*H)==12.0 and rest(T,300*H+15*24*H) is None and rest([],5.) is None and rest(T,5*H) is None
assert rest_state(84,144)=='TIRED_H' and rest_state(144,84)=='TIRED_A' and rest_state(85,144) is None and rest_state(84,143) is None and rest_state(70,80)=='BOTH' and rest_state(120,240)=='EVEN' and rest_state(119,200) is None and rest_state(None,100) is None and rest_state(100,100) is None
G=[(0.,'a'),(10*DAY,'b')]
assert first_leg(G,13*DAY)=='b' and first_leg(G,12*DAY)=='a' and first_leg(G,40*DAY) is None and first_leg(G,1*DAY) is None
assert secs(pd.Series(pd.to_datetime(['2026-01-01 00:00:00+00:00']))).iloc[0]==1767225600.0
print("checks: OK",flush=True); T0=time.time()
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
TY=['MATCH_ODDS','OVER_UNDER_25']
RS,dr=load_results(con,TY); print("official markets",len(RS),"dropped, not one winner",dr,f"{time.time()-T0:.0f}s",flush=True)
cur.execute("SELECT DISTINCT market_id,event_name,extract(epoch from market_time)::float8 FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND market_time>='2023-12-01' AND market_time<'2026-10-01'")
SC=[(m,e,float(t)) for m,e,t in cur.fetchall() if ' v ' in e and group(e) is None]
print("schedule rows",len(SC),f"{time.time()-T0:.0f}s",flush=True)
TIMES=defaultdict(set); FX=defaultdict(list)
for m,e,t in SC:
    h,a=e.split(' v ',1); TIMES[h].add(t); TIMES[a].add(t); FX[(h,a)].append((t,m))
TIMES={k:sorted(v) for k,v in TIMES.items()}
for k in FX: FX[k].sort()
C=Counter(); LAB={}
for m,e,t in SC:
    h,a=e.split(' v ',1); key=(e,t)
    if key in LAB: continue
    L=dict(rest=rest_state(rest(TIMES[h],t),rest(TIMES[a],t)),h=h,a=a,derby=derby(h,a),leg=None)
    fm=first_leg(FX.get((a,h),[]),t)
    if fm is not None:
        r=RS.get(fm)
        if not r: C['310 first leg no official']+=1
        else:
            w=[s for s,x in r.items() if x][0]
            if w=='The Draw': L['leg']=('DRAWN',None)
            elif w in (h,a): L['leg']=('WON',w)
            else: C['310 winner name not a team']+=1
    LAB[key]=L
    C['rest '+str(L['rest'])]+=1
    if L['leg']: C['leg '+L['leg'][0]]+=1
    if L['derby']: C['derby']+=1
print("labels",dict(sorted(C.items())),f"{time.time()-T0:.0f}s",flush=True)
ex=[k[0] for k,v in LAB.items() if v['derby']]; print("derby sample",ex[:25],flush=True)
rows=[]
def add(item,lab,off,ev,a,b,won):
    """Prints a, b of one runner, pre-off, sorted. Entry last print T-5 to T-2. Back and lay."""
    i=last_in(a,off-300,off-120)
    if i is None: C[f'{item} no entry print']+=1; return
    Lp,Bp=fill(a,b,i,'L'),fill(a,b,i,'B')
    if Lp<=50: rows.append((item,lab,'lay',off,ev,ly(Lp,won),won,Lp))
    if Bp<=50:
        v=bk(Bp,won)
        if v is not None: rows.append((item,lab,'back',off,ev,v,won,Bp))
def month_chunks():
    for y,ms in ((2024,range(1,11)),(2026,range(5,10))):
        for m in ms:
            a=pd.Timestamp(y,m,1); e=a+pd.offsets.MonthBegin(1)
            if (y,m)>=(2026,8):   # Sep 2026 alone broke the 2.5 GB cap on 499_ht_break: read these by 5 days, no change to the rule
                while a<e:
                    b=min(a+pd.Timedelta(days=5),e); yield str(a.date()),str(b.date()); a=b
            else: yield str(a.date()),str(e.date())
for lo,hi in month_chunks():
    X=pd.read_sql("SELECT market_id,event_name ev,market_type ty,market_time mt,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type=ANY(%s) AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND ts>=market_time-interval '20 minutes' AND ts<=market_time+interval '6 minutes' AND market_time>=%s AND market_time<%s",con,params=(TY,lo,hi))
    if X.empty: print(lo,"no rows",flush=True); continue
    X['tt']=secs(X.ts); X['off']=secs(X.mt); X=X.sort_values('tt',kind='stable').drop_duplicates(['market_id','sel','tt'])
    nm=0
    for ev,G_ in X.groupby('ev',sort=False):
        if ' v ' not in ev or group(ev): continue
        for off,G1 in G_.groupby('off',sort=False):
            L=LAB.get((ev,off))
            if L is None: C['no label, event not in MO schedule']+=1; continue
            h,a=L['h'],L['a']; mo=None; ou=None
            for ty,G2 in G1.groupby('ty',sort=False):
                ids=sorted(G2.market_id.unique())
                if len(ids)>1: C['second id']+=1
                if ids[0] not in RS: C['no official, '+ty]+=1; continue
                d={s:(y.tt.values,y.ltp.values) for s,y in G2[G2.market_id==ids[0]].groupby('sel',sort=False)}
                if ty=='MATCH_ODDS': mo=(ids[0],d)
                else: ou=(ids[0],d)
            nm+=1
            rs=L['rest']; ln=L['leg']; O='Over 2.5 Goals'; U='Under 2.5 Goals'
            if mo:
                mk,d=mo; res=RS[mk]; last={}
                for s,(t_,p_) in d.items():
                    i=last_in(t_,off-1200,off-120)
                    if i is not None: last[s]=float(p_[i])
                if h in last and a in last and last[h]!=last[a]:
                    fav=h if last[h]<last[a] else a; out=a if fav==h else h
                    if rs in ('TIRED_H','TIRED_A'):
                        tir=h if rs=='TIRED_H' else a
                        s=tir; add(309,'TIRED FAV' if s==fav else 'TIRED OUT',off,ev,*d[s],res[s]) if s in res else None
                    if rs=='EVEN':
                        for s,lb in ((fav,'CTRL EVEN FAV'),(out,'CTRL EVEN OUT')):
                            if s in res: add(309,lb,off,ev,*d[s],res[s])
                elif h not in last or a not in last: C['MO team not priced or name differs']+=1
                else: C['MO roles level']+=1
                dr_='The Draw'
                if dr_ in d and dr_ in res:
                    if rs in ('TIRED_H','TIRED_A'): add(309,'TIRED DRAW',off,ev,*d[dr_],res[dr_])
                    if rs=='EVEN': add(309,'CTRL EVEN DRAW',off,ev,*d[dr_],res[dr_])
                    if ln and ln[0]=='WON': add(310,'W DRAW',off,ev,*d[dr_],res[dr_])
                    add(311,'DERBY DRAW' if L['derby'] else 'CTRL NON DRAW',off,ev,*d[dr_],res[dr_])
                if ln and ln[0]=='WON':
                    w=ln[1]; l_=a if w==h else h
                    if w in d and w in res: add(310,'WINNER',off,ev,*d[w],res[w])
                    if l_ in d and l_ in res: add(310,'LOSER',off,ev,*d[l_],res[l_])
            if ou:
                mk,d=ou; res=RS[mk]
                if O in d and O in res:
                    if rs=='BOTH': add(309,'BOTH OVER',off,ev,*d[O],res[O])
                    if rs=='EVEN': add(309,'CTRL EVEN OVER',off,ev,*d[O],res[O])
                    if ln: add(310,'W OVER' if ln[0]=='WON' else 'D OVER',off,ev,*d[O],res[O])
                    add(311,'DERBY OVER' if L['derby'] else 'CTRL NON OVER',off,ev,*d[O],res[O])
                if U in d and U in res and rs=='BOTH': add(309,'BOTH UNDER',off,ev,*d[U],res[U])
    print(lo,"rows",len(X),"games",nm,"cands",len(rows),f"{time.time()-T0:.0f}s",flush=True); del X
con.close()
print("counts",dict(sorted(C.items())),flush=True)
R=pd.DataFrame(rows,columns='item lab side off ev v won px'.split()); R['v']=R.v.astype(float); R['won']=R.won.astype(bool)
assert not R.duplicated(['item','lab','side','off','ev']).any(),"more than one bet per game per line"
med=R.off.median(); print("dates",pd.Timestamp(R.off.min(),unit='s'),pd.Timestamp(R.off.max(),unit='s'),"median",pd.Timestamp(med,unit='s'),flush=True)
tot=0; tp=0
for it in (309,310,311):
    o=[]
    for (l,s),x in R[R['item']==it].groupby(['lab','side']):
        if len(x)<2: continue
        m=x.off.median(); d=line(x.v.values,np.where(x.off<=m,1,2)); v=x.v.values
        o.append(dict(line=f"{l} {s}",n=d['n'],per10=round(d['per10'],3),t=round(d['t'],2),h1=round(d['h1'],3),h2=round(d['h2'],3),n1=d['n1'],n2=d['n2'],no_top=round(np.delete(v,v.argmax()).mean(),3),won=round(x.won.mean(),3),implied=round((1/x.px).mean(),3),games=x[['off','ev']].drop_duplicates().shape[0],PASS=d['PASS'] and not l.startswith('CTRL')))
    O=pd.DataFrame(o).sort_values('t',ascending=False); A=O[~O.line.str.startswith('CTRL')]; tot+=len(A)
    print(f"\n== ITEM {it}: {len(A)} scored lines\n",A.to_string(index=False)); print("-- control, cannot pass\n",O[O.line.str.startswith('CTRL')].drop(columns='PASS').to_string(index=False))
    S=A[A.PASS]; tp+=len(S); print(f"SURVIVORS {it}: {len(S)}\n",S.to_string(index=False) if len(S) else "none",flush=True)
print(f"\nALL ITEMS: {tp} of {tot} scored lines pass; total {time.time()-T0:.0f}s")
PY
