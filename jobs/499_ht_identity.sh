#!/bin/bash
set -o pipefail
# 499_ht_identity (Finder 2026-11-07, queue items 407 and 408, Finder's own, source c): the same bet in two markets during the half-time break. Rule pushed in the queue before any price. Read only, no tables written. Prints only, so a pass is an upper bound.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,step,back_settle,lay_settle
from lib_official import bk,ly,fill,last_in,secs,checks,group
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',220); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',200)
TY=['MATCH_ODDS','HALF_TIME_FULL_TIME','DOUBLE_CHANCE','DRAW_NO_BET','OVER_UNDER_05','OVER_UNDER_15','CORRECT_SCORE']
U05='Under 0.5 Goals'; U15='Under 1.5 Goals'
WIN0,WIN1,STALE=52*60,60*60,300
GS=(2,4,8)
def nm(x): return 'Draw' if x=='The Draw' else x
def kind(g,G):
    """DEAR: traded leg implied higher than the other side by G points or more, lay it. CHEAP: lower by G or more, back it."""
    return 'DEAR' if g>=G else 'CHEAP' if g<=-G else None
def imp_mo(p): return 1/p
def imp_dc(p_left_out): return 1-1/p_left_out
def imp_dnb(p_f,p_o): return (1/p_f)/((1/p_f)+(1/p_o))
def gap_pts(px,fair): return 100*(1/px-fair)
def older(tt,lp,t):
    """Last print at or before t, at most STALE seconds old, else None. No forward fill."""
    i=last_in(tt,t-STALE,t)
    return None if i is None else float(lp[i])
def settle(side,a,won):
    """won None is a void: stake back, 0. Fill a already includes the ticks."""
    if won is None: return 0.0
    return back_settle(a,won) if side=='B' else lay_settle(a,won)
def ok_markets(w,dc):
    """Markets with a clean result: one winner, but two on Double Chance, as two of its three runners win. First run dropped every DC market here."""
    return {m for m,k in w.items() if k==(2 if m in dc else 1)}
assert ok_markets(pd.Series({'a':1,'b':2,'c':2,'d':1}),{'c','d'})=={'a','c'}
# known answers, worked by hand
assert kind(2.0,2)=='DEAR' and kind(-2.0,2)=='CHEAP' and kind(1.99,2) is None and kind(-7.9,8) is None
assert abs(imp_dc(4.0)-0.75)<1e-12 and abs(imp_dnb(2.0,4.0)-2/3)<1e-12
assert abs(gap_pts(2.0,0.4)-10)<1e-9 and abs(gap_pts(4.0,0.5)+25)<1e-9
_t=np.array([0.,100.,400.]); _p=np.array([2.0,2.2,3.0])
assert older(_t,_p,100.)==2.2 and older(_t,_p,399.)==2.2 and older(_t,_p,401.)==3.0 and older(_t,_p,-1.) is None and older(_t,_p,1000.) is None
assert older(np.array([0.,1000.]),np.array([2.0,3.0]),999.) is None   # older than 300 s, never carried
assert settle('B',2.0,None)==0.0 and settle('L',2.0,None)==0.0 and abs(settle('B',2.0,True)-9.8)<1e-9 and settle('L',2.0,True)==-10.0 and abs(settle('L',2.0,False)-9.8)<1e-9
print("checks: OK",flush=True); T0=time.time()
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
# Correct Score rows cut to the 0 - 0 runner and the winner, all this job reads: the full load broke the 2.5 GB cap on the second run. No rule changes.
R=pd.read_sql("SELECT market_id,event_id,market_type ty,sel,status FROM bf_hist_result WHERE sport='Soccer' AND market_type=ANY(%s) AND (market_type<>'CORRECT_SCORE' OR sel='0 - 0' OR status='WINNER')",con,params=(TY+['HALF_TIME','HALF_TIME_SCORE'],))
w=R[R.status=='WINNER'].groupby('market_id').size(); ok=ok_markets(w,set(R.market_id[R.ty=='DOUBLE_CHANCE']))
print("DC markets kept",len(ok&set(R.market_id[R.ty=='DOUBLE_CHANCE'])),flush=True)
RS={}
for m,g in R[R.market_id.isin(ok)].groupby('market_id'): RS[m]=dict(zip(g.sel,g.status=='WINNER'))
H=R[R.market_id.isin(ok)&(R.status=='WINNER')&R.ty.isin(['HALF_TIME','HALF_TIME_SCORE'])]
n_ev=H.groupby(['event_id','ty']).market_id.nunique(); bad=set(n_ev[n_ev>1].index)
HT={}; HS={}
for r in H.itertuples():
    if (r.event_id,r.ty) in bad: continue
    (HT if r.ty=='HALF_TIME' else HS)[r.event_id]=r.sel
