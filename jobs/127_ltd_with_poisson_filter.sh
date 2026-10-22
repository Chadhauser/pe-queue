#!/bin/bash
# 127: Peter 22 Oct: "why can't we pick games by hand? you were running a form guide using Poisson". Correct — 121 tested Lay the
# Draw with its selection step removed. This re-runs LTD on the same 2-year Betfair history WITH a rolling-form Poisson filter:
# for each team, attack/defence strength from its previous 10 matches in football_matches (8 seasons, goals for/against vs league
# average) -> expected goals for the fixture (lambda_h + lambda_a) and P(home win) by Poisson. Joined to bf_hist_other soccer
# markets by normalised team names + date (+-1 day). Cells: LTD by expected-goals band; LTD where xG>=2.6 AND P(home)>=0.50;
# and the unfiltered baseline for comparison. Same accounting as 121. Results -> strategy_results sport='Soccer-copy'.
cd /root/pe-factory && cat > ltd_poisson.py <<'PYFILE'
import sys, re, math, datetime, unicodedata, psycopg2, psycopg2.extras, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
SP_=0.02; COMM=0.02; today=datetime.date.today()
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
pd.set_option('display.width',250)
def tstat(x): x=pd.Series(x,dtype=float).dropna(); return float(x.mean()/(x.std(ddof=1)/math.sqrt(len(x)))) if len(x)>2 and x.std(ddof=1)>0 else 0.0
def prof(p): return p*(1-COMM) if p>0 else p
def lay_hedge(e,x): return prof(1-(e*(1+SP_))/(x*(1-SP_)))
def lay_settle(px,won): return -(px*(1+SP_)-1) if won else prof(1.0)
out=[]
def emit(strat,df,col,bandcol='band'):
    if df is None or len(df)<60: print(f"  {strat}: n={0 if df is None else len(df)} too small"); return
    df=df.copy(); med=pd.to_datetime(df.mt).median(); df['half']=np.where(pd.to_datetime(df.mt)<med,1,2)
    print(f"\n== {strat}: n {len(df)} | per £100 {df[col].mean()*100:+.1f} | t {tstat(df[col]):.1f}")
    for band,g in df.groupby(bandcol,observed=True):
        a=g[g.half==1][col]; b=g[g.half==2][col]
        if len(a)<25 or len(b)<25: continue
        p1,p2=a.mean()*100,b.mean()*100; t1,t2=tstat(a),tstat(b); surv=bool(p1>1 and p2>1 and t1>=2 and t2>=2 and len(g)>=100)
        print(f"   band {band}: n {len(g)} | h1 {p1:+.1f} (t {t1:.1f}) | h2 {p2:+.1f} (t {t2:.1f}) {'SURVIVOR' if surv else ''}")
        out.append((today,'Soccer-copy',strat,str(band),int(len(g)),int(len(a)),float(round(p1,2)),float(round(t1,2)),int(len(b)),float(round(p2,2)),float(round(t2,2)),float(round(g[col].mean()*100,2)),bool(surv),f"{pd.to_datetime(df.mt).min():%Y-%m}->{pd.to_datetime(df.mt).max():%Y-%m}"))
