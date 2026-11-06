#!/bin/bash
set -o pipefail
# 499_team_goal_rates (Finder 2026-11-06, queue item 189, Finder's own, source b): walk-forward team goal rates (a simplified Dixon-Coles, from memory, not their likelihood fit) against Over 2.5 and BTTS at the first in-play print. Rule pushed before prices were read (commit 2e71b9a). The number 499 is reused: 450-499 are all taken.
# RATES af_fixtures 2016 on, all competitions, per team decayed goals for, against and weight, half-life 180 days, 5 pseudo-games at 1.35. Only earlier kick-offs feed a game's rates.
# MAPS logistic, fit only on kick-offs before 2024-01-01 with both teams >= 20 games, frozen before any price is read. Home advantage is left to the maps' intercepts.
# ENTRY and guards as jobs/499_rest_gap.sh: earliest real print tape minutes 0..2; lag outside -5..+20 min dropped; a goal with af minute before the print minute dropped. One tick adverse, 2%, £10 risk, hold to FT. Halves seasons 2024 v 2025. LTP only, so a pass is an upper bound.
# SUPPORT fd_matches' own rates at Pinnacle closes (raw PC>2.5, PC<2.5), map fit before 2019-07-01, scored 2019-07 to 2024-06. Not an exchange fill, cannot pass. A lay there collects Pinnacle's margin, so read the back column.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,math,psycopg2,pandas as pd,numpy as np
from scipy.optimize import minimize
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,back_settle,lay_settle,line,tstat
pd.set_option('display.width',240); pd.set_option('display.max_rows',120); pd.set_option('display.max_columns',30)
T0=time.time(); HL=180*86400.0; MU=1.35; PSEUDO=5.0; MING=20; CUTS=(0.03,0.05,0.08)
def bk(x,won):
    a=step(x,-1); return None if a<=1.01 else back_settle(a,won)
def ly(x,won): return lay_settle(step(x,1),won)
def rate(s,w): return (s+PSEUDO*MU)/(w+PSEUDO)
def walk(rows):
    """rows: (id,seconds,home,away,hg,ag). {id:(rate_home,rate_away,games_home,games_away)} from earlier kick-offs only."""
    St={};N={};out={}
    def get(t,now):
        if t not in St: return 0.0,0.0,0.0
        f,a,w,t0=St[t]; d=0.5**((now-t0)/HL); return f*d,a*d,w*d
    for i,t,h,a,hg,ag in sorted(rows,key=lambda z:z[1]):
        hf,ha,hw=get(h,t); af,aa,aw=get(a,t)
        out[i]=(rate(hf,hw)*rate(aa,aw)/MU,rate(af,aw)*rate(ha,hw)/MU,N.get(h,0),N.get(a,0))
        St[h]=(hf+hg,ha+ag,hw+1,t); St[a]=(af+ag,aa+hg,aw+1,t); N[h]=N.get(h,0)+1; N[a]=N.get(a,0)+1
    return out
def Lg(x): return 1/(1+np.exp(-x))
def fit_logit(X,y):
    """X columns without intercept. Returns coefficients, intercept first."""
    X=np.column_stack([np.ones(len(y)),np.asarray(X,float)]); y=np.asarray(y,float)
    def nll(b):
        q=np.clip(Lg(X@b),1e-12,1-1e-12); return -(y*np.log(q)+(1-y)*np.log(1-q)).sum()
    def gr(b): return -X.T@(y-Lg(X@b))
    return minimize(nll,np.zeros(X.shape[1]),jac=gr,method='BFGS').x
def p_over(m,rh,ra): return float(Lg(m[0]+m[1]*math.log(rh+ra)))
def p_btts(m,rh,ra): return float(Lg(m[0]+m[1]*math.log(rh)+m[2]*math.log(ra)))
def picks(p,xa,xb,a,b):
    """Runners a, b with prints xa, xb; p is the model's p of a. [(cut,side,runner)]: runner's edge >= cut is a back, <= -cut a lay."""
    ea=p-(1/xa)/((1/xa)+(1/xb)); out=[]
    for c in CUTS:
        if ea>=c: out+=[(c,'BACK',a),(c,'LAY',b)]
        if ea<=-c: out+=[(c,'LAY',a),(c,'BACK',b)]
    return out
