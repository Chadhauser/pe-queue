#!/bin/bash
# 516: H0 POST-GOAL FADE as a daily forward-paper hypothesis in the sports team (the one named line allowed — Peter's verified result;
# the scoreboard question is capacity). Entry from the real ladder (liq_goal_depth), exit from the local tape archive, one tick adverse,
# 2% commission, IS/OOS halves by time, random-side control. Added to hypotheses.json with repeat_hours=24. The five's fade line now
# points at the H0 rows of the verdict table instead of the paper_ledger lookup that found nothing.
set -o pipefail
cd /root/pe-sports/team
cat > fade_forward.py <<'PYFILE'
# H0 POST-GOAL FADE — forward paper on the real ladder (the one named line allowed: Peter's verified result; the question is capacity).
# Entry: lay the scorer (MO runner whose LTP fell 10%+ on reopen) or lay OVER in OU25 at the BEST LAY recorded at +60/+120/+300 s after
# the goal (liq_goal_depth, Railway). Exit: back at the best back nearest +10 min from the archived 1/min tape (local liq_sample), or
# nothing if no sample within 3 min. One tick adverse on entry (lay one tick higher than recorded), 2% commission on wins. Per £10 stake.
# IS/OOS = older half / newer half of goals by time. Control = side chosen at random (back the scorer instead of laying).
# RESULT per market x offset (all tiers) and for tier 1+2 only. Re-runs daily; n grows with every goal the recorder sees.
import sys, math, json, numpy as np, pandas as pd, psycopg2
sys.path.insert(0,'/root/pe-queue/runner'); import creds
COMM=0.02; rng=np.random.default_rng(11)
LADDER=[(2,0.01),(3,0.02),(4,0.05),(6,0.1),(10,0.2),(20,0.5),(30,1),(50,2),(100,5),(1000,10)]
def tick_up(p):
    for lim,inc in LADDER:
        if p<lim: return round(p+inc,2)
    return p+10
R=psycopg2.connect(creds.pg_railway(),sslmode='require'); rc=R.cursor(); rc.execute("SET statement_timeout='300s'")
G=pd.read_sql("SELECT market_id, event_name, competition, mkt, sel, goal_ts, offset_s, ts, pre_ltp, ltp, lay_px, lay3_sz, minute FROM liq_goal_depth WHERE offset_s IN (60,120,300) AND lay_px IS NOT NULL",R)
for c in ('pre_ltp','ltp','lay_px','lay3_sz'): G[c]=pd.to_numeric(G[c],errors='coerce')
G['moved']=G.ltp/G.pre_ltp-1
E=G[((G.mkt=='MO')&(G.moved<-0.10))|((G.mkt=='OU25')&(G.sel=='OVER'))].copy()
print("goal-depth entries:",len(E),"markets",E.market_id.nunique(),"goals from",str(E.goal_ts.min())[:10],"to",str(E.goal_ts.max())[:10],flush=True)
L=psycopg2.connect(creds.pg_local()); lc=L.cursor(); lc.execute("SET statement_timeout='900s'")
mids=list(E.market_id.unique())
S=pd.read_sql("SELECT ts, market_id, sel, back_px FROM liq_sample WHERE market_id = ANY(%(m)s) AND back_px IS NOT NULL",L,params={'m':mids}).sort_values('ts')
S['back_px']=pd.to_numeric(S.back_px,errors='coerce'); print("tape rows for those markets (local archive):",len(S),flush=True)
TOP5={'English Premier League','Spanish La Liga','Italian Serie A','German Bundesliga','French Ligue 1','UEFA Champions League'}
EUR={'English Championship','Dutch Eredivisie','Portuguese Primeira Liga','Belgian Pro League','Turkish Super League','Scottish Premiership','Spanish Segunda Division','Italian Serie B','German Bundesliga 2','French Ligue 2','UEFA Europa League'}
E['tier']=E.competition.map(lambda c:'1' if c in TOP5 else '2' if c in EUR else '3')
SK={k:g.reset_index(drop=True) for k,g in S.groupby(['market_id','sel'])}
def exit_px(mid,sel,when):
    g=SK.get((mid,sel))
    if g is None: return None
    i=g.ts.searchsorted(when); cands=[j for j in (i-1,i) if 0<=j<len(g)]
    if not cands: return None
    j=min(cands,key=lambda j:abs((g.ts.iloc[j]-when).total_seconds()))
    return float(g.back_px.iloc[j]) if abs((g.ts.iloc[j]-when).total_seconds())<=180 else None