def norm(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
    s=re.sub(r"\b(fc|cf|afc|sc|ac|as|ss|us|sv|vfb|vfl|tsg|fk|nk|sk|bk|if|club|de|the|athletic|atletico|sporting|real|cd|ud|sd|rcd)\b"," ",s)
    s=re.sub(r"[^a-z0-9 ]"," ",s); s=re.sub(r"\s+"," ",s).strip()
    return s
# ---- rolling Poisson from football_matches
F=pd.read_sql("SELECT date::date d, league_code, home_team, away_team, fthg, ftag FROM football_matches WHERE fthg IS NOT NULL ORDER BY date",con)
F['h']=F.home_team.map(norm); F['a']=F.away_team.map(norm)
lg_avg=F.groupby('league_code').apply(lambda g: pd.Series({'hg':g.fthg.mean(),'ag':g.ftag.mean()}))
long=pd.concat([F[['d','league_code','h','fthg','ftag']].rename(columns={'h':'team','fthg':'gf','ftag':'ga'}).assign(home=1),
                F[['d','league_code','a','ftag','fthg']].rename(columns={'a':'team','ftag':'gf','fthg':'ga'}).assign(home=0)]).sort_values('d')
long['gf10']=long.groupby('team').gf.transform(lambda s: s.shift(1).rolling(10,min_periods=6).mean())
long['ga10']=long.groupby('team').ga.transform(lambda s: s.shift(1).rolling(10,min_periods=6).mean())
form=long.dropna(subset=['gf10','ga10']).drop_duplicates(['team','d'])[['team','d','league_code','gf10','ga10']]
print("teams with rolling form:",form.team.nunique(),"rows",len(form),flush=True)
def poisson_probs(lh,la):
    ph=[math.exp(-lh)*lh**i/math.factorial(i) for i in range(8)]; pa=[math.exp(-la)*la**j/math.factorial(j) for j in range(8)]
    return sum(ph[i]*pa[j] for i in range(8) for j in range(8) if i>j)
# ---- LTD outcomes on history (same logic as 121), keep event date + team names
cur.execute("SELECT market_id FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND market_id<>'1' GROUP BY market_id HAVING bool_or(inplay) AND bool_or(NOT inplay)")
mids=[r[0] for r in cur.fetchall()]; recs=[]
for i in range(0,len(mids),1500):
    D=pd.read_sql("SELECT market_id, event_name, market_time mt, sel, ts, ltp::float ltp, inplay FROM bf_hist_other WHERE market_id = ANY(%s) AND market_type='MATCH_ODDS' ORDER BY market_id, ts",con,params=(mids[i:i+1500],))
    for mid,g in D.groupby('market_id',sort=False):
        pre=g[~g.inplay]; ip=g[g.inplay]
        if pre.empty or ip.empty: continue
        sels=list(g.sel.unique()); draw=[s for s in sels if str(s).strip().lower() in ('the draw','draw')]
        if len(draw)!=1 or len(sels)!=3: continue
        draw=draw[0]; ev=str(g.event_name.iloc[0])
        if ' v ' not in ev: continue
        home,away=[x.strip() for x in ev.split(' v ',1)]
        sp={s:pre[pre.sel==s].ltp.iloc[-1] for s in sels if not pre[pre.sel==s].empty}
        if len(sp)!=3 or sp[draw]<=1: continue
        hs=[s for s in sels if s!=draw and str(s).strip()==home]
        if not hs: continue
        mt=pd.Timestamp(g.mt.iloc[0]); dr=ip[ip.sel==draw].copy()
        if len(dr)<10: continue
        dr['minute']=(pd.to_datetime(dr.ts)-mt).dt.total_seconds()/60.0; dr=dr[(dr.minute>=0)&(dr.minute<=120)]
        if dr.empty: continue
        prev=dr.ltp.shift(1); jump=dr[(dr.ltp>=prev*1.20)&(dr.minute>=1)]; e=sp[draw]
        last=ip[ip.sel==draw].ltp.iloc[-1]; draw_won=last<1.15
        if not jump.empty and jump.minute.iloc[0]<=65: pnl=lay_hedge(e,jump.ltp.iloc[0])
        else:
            at65=dr[dr.minute>=65]; pnl=lay_settle(e,draw_won) if at65.empty else lay_hedge(e,at65.ltp.iloc[0])
        recs.append(dict(mid=mid,mt=mt,d=mt.date(),h=norm(home),a=norm(away),home_sp=sp[hs[0]],draw_sp=e,pnl=pnl))
    print(" processed",min(i+1500,len(mids)),flush=True)
R=pd.DataFrame(recs); print("LTD-scored markets:",len(R),flush=True)
# ---- join form (date +-1 day)
R['d']=pd.to_datetime(R.d)
form['d']=pd.to_datetime(form.d)
def join_side(R,col,prefix):
    f=form.rename(columns={'team':col,'gf10':prefix+'gf','ga10':prefix+'ga','league_code':prefix+'lg'})
    m=pd.merge_asof(R.sort_values('d'),f.sort_values('d'),on='d',by=col,tolerance=pd.Timedelta(days=1),direction='nearest')
    return m
M=join_side(R,'h','h_'); M=join_side(M,'a','a_')
M=M[M.h_gf.notna()&M.a_gf.notna()].copy(); print("matched to form:",len(M),"of",len(R),"(unmatched names are lower leagues / spelling)",flush=True)
M['lam_h']=np.sqrt(M.h_gf*M.a_ga); M['lam_a']=np.sqrt(M.a_gf*M.h_ga); M['xg']=M.lam_h+M.lam_a
M['p_home']=[poisson_probs(lh,la) for lh,la in zip(M.lam_h,M.lam_a)]
Q=M[(M.home_sp>=1.5)&(M.home_sp<=2.2)&(M.draw_sp>=3.2)&(M.draw_sp<=4.2)].copy()
Q['band']=pd.cut(Q.xg,[0,2.2,2.6,3.0,10]); emit('LTD classic by Poisson expected goals',Q,'pnl')
Q['band']=pd.cut(Q.p_home,[0,0.4,0.5,0.6,1]); emit('LTD classic by Poisson P(home win)',Q,'pnl')
S=Q[(Q.xg>=2.6)&(Q.p_home>=0.5)].copy(); S['band']='xg>=2.6 & p_home>=0.5'; emit('LTD classic + Poisson filter (xg>=2.6, p_home>=0.5)',S,'pnl')
W=M[(M.draw_sp>=3.0)&(M.draw_sp<=5.0)].copy(); W['band']=pd.cut(W.xg,[0,2.2,2.6,3.0,10]); emit('LTD any fav by Poisson expected goals',W,'pnl')
B=M[(M.home_sp>=1.5)&(M.home_sp<=2.2)&(M.draw_sp>=3.2)&(M.draw_sp<=4.2)].copy(); B['band']='all (baseline, form-matched games)'; emit('LTD classic baseline on the same matched games',B,'pnl')
if out:
    cur.execute("DELETE FROM strategy_results WHERE run_date=%s AND strategy LIKE 'LTD%%Poisson%%'",(today,))
    psycopg2.extras.execute_values(cur,"INSERT INTO strategy_results VALUES %s",out); print("cells written:",len(out))
PYFILE
python3 -m py_compile ltd_poisson.py || exit 1
timeout 3300 python3 ltd_poisson.py 2>&1 | grep -v -E "UserWarning|pd.read_sql"
