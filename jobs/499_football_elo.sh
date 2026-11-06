#!/bin/bash
set -o pipefail
# 499_football_elo (Finder 2026-11-06, queue item 186, Finder's own, source b): walk-forward football Elo (Hvattum and Arntzen, formula from memory, not checked) against the exchange's first in-play print. Rule pushed before prices were read (commit 91a70c9). The number 499 is reused: 450-499 are all taken.
# ELO af_fixtures 2016 on, 27 competitions, start 1500, home advantage 65, K = 10 x (1 + goal difference). No promoted-side prior, so a promoted side starts at its own Elo or 1500.
# MAP ordered logit, Elo gap to H/D/A, fit only on kick-offs before 2024-01-01 with both teams on >= 20 games, frozen before any price is read.
# ENTRY and guards as jobs/499_rest_gap.sh: earliest real print tape minutes 0..2; lag outside -5..+20 min dropped; a goal with af minute before the print minute dropped. One tick adverse, 2%, £10 risk, hold to FT. Halves are seasons 2024 v 2025. LTP only, so a pass is an upper bound. Neutral-venue UEFA finals get home advantage they did not have, in the fit and in any trade the tape holds; a handful of games, not removed.
# SUPPORT fd_matches' own Elo at Pinnacle closes, map fit before 2016-07-01, scored 2016-07 to 2024-06. Not a fill on the exchange, cannot pass. A lay there collects Pinnacle's margin, so read the back column.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,math,psycopg2,pandas as pd,numpy as np
from scipy.optimize import minimize
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,back_settle,lay_settle,line,tstat
pd.set_option('display.width',240); pd.set_option('display.max_rows',120); pd.set_option('display.max_columns',30)
T0=time.time(); H=65.0; START=1500.0; MINGAMES=20
CUTS=(0.03,0.05,0.08); SELS=('HOME','DRAW','AWAY')
def bk(x,won):
    a=step(x,-1); return None if a<=1.01 else back_settle(a,won)
def ly(x,won): return lay_settle(step(x,1),won)
def elo_e(rh,ra): return 1/(1+10**(-(rh+H-ra)/400))
def elo_update(rh,ra,hg,ag):
    s=1.0 if hg>ag else 0.0 if ag>hg else 0.5
    d=10*(1+abs(hg-ag))*(s-elo_e(rh,ra)); return rh+d,ra-d
def walk(rows):
    """rows: (id,seconds,home,away,hg,ag) with hg None when not played. {id:(gap,games_home,games_away)}, gap=(rh+H-ra)/400 BEFORE this game. Only earlier kick-offs feed it."""
    R={};N={};out={}
    for i,t,h,a,hg,ag in sorted(rows,key=lambda z:z[1]):
        rh,ra=R.get(h,START),R.get(a,START); out[i]=((rh+H-ra)/400,N.get(h,0),N.get(a,0))
        if hg is not None:
            R[h],R[a]=elo_update(rh,ra,hg,ag); N[h]=N.get(h,0)+1; N[a]=N.get(a,0)+1
    return out
def Lg(x): return 1/(1+np.exp(-x))
def fit_ol(gap,y):
    """Ordered logit. y 0 away, 1 draw, 2 home. P(y<=0)=F(c1-b g), P(y<=1)=F(c2-b g). Returns (c1,c2,b)."""
    gap=np.asarray(gap,float); y=np.asarray(y,int)
    def nll(p):
        c1,d,b=p; c2=c1+math.exp(d)
        f1,f2=Lg(c1-b*gap),Lg(c2-b*gap); q=np.where(y==0,f1,np.where(y==1,f2-f1,1-f2))
        return -np.log(np.clip(q,1e-12,1)).sum()
    r=minimize(nll,[-0.5,0.0,1.0],method='Nelder-Mead',options=dict(maxiter=4000,xatol=1e-4,fatol=1e-3))
    return r.x[0],r.x[0]+math.exp(r.x[1]),r.x[2]
def ol_p(m,g):
    c1,c2,b=m; f1,f2=float(Lg(c1-b*g)),float(Lg(c2-b*g)); return {'HOME':1-f2,'DRAW':f2-f1,'AWAY':f1}
