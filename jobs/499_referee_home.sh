#!/bin/bash
set -o pipefail
# 499_referee_home (Finder 2026-11-06, queue item 217, Finder's own, source d): is a referee's home-win record priced in? Rule pushed before any price was read. The number 499 is reused: 450-499 are all taken.
# DATA and METHOD as jobs/499_referee_goals.sh, which read goals only. Mapped FT games, first MO prints in tape minutes 0-2, LTP only so a pass is an upper bound. Referee key = first initial + last word. Error = home won minus overround-free implied home, less the league's mean in the FIT season; referee mean, at least 15 games.
# RULE fit one season, trade the other. >= +X back home, lay away. <= -X back away, lay home. X = 0.03, 0.05. One tick, 2%, £10 risk, to the score. Halves: median kick-off inside the line. Control: same sides on every traded game. Guard from jobs/499_home_dog.sh: a goal known before the print, or a print outside -5..+20 min of kick-off, is no game.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_500_000_000,1_500_000_000))  # this job only
import sys,re,time,unicodedata,warnings,psycopg2,pandas as pd,numpy as np
warnings.filterwarnings('ignore')
pd.set_option('display.width',230); pd.set_option('display.max_rows',80); pd.set_option('display.max_columns',30)
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,back_settle,lay_settle,tstat,passes
T0=time.time(); MIN_GAMES=15
def bk(x,won):
    a=step(x,-1); return np.nan if a<=1.01 else back_settle(a,won)
def ly(x,won): return lay_settle(step(x,1),won)
def refkey(s):
    if s is None or s!=s: return None
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower().split(',')[0]
    w=re.sub(r"[^a-z ]"," ",s).split()
    return f"{w[0][0]} {w[-1]}" if len(w)>=2 else None
def implied_home(h,d,a): return (1/h)/(1/h+1/d+1/a)
def spearman(a,b): return float(np.corrcoef(pd.Series(a).rank().values,pd.Series(b).rank().values)[0,1])
def perm_p(a,b,n=5000,seed=5):
    r=spearman(a,b); rng=np.random.default_rng(seed); ra=pd.Series(a).rank().values; rb=pd.Series(b).rank().values
    return (sum(abs(np.corrcoef(rng.permutation(ra),rb)[0,1])>=abs(r) for _ in range(n))+1)/(n+1)
def fit_errors(F,min_games=MIN_GAMES):
    x=F.assign(res=F.err-F.groupby('league').err.transform('mean')); g=x[x.ref.notna()].groupby('ref').res.agg(['mean','size'])
    return g[g['size']>=min_games]['mean'].to_dict()
def gate(v,when):
    m=np.isfinite(v); v=v[m]; when=when[m]
    if len(v)==0: return dict(n=0,mean=np.nan,t=0.0,n1=0,h1=np.nan,n2=0,h2=np.nan,PASS=False)
    md=np.median(when); a=v[when<md]; b=v[when>=md]; t=tstat(v)
    return dict(n=len(v),mean=v.mean(),t=t,n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,PASS=passes(len(v),len(a),len(b),t,a.mean() if len(a) else 0,b.mean() if len(b) else 0,v.mean()))
