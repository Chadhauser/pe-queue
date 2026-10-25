#!/bin/bash
# 227: THE OPPORTUNITY MAP — the "ideal full back test on every game" Peter asked for on 19 Oct and again on 25 Oct. For every
# in-play market the recorder has tracked from kick-off (liq_sample, real back/lay ladders, ~1/min, since 20 Oct) and every selection:
# the best hindsight hedged trade — back at the best back price at minute i then lay at the best lay price at minute j>=i+2
# (back-then-lay), and lay at i then back at j (lay-then-back) — per £10 stake, 2% commission. Records the best of each per selection
# with its entry minute, exit minute, prices and the score state at entry (goals so far from draw-book jumps; ESPN score where matched).
# Output: table opp_map (one row per market x selection x direction) and a summary — total hindsight money by market type, by entry
# minute band, by direction, by state; how concentrated it is (top 10% of games share); and what fraction our live rules captured.
# This is the ceiling against which every strategy is judged from now on. Nightly at 04:40 after today.
mkdir -p /root/pe-factory && cat > /root/pe-factory/opp_map.py <<'PYFILE'
import sys, psycopg2, psycopg2.extras, pandas as pd, numpy as np, datetime
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',230); pd.set_option('display.max_rows',200); COMM=0.02; HOLD=2
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("""CREATE TABLE IF NOT EXISTS opp_map (run_date DATE, market_id TEXT, event_name TEXT, competition TEXT, mkt TEXT, sel TEXT, direction TEXT, entry_min INT, exit_min INT, entry_px NUMERIC, exit_px NUMERIC,
  pnl_per_10 NUMERIC, goals_at_entry INT, n_samples INT, UNIQUE (market_id, sel, direction))""")
days=int(sys.argv[1]) if len(sys.argv)>1 else 30
ev=pd.read_sql("SELECT event_name FROM liq_sample WHERE mkt='MO' AND ts>now()-interval '%s days' GROUP BY event_name HAVING min(minute)<=5 AND max(minute)>=88 AND count(DISTINCT market_id)=1"%days,con)
events=list(ev.event_name); print("events tracked from kick-off:",len(events),flush=True)
rows=[]
for b in range(0,len(events),150):
    S=pd.read_sql("SELECT market_id, event_name, competition, ts, minute, mkt, sel, back_px::float bp, lay_px::float lp FROM liq_sample WHERE event_name = ANY(%s) AND back_px IS NOT NULL AND lay_px IS NOT NULL AND lay_px<=back_px*1.25 AND minute BETWEEN 0 AND 95 ORDER BY event_name, ts",con,params=(events[b:b+150],))
    for evn,g in S.groupby('event_name',sort=False):
        d=g[(g.mkt=='MO')&(g.sel=='DRAW')].copy(); d['pb']=d.bp.shift(); d['pl']=d.lp.shift(); jumps=sorted(d[(d.bp>=d.pb*1.25)&(d.bp>=d.pl*1.25)].minute.tolist())
        def goals_at(m): return sum(1 for j in jumps if j<=m)
        for (mid,mkt,sel),s in g.groupby(['market_id','mkt','sel'],sort=False):
            s=s.drop_duplicates('minute').sort_values('minute')
            if len(s)<10: continue
            mins=s.minute.values; bp=s.bp.values; lp=s.lp.values
            # back-then-lay: profit = 10*(bp_i/lp_j - 1) for j with minute>=minute_i+HOLD; best over i,j
            best={'BL':(-99,None,None,None,None),'LB':(-99,None,None,None,None)}
            n=len(mins)
            # suffix minimum of lay price (for back-then-lay) and suffix maximum of back price (for lay-then-back) over eligible j
            for i in range(n):
                j0=np.searchsorted(mins,mins[i]+HOLD)
                if j0>=n: break
                jmin=j0+int(np.argmin(lp[j0:])); p=10*(bp[i]/lp[jmin]-1); p=p*(1-COMM) if p>0 else p
                if p>best['BL'][0]: best['BL']=(p,int(mins[i]),int(mins[jmin]),float(bp[i]),float(lp[jmin]))
                jmax=j0+int(np.argmax(bp[j0:])); q=10*(1-lp[i]/bp[jmax]); q=q*(1-COMM) if q>0 else q
                if q>best['LB'][0]: best['LB']=(q,int(mins[i]),int(mins[jmax]),float(lp[i]),float(bp[jmax]))
            for dr,(p,ei,xi,epx,xpx) in best.items():
                if ei is None: continue
                rows.append((datetime.date.today(),mid,evn,g.competition.iloc[0],mkt,sel,dr,ei,xi,round(epx,2),round(xpx,2),round(p,2),goals_at(ei),n))
    print("  ",min(b+150,len(events)),"events, rows",len(rows),flush=True)
