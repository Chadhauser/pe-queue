#!/bin/bash
set -o pipefail
# 499_referee_goals (Finder 2026-11-04, queue item 72): is a referee's goal record priced in?
# DATA: mapped FT games (af_price_map, af_fixtures), first OU25 OVER and UNDER prints in tape minutes 0-2 (bf_hist_price, LTP only, so a pass is an upper bound). AET/PEN excluded. Referee key = first initial + last word of the name, country removed, because the same person appears as "M. Oliver" and "Michael Oliver, England".
# ERROR: over (goals >= 3, 1 or 0) minus overround-free implied Over, less the league's mean error in the FIT season. Referee error = mean over his games in the FIT season, at least 15 games.
# RULE: fit on one season, trade the other, nothing from the traded season is used. Referee error >= +X points: back Over or lay Under. <= -X points: back Under or lay Over. X = 3, 5, fixed in advance. Fit 2024 / trade 2025 is the test; fit 2025 / trade 2024 is the check. One bet per game per line, one tick adverse, 2% commission, £10 risk, hold to the score. Halves: median kick-off inside the traded line.
# CONTROL: the same sides on every traded game, whatever the referee.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,re,time,unicodedata,warnings,psycopg2,pandas as pd,numpy as np
warnings.filterwarnings('ignore')
pd.set_option('display.width',230); pd.set_option('display.max_rows',80); pd.set_option('display.max_columns',30)
sys.path.insert(0,'/root/pe-queue/runner'); import creds
T0=time.time(); MIN_GAMES=15
LAD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    x=lo
    while x<hi-1e-9: LAD.append(round(x,2)); x+=st
LAD.append(1000.0); LADA=np.array(LAD)
def pos(p): return int(np.searchsorted(LADA,round(float(p),2)-1e-9))
def dn(p): return float(LADA[max(pos(p)-1,0)])
def up(p): return float(LADA[min(pos(p)+1,len(LADA)-1)])
def comm(x): return x*0.98 if x>0 else x
def back_settle(p,won):
    a=dn(p)
    if a<=1.01: return np.nan
    return comm(10*(a-1)) if won else -10.0
def lay_settle(p,won):
    a=up(p); return -10.0 if won else comm(10/(a-1))
def tstat(v):
    v=np.asarray(v,dtype=float); v=v[np.isfinite(v)]
    if len(v)<2: return 0.0
    s=v.std(ddof=1); return float(v.mean()/(s/len(v)**0.5)) if s>0 else 0.0
def refkey(s):
    if s is None or s!=s: return None
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower().split(',')[0]
    w=re.sub(r"[^a-z ]"," ",s).split()
    return f"{w[0][0]} {w[-1]}" if len(w)>=2 else None
def implied_over(o,u): return (1/o)/(1/o+1/u)
def spearman(a,b):
    a=pd.Series(a).rank().values; b=pd.Series(b).rank().values
    return float(np.corrcoef(a,b)[0,1])
def perm_p(a,b,n=5000,seed=5):
    r=spearman(a,b); rng=np.random.default_rng(seed); ra=pd.Series(a).rank().values; rb=pd.Series(b).rank().values
    c=sum(abs(np.corrcoef(rng.permutation(ra),rb)[0,1])>=abs(r) for _ in range(n)); return (c+1)/(n+1)
def fit_errors(F,min_games=MIN_GAMES):
    """F: league, ref, err (over minus implied). Returns referee -> mean of err less league mean, referees with at least min_games only. League mean uses all the league's games in F."""
    x=F.assign(res=F.err-F.groupby('league').err.transform('mean')); g=x[x.ref.notna()].groupby('ref').res.agg(['mean','size'])
    return g[g['size']>=min_games]['mean'].to_dict()
def gate(v,when):
    m=np.isfinite(v); v=v[m]; when=when[m]
    if len(v)==0: return dict(n=0,mean=np.nan,t=0.0,n1=0,h1=np.nan,n2=0,h2=np.nan,PASS=False)
    md=np.median(when); a=v[when<md]; b=v[when>=md]; t=tstat(v)
    return dict(n=len(v),mean=v.mean(),t=t,n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,
                PASS=bool(len(v)>=300 and len(a)>=150 and len(b)>=150 and t>=3.5 and a.mean()>0 and b.mean()>0 and v.mean()>=0.15))
