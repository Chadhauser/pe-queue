#!/bin/bash
set -o pipefail
# 499_season_goal_persist (Finder 2026-11-04, queue item 73, Finder's own, source a; from 499_cand_c2_segunda): does a league's goal-pricing error in the first third of a season persist through the rest of THAT season? Items 52 and 66 found errors do not persist BETWEEN seasons; within a season is untested. Rule written before any result was read.
# DATA fd_matches, all divisions, 2019-20 to 2025-26 (closing OU2.5 exists from 2019-20); 2026-27 is partial, so it only lists the leagues the rule names today, no P&L. Price: exchange close (BFEC) if the file has it, else Pinnacle close (PC), else Bet365 close. Fair = de-vigged.
# FIT first third of a league-season's games by date, games on the cut date all in fit: error = Under won minus mean fair Under, points. A league-season with fewer than 60 fit games is skipped. Team strengths and the total games in a season are known beforehand, so the cut is not look-ahead.
# TRADE the remaining games of that season, one bet per game, cuts |error| >= 3, 5, 8 points. FOLLOW: if Under under-won, lay Under, else lay Over. FADE: the opposite, as a control. Fill = close + 1 tick, 2% commission, £10 liability, held to FT.
# BAR standard, halves by season <= 2021-22 v later (2019-20 to 2021-22 = PC, later has BFEC from 2024-25, so the BFEC seasons are also shown alone). A close is not a print and a Pinnacle price cannot be laid, so A PASS IS AN UPPER BOUND ON A PROXY, not a tradable line. League-seasons share a sign within a trade set, so t is inflated; the league-season count is shown, with t on league-season means as the honest check.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import *
import lib_cand; lib_cand._checks()
pd.set_option('display.width',240); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',30)
T0=time.time()
def num(x):
    try: v=float(x)
    except (TypeError,ValueError): return np.nan
    return v if v>1 else np.nan
def close(raw):
    for src,a,b in (('BFEC','BFEC<2.5','BFEC>2.5'),('PC','PC<2.5','PC>2.5'),('B365C','B365C<2.5','B365C>2.5')):
        u,o=num(raw.get(a)),num(raw.get(b))
        if u==u and o==o: return u,o,src
    return np.nan,np.nan,None