# known answers, worked by hand
assert refkey('M. Oliver')==refkey('Michael Oliver, England')=='m oliver' and refkey(None) is None and refkey('Oliver') is None
assert abs(implied_home(2.,4.,4.)-0.5)<1e-12 and abs(implied_home(3.,3.,3.)-1/3)<1e-12
assert abs(bk(2.0,True)-9.702)<1e-9 and bk(2.0,False)==-10.0 and np.isnan(bk(1.02,True))
assert abs(ly(2.0,False)-10/1.02*0.98)<1e-9 and ly(2.0,True)==-10.0
_F=pd.DataFrame(dict(league=['A']*4,ref=['r','r','s','s'],err=[.3,.3,-.1,-.1])); _e=fit_errors(_F,2); assert abs(_e['r']-0.2)<1e-12 and abs(_e['s']+0.2)<1e-12 and fit_errors(_F,3)=={}
assert gate(np.array([1.0,0.5]*200),np.arange(400.0))['PASS'] is True and gate(np.array([1.0]*300+[0.0]*300),np.arange(600.0))['PASS'] is False
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.league,f.season,f.kickoff,f.hg,f.ag,f.referee FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.season IN (2024,2025) AND f.league NOT LIKE 'UEFA%%'""",con)
EV=pd.read_sql("SELECT fixture_id,min(coalesce(minute,0)) gm FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal') AND coalesce(minute,0)<=2 GROUP BY 1",con,params=(list(map(int,G.fixture_id)),))
first_goal=dict(zip(EV.fixture_id,EV.gm)); parts=[]
for i in range(0,len(G),1000):
    P=pd.read_sql("SELECT event_id,sel,minute,m,ltp::float8 ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt='MO' AND sel IN ('HOME','AWAY','DRAW') AND minute>=0 AND minute<=2 AND ltp>=1.01 AND ltp<1000",con,params=(list(G.event_id.iloc[i:i+1000]),))
    parts.append(P.sort_values(['event_id','sel','minute','m']).drop_duplicates(['event_id','sel']))
con.close(); P=pd.concat(parts,ignore_index=True).merge(G[['event_id','fixture_id','kickoff']],on='event_id')
lag=(pd.to_datetime(P.m,utc=True)-pd.to_datetime(P.kickoff,utc=True)).dt.total_seconds()/60; gm=P.fixture_id.map(first_goal)
bad=(lag<-5)|(lag>20)|(gm.notna()&(gm<P.minute)); print(f"rows dropped by the guards {int(bad.sum())} of {len(P)}",flush=True); P=P[~bad]
W=P.pivot_table(index='event_id',columns='sel',values='ltp',aggfunc='first')
D=G.merge(W[['HOME','DRAW','AWAY']].dropna().reset_index(),on='event_id')
print(f"mapped FT games {len(G)}, with all three first prints {len(D)}, by season {D.season.value_counts().to_dict()} | {time.time()-T0:.0f}s",flush=True)
D['ref']=D.referee.map(refkey); D['hw']=D.hg>D.ag; D['aw']=D.ag>D.hg; D['imp']=implied_home(D.HOME,D.DRAW,D.AWAY); D['err']=D.hw.astype(float)-D.imp; D['when']=pd.to_datetime(D.kickoff,utc=True).astype('int64').astype(float)
print(f"referee key known {D.ref.notna().mean():.3f}, referees {D.ref.nunique()}, home won {D.hw.mean():.3f} v implied {D.imp.mean():.3f}",flush=True)
SIDES=(('back home','HOME','hw',bk),('lay away','AWAY','aw',ly),('back away','AWAY','aw',bk),('lay home','HOME','hw',ly))
def pnl(d,col,w,f): return np.array([f(p,x) for p,x in zip(d[col],d[w])],dtype=float)
out=[]
for fit,tr in ((2024,2025),(2025,2024)):
    A=D[D.season==fit]; B=D[D.season==tr].copy(); e=fit_errors(A); ef=fit_errors(B)
    both=sorted(set(e)&set(ef)); r=spearman([e[k] for k in both],[ef[k] for k in both]); p=perm_p([e[k] for k in both],[ef[k] for k in both])
    print(f"\n== fit {fit}: referees at {MIN_GAMES}+ games {len(e)}, sd of error {np.std(list(e.values())):.3f}; in both seasons {len(both)}, rank correlation {fit} v {tr} {r:.3f}, permutation p {p:.3f}",flush=True)
    B['e']=B.ref.map(e)
    for X in (0.03,0.05):
        for grp,mask,sides in ((f'high >=+{int(X*100)}',B.e>=X,SIDES[:2]),(f'low <=-{int(X*100)}',B.e<=-X,SIDES[2:])):
            d=B[mask]
            for nm,col,w,f in sides:
                out.append(dict(fit=fit,trade=tr,group=grp,line=nm,**gate(pnl(d,col,w,f),d.when.values),games=len(d),refs=d.ref.nunique(),home_won=d.hw.mean() if len(d) else np.nan,implied=d.imp.mean() if len(d) else np.nan))
    for nm,col,w,f in SIDES:
        out.append(dict(fit=fit,trade=tr,group='control, all games',line=nm,**gate(pnl(B,col,w,f),B.when.values),games=len(B),refs=B.ref.nunique(),home_won=B.hw.mean(),implied=B.imp.mean()))
S=pd.DataFrame(out)
print("\n== ALL LINES, per £10, sorted by t\n",S.sort_values('t',ascending=False).round(3).to_string(index=False))
W2=S[S.PASS&~S.group.str.startswith('control')]; print(f"\n== SURVIVORS: {len(W2)} of {int((~S.group.str.startswith('control')).sum())} lines (control lines not counted)\n",W2.round(3).to_string(index=False) if len(W2) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
