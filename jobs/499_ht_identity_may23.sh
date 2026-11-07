#!/bin/bash
set -o pipefail
# 499_ht_identity_may23 (Finder 2026-11-07, queue item 420, first read): job 499_ht_identity_audit unchanged except the window, May 2023 only, unseen by item 407. Scored line HTFT G2 CHEAP back; every other line is for reading only. Read only, no tables written. Prints only. The months chose the line, so it cannot pass.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,step,back_settle,lay_settle
from lib_official import fill,last_in,secs,checks
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',220); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',200)
WIN0,WIN1,STALE=52*60,60*60,300
GS=(2,4,8)
def nm(x): return 'Draw' if x=='The Draw' else x
def kind(g,G): return 'DEAR' if g>=G else 'CHEAP' if g<=-G else None
def older(tt,lp,t):
    i=last_in(tt,t-STALE,t)
    return None if i is None else float(lp[i])
def band(p): return '<=3' if p<=3 else '3-8' if p<=8 else '8-20' if p<=20 else '20-50' if p<=50 else None
def first_signal(gaps,G,want):
    """gaps in time order, None where unread. Index of the first gap of kind want at G, else None. Later, larger gaps are never looked at."""
    for j,g in enumerate(gaps):
        if g is not None and kind(g,G)==want: return j
    return None
# known answers, worked by hand
assert first_signal([None,-1.0,-3.0,-9.0],2,'CHEAP')==2 and first_signal([None,-1.0,-3.0,-9.0],8,'CHEAP')==3
assert first_signal([1.0,5.0,-5.0],4,'DEAR')==1 and first_signal([1.0],2,'DEAR') is None and first_signal([],2,'DEAR') is None
assert band(3)=='<=3' and band(3.05)=='3-8' and band(20)=='8-20' and band(50)=='20-50' and band(60) is None
print("checks: OK",flush=True); T0=time.time()
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
R=pd.read_sql("SELECT market_id,event_id,market_type ty,sel,status FROM bf_hist_result WHERE sport='Soccer' AND market_type=ANY(%s)",con,params=(['MATCH_ODDS','HALF_TIME_FULL_TIME','HALF_TIME'],))
w=R[R.status=='WINNER'].groupby('market_id').size(); ok=set(w[w==1].index); R=R[R.market_id.isin(ok)]
RS={}
for m,g in R[R.ty!='HALF_TIME'].groupby('market_id'): RS[m]=dict(zip(g.sel,g.status=='WINNER'))
H=R[(R.status=='WINNER')&(R.ty=='HALF_TIME')]; n_ev=H.groupby('event_id').market_id.nunique(); H=H[H.event_id.isin(n_ev[n_ev==1].index)]
HT=dict(zip(H.event_id,H.sel)); print("official",len(RS),"HT",len(HT),f"{time.time()-T0:.0f}s",flush=True); del R,H
C=Counter(); rows=[]
def chunks():
    for y,m in [(2023,5)]:
        a=pd.Timestamp(y,m,1); e=a+pd.offsets.MonthBegin(1)
        if (y,m)>=(2026,8):
            while a<e:
                b=min(a+pd.Timedelta(days=5),e); yield str(a.date()),str(b.date()); a=b
        else: yield str(a.date()),str(e.date())
