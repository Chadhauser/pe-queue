#!/bin/bash
set -o pipefail
# 499_ht_youth_may23 (Finder 2026-11-07, queue item 421, first read): job 499_ht_women_youth unchanged except the window, May 2023 only, unseen by item 409. Scored line YOUTH G1 25 lay; every other line is for reading only. Rule pushed in the queue before any price. Read only, no tables written. Prints only, so a pass is an upper bound.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line
from lib_official import bk,ly,fill,first_in,secs,checks,group,load_results
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',220); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',200)
TY={'OVER_UNDER_15':'Over 1.5 Goals','OVER_UNDER_25':'Over 2.5 Goals','OVER_UNDER_35':'Over 3.5 Goals'}
WHICH={'G0':['OVER_UNDER_15','OVER_UNDER_25'],'G1':['OVER_UNDER_25','OVER_UNDER_35']}
def state(score):
    """Official HALF_TIME_SCORE winner to a state: 0 - 0 is G0, one goal G1, anything else no trade."""
    return {'0 - 0':'G0','1 - 0':'G1','0 - 1':'G1'}.get(score)
# known answers, worked by hand
assert state('0 - 0')=='G0' and state('1 - 0')=='G1' and state('0 - 1')=='G1' and state('1 - 1') is None and state('2 - 0') is None and state('Any Unquoted') is None
print("checks: OK",flush=True); T0=time.time()
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
RS,dr=load_results(con,list(TY)); print("official markets",len(RS),"dropped, not one winner",dr,f"{time.time()-T0:.0f}s",flush=True)
H=pd.read_sql("SELECT market_id,event_id,sel FROM bf_hist_result WHERE sport='Soccer' AND market_type='HALF_TIME_SCORE' AND status='WINNER'",con)
n=H.groupby('event_id').market_id.nunique(); H=H[H.event_id.isin(n[n==1].index)]; w=H.groupby('market_id').size(); H=H[H.market_id.isin(w[w==1].index)]
HS=dict(zip(H.event_id,H.sel)); print("HT scores",len(HS),flush=True); del H
C=Counter(); rows=[]
def chunks():
    for y,m in [(2023,5)]:
        a=pd.Timestamp(y,m,1); e=a+pd.offsets.MonthBegin(1)
        if (y,m)>=(2026,8):
            while a<e:
                b=min(a+pd.Timedelta(days=5),e); yield str(a.date()),str(b.date()); a=b
        else: yield str(a.date()),str(e.date())
SELS=list(TY.values()); MK=list(TY)
for lo,hi in chunks():
    F=pd.read_sql("SELECT event_id,market_time mt,min(ts) f FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND inplay AND ts>=market_time-interval '30 minutes' AND ts<=market_time+interval '60 minutes' AND market_time>=%s AND market_time<%s GROUP BY 1,2",con,params=(lo,hi))
    ontime=set(F.event_id[(secs(F.f)-secs(F.mt))<=240]); C['MO late off']+=int(((secs(F.f)-secs(F.mt))>240).sum()); del F
    X=pd.read_sql("SELECT market_id,event_id eid,event_name ev,market_type ty,market_time mt,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type=ANY(%s) AND sel=ANY(%s) AND inplay AND ltp>=1.01 AND ltp<1000 AND ts>=market_time+interval '52 minutes' AND ts<=market_time+interval '62 minutes' AND market_time>=%s AND market_time<%s",con,params=(MK,SELS,lo,hi))
    if X.empty: print(lo,"no rows",flush=True); continue
    X['tt']=secs(X.ts); X['off']=secs(X.mt); X=X.sort_values('tt',kind='stable').drop_duplicates(['market_id','sel','tt']); ng=0
    for (eid,ev,off),G_ in X.groupby(['eid','ev','off'],sort=False):
        if ' v ' not in ev: C['no H v A']+=1; continue
        if eid not in ontime: C['not on time']+=1; continue
        st=state(HS.get(eid))
        if st is None: C['state out or no official']+=1; continue
        grp=group(ev) or 'SENIOR'; ng+=1
        for ty in WHICH[st]:
            g=G_[G_.ty==ty]
            if g.empty: C[ty+' no print']+=1; continue
            mk=sorted(g.market_id.unique())[0]; sel=TY[ty]
            y=g[(g.market_id==mk)&(g.sel==sel)]
            if y.empty: C[ty+' no print']+=1; continue
            if mk not in RS or sel not in RS[mk]: C[ty+' no official']+=1; continue
            ts,px=y.tt.values,y.ltp.values; i=first_in(ts,off+52*60,off+60*60)
            if i is None: C[ty+' no print in the window']+=1; continue
            L=fill(ts,px,i,'L'); B=fill(ts,px,i,'B'); won=bool(RS[mk][sel])
            lb=f"{grp} {st} {ty[-2:]}"
            if L<=50: rows.append((lb,'lay',off,ev,ly(L,won),won,L))
            if B<=50:
                v=bk(B,won)
                if v is not None: rows.append((lb,'back',off,ev,v,won,B))
    print(lo,"rows",len(X),"games",ng,"cands",len(rows),f"{time.time()-T0:.0f}s",flush=True); del X
con.close()
print("counts",dict(sorted(C.items())),flush=True)
T=pd.DataFrame(rows,columns=['lab','side','off','ev','v','won','px']).drop_duplicates(['lab','side','off','ev'])
med=T.off[~T.lab.str.startswith('SENIOR')].median(); T['h']=np.where(T.off<=med,1,2); print("halves split at",pd.Timestamp(med,unit='s',tz='UTC'),flush=True)
out=[];ctl=[]
for (l,s),x in T.groupby(['lab','side']):
    if len(x)<2: continue
    d=line(x.v.values,x.h.values); v=x.v.values; xl=np.delete(v,v.argmax()).mean()
    r=dict(line=f"{l} {s}",n=d['n'],games=x[['off','ev']].drop_duplicates().shape[0],per10=round(d['per10'],3),t=round(d['t'],2),h1=round(d['h1'],3),h2=round(d['h2'],3),n1=d['n1'],n2=d['n2'],no_top=round(xl,3),won=round(x.won.mean(),3),imp=round((1/x.px).mean(),3),PASS=d['PASS'])
    (ctl if l.startswith('SENIOR') else out).append(r)
O=pd.DataFrame(out).sort_values('t',ascending=False); K=pd.DataFrame(ctl).sort_values('t',ascending=False)
print("scored lines",len(O)); print(O.to_string(index=False))
print("control, senior games, not scored"); print(K.to_string(index=False))
print("SURVIVORS"); S=O[O.PASS]; print(S.to_string(index=False) if len(S) else "none",flush=True)
print(f"total {time.time()-T0:.0f}s")
PY