cur.execute("DELETE FROM opp_map WHERE market_id IN %s",(tuple(set(r[1] for r in rows)) or ('x',),)) if rows else None
psycopg2.extras.execute_values(cur,"INSERT INTO opp_map VALUES %s ON CONFLICT (market_id, sel, direction) DO UPDATE SET pnl_per_10=EXCLUDED.pnl_per_10, entry_min=EXCLUDED.entry_min, exit_min=EXCLUDED.exit_min, entry_px=EXCLUDED.entry_px, exit_px=EXCLUDED.exit_px, goals_at_entry=EXCLUDED.goals_at_entry, run_date=EXCLUDED.run_date",rows,page_size=2000)
R=pd.DataFrame(rows,columns=['d','market_id','event','comp','mkt','sel','dir','entry_min','exit_min','entry_px','exit_px','p','goals','n'])
print(f"\n=== OPPORTUNITY MAP: {R.event.nunique()} games, {len(R)} market-selection-direction cells, hindsight best hedged trade per £10, 2% comm ===")
print("\nMoney available per game by market type (sum of best trades across its selections, both directions):")
print(R.groupby(['event','mkt']).p.sum().groupby('mkt').agg(['mean','median','max']).round(2).to_string())
print("\nBest single trade per game — distribution:",R.groupby('event').p.max().describe().round(2).to_dict())
top=R.groupby('event').p.max().sort_values(ascending=False); print("share of total best-trade money in the top 10% of games:",round(top.head(max(1,len(top)//10)).sum()/top.sum(),2))
R['band']=pd.cut(R.entry_min,[-1,15,30,45,60,75,95],labels=['0-15','16-30','31-45','46-60','61-75','76-95'])
print("\nMean best trade by entry-minute band x direction (BL=back then lay, LB=lay then back):\n",R.pivot_table(index='band',columns='dir',values='p',aggfunc='mean',observed=True).round(2).to_string())
print("\nMean best trade by market x direction:\n",R.pivot_table(index='mkt',columns='dir',values='p',aggfunc='mean',observed=True).round(2).to_string())
print("\nMean best trade by goals-at-entry (MO + OU25 only):\n",R[R.mkt.isin(['MO','OU25'])].pivot_table(index='goals',columns=['mkt','dir'],values='p',aggfunc='mean',observed=True).round(2).to_string())
print("\nTop 15 selections by hindsight money (where the big moves are):\n",R.groupby(['mkt','sel','dir']).p.agg(['size','mean']).sort_values('mean',ascending=False).head(15).round(2).to_string())
print("\nTypical late lay-Over opportunity (OU25 OVER, LB, entry 70-85):",R[(R.mkt=='OU25')&(R.sel=='OVER')&(R['dir']=='LB')&(R.entry_min.between(70,85))].p.describe().round(2).to_dict())
PYFILE
python3 -m py_compile /root/pe-factory/opp_map.py || exit 1
python3 - <<'PY'
# unit test of the hindsight search on a synthetic path
import numpy as np
mins=np.array([0,1,2,3,4,5]); bp=np.array([2.0,2.1,2.2,2.3,2.4,2.5]); lp=bp+0.02; HOLD=2; COMM=0.02
best=(-99,None,None); n=len(mins)
for i in range(n):
    j0=np.searchsorted(mins,mins[i]+HOLD)
    if j0>=n: break
    jmax=j0+int(np.argmax(bp[j0:])); q=10*(1-lp[i]/bp[jmax]); q=q*(1-COMM) if q>0 else q
    if q>best[0]: best=(q,int(mins[i]),int(mins[jmax]))
print(best); assert best[1]==0 and best[2]==5 and abs(best[0]-10*(1-2.02/2.5)*0.98)<1e-6; print("hindsight search PASS")
PY
cd /root/pe-factory && timeout 3000 python3 opp_map.py 30 2>&1 | grep -v -E "UserWarning|pd.read_sql"
( crontab -l 2>/dev/null | grep -v opp_map ; echo "40 4 * * * cd /root/pe-factory && python3 opp_map.py 3 >> opp_map.log 2>&1" ) | crontab -
echo "nightly 04:40 installed"