# known answers, worked by hand
assert abs(rate(0,0)-1.35)<1e-12 and abs(rate(10,5)-(10+6.75)/10)<1e-12
_w=walk([(1,0,'A','B',3,1)]); assert _w[1]==(1.35,1.35,0,0)
_w=walk([(2,int(HL),'A','C',0,0),(1,0,'A','B',3,1)])                 # a half-life later, A's weights are halved: for 1.5, against 0.5, weight 0.5
assert abs(_w[2][0]-((1.5+6.75)/5.5)*1.35/1.35)<1e-9 and abs(_w[2][1]-1.35*((0.5+6.75)/5.5)/1.35)<1e-9 and _w[2][2]==1 and _w[2][3]==0
_r=np.random.default_rng(2); _x=_r.normal(0.9,0.25,8000); _y=_r.random(8000)<Lg(-1.0+1.5*_x); _f=fit_logit(_x,_y); assert abs(_f[0]+1)<0.25 and abs(_f[1]-1.5)<0.3,_f
assert abs(p_over((0.,1.),0.5,0.5)-0.5)<1e-12 and abs(p_btts((0.,1.,1.),1.,1.)-0.5)<1e-12
_k=picks(0.6,2.0,2.0,'OVER','UNDER'); assert (0.05,'BACK','OVER') in _k and (0.08,'LAY','UNDER') in _k and (0.03,'LAY','OVER') not in _k and len(_k)==6   # edge 0.10 clears all three cuts
_k=picks(0.46,2.0,2.0,'OVER','UNDER'); assert _k==[(0.03,'LAY','OVER'),(0.03,'BACK','UNDER')]                                                               # edge -0.04 clears one
assert abs(bk(2.04,True)-9.996)<1e-9 and bk(2.04,False)==-10.0 and ly(2.0,True)==-10.0 and abs(ly(2.0,False)-10/1.02*.98)<1e-9
print("checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
F=pd.read_sql("SELECT fixture_id,kickoff,home,away,hg,ag FROM af_fixtures WHERE kickoff IS NOT NULL AND season>=2016 AND status IN ('FT','AET','PEN') AND hg IS NOT NULL AND ag IS NOT NULL",con)
F['ks']=pd.to_datetime(F.kickoff,utc=True).map(lambda t:int(t.timestamp()))
W=walk([(r.fixture_id,r.ks,r.home,r.away,int(r.hg),int(r.ag)) for r in F.itertuples()])
for j,c in enumerate(('rh','ra','nh','na')): F[c]=F.fixture_id.map(lambda i:W[i][j])
CUT=int(pd.Timestamp('2024-01-01',tz='UTC').timestamp()); Tr=F[(F.ks<CUT)&(F.nh>=MING)&(F.na>=MING)]
MO=fit_logit(np.log(Tr.rh+Tr.ra),(Tr.hg+Tr.ag)>2.5); MB=fit_logit(np.column_stack([np.log(Tr.rh),np.log(Tr.ra)]),(Tr.hg>0)&(Tr.ag>0))
print(f"fixtures {len(F)}; fit on {len(Tr)}: Over {np.round(MO,3)} BTTS {np.round(MB,3)}; base Over {((Tr.hg+Tr.ag)>2.5).mean():.3f} BTTS {((Tr.hg>0)&(Tr.ag>0)).mean():.3f} | {time.time()-T0:.0f}s",flush=True)
G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.season,f.kickoff,f.hg,f.ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.season IN (2024,2025)""",con)
EV=pd.read_sql("SELECT fixture_id,min(coalesce(minute,0)) gm FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal') AND coalesce(minute,0)<=2 GROUP BY 1",con,params=(list(map(int,G.fixture_id)),))
first_goal=dict(zip(EV.fixture_id,EV.gm)); parts=[]
for i in range(0,len(G),1000):
    P=pd.read_sql("SELECT event_id,mkt,upper(sel) sel,minute,m,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt IN ('OU25','BTTS') AND minute>=0 AND minute<=2 AND ltp>=1.01 AND ltp<1000",con,params=(list(G.event_id.iloc[i:i+1000]),))
    parts.append(P.sort_values(['event_id','mkt','sel','minute','m']).drop_duplicates(['event_id','mkt','sel']))
    print(f"  {min(i+1000,len(G))}/{len(G)} {time.time()-T0:.0f}s",flush=True)
P=pd.concat(parts,ignore_index=True).merge(G,on='event_id'); print("selections",P.groupby('mkt').sel.unique().to_dict(),flush=True)
assert {'OVER','UNDER','YES','NO'}<=set(P.sel),"selection names differ"
P['lag']=(pd.to_datetime(P.m,utc=True)-pd.to_datetime(P.kickoff,utc=True)).dt.total_seconds()/60
bad=(P.lag<-5)|(P.lag>20); gm=P.fixture_id.map(first_goal); kn=gm.notna()&(gm<P.minute)
print(f"games with a print {P.event_id.nunique()}; rows dropped, lag {int(bad.sum())}, goal known before the print {int(kn.sum())}",flush=True); P=P[~bad&~kn]
rows=[];LL=[];sk={'under 20 games':0,'no rates':0}
for (e,fx,s,hg,ag),x in P.groupby(['event_id','fixture_id','season','hg','ag']):
    if fx not in W: sk['no rates']+=1; continue
    rh,ra,nh,na=W[fx]
    if nh<MING or na<MING: sk['under 20 games']+=1; continue
    pr=dict(zip(zip(x.mkt,x.sel),x.ltp)); over=hg+ag>2.5; btts=hg>0 and ag>0
    for mk,a,b,p,won_a in (('OU25','OVER','UNDER',p_over(MO,rh,ra),over),('BTTS','YES','NO',p_btts(MB,rh,ra),btts)):
        if (mk,a) not in pr or (mk,b) not in pr: continue
        xa,xb=pr[(mk,a)],pr[(mk,b)]; q=(1/xa)/((1/xa)+(1/xb)); LL.append((mk,s,-(math.log(p) if won_a else math.log(1-p)),-(math.log(q) if won_a else math.log(1-q))))
        for c,side,sel in picks(p,xa,xb,a,b):
            xs=xa if sel==a else xb; won=won_a if sel==a else not won_a
            v=bk(xs,won) if side=='BACK' else ly(xs,won)
            if v is not None: rows.append((c,side,sel,s,fx,xs,won,v))
print("skipped",sk,flush=True)
R=pd.DataFrame(rows,columns='cut side sel season fx x won v'.split()); assert not R.duplicated(['cut','side','sel','fx']).any(),"more than one bet per game per line"
print(f"trades {len(R)} games {R.fx.nunique()} {time.time()-T0:.0f}s",flush=True)
L=pd.DataFrame(LL,columns=['mk','s','model','market']); print("\n== log loss per game, lower is better"); print(L.groupby(['mk','s']).agg(n=('model','size'),model=('model','mean'),market=('market','mean')).round(4).to_string())
for mk,x in L.groupby('mk'): print(f"{mk}: t of market less model {tstat((x.market-x.model).values):.2f}")
out=[]
for k,x in R.groupby(['cut','side','sel']):
    l=line(x.v.values,np.where(x.season==2024,1,2)); out.append(dict(cut=k[0],side=k[1],sel=k[2],n=l['n'],per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2'],n1=l['n1'],n2=l['n2'],won=x.won.mean(),implied=(1/x.x).mean(),maxwin=l['maxwin'],PASS=l['PASS']))
O=pd.DataFrame(out).sort_values('t',ascending=False); print(f"\n== ALL {len(O)} LINES, per £10, by t"); print(O.round(3).to_string(index=False))
# support: fd_matches' own rates at Pinnacle closes
D=pd.read_sql("SELECT date,home,away,fthg,ftag,raw->>'PC>2.5' pco,raw->>'PC<2.5' pcu FROM fd_matches WHERE fthg IS NOT NULL AND ftag IS NOT NULL",con); con.close()
D['t']=pd.to_datetime(D.date,utc=True); D['ks']=D.t.map(lambda t:int(t.timestamp())); D['i']=range(len(D)); D['pco']=pd.to_numeric(D.pco,errors='coerce'); D['pcu']=pd.to_numeric(D.pcu,errors='coerce')
Wd=walk([(r.i,r.ks,r.home,r.away,int(r.fthg),int(r.ftag)) for r in D.itertuples()])
for j,c in enumerate(('rh','ra','nh','na')): D[c]=D.i.map(lambda i:Wd[i][j])
c1=pd.Timestamp('2019-07-01',tz='UTC'); c2=pd.Timestamp('2024-07-01',tz='UTC'); Ok=D[(D.nh>=MING)&(D.na>=MING)]; Tf=Ok[Ok.t<c1]; Md=fit_logit(np.log(Tf.rh+Tf.ra),(Tf.fthg+Tf.ftag)>2.5)
Sc=Ok[(Ok.t>=c1)&(Ok.t<c2)&(Ok.pco>1)&(Ok.pcu>1)]; rows=[]; LL=[]
for r in Sc.itertuples():
    p=p_over(Md,r.rh,r.ra); ov=r.fthg+r.ftag>2.5; q=(1/r.pco)/((1/r.pco)+(1/r.pcu)); LL.append((-(math.log(p) if ov else math.log(1-p)),-(math.log(q) if ov else math.log(1-q))))
    for c,side,sel in picks(p,r.pco,r.pcu,'OVER','UNDER'):
        xs=r.pco if sel=='OVER' else r.pcu; won=ov if sel=='OVER' else not ov
        rows.append((c,side,sel,r.t,back_settle(xs,won) if side=='BACK' else lay_settle(xs,won)))
Q=pd.DataFrame(rows,columns='cut side sel t v'.split()); LL=np.array(LL); md=Q.t.median(); out=[]
print(f"\n== SUPPORT fd_matches, fit on {len(Tf)}, {len(Sc)} games at Pinnacle closes, exact price, 2%, not a fill: log loss rates {LL[:,0].mean():.4f}, Pinnacle {LL[:,1].mean():.4f}, t of the difference {tstat(LL[:,1]-LL[:,0]):.2f}")
for k,x in Q.groupby(['side','sel','cut']):
    l=line(x.v.values,np.where(x.t<md,1,2)); out.append(dict(side=k[0],sel=k[1],cut=k[2],n=l['n'],per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2']))
print(pd.DataFrame(out).round(3).to_string(index=False))
S=O[O.PASS]; print("\n== SURVIVORS (bar: n>=300, n>=150 per half, both halves > 0, t>=3.5, mean>=+0.15, LTP upper bound)"); print(S.round(3).to_string(index=False) if len(S) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