# an MO winner per event, to settle DNB: void at a draw, a DNB market holds no winner then
MOW={r.event_id:r.sel for r in R[(R.ty=='MATCH_ODDS')&(R.status=='WINNER')&R.market_id.isin(ok)].itertuples()}
print("official markets",len(RS),"HT",len(HT),"HTS",len(HS),"MO winners",len(MOW),f"{time.time()-T0:.0f}s",flush=True); del R,H
C=Counter(); rows=[]
def add(pair,off,ev,grp,g,ts,px,i,won):
    """One signal on the traded leg at print i. won: True, False, None for a void. Both sides at each G; the largest gap per game per line is kept later."""
    for G in GS:
        k=kind(g,G)
        if k is None: continue
        L=fill(ts,px,i,'L'); B=fill(ts,px,i,'B')
        lv=None if L>50 else settle('L',step(L,1),won); lv3=None if L>50 else settle('L',step(L,3),won)
        a1=step(B,-1); a3=step(B,-3)
        bv=None if (B>50 or a1<=1.01) else settle('B',a1,won); bv3=None if (B>50 or a3<=1.01) else settle('B',a3,won)
        rows.append((pair,G,k,off,ev,grp,abs(g),lv,bv,lv3,bv3,float(ts[i])))
def chunks():
    for y,m in [(2023,x) for x in range(6,13)]+[(2024,x) for x in range(1,12)]+[(2026,x) for x in range(5,11)]:
        a=pd.Timestamp(y,m,1); e=a+pd.offsets.MonthBegin(1)
        if (y,m)>=(2026,8):
            while a<e:
                b=min(a+pd.Timedelta(days=5),e); yield str(a.date()),str(b.date()); a=b
        else: yield str(a.date()),str(e.date())