for lo,hi in chunks():
    F=pd.read_sql("SELECT market_id,market_time mt,min(ts) f FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND inplay AND ts>=market_time-interval '30 minutes' AND ts<=market_time+interval '60 minutes' AND market_time>=%s AND market_time<%s GROUP BY 1,2",con,params=(lo,hi))
    ontime=set(F.market_id[(secs(F.f)-secs(F.mt))<=240]); del F
    X=pd.read_sql("SELECT market_id,event_id eid,event_name ev,market_type ty,market_time mt,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type=ANY(%s) AND inplay AND ltp>=1.01 AND ltp<1000 AND ts>=market_time+interval '47 minutes' AND ts<=market_time+interval '62 minutes' AND market_time>=%s AND market_time<%s",con,params=(['MATCH_ODDS','HALF_TIME_FULL_TIME'],lo,hi))
    if X.empty: print(lo,"no rows",flush=True); continue
    X['tt']=secs(X.ts); X['off']=secs(X.mt); X=X.sort_values('tt',kind='stable').drop_duplicates(['market_id','sel','tt']); ng=0
    for (eid,ev,off),G_ in X.groupby(['eid','ev','off'],sort=False):
        if ' v ' not in ev or eid not in HT: continue
        tys=dict(tuple(G_.groupby('ty',sort=False)))
        if 'MATCH_ODDS' not in tys or 'HALF_TIME_FULL_TIME' not in tys: continue
        mo_id=sorted(tys['MATCH_ODDS'].market_id.unique())[0]; hf_id=sorted(tys['HALF_TIME_FULL_TIME'].market_id.unique())[0]
        if mo_id not in ontime: C['not on time']+=1; continue
        rs=RS.get(hf_id); rm=RS.get(mo_id)
        if rs is None: C['HTFT no official']+=1; continue
        MO={s:(y.tt.values,y.ltp.values) for s,y in tys['MATCH_ODDS'][tys['MATCH_ODDS'].market_id==mo_id].groupby('sel',sort=False)}
        HF={s:(y.tt.values,y.ltp.values) for s,y in tys['HALF_TIME_FULL_TIME'][tys['HALF_TIME_FULL_TIME'].market_id==hf_id].groupby('sel',sort=False)}
        h,a=ev.split(' v ',1); x=nm(HT[eid]); name={h:h,a:a,'Draw':'The Draw'}; ng+=1
        sigs=[]
        for f in (h,a,'Draw'):
            sel=f"{x}/{f}"; ms=name[f]
            if sel not in HF or sel not in rs or ms not in MO: continue
            ts,px=HF[sel]; mt,mp=MO[ms]
            for i in range(int(np.searchsorted(ts,off+WIN0,side='left')),int(np.searchsorted(ts,off+WIN1,side='right'))):
                p=older(mt,mp,ts[i])
                if p is None: continue
                sigs.append((float(ts[i]),sel,ms,i,100*(1/float(px[i])-1/p),p))
        sigs.sort(key=lambda z:z[0])
        gaps=[z[4] for z in sigs]
        for G in GS:
            for want in ('CHEAP','DEAR'):
                j=first_signal(gaps,G,want)
                if j is None: continue
                t_,sel,ms,i,g,pm=sigs[j]; ts,px=HF[sel]; won=bool(rs[sel])
                B=fill(ts,px,i,'B'); L=fill(ts,px,i,'L')
                if want=='CHEAP':
                    a1=step(B,-1)
                    if B>50 or a1<=1.01: continue
                    v=back_settle(a1,won); pr=B
                    mv=back_settle(step(pm,-1),won) if step(pm,-1)>1.01 else None
                else:
                    if L>50: continue
                    v=lay_settle(step(L,1),won); pr=L
                    mv=lay_settle(step(pm,1),won)
                nx=None
                if i+1<len(ts):
                    p2=older(MO[ms][0],MO[ms][1],ts[i+1])
                    if p2 is not None: nx=100*(1/float(px[i+1])-1/p2)
                rows.append((G,want,off,ev,v,mv,won,1/float(px[i]),1/pm,float(px[i]),band(float(px[i])),g,nx,ts[i+1]-ts[i] if i+1<len(ts) else None))
    print(lo,"games",ng,"cands",len(rows),f"{time.time()-T0:.0f}s",flush=True); del X
con.close(); print("counts",dict(C),flush=True)
T=pd.DataFrame(rows,columns=['G','kind','off','ev','v','mv','won','imp_hf','imp_mo','px','band','gap','next_gap','next_s'])
med=T.off.median(); T['h']=np.where(T.off<=med,1,2); print("halves split at",pd.Timestamp(med,unit='s',tz='UTC'),"games",T[['off','ev']].drop_duplicates().shape[0],flush=True)
out=[]
for (G,k),x in T.groupby(['G','kind']):
    d=line(x.v.values,x.h.values); v=x.v.values; xl=np.delete(v,v.argmax()).mean() if len(v)>1 else np.nan
    mv=pd.to_numeric(x.mv,errors='coerce')
    out.append(dict(line=f"HTFT G{G} {k} {'back' if k=='CHEAP' else 'lay'}",n=d['n'],per10=round(d['per10'],3),t=round(d['t'],2),h1=round(d['h1'],3),h2=round(d['h2'],3),n1=d['n1'],n2=d['n2'],no_top=round(xl,3),won=round(x.won.mean(),3),imp_hf=round(x.imp_hf.mean(),3),imp_mo=round(x.imp_mo.mean(),3),mo_same=round(mv.mean(),3),next_gap=round(pd.to_numeric(x.next_gap,errors='coerce').median(),2),PASS=d['PASS']))
print(pd.DataFrame(out).to_string(index=False))
print("by price band"); b=[]
for (G,k,bd),x in T.groupby(['G','kind','band']):
    if len(x)<10: continue
    d=line(x.v.values,x.h.values)
    b.append(dict(line=f"G{G} {k} {bd}",n=d['n'],per10=round(d['per10'],3),t=round(d['t'],2),h1=round(d['h1'],3),h2=round(d['h2'],3),won=round(x.won.mean(),3),imp_hf=round(x.imp_hf.mean(),3),imp_mo=round(x.imp_mo.mean(),3)))
print(pd.DataFrame(b).to_string(index=False))
print("SURVIVORS\nnone possible yet, scored line is under n 300 on one month",flush=True)
print(f"total {time.time()-T0:.0f}s")
PY