E['exit']=[exit_px(m,s,t+pd.Timedelta(minutes=10)) for m,s,t in zip(E.market_id,E.sel,E.ts)]
E=E[E.exit.notna()&(E.lay_px>1.01)].copy(); E['entry']=E.lay_px.map(tick_up)
# lay £10 at entry, back £10 at exit: pnl per £10 = 10*(1 - entry/exit) ... (lay liability view: profit if price rises)
E['pnl']=10*(1-E.entry/E.exit); E['pnl']=np.where(E.pnl>0,E.pnl*(1-COMM),E.pnl)
E=E.sort_values('goal_ts'); E['oos']=np.arange(len(E))>=len(E)//2
def tstat(x): x=np.asarray(x,float); return float(x.mean()/(x.std(ddof=1)/math.sqrt(len(x)))) if len(x)>5 and x.std(ddof=1)>0 else 0.0
def emit(name,X):
    if len(X)<30: return
    ctrl=np.where(rng.random(len(X))<0.5,X.pnl.values,-X.pnl.values)
    isx=X.loc[~X.oos,'pnl'].values; oox=X.loc[X.oos,'pnl'].values
    print("RESULT "+json.dumps(dict(name=name,n=int(len(X)),mean_per10=round(float(X.pnl.mean()),3),t=round(tstat(X.pnl.values),2),is_mean=round(float(isx.mean()),3) if len(isx) else 0,is_t=round(tstat(isx),2),oos_mean=round(float(oox.mean()),3) if len(oox) else 0,oos_t=round(tstat(oox),2),control_t=round(tstat(ctrl),2),size3_med=float(X.lay3_sz.median()) if X.lay3_sz.notna().any() else None)),flush=True)
for mkt in ('MO','OU25'):
    for off in (60,120,300):
        X=E[(E.mkt==mkt)&(E.offset_s==off)]; emit(f"H0 fade {mkt} lay +{off}s exit +10m (all tiers)",X)
        emit(f"H0 fade {mkt} lay +{off}s exit +10m (tier 1+2)",X[X.tier!='3'])
print("entries priced with a +10 min exit:",len(E),"| OOS half from",str(E.loc[E.oos,'goal_ts'].min())[:10] if E.oos.any() else None)
print("NEXT DOOR (pre-registered): exit +5m / +15m; entry at best lay vs one tick inside the spread (maker).")
PYFILE
python3 -m py_compile fade_forward.py || exit 1
python3 - <<'PY'
import json; p='/root/pe-sports/team/hypotheses.json'; r=json.load(open(p))
if not any(h['id'].startswith('H0 post-goal fade') for h in r['hypotheses']):
    r['hypotheses'].insert(0,{"id":"H0 post-goal fade forward paper (lay scorer / lay Over after reopen, exit +10m)","script":"/root/pe-sports/team/fade_forward.py","status":"proposed","kind":"single","pre_registered_sign":"lay the scorer after the reopen; price drifts back","next_door":"exit +5m / +15m; maker entry one tick inside","timeout":3000,"repeat_hours":24})
json.dump(r,open(p,'w'),indent=1); print([(h['id'][:24],h['status']) for h in r['hypotheses']])
PY
sed -i "s|L\['1 post-goal fade'\]=f\"paper_ledger: {r}\" if r else \"paper_ledger has no fade rows yet (356 first run pending)\"|L['1 post-goal fade']='see the H0 rows in the verdict table (daily forward paper on the real ladder; m1_alerts real trades: '+str(tryq('railway',\"select count(actual_pnl), round(sum(actual_pnl)::numeric,2) from m1_alerts\"))+')'|" sports_team.py
python3 -m py_compile sports_team.py || { echo "daemon patch failed compile"; exit 1; }
grep -c "H0 rows" sports_team.py
echo "daemon restarts via keepalive at its next idle restart; H0 runs on the next cycle"