def picks(edge):
    """edge {sel:model-market}. Yields (cut,'BACK'|'LAY',label,sel), one per label. BEST is the largest edge for a back, the smallest for a lay."""
    out=[]; hi=max(edge,key=edge.get); lo=min(edge,key=edge.get)
    for c in CUTS:
        for s,e in edge.items():
            if e>=c: out.append((c,'BACK',s,s))
            if e<=-c: out.append((c,'LAY',s,s))
        if edge[hi]>=c: out.append((c,'BACK','BEST',hi))
        if edge[lo]<=-c: out.append((c,'LAY','BEST',lo))
    return out
# known answers, worked by hand
assert abs(elo_e(1500,1500)-1/(1+10**(-65/400)))<1e-12 and abs(elo_e(1500,1500)-0.59249)<1e-4
a,b=elo_update(1500,1500,1,0); assert abs(a-(1500+20*(1-0.59249)))<1e-2 and abs((a-1500)+(b-1500))<1e-9      # K 20, gain 8.15, zero sum
a,b=elo_update(1500,1500,0,0); assert abs(a-(1500+10*(0.5-0.59249)))<1e-2                                     # draw at home costs 0.92
a,b=elo_update(1500,1500,0,3); assert abs(a-(1500-40*0.59249))<1e-2                                           # K 40 on a three-goal defeat
w=walk([(2,200,'A','B',None,None),(1,100,'A','B',2,0)]); assert w[1]==(65/400,0,0) and w[2][1]==1 and w[2][0]>65/400 # order by time, not by list, and an unplayed game feeds nothing
w=walk([(1,100,'A','B',None,None),(2,200,'A','B',1,0)]); assert w[2]==(65/400,0,0)
_m=(-1.0,0.2,1.0); _p=ol_p(_m,0.0); assert abs(sum(_p.values())-1)<1e-12 and abs(_p['AWAY']-1/(1+math.e))<1e-9 and _p['HOME']>0
_r=np.random.default_rng(1); _g=_r.normal(0.1,0.4,6000); _u=_r.logistic(size=6000)+1.2*_g; _y=np.where(_u<-0.8,0,np.where(_u<0.3,1,2)); _f=fit_ol(_g,_y)
assert abs(_f[2]-1.2)<0.15 and abs(_f[0]+0.8)<0.1 and abs(_f[1]-0.3)<0.1,_f                                     # recovers a known map
_e={'HOME':0.06,'DRAW':-0.01,'AWAY':-0.05}; _k=picks(_e)
assert (0.03,'BACK','HOME','HOME') in _k and (0.05,'BACK','BEST','HOME') in _k and (0.08,'BACK','BEST','HOME') not in _k and (0.05,'LAY','AWAY','AWAY') in _k and (0.05,'LAY','BEST','AWAY') in _k and (0.03,'BACK','DRAW','DRAW') not in _k
assert abs(bk(2.04,True)-9.996)<1e-9 and bk(2.04,False)==-10.0 and ly(2.0,True)==-10.0 and abs(ly(2.0,False)-10/1.02*.98)<1e-9
print("checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
F=pd.read_sql("SELECT fixture_id,kickoff,home,away,hg,ag,status,season FROM af_fixtures WHERE kickoff IS NOT NULL AND season>=2016",con)
print("status",F.status.value_counts().head(8).to_dict(),flush=True)
F=F[F.status.isin(['FT','AET','PEN'])&F.hg.notna()&F.ag.notna()].copy(); F['ks']=pd.to_datetime(F.kickoff,utc=True).map(lambda t:int(t.timestamp()))
W=walk([(r.fixture_id,r.ks,r.home,r.away,int(r.hg),int(r.ag)) for r in F.itertuples()])
F['gap']=F.fixture_id.map(lambda i:W[i][0]); F['nh']=F.fixture_id.map(lambda i:W[i][1]); F['na']=F.fixture_id.map(lambda i:W[i][2]); F['y']=np.where(F.hg>F.ag,2,np.where(F.hg<F.ag,0,1))
CUT=int(pd.Timestamp('2024-01-01',tz='UTC').timestamp()); Tr=F[(F.ks<CUT)&(F.nh>=MINGAMES)&(F.na>=MINGAMES)]
M=fit_ol(Tr.gap.values,Tr.y.values); print(f"fixtures {len(F)}; map fit on {len(Tr)} games before 2024-01-01: c1 {M[0]:.3f} c2 {M[1]:.3f} b {M[2]:.3f}; base rates H {np.mean(Tr.y==2):.3f} D {np.mean(Tr.y==1):.3f} A {np.mean(Tr.y==0):.3f} | {time.time()-T0:.0f}s",flush=True)
G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.league,f.season,f.kickoff,f.hg,f.ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.season IN (2024,2025)""",con)
EV=pd.read_sql("SELECT fixture_id,min(coalesce(minute,0)) gm FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal') AND coalesce(minute,0)<=2 GROUP BY 1",con,params=(list(map(int,G.fixture_id)),))
first_goal=dict(zip(EV.fixture_id,EV.gm)); parts=[]
for i in range(0,len(G),1000):
    P=pd.read_sql("SELECT event_id,sel,minute,m,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt='MO' AND sel IN ('HOME','DRAW','AWAY') AND minute>=0 AND minute<=2 AND ltp>=1.01 AND ltp<1000",con,params=(list(G.event_id.iloc[i:i+1000]),))
    parts.append(P.sort_values(['event_id','sel','minute','m']).drop_duplicates(['event_id','sel']))
    print(f"  {min(i+1000,len(G))}/{len(G)} {time.time()-T0:.0f}s",flush=True)
P=pd.concat(parts,ignore_index=True).merge(G,on='event_id')
P['lag']=(pd.to_datetime(P.m,utc=True)-pd.to_datetime(P.kickoff,utc=True)).dt.total_seconds()/60
bad=(P.lag<-5)|(P.lag>20); gm=P.fixture_id.map(first_goal); kn=gm.notna()&(gm<P.minute)
print(f"games with a print {P.event_id.nunique()}; rows dropped, lag {int(bad.sum())}, goal known before the print {int(kn.sum())}",flush=True); P=P[~bad&~kn]
rows=[];ctrl=[];LL=[];sk={'not three prints':0,'under 20 games':0,'no elo':0}
for (e,fx,lg,s,hg,ag),x in P.groupby(['event_id','fixture_id','league','season','hg','ag']):
    pr=dict(zip(x.sel,x.ltp))
    if len(pr)!=3: sk['not three prints']+=1; continue
    if fx not in W: sk['no elo']+=1; continue
    g,nh,na=W[fx]
    if nh<MINGAMES or na<MINGAMES: sk['under 20 games']+=1; continue
    res='HOME' if hg>ag else 'AWAY' if ag>hg else 'DRAW'; tot=sum(1/v for v in pr.values()); mk={k:(1/v)/tot for k,v in pr.items()}; mo=ol_p(M,g); ed={k:mo[k]-mk[k] for k in SELS}
    LL.append((s,-math.log(mo[res]),-math.log(mk[res])))
    for k in SELS:
        v=bk(pr[k],res==k)
        if v is not None: ctrl.append((k,'BACK',s,fx,v))
        ctrl.append((k,'LAY',s,fx,ly(pr[k],res==k)))
    for c,side,lab,sel in picks(ed):
        v=bk(pr[sel],res==sel) if side=='BACK' else ly(pr[sel],res==sel)
        if v is not None: rows.append((c,side,lab,sel,s,fx,lg,pr[sel],res==sel,mo[sel],v))
print("skipped",sk,flush=True)
R=pd.DataFrame(rows,columns='cut side lab sel season fx league x won model v'.split()); assert not R.duplicated(['cut','side','lab','fx']).any(),"more than one bet per game per line"
print(f"trades {len(R)} games {R.fx.nunique()} {time.time()-T0:.0f}s",flush=True)
L=pd.DataFrame(LL,columns=['s','model','market']); print("\n== log loss per game, lower is better"); print(L.groupby('s').agg(n=('model','size'),model=('model','mean'),market=('market','mean')).round(4).to_string()); print(f"all: model {L.model.mean():.4f} market {L.market.mean():.4f}, t of the difference {tstat((L.market-L.model).values):.2f}")
C=pd.DataFrame(ctrl,columns='sel side season fx v'.split()); out=[]
for k,x in C.groupby(['side','sel']):
    l=line(x.v.values,np.where(x.season==2024,1,2)); out.append(dict(side=k[0],sel=k[1],n=l['n'],per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2']))
print("\n== control, every runner, not counted as a line"); print(pd.DataFrame(out).round(3).to_string(index=False))
out=[]
for k,x in R.groupby(['cut','side','lab']):
    l=line(x.v.values,np.where(x.season==2024,1,2)); out.append(dict(cut=k[0],side=k[1],sel=k[2],n=l['n'],games=x.fx.nunique(),per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2'],n1=l['n1'],n2=l['n2'],won=x.won.mean(),implied=(1/x.x).mean(),model=x.model.mean(),maxwin=l['maxwin'],PASS=l['PASS']))
O=pd.DataFrame(out).sort_values('t',ascending=False); print(f"\n== ALL {len(O)} LINES, per £10, by t"); print(O.round(3).to_string(index=False))
# support: fd_matches' own Elo at Pinnacle closes
D=pd.read_sql("SELECT div,date,home,away,fthg,ftag,psch::float psch,pscd::float pscd,psca::float psca FROM fd_matches WHERE fthg IS NOT NULL AND ftag IS NOT NULL",con); con.close()
D['t']=pd.to_datetime(D.date,utc=True); assert D.t.dt.year.between(2006,2027).all(),"fd date parse"
D['ks']=D.t.map(lambda t:int(t.timestamp())); D['i']=range(len(D))
Wd=walk([(r.i,r.ks,r.home,r.away,int(r.fthg),int(r.ftag)) for r in D.itertuples()])
D['gap']=D.i.map(lambda i:Wd[i][0]); D['nh']=D.i.map(lambda i:Wd[i][1]); D['na']=D.i.map(lambda i:Wd[i][2]); D['y']=np.where(D.fthg>D.ftag,2,np.where(D.fthg<D.ftag,0,1))
c1=pd.Timestamp('2016-07-01',tz='UTC'); c2=pd.Timestamp('2024-07-01',tz='UTC'); Tf=D[(D.t<c1)&(D.nh>=MINGAMES)&(D.na>=MINGAMES)]; Md=fit_ol(Tf.gap.values,Tf.y.values)
print(f"\n== SUPPORT fd_matches: map fit on {len(Tf)} games before 2016-07: c1 {Md[0]:.3f} c2 {Md[1]:.3f} b {Md[2]:.3f}; scored 2016-07 to 2024-06 at Pinnacle closes, exact price, 2%, not a fill",flush=True)
Sc=D[(D.t>=c1)&(D.t<c2)&(D.nh>=MINGAMES)&(D.na>=MINGAMES)&(D.psch>1)&(D.pscd>1)&(D.psca>1)]; rows=[]; LL=[]
for r in Sc.itertuples():
    pr={'HOME':r.psch,'DRAW':r.pscd,'AWAY':r.psca}; res={2:'HOME',1:'DRAW',0:'AWAY'}[r.y]; tot=sum(1/v for v in pr.values()); mk={k:(1/v)/tot for k,v in pr.items()}; mo=ol_p(Md,r.gap); ed={k:mo[k]-mk[k] for k in SELS}
    LL.append((-math.log(mo[res]),-math.log(mk[res])))
    for c,side,lab,sel in picks(ed):
        v=back_settle(pr[sel],res==sel) if side=='BACK' else lay_settle(pr[sel],res==sel)
        rows.append((c,side,lab,r.t,v))
Q=pd.DataFrame(rows,columns='cut side lab t v'.split()); LL=np.array(LL); md=Q.t.median(); out=[]
print(f"games {len(Sc)}; log loss model {LL[:,0].mean():.4f} Pinnacle close {LL[:,1].mean():.4f}, t of the difference {tstat(LL[:,1]-LL[:,0]):.2f}")
for k,x in Q.groupby(['cut','side','lab']):
    l=line(x.v.values,np.where(x.t<md,1,2)); out.append(dict(cut=k[0],side=k[1],sel=k[2],n=l['n'],per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2']))
print(pd.DataFrame(out).sort_values(['side','t'],ascending=[True,False]).round(3).to_string(index=False))
S=O[O.PASS]; print("\n== SURVIVORS (bar: n>=300, n>=150 per half, both halves > 0, t>=3.5, mean>=+0.15, LTP upper bound)"); print(S.round(3).to_string(index=False) if len(S) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
