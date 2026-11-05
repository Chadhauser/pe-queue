#!/bin/bash
set -o pipefail
# 499_oct24_rules (Finder 2026-11-05, queue items 145, 146, 162; from jobs/499_longtail_late.sh, jobs/499_xmarket_official.sh, jobs/499_fav_move_follow_unseen.sh): three rules fixed earlier, read on Oct 2024, a month none of them chose. Rules pushed before any Oct 2024 price was read (commit e987e9e). No new cuts. Read only.
# 145 S_THIN OU25 T95 1.15-1.40 back, as item 143, cuts 8, 20 from that job's log. 146 BTTS 0.02 CHEAP_OVER BACK_CHEAP, as item 142, residual less the walk-forward mean of the previous 300 Oct 2024 games, first 300 not traded. 162 FAV SHORT back, as item 161, senior, early print T-180 to T-60, entry T-20 to T-2, but official results as goal_timeline starts Jul 2026.
# Each item's queue rule says score once n >= 300: a smaller n here is an interim read and the item stays open. Prints only: a pass is an upper bound. Halves by date inside the month.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(3_500_000_000,3_500_000_000))  # this job only
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import deque,Counter
from scipy.optimize import minimize
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,norm,jac
from lib_official import group,bk,ly,fill,first_in,last_in,secs,load_results,checks
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',250); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',40)
T0=time.time(); LO,HI='2024-10-01','2024-11-01'; C1,C2=8,20
FH=0.45; N=11; I=np.arange(N); WARM=300; F_=np.cumprod(np.r_[1.,np.arange(1,N)])
def shortest(rows):
    rows=sorted(rows,key=lambda r:r[1]); return None if len(rows)<2 or rows[0][1]==rows[1][1] else rows[0][0]
def band(p): return '<1.15' if p<1.15 else '1.15-1.40' if p<1.40 else '1.40-2.00' if p<2.0 else None
def mo_pair(home,away,runners):
    r=[x for x in runners if str(x).strip().lower()!='the draw']
    if len(r)!=2: return None
    H,A,a,b=norm(home),norm(away),norm(r[0]),norm(r[1])
    s1,s2=jac(a,H)+jac(b,A),jac(a,A)+jac(b,H)
    if s1==s2: return None
    x,y=(r[0],r[1]) if s1>s2 else (r[1],r[0])
    if not (norm(x)&H and norm(y)&A): return None
    return x,y
def mv(entry,early):
    r=entry/early
    return 'SHORT' if r<=0.90 else 'DRIFT' if r>=1.10 else None
def pmf(l): return np.exp(-l)*l**I/F_
def probs(lh,la):
    M=np.outer(pmf(lh),pmf(la)); M=M/M.sum(); S=I[:,None]+I[None,:]
    o=lambda k:M[S>k].sum()
    return dict(H=np.tril(M,-1).sum(),D=np.trace(M),A=np.triu(M,1).sum(),OU25=o(2),BTTS=M[1:,1:].sum())
def fit(h,d,a,ov):
    def f(x):
        p=probs(np.exp(x[0]),np.exp(x[1])); return (p['H']-h)**2+(p['D']-d)**2+(p['A']-a)**2+(p['OU25']-ov)**2
    r=minimize(f,[np.log(1.4),np.log(1.1)],method='Nelder-Mead',options=dict(xatol=1e-3,fatol=1e-7,maxiter=200))
    return float(np.exp(r.x[0])),float(np.exp(r.x[1])),float(r.fun)
