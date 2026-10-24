#!/bin/bash
# 146: 145 re-run with STALE-PRICE PROTECTION: the goal minute and the one after are barred as entries (the scorer's LTP is still the
# pre-goal print while the market is suspended, which made 'back the scorer in the goal minute' look like £100+ per £10). GOAL
# trigger now = entry 2-5 minutes after the draw jump. Also adds the capture test: for each GOAL-trigger perfect trade on the scorer,
# what a fixed exit at +5/+10/+15 minutes would have taken.
# 145: THE PERFECT-EXIT (ORACLE) ANALYSIS (Peter 24 Oct: "run tests whereby you see the ideal exit that would make money in every game
# and see the pattern"). Two seasons of 1-minute MO prices (bf_hist_price, Aug 2024 -> Jun 2026). For every game and each of
# HOME / DRAW / AWAY: the best lay->back (price falls) and best back->lay (price rises) trade in the match, hedged, 2pct comm, per £10,
# minimum hold 2 minutes. Each best entry is labelled by what was happening then: GOAL (within 3 min of a draw-price jump), HT (44-47),
# EARLY (<=5'), LATE (>=75'), else HINDSIGHT. Outputs: (1) perfect profit per game and how much of it is behind a repeatable trigger;
# (2) by trigger x side x direction: n, mean profit, median hold, median entry minute; (3) the capture test — for the GOAL trigger,
# what simple fixed exits (+5/+10/+15 min, or next goal) capture as a share of the perfect exit. -> oracle_summary table + printed.
cd /root/pe-factory && cat > oracle_clean.py <<'PYFILE'
import sys, math, datetime, psycopg2, psycopg2.extras, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
COMM=0.02; STAKE=10.0; today=datetime.date.today()
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET statement_timeout='3000s'")
pd.set_option('display.width',250); pd.set_option('display.max_rows',200)
cur.execute("""CREATE TABLE IF NOT EXISTS oracle_games (run_date DATE, event_id TEXT, event_name TEXT, country TEXT, mt TIMESTAMPTZ, sel TEXT, direction TEXT, entry_min INT, entry_px NUMERIC, exit_min INT, exit_px NUMERIC, profit_10 NUMERIC, trigger TEXT, goals INT)""")
cur.execute("DELETE FROM oracle_games WHERE run_date=%s",(today,))
def prof(p): return p*(1-COMM) if p>0 else p
cur.execute("SELECT DISTINCT event_id FROM bf_hist_price WHERE mkt='MO'"); evs=[r[0] for r in cur.fetchall()]; print("games:",len(evs),flush=True)
rows=[]
def best_windows(mins,px,barred=set()):
    # best back->lay: max px[i]/px[j]-1 with j>i+1 (price falls after back)  ; best lay->back: max px[j]/px[i]-1 ... careful: lay at e then back at x<e profits (1-e/x)? no: lay at e (high), back at x (low) profit = (e/x-1)*stake? Lay stake s at e, back s*e/x at x -> green = s*(e/x-1)... use hedged per £10 stake: back->lay (back e, lay x<e): 10*(e/x-1); lay->back (lay e, back x>e?) no.
    # Correct: BACK at e then LAY at x where x<e profits 10*(e/x-1). LAY at e then BACK at x where x>e profits 10*(1-e/x).
    n=len(px); bl=(None,-1); lb=(None,-1)
    sufmin=np.minimum.accumulate(px[::-1])[::-1]; sufmax=np.maximum.accumulate(px[::-1])[::-1]
    for i in range(n-2):
        if int(mins[i]) in barred: continue
        j=i+2
        mn=sufmin[j:].min() if j<n else None
        if mn is not None and mn>0:
            p=10*(px[i]/mn-1)
            if p>bl[1]: k=j+int(np.argmin(px[j:])); bl=((i,k),p)
        mx=sufmax[j:].max() if j<n else None
        if mx is not None and mx>0:
            p2=10*(1-px[i]/mx)
            if p2>lb[1]: k=j+int(np.argmax(px[j:])); lb=((i,k),p2)
    return bl,lb
for b in range(0,len(evs),1500):
    D=pd.read_sql("SELECT event_id, event_name, country, m, minute, sel, ltp::float ltp FROM bf_hist_price WHERE mkt='MO' AND event_id = ANY(%s) AND minute BETWEEN 0 AND 95 ORDER BY event_id, sel, minute",con,params=(evs[b:b+1500],))
    for eid,g in D.groupby('event_id',sort=False):
        dr=g[g.sel=='DRAW'].drop_duplicates('minute')
        if len(dr)<30: continue
        # goal minutes = draw jumps >=20pct minute to minute
        dv=dr.ltp.values; dm=dr.minute.values; goals=[int(dm[i]) for i in range(1,len(dv)) if dv[i]>=dv[i-1]*1.20]
        gl=[];
        for gm in goals:
            if not gl or gm-gl[-1]>=4: gl.append(gm)
        barred=set(x for x in gl)|set(x+1 for x in gl)
        def trig(m):
            if any(2<=m-x<=5 for x in gl): return 'GOAL'
            if 44<=m<=47: return 'HT'
            if m<=5: return 'EARLY'
            if m>=75: return 'LATE'
            return 'HINDSIGHT'
        for sel,s in g.groupby('sel'):
            s=s.drop_duplicates('minute'); px=s.ltp.values; mins=s.minute.values
            if len(px)<30 or (px<=1).any(): continue
            bl,lb=best_windows(mins,px,barred)
            for (ij,p),direction in ((bl,'back->lay'),(lb,'lay->back')):
                if ij is None: continue
                i,k=ij; pr=prof(p)
                rows.append((today,eid,g.event_name.iloc[0],g.country.iloc[0],pd.Timestamp(g.m.iloc[0]),sel,direction,int(mins[i]),float(px[i]),int(mins[k]),float(px[k]),round(float(pr),2),trig(int(mins[i])),len(gl)))
    print(" processed",min(b+1500,len(evs)),flush=True)