for lo,hi in chunks():
    F=pd.read_sql("SELECT market_id,market_time mt,min(ts) f FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND inplay AND ts>=market_time-interval '30 minutes' AND ts<=market_time+interval '60 minutes' AND market_time>=%s AND market_time<%s GROUP BY 1,2",con,params=(lo,hi))
    late=set(F.market_id[(secs(F.f)-secs(F.mt))>240]); ontime=set(F.market_id)-late; C['MO late off']+=len(late); del F
    X=pd.read_sql("SELECT market_id,event_id eid,event_name ev,market_type ty,market_time mt,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type=ANY(%s) AND inplay AND ltp>=1.01 AND ltp<1000 AND ts>=market_time+interval '47 minutes' AND ts<=market_time+interval '62 minutes' AND market_time>=%s AND market_time<%s",con,params=(TY,lo,hi))
    if X.empty: print(lo,"no rows",flush=True); continue
    X['tt']=secs(X.ts); X['off']=secs(X.mt); X=X.sort_values('tt',kind='stable').drop_duplicates(['market_id','sel','tt']); ng=0
    for (eid,ev,off),G_ in X.groupby(['eid','ev','off'],sort=False):
        if ' v ' not in ev: C['no H v A']+=1; continue
        B={}
        for ty,g in G_.groupby('ty',sort=False):
            mk=sorted(g.market_id.unique())[0]
            B[ty]=(mk,{s:(y.tt.values,y.ltp.values) for s,y in g[g.market_id==mk].groupby('sel',sort=False)})
        if 'MATCH_ODDS' not in B: C['no MO print in the break']+=1; continue
        mo_id,MO=B['MATCH_ODDS']
        if mo_id not in ontime: C['MO not on time']+=1; continue
        if eid not in HT: C['no official HT']+=1; continue
        ng+=1; grp=group(ev) or 'SENIOR'; h,a=ev.split(' v ',1); x=nm(HT[eid]); moname={h:h,a:a,'Draw':'The Draw'}
        wmo=MOW.get(eid)
        lo_,hi_=off+WIN0,off+WIN1
        def legs(ty,sel):
            if ty not in B or sel not in B[ty][1]: return None
            ts,px=B[ty][1][sel]; i0=int(np.searchsorted(ts,lo_,side='left')); i1=int(np.searchsorted(ts,hi_,side='right'))
            return (ts,px,i0,i1) if i1>i0 else None
        def mo_at(f,t):
            s=moname[f]
            return None if s not in MO else older(MO[s][0],MO[s][1],t)
        # 407: X/F on HT/FT v F on MO
        if 'HALF_TIME_FULL_TIME' in B:
            mk=B['HALF_TIME_FULL_TIME'][0]; rs=RS.get(mk)
            for f in (h,a,'Draw'):
                sel=f"{x}/{f}"; L=legs('HALF_TIME_FULL_TIME',sel)
                if L is None: C['HTFT no print on the runner']+=1; continue
                if rs is None or sel not in rs: C['HTFT no official']+=1; continue
                ts,px,i0,i1=L
                for i in range(i0,i1):
                    p=mo_at(f,ts[i])
                    if p is None: C['HTFT MO stale']+=1; continue
                    C['HTFT read']+=1; add('HTFT',off,ev,grp,gap_pts(float(px[i]),imp_mo(p)),ts,px,i,bool(rs[sel]))
        # 408: DC runner v 1 - implied MO of the runner left out
        if 'DOUBLE_CHANCE' in B:
            mk=B['DOUBLE_CHANCE'][0]; rs=RS.get(mk)
            for sel,out in (('Home or Draw',a),('Draw or Away',h),('Home or Away','Draw')):
                L=legs('DOUBLE_CHANCE',sel)
                if L is None: C['DC no print on the runner']+=1; continue
                if rs is None or sel not in rs: C['DC no official']+=1; continue
                ts,px,i0,i1=L
                for i in range(i0,i1):
                    p=mo_at(out,ts[i])
                    if p is None or p<=1.0: C['DC MO stale']+=1; continue
                    C['DC read']+=1; add('DC',off,ev,grp,gap_pts(float(px[i]),imp_dc(p)),ts,px,i,bool(rs[sel]))
        # 408: DNB, settled from the official MO winner, void at a draw
        if 'DRAW_NO_BET' in B and wmo is not None:
            for f,o in ((h,a),(a,h)):
                L=legs('DRAW_NO_BET',f)
                if L is None: C['DNB no print on the runner']+=1; continue
                ts,px,i0,i1=L
                won=None if wmo=='The Draw' else (wmo==f)
                for i in range(i0,i1):
                    p1=mo_at(f,ts[i]); p2=mo_at(o,ts[i])
                    if p1 is None or p2 is None: C['DNB MO stale']+=1; continue
                    C['DNB read']+=1; add('DNB',off,ev,grp,gap_pts(float(px[i]),imp_dnb(p1,p2)),ts,px,i,won)
        # 408: at an official 0-0 half-time, goal lines v CS
        if HS.get(eid)=='0 - 0':
            def cs_at(sel,t):
                if 'CORRECT_SCORE' not in B or sel not in B['CORRECT_SCORE'][1]: return None
                return older(B['CORRECT_SCORE'][1][sel][0],B['CORRECT_SCORE'][1][sel][1],t)
            def ou_at(ty,sel,t):
                if ty not in B or sel not in B[ty][1]: return None
                return older(B[ty][1][sel][0],B[ty][1][sel][1],t)
            for pair,ty,sel,others in (('U05','OVER_UNDER_05',U05,[('CORRECT_SCORE','0 - 0')]),
                                       ('CS00','CORRECT_SCORE','0 - 0',[('OVER_UNDER_05',U05)]),
                                       ('U15','OVER_UNDER_15',U15,[('CORRECT_SCORE','0 - 0'),('CORRECT_SCORE','1 - 0'),('CORRECT_SCORE','0 - 1')])):
                L=legs(ty,sel)
                if L is None: C[pair+' no print']+=1; continue
                rs=RS.get(B[ty][0])
                if rs is None or sel not in rs: C[pair+' no official']+=1; continue
                ts,px,i0,i1=L
                for i in range(i0,i1):
                    vals=[(cs_at(s,ts[i]) if t=='CORRECT_SCORE' else ou_at(t,s,ts[i])) for t,s in others]
                    if any(v is None for v in vals): C[pair+' other side stale']+=1; continue
                    C[pair+' read']+=1; add(pair,off,ev,grp,gap_pts(float(px[i]),sum(1/v for v in vals)),ts,px,i,bool(rs[sel]))
    print(lo,"rows",len(X),"games",ng,"cands",len(rows),f"{time.time()-T0:.0f}s",flush=True); del X