def nrm(a,b): return (1/a)/(1/a+1/b)
# known answers, as the source jobs
assert shortest([('a',1.2),('b',3.0)])=='a' and shortest([('a',2.0),('b',2.0)]) is None and shortest([('a',2.0)]) is None
assert band(1.14)=='<1.15' and band(1.15)=='1.15-1.40' and band(1.40)=='1.40-2.00' and band(2.0) is None
assert mv(1.8,2.0)=='SHORT' and mv(1.82,2.0) is None and mv(2.2,2.0)=='DRIFT' and mv(2.18,2.0) is None
_p=probs(1.0,1.0); assert abs(_p['H']-_p['A'])<1e-9 and abs(_p['BTTS']-(1-np.exp(-1))**2)<1e-5
_x=probs(1.7,0.9); _f=fit(_x['H'],_x['D'],_x['A'],_x['OU25']); assert abs(_f[0]-1.7)<0.02 and abs(_f[1]-0.9)<0.02 and _f[2]<1e-5
assert abs(nrm(1.5,3.0)-2/3)<1e-9 and mo_pair('Hull','Leeds',['Leeds','Hull'])==('Hull','Leeds')
print("checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
TY=['MATCH_ODDS','OVER_UNDER_25','OVER_UNDER_35','BOTH_TEAMS_TO_SCORE']
cur.execute("SELECT DISTINCT market_id,event_id,event_name,market_type,market_time FROM bf_hist_other WHERE sport='Soccer' AND market_type=ANY(%s) AND market_time>=%s AND market_time<%s",(TY,LO,HI))
MK=pd.DataFrame(cur.fetchall(),columns='market_id event_id ev mty mt'.split()); MK['off']=secs(MK.mt)
RS,bad=load_results(con,TY); n0=len(MK); MK=MK[MK.market_id.isin(set(RS))].sort_values('market_id').drop_duplicates(['event_id','mty'])
print(f"Oct 2024 markets {n0}, with one WINNER and one id per event {len(MK)}, events {MK.event_id.nunique()}, {time.time()-T0:.0f}s",flush=True)
def pull(mset,where):
    parts=[]
    for i in range(0,len(mset),2000): parts.append(pd.read_sql(f"SELECT market_id,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s) AND ltp>=1.01 AND ltp<1000 AND {where}",con,params=(mset[i:i+2000],)))
    P=pd.concat(parts,ignore_index=True); P['tt']=secs(P.ts); return P.drop_duplicates(['market_id','sel','tt']).sort_values('tt',kind='stable')
def score(nm,x,cols):
    if not len(x): print(f"  {nm}: n 0"); return dict(line=nm,n=0,PASS=False)
    md=np.median(x.off.values); l=line(x.v.values,np.where(x.off<md,1,2))
    d=dict(line=nm,n=l['n'],games=x.e.nunique(),per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],won=x.won.mean(),imp=(1/x.p).mean(),PASS=l['PASS']); return d
SCORED=[]
# ---- 162, then 146 use the pre-off tape; MO T-180 on
MOx=MK[MK.mty=='MATCH_ODDS']; Pm=pull(list(MOx.market_id),"NOT inplay AND ts>=market_time-interval '180 minutes'"); PMX={k:g for k,g in Pm.groupby('market_id')}; print(f"MO pre-off rows {len(Pm)}, {time.time()-T0:.0f}s",flush=True)
liq={}; C=Counter(); rows=[]
for r in MOx.itertuples():
    o=float(r.off); g=PMX.get(r.market_id)
    if g is None: C['no pre-off print']+=1; liq[r.event_id]=0; continue
    liq[r.event_id]=int(((g.tt>=o-3600)&(g.tt<o-1200)).sum())
    if group(r.ev) is not None: C['women or youth']+=1; continue
    hm,_x,aw=r.ev.partition(' v '); pr=mo_pair(hm,aw,list(g.sel.unique()))
    if pr is None: C['runners not matched']+=1; continue
    ent={}
    for s in pr:
        y=g[g.sel==s]; ts,px=y.tt.values,y.ltp.values; i=last_in(ts,o-1200,o-120)
        if i is not None: ent[s]=(ts,px,i)
    if len(ent)<2: C['no print on both teams']+=1; continue
    hf=ent[pr[0]][1][ent[pr[0]][2]]<=ent[pr[1]][1][ent[pr[1]][2]]; fav=pr[0] if hf else pr[1]
    ts,px,i=ent[fav]; j=last_in(ts,o-10800,o-3600)
    if j is None: C['no early print']+=1; continue
    m=mv(float(px[i]),float(px[j]))
    if m is None: C['middle, no trade']+=1; continue
    if fav not in RS[r.market_id]: C['favourite has no result']+=1; continue
    side='B' if m=='SHORT' else 'L'; p=fill(ts,px,i,side)
    if p>50: C['over 50']+=1; continue
    won=RS[r.market_id][fav]; v=bk(p,won) if side=='B' else ly(p,won)
    if v is None: C['bottom of ladder, no back']+=1; continue
    rows.append((r.event_id,o,m,won,p,v))