psycopg2.extras.execute_values(cur,"INSERT INTO oracle_games VALUES %s",rows,page_size=2000)
R=pd.DataFrame(rows,columns=['d','eid','ev','country','mt','sel','direction','emin','epx','xmin','xpx','p10','trigger','goals'])
print("\n=== PERFECT EXITS — two seasons, per £10 stake ===")
G=R.groupby('eid').p10.agg(['sum','max']); print(f"games {len(G)} | perfect profit if you took the best trade on every selection both ways: mean £{G['sum'].mean():.2f}/game | best single trade per game: mean £{G['max'].mean():.2f}")
T=R.groupby('trigger').p10.agg(['count','sum','mean']).sort_values('sum',ascending=False); T['share_of_profit']=(T['sum']/T['sum'].sum()).round(3); print("\nWhere the perfect profit sits, by what was happening at the entry:\n",T.round(2).to_string())
print("\nBy trigger x selection x direction (n, mean £/£10, median hold mins, median entry minute):")
X=R.assign(hold=R.xmin-R.emin).groupby(['trigger','sel','direction']).agg(n=('p10','size'),mean_p=('p10','mean'),med_hold=('hold','median'),med_entry=('emin','median')).round(2); print(X.sort_values('mean_p',ascending=False).to_string())
# capture test for GOAL trigger: lay the side whose price just fell (the scorer) vs back the draw etc is covered by M1; here: for each GOAL-trigger oracle trade, what share does a fixed exit capture?
print("\nCapture test (GOAL-trigger entries only): share of the perfect exit captured by fixed exits")
goal_rows=R[R.trigger=='GOAL']; print("  perfect GOAL-trigger trades:",len(goal_rows),"| mean perfect £",round(goal_rows.p10.mean(),2))
cap=[]
for b in range(0,len(evs),3000):
    sub=goal_rows[goal_rows.eid.isin(evs[b:b+3000])&(goal_rows.direction=='back->lay')]
    if sub.empty: continue
    P=pd.read_sql("SELECT event_id, sel, minute, ltp::float ltp FROM bf_hist_price WHERE mkt='MO' AND event_id = ANY(%s) AND minute BETWEEN 0 AND 95",con,params=(list(sub.eid.unique()),))
    for _,r in sub.iterrows():
        s_=P[(P.event_id==r.eid)&(P.sel==r.sel)].drop_duplicates('minute').set_index('minute').ltp
        if r.emin not in s_.index: continue
        e=s_[r.emin]; out={}
        for h in (5,10,15):
            m=r.emin+h; m=m if m in s_.index else (s_.index[s_.index>=m].min() if (s_.index>=m).any() else None)
            if m is None or pd.isna(m): continue
            x=s_[m]; p=10*(e/x-1); out[h]=p*(1-COMM) if p>0 else p
        cap.append(dict(perfect=r.p10,**{f'fix{h}':out.get(h) for h in (5,10,15)}))
C=pd.DataFrame(cap); print("  scorer-side back->lay after a goal (entry 2-5 min after the jump), n",len(C))
for h in (5,10,15): print(f"   fixed exit +{h} min: mean £{C[f'fix{h}'].mean():+.2f} per £10 | positive {int((C[f'fix{h}']>0).mean()*100)}% | share of perfect {C[f'fix{h}'].sum()/C.perfect.sum():.1%}")
cur.execute("""CREATE TABLE IF NOT EXISTS oracle_summary (run_date DATE, trigger TEXT, n INT, total NUMERIC, mean NUMERIC, share NUMERIC)"""); cur.execute("DELETE FROM oracle_summary WHERE run_date=%s",(today,))
psycopg2.extras.execute_values(cur,"INSERT INTO oracle_summary VALUES %s",[(today,t,int(r['count']),float(round(r['sum'],2)),float(round(r['mean'],3)),float(r['share_of_profit'])) for t,r in T.iterrows()])
print("\nBy country (perfect profit per game):\n",R.groupby('country').apply(lambda g: g.groupby('eid').p10.sum().mean()).round(2).sort_values(ascending=False).to_string())
PYFILE
python3 -m py_compile oracle_clean.py || exit 1
timeout 3500 python3 oracle_clean.py 2>&1 | grep -v -E "UserWarning|pd.read_sql"
