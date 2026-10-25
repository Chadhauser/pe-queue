#!/bin/bash
# 152: PUT THE FOOTBALL INTO THE FOOTBALL LINES (Peter 25 Oct: "are you actually adding in the football side not just price?").
# (a) late CS: every leg gets the match stats at its entry minute from ip_stats (shots, on target, xG, dangerous attacks, both teams)
#     and the nightly report splits P&L by shot pressure — the hypothesis is that the next-goal CS back only pays when the game is
#     producing chances (combined SOT >= 6 or xG >= 1.8 by the hour). (b) M1 pushes get the same columns so Monday's direction decision
#     can be conditioned on pressure, not price alone. (c) Coverage check: what share of our CS/M1 markets have stats at all (API-Football
#     live covers top leagues only) — if coverage is thin the stats recorder's league list is widened. Runs nightly 03:20 after cs_late.
cat > /root/pe-cs/stats_join.py <<'PYFILE'
import sys, psycopg2, pandas as pd
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',220)
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
for t,mincol in (('cs_late_paper','entry_min'),('m1_alerts','minute')):
    for c in ('h_sot','a_sot','h_shots','a_shots','h_xg','a_xg','h_dang','a_dang','stats_min'):
        cur.execute(f"ALTER TABLE {t} ADD COLUMN IF NOT EXISTS {c} NUMERIC")
    # latest stats row at or before the entry minute for the same market
    cur.execute(f"""UPDATE {t} p SET h_sot=s.h_sot, a_sot=s.a_sot, h_shots=s.h_shots, a_shots=s.a_shots, h_xg=s.h_xg, a_xg=s.a_xg, h_dang=s.h_dang, a_dang=s.a_dang, stats_min=s.minute
        FROM (SELECT DISTINCT ON (market_id) market_id, minute, h_sot, a_sot, h_shots, a_shots, h_xg, a_xg, h_dang, a_dang FROM ip_stats WHERE market_id IS NOT NULL ORDER BY market_id, minute DESC) s
        WHERE p.market_id=s.market_id AND p.stats_min IS NULL AND s.minute<=coalesce(p.{mincol},95)""")
    print(t,"rows given stats:",cur.rowcount)
    cur.execute(f"SELECT count(*), count(stats_min) FROM {t} WHERE market_id IS NOT NULL"); n,c=cur.fetchone(); print(f"  coverage: {c} of {n} markets have stats ({(c/n*100 if n else 0):.0f}%)")
D=pd.read_sql("SELECT entry_min, live_score, leg, back_px, pnl, h_sot, a_sot, h_shots, a_shots, h_xg, a_xg FROM cs_late_paper WHERE pnl IS NOT NULL",con)
if len(D):
    D['sot']=D.h_sot+D.a_sot; D['xg']=D.h_xg+D.a_xg; D['shots']=D.h_shots+D.a_shots
    print("\nLATE CS by shot pressure at entry (settled legs, per £10):")
    for col,bins in (('sot',[-1,3,5,7,9,99]),('xg',[-1,1.0,1.5,2.0,2.5,99]),('shots',[-1,10,15,20,25,99])):
        d=D.dropna(subset=[col]);
        if d.empty: print(" ",col,": no stats yet"); continue
        d=d.assign(b=pd.cut(d[col],bins)); print(d.groupby('b',observed=True).pnl.agg(['count','sum','mean']).round(2).to_string())
    print("  no stats at entry: n",int(D.sot.isna().sum()),"pnl",round(D[D.sot.isna()].pnl.sum(),2))
M=pd.read_sql("SELECT goal_ts::date d, exit_reason, entry_px, exit_px, h_sot, a_sot, h_xg, a_xg FROM m1_alerts WHERE reason NOT LIKE 'SKIP%%' AND exit_px IS NOT NULL",con)
if len(M):
    M['pnl']=10*(1-M.entry_px/M.exit_px); M['sot']=M.h_sot+M.a_sot
    print("\nM1 (lay scorer) by combined SOT at the goal, per £10:")
    m=M.dropna(subset=['sot']); print(m.assign(b=pd.cut(m.sot,[-1,3,6,9,99])).groupby('b',observed=True).pnl.agg(['count','sum','mean']).round(2).to_string() if len(m) else "  no stats yet")
    print("  M1 pushes without stats:",int(M.sot.isna().sum()))
cur.execute("SELECT league, count(DISTINCT market_id) FROM ip_stats WHERE ts>now()-interval '3 days' AND market_id IS NOT NULL GROUP BY 1 ORDER BY 2 DESC LIMIT 25"); print("\nstats coverage by league, last 3 days (matched to a Betfair market):",cur.fetchall())
cur.execute("SELECT count(DISTINCT market_id) FROM liq_sample WHERE mkt='MO' AND ts>now()-interval '3 days'"); print("Betfair MO markets recorded, last 3 days:",cur.fetchone()[0])
PYFILE
python3 -m py_compile /root/pe-cs/stats_join.py || exit 1
( crontab -l 2>/dev/null | grep -v stats_join.py ; echo "20 3 * * * cd /root/pe-cs && python3 stats_join.py >> stats_join.log 2>&1" ) | crontab -
cd /root/pe-cs && python3 stats_join.py 2>&1 | grep -v -E "UserWarning|pd.read_sql"
