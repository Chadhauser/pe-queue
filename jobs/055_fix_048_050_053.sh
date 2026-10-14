#!/bin/bash
# 055: three scan failures from 13 Oct fixed and rerun in one go.
#  048 racing pre-off: tz-aware vs naive timestamp compare -> compare in UTC.
#  050 reopen scan: itertuples attribute access bug; also wait for 7 days of tape (not 3,000 reopens) so the halves are real.
#  053 goal signal vs market: predictions since Aug 22 have watchlist_id NULL -> names come from goal_timeline (fixture_id -> teams/league, 20,799 fixtures).
set -e
cd /root/pe-scan
python3 - <<'PY'
import re
p='racing_preoff_scan.py'; s=open(p).read()
s=s.replace("pd.to_datetime(D.market_start)<pd.Timestamp('2026-10-01')","pd.to_datetime(D.market_start,utc=True)<pd.Timestamp('2026-10-01',tz='UTC')")
open(p,'w').write(s)
p='inplay_reopen_scan.py'; s=open(p).read()
s=s.replace("x=r[f'mid{off}']","x=getattr(r,f'mid{off}')")
s=s.replace('if n<3000 and (t1 is None or (t1-t0).days<7): print("WAITING: need 7 days or 3,000 reopens"); sys.exit(75)','if t1 is None or (t1-t0).days<7: print("WAITING: need 7 days of tape, have",(t1-t0) if t1 else None); sys.exit(75)')
open(p,'w').write(s)
p='goal_signal_vs_market_v2.py'; s=open(p).read()
old=s[s.index('P=pd.read_sql("""SELECT p.id'):s.index('print("predictions since tape start:"')]
new='''P=pd.read_sql("""SELECT p.id, p.captured_at, p.minute, p.score_home, p.score_away, p.p_goal_next_10, p.p_goal_next_15, p.signal_direction, p.alert_sent,
   p.goal_within_10, p.next_goal_minute, t.home_team, t.away_team, t.league_name AS league FROM goal_live_predictions p
   JOIN (SELECT DISTINCT ON (fixture_id) fixture_id, home_team, away_team, league_name FROM goal_timeline ORDER BY fixture_id, captured_at) t ON t.fixture_id=p.fixture_id
   WHERE p.captured_at >= '2026-08-22' AND p.settled AND p.minute BETWEEN 10 AND 80""",con)
P['captured_at']=pd.to_datetime(P.captured_at,utc=True)
'''
s=s.replace(old,new)
s=s.replace("T=pd.read_sql(\"\"\"SELECT captured_at, market_name","T=pd.read_sql(\"\"\"SELECT captured_at AT TIME ZONE 'UTC' AS captured_at, market_name")
s=s.replace("print(\"tape rows\",len(T),flush=True)","T['captured_at']=pd.to_datetime(T.captured_at,utc=True); print(\"tape rows\",len(T),flush=True)")
open(p,'w').write(s)
PY
python3 -m py_compile racing_preoff_scan.py inplay_reopen_scan.py goal_signal_vs_market_v2.py
echo "=================== 048 RACING PRE-OFF ==================="; python3 racing_preoff_scan.py || true
echo "=================== 053 GOAL SIGNAL VS MARKET ==================="; python3 goal_signal_vs_market_v2.py || true
echo "=================== 050 (re-queued as waiting job) ==================="; python3 inplay_reopen_scan.py || true