print("162 counted:",dict(sorted(C.items())),flush=True)
R=pd.DataFrame(rows,columns='e off m won p v'.split()); assert R.e.is_unique
A=score('162 FAV SHORT back (scored)',R[R.m=='SHORT'],None); B=score('162 FAV DRIFT lay (context)',R[R.m=='DRIFT'],None); SCORED.append(A); print(pd.DataFrame([A,B]).round(3).to_string(index=False),flush=True)
del Pm,PMX
# ---- 146
Tm={'MATCH_ODDS':'MO','OVER_UNDER_25':'OU25','BOTH_TEAMS_TO_SCORE':'BTTS'}; Mx=MK[MK.mty.isin(Tm)]
Px=pull(list(Mx.market_id),"NOT inplay AND ts>=market_time-interval '21 min'"); PX={k:g for k,g in Px.groupby('market_id')}; print(f"146 rows {len(Px)}, {time.time()-T0:.0f}s",flush=True); del Px
SK=Counter(); rec=[]
for e,g in Mx.groupby('event_id'):
    ev=g.ev.iloc[0]; home,_x,away=ev.partition(' v '); E={}
    for r in g.itertuples():
        x=PX.get(r.market_id)
        if x is None: continue
        o=float(r.off)
        for s,y in x.groupby('sel',sort=False):
            if s not in RS[r.market_id]: continue
            ts,px=y.tt.values,y.ltp.values; i=last_in(ts,o-1200,o-120)
            if i is None: continue
            sl=str(s).strip().lower(); tag=sl.split()[0] if sl.split() else sl
            E[(Tm[r.mty],s if Tm[r.mty]=='MO' else tag)]=(ts,px,i,RS[r.market_id][s])
    if not all(k in E for k in (('MO',home),('MO',away),('MO','The Draw'),('OU25','over'),('OU25','under'))): SK['no MO or OU25 at entry']+=1; continue
    pr=lambda k:float(E[k][1][E[k][2]])
    ih,idr,ia=1/pr(('MO',home)),1/pr(('MO','The Draw')),1/pr(('MO',away)); z=ih+idr+ia
    if not 0.95<z<1.15: SK['MO book out of 0.95-1.15']+=1; continue
    lh,la,err=fit(ih/z,idr/z,ia/z,nrm(pr(('OU25','over')),pr(('OU25','under'))))
    if err>0.002: SK['fit error over 0.002']+=1; continue
    rec.append(dict(e=e,off=float(g.off.iloc[0]),M=probs(lh,la),E=E))