# known answers, worked by hand
assert refkey('M. Oliver')==refkey('Michael Oliver, England')==refkey('Michael Oliver')=='m oliver' and refkey('Oliver Langford, England')=='o langford'
assert refkey(None) is None and refkey('Oliver') is None and refkey(float('nan')) is None and refkey('José Sánchez')=='j sanchez'
assert abs(implied_over(2.0,2.0)-0.5)<1e-12 and abs(implied_over(1.5,3.0)-2/3)<1e-12                                          # 0.667/(0.667+0.333)
assert abs(back_settle(2.0,True)-9.702)<1e-9 and back_settle(2.0,False)==-10.0 and np.isnan(back_settle(1.02,True))             # 2.0 fills 1.99: 10 x 0.99 x 0.98
assert abs(lay_settle(2.0,False)-10/1.02*0.98)<1e-9 and lay_settle(2.0,True)==-10.0                                             # 2.0 fills 2.02
assert abs(spearman([1,2,3],[1,2,3])-1)<1e-9 and abs(spearman([1,2,3],[3,2,1])+1)<1e-9
# league A mean err 0.1; ref r has +0.3, +0.3 -> residual +0.2; ref s has -0.1, -0.1 -> -0.2; ref t has one game, below the minimum
_F=pd.DataFrame(dict(league=['A']*4,ref=['r','r','s','s'],err=[.3,.3,-.1,-.1])); _e=fit_errors(_F,2); assert abs(_e['r']-0.2)<1e-12 and abs(_e['s']+0.2)<1e-12
assert fit_errors(_F,3)=={}
_g=gate(np.array([1.0,0.5]*200),np.arange(400.0)); assert _g['PASS'] is True
_g=gate(np.array([1.0]*300+[0.0]*300),np.arange(600.0)); assert _g['PASS'] is False
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)

con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.league,f.season,f.kickoff,f.hg,f.ag,f.referee FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.season IN (2024,2025)""",con)
P=pd.read_sql("""SELECT DISTINCT ON (event_id,sel) event_id,sel,ltp::float ltp FROM bf_hist_price WHERE mkt='OU25' AND minute BETWEEN 0 AND 2 AND ltp>=1.01 AND ltp<1000 AND event_id=ANY(%s) ORDER BY event_id,sel,minute,m""",con,params=(list(G.event_id),))
con.close()
W=P.pivot_table(index='event_id',columns='sel',values='ltp',aggfunc='first')
D=G.merge(W[['OVER','UNDER']].dropna().reset_index(),on='event_id')
print(f"mapped FT games {len(G)}, with both first prints {len(D)}, by season {D.season.value_counts().to_dict()} | {time.time()-T0:.0f}s",flush=True)
D['ref']=D.referee.map(refkey); D['over']=(D.hg+D.ag>=3); D['imp']=implied_over(D.OVER,D.UNDER); D['err']=D.over.astype(float)-D.imp; D['when']=pd.to_datetime(D.kickoff,utc=True).astype('int64')
print(f"referee key known {D.ref.notna().mean():.3f}, referees {D.ref.nunique()}, over won {D.over.mean():.3f} v implied {D.imp.mean():.3f}",flush=True)
SIDES=(('back Over','OVER',True,back_settle),('lay Under','UNDER',False,lay_settle),('back Under','UNDER',False,back_settle),('lay Over','OVER',True,lay_settle))
def pnl(d,col,over_side,f): return np.array([f(p,(o if over_side else not o)) for p,o in zip(d[col],d.over)],dtype=float)
out=[]; SEL={}
for fit,tr in ((2024,2025),(2025,2024)):
    A=D[D.season==fit]; B=D[D.season==tr].copy(); e=fit_errors(A); SEL[fit]=e; ef=fit_errors(B)
    both=sorted(set(e)&set(ef)); r=spearman([e[k] for k in both],[ef[k] for k in both]); p=perm_p([e[k] for k in both],[ef[k] for k in both])
    print(f"\n== fit {fit}: referees at {MIN_GAMES}+ games {len(e)}, spread of error sd {np.std(list(e.values())):.3f} (chance alone at 30 games would be about 0.09); in both seasons {len(both)}, rank correlation {fit} v {tr} {r:.3f}, permutation p {p:.3f}",flush=True)
    B['e']=B.ref.map(e)
    for X in (0.03,0.05):
        for grp,mask,sides in ((f'high >=+{int(X*100)}',B.e>=X,SIDES[:2]),(f'low <=-{int(X*100)}',B.e<=-X,SIDES[2:])):
            d=B[mask]
            for nm,col,ov,f in sides:
                r2=gate(pnl(d,col,ov,f),d.when.values.astype(float))
                out.append(dict(fit=fit,trade=tr,group=grp,line=nm,**r2,games=len(d),refs=d.ref.nunique(),over_won=d.over.mean() if len(d) else np.nan,implied=d.imp.mean() if len(d) else np.nan))
    for nm,col,ov,f in SIDES:
        r2=gate(pnl(B,col,ov,f),B.when.values.astype(float))
        out.append(dict(fit=fit,trade=tr,group='control, all games',line=nm,**r2,games=len(B),refs=B.ref.nunique(),over_won=B.over.mean(),implied=B.imp.mean()))
S=pd.DataFrame(out)
print("\n== ALL LINES, per £10, sorted by t\n",S.sort_values('t',ascending=False).round(3).to_string(index=False))
W2=S[S.PASS&~S.group.str.startswith('control')]; print(f"\n== SURVIVORS: {len(W2)} of {int((~S.group.str.startswith('control')).sum())} lines (control lines not counted)\n",W2.round(3).to_string(index=False) if len(W2) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