def fit_cut(dates):
    """Sorted dates -> last date in the fit: the date of the game at one third, so all games on that date are fit."""
    return dates[max(len(dates)//3-1,0)]
def trade(err,cut,mode,u,o,under):
    """err = Under won minus fair. None if |err| < cut. FOLLOW lays the side that has under-won; FADE the other. Returns P&L per £10 liability."""
    if abs(err)<cut: return None
    lay_under=(err<0)==(mode=='FOLLOW')
    return lay_settle(step(u,1),under) if lay_under else lay_settle(step(o,1),not under)
# known answers. 9 dates: the third game is the cut. Under under-won by 6 points, cut 5, FOLLOW lays Under at 2.0->2.02: stake 10/1.02=9.803922, wins 9.607843 net if Under loses, -10 if it wins. FADE lays Over at 2.0->2.02: Under wins, so Over loses, same +9.607843. Below the cut: no trade.
assert fit_cut(list(range(9)))==2 and fit_cut(list(range(10)))==2 and fit_cut([1])==1
assert abs(trade(-.06,.05,'FOLLOW',2.0,2.0,False)-9.607843)<1e-5 and trade(-.06,.05,'FOLLOW',2.0,2.0,True)==-10.0
assert abs(trade(-.06,.05,'FADE',2.0,2.0,True)-9.607843)<1e-5 and trade(-.06,.05,'FADE',2.0,2.0,False)==-10.0
assert trade(.06,.05,'FOLLOW',2.0,2.0,True)==abs(trade(.06,.05,'FOLLOW',2.0,2.0,True)) and trade(.04,.05,'FOLLOW',2.0,2.0,True) is None
print("checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='600s'")
D=pd.read_sql("SELECT div,season,date,fthg,ftag,raw FROM fd_matches WHERE fthg IS NOT NULL AND season>='1920' AND season<'9000'",con); con.close()
c=[close(r) for r in D.raw]; D['u']=[x[0] for x in c]; D['o']=[x[1] for x in c]; D['src']=[x[2] for x in c]; D=D.drop(columns='raw')
D=D[D.u.notna()].copy(); D['dt']=pd.to_datetime(D.date,dayfirst=True,errors='coerce'); print(f"priced games {len(D)}, bad dates {int(D.dt.isna().sum())}, sources {D.src.value_counts().to_dict()}",flush=True); D=D[D.dt.notna()]
D['under']=(D.fthg+D.ftag)<2.5; D['fair']=(1/D.u)/(1/D.u+1/D.o)
rows=[]; ls=[]; now=[]
for (dv,s),g in D.groupby(['div','season']):
    g=g.sort_values('dt'); ds=list(g.dt); fc=fit_cut(ds); fit=g[g.dt<=fc]; rest=g[g.dt>fc]
    if s=='2627':
        # partial season: the fit is what has been played so far, no trade
        if len(g)>=40: now.append(dict(div=dv,games=len(g),under=g.under.mean(),fair=g.fair.mean(),err=(g.under.mean()-g.fair.mean())*100,z=zscore(int(g.under.sum()),len(g),g.fair.mean())))
        continue
    if len(fit)<60 or not len(rest): continue
    e=fit.under.mean()-fit.fair.mean(); e2=rest.under.mean()-rest.fair.mean(); ls.append(dict(div=dv,season=s,fit=len(fit),rest=len(rest),e1=e*100,e2=e2*100))
    for r in rest.itertuples():
        for cut in (.03,.05,.08):
            for mode in ('FOLLOW','FADE'):
                v=trade(e,cut,mode,r.u,r.o,r.under)
                if v is not None: rows.append((dv,s,cut,mode,r.src,v))
L=pd.DataFrame(ls); rho=L[['e1','e2']].corr(method='spearman').iloc[0,1]; print(f"\n== persistence, {len(L)} league-seasons: Spearman first third v rest {rho:.3f}; same sign {(np.sign(L.e1)==np.sign(L.e2)).mean():.3f}")
for s_,x in L.groupby('season'): print(f"  {s_}: n {len(x)} rho {x[['e1','e2']].corr(method='spearman').iloc[0,1]:+.3f}")
print("-- at |e1| >= 5: mean e2 signed in e1's direction, points:",round(float((L[L.e1.abs()>=5].e2*np.sign(L[L.e1.abs()>=5].e1)).mean()),2),"n",int((L.e1.abs()>=5).sum()))
R=pd.DataFrame(rows,columns=['div','season','cut','mode','src','v']); R['h']=np.where(R.season<='2122',1,2); o=[]
for (cut,mode),x in R.groupby(['cut','mode']):
    ms=x.groupby(['div','season']).v.mean(); o.append(dict(cut=cut,mode=mode,**line(x.v.values,x.h.values),lg_seasons=len(ms),lg_pos=float((ms>0).mean()),t_ls=tstat(ms.values)))
O=pd.DataFrame(o); print("\n== trades, close + 1 tick PROXY"); print(O.drop(columns='maxwin').round(3).to_string(index=False))
b=R[R.src=='BFEC']; o2=[]
for (cut,mode),x in b.groupby(['cut','mode']): o2.append(dict(cut=cut,mode=mode,n=len(x),per10=x.v.mean(),t=tstat(x.v),lg_seasons=x.groupby(['div','season']).ngroups))
print("\n-- exchange closes only (BFEC, 2024-25, 2025-26), these seasons were seen by the candidates, shown as a check"); print(pd.DataFrame(o2).round(3).to_string(index=False))
print("\n== today: 2026-27 so far, the leagues the rule would name at the first third, no P&L"); N=pd.DataFrame(now); print(N[N.err.abs()>=5].sort_values('err').round(3).to_string(index=False) if len(N) else "none")
print("\n== SURVIVORS (bar: n>=300, n>=150 per half, both halves > 0, t>=3.5, mean>=+0.15, proxy upper bound; t_ls is the honest t)"); S=O[O.PASS&(O['mode']=='FOLLOW')]; print(S.drop(columns='maxwin').round(3).to_string(index=False) if len(S) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