print(f"146 fitted {len(rec)}; {dict(SK)}; {time.time()-T0:.0f}s",flush=True)
rec.sort(key=lambda r:r['off']); BUF=deque(maxlen=WARM); rows=[]; rs=Counter(); i=0
while i<len(rec):
    j=i
    while j<len(rec) and rec[j]['off']==rec[i]['off']: j+=1
    add=[]
    for r in rec[i:j]:
        E=r['E']
        if ('BTTS','yes') not in E or ('BTTS','no') not in E: rs['BTTS no pair']+=1; continue
        a,b=E[('BTTS','yes')],E[('BTTS','no')]; raw=nrm(float(a[1][a[2]]),float(b[1][b[2]]))-r['M']['BTTS']; add.append(raw)
        if len(BUF)<WARM: rs['warm-up']+=1; continue
        rr=raw-float(np.mean(BUF))
        if rr<=-0.02:
            pb=fill(a[0],a[1],a[2],'B'); v=bk(pb,a[3])
            if v is not None: rows.append((r['e'],r['off'],a[3],pb,v))
    BUF.extend(add); i=j
print("146 counts:",dict(rs),flush=True)
R=pd.DataFrame(rows,columns='e off won p v'.split()); A=score('146 BTTS 0.02 CHEAP back Yes (scored)',R,None); SCORED.append(A); print(pd.DataFrame([A]).round(3).to_string(index=False),flush=True)
del PX
# ---- 145
Lx=MK[MK.mty.isin(['MATCH_ODDS','OVER_UNDER_25','OVER_UNDER_35'])]; TL={'MATCH_ODDS':'MO','OVER_UNDER_25':'OU25','OVER_UNDER_35':'OU35'}
Pi=pull(list(Lx.market_id),"inplay"); PI={k:g for k,g in Pi.groupby('market_id')}; print(f"145 in-play rows {len(Pi)}, {time.time()-T0:.0f}s",flush=True); del Pi; con.close()
SK=Counter(); rows=[]
for r in Lx.itertuples():
    x=PI.get(r.market_id); k=TL[r.mty]
    if x is None: SK[k+' no in-play print']+=1; continue
    o=float(r.off); lo,hi=o+95*60,o+100*60
    win=x[(x.tt>=lo)&(x.tt<=hi)]
    if not len(win): SK[f'{k} T95 no print in window']+=1; continue
    tf=float(win.tt.iloc[0]); seen=x[(x.tt<=tf)&(x.tt>=tf-300)].groupby('sel',sort=False).ltp.last(); s=shortest(list(seen.items()))
    if s is None or s not in RS[r.market_id]: SK[f'{k} T95 no shortest runner']+=1; continue
    y=x[x.sel==s]; ts,px=y.tt.values,y.ltp.values; i=first_in(ts,tf,hi)
    if i is None: SK[f'{k} T95 shortest has no print in window']+=1; continue
    b=band(float(px[i]))
    if b is None: SK['outside the bands']+=1; continue
    won=RS[r.market_id][s]; grp=group(r.ev); lq=liq.get(r.event_id,0)
    g_=grp if isinstance(grp,str) else ('S_THIN' if lq<=C1 else 'S_MID' if lq<=C2 else 'S_DEEP')
    p=fill(ts,px,i,'B'); v=bk(p,won)
    if v is None: SK['bottom of ladder, no back']+=1; continue
    rows.append((r.event_id,o,g_,k,b,won,p,v))
print("145 counted:",dict(sorted(SK.items())),flush=True)
R=pd.DataFrame(rows,columns='e off g k b won p v'.split()); out=[]
for key,x in R.groupby(['g','k','b']): out.append(score(f"{key[0]} {key[1]} T95 {key[2]} back",x,None))
O=pd.DataFrame(out); print("\n145, all T95 back lines, context except the first named below:"); print(O.sort_values('t',ascending=False).round(3).to_string(index=False))
x=R[(R.g=='S_THIN')&(R.k=='OU25')&(R.b=='1.15-1.40')]; A=score('145 S_THIN OU25 T95 1.15-1.40 back (scored)',x,None); SCORED.append(A)
print("\n== the three scored lines, Oct 2024"); O=pd.DataFrame(SCORED); print(O.round(3).to_string(index=False))
S=O[O.PASS==True]; print(f"\n== SURVIVORS: {len(S)} of {len(O)}\n",S.round(3).to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