con.close()
print("counts",dict(sorted(C.items())),flush=True)
T=pd.DataFrame(rows,columns=['pair','G','kind','off','ev','grp','abs_gap','layv','backv','lay3','back3','sig'])
if T.empty: print("no signals\nSURVIVORS\nnone"); sys.exit(0)
# first qualifying print per game per line: the first run kept the largest gap in the window, which a trader cannot know at the time (item 410)
T=T.sort_values('sig',kind='stable').drop_duplicates(['pair','G','kind','off','ev'])
med=T.off.median(); T['h']=np.where(T.off<=med,1,2); print("halves split at",pd.Timestamp(med,unit='s',tz='UTC'),"games with a signal",T[['off','ev']].drop_duplicates().shape[0],flush=True)
print("signals by group, G2"); print(T[T.G==2].groupby(['pair','grp']).size().to_string())
out=[];ctl=[]
for (p,G,k),x in T.groupby(['pair','G','kind']):
    for scored,col,c3,side in ((k=='CHEAP','backv','back3','back'),(k=='DEAR','layv','lay3','lay')):
        y=x[x[col].notna()]; y=y.assign(**{col:y[col].astype(float)})
        if len(y)<2: continue
        d=line(y[col].values,y.h.values); v=y[col].values; xl=np.delete(v,v.argmax()).mean()
        s3=pd.to_numeric(y[c3],errors='coerce').mean()
        r=dict(line=f"{p} G{G} {k} {side}",n=d['n'],per10=round(d['per10'],3),t=round(d['t'],2),h1=round(d['h1'],3),h2=round(d['h2'],3),n1=d['n1'],n2=d['n2'],no_top=round(xl,3),ticks3=round(s3,3),gap=round(y.abs_gap.median(),1),PASS=d['PASS'])
        (out if scored else ctl).append(r)
O=pd.DataFrame(out).sort_values('t',ascending=False); K=pd.DataFrame(ctl).sort_values('t',ascending=False)
print("scored lines",len(O)); print(O.to_string(index=False))
print("control, swapped sides, not scored"); print(K.head(10).to_string(index=False))
print("SURVIVORS"); S=O[O.PASS]; print(S.to_string(index=False) if len(S) else "none",flush=True)
print(f"total {time.time()-T0:.0f}s")
PY
