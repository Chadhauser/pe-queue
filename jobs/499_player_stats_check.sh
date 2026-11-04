#!/bin/bash
set -o pipefail
# 499_player_stats_check (Finder 2026-11-04, queue item 62): read only. Is af_player_stats right? Known answers come from af_fixtures and af_events, which it was not loaded from: summed player goals v the FT score plus own goals, team names v the fixture's home and away, minutes per team, and what a null goals or shots value means.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,psycopg2,pandas as pd
sys.path.insert(0,'/root/pe-queue/runner'); import creds
pd.set_option('display.width',200); pd.set_option('display.max_columns',20)
def goal_check(player_goals,ft,own):
    """Player goals exclude own goals: a clean fixture has player_goals + own == ft."""
    return player_goals+own==ft
assert goal_check(2,3,1) and goal_check(3,3,0) and not goal_check(3,3,1) and not goal_check(0,1,0)
print("checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; k=con.cursor(); k.execute("SET work_mem='64MB'; SET statement_timeout='600s'")
print(pd.read_sql("SELECT fixture_id,league,season,kickoff::date,home,away,hg,ag FROM af_fixtures WHERE fixture_id=1636350",con).to_string(index=False))
P=pd.read_sql("""SELECT s.fixture_id,count(*) n,count(DISTINCT s.team) teams,coalesce(sum(s.goals),0) g,count(*) FILTER (WHERE s.goals=0) zero_g,count(*) FILTER (WHERE s.goals IS NULL AND s.minutes>0) null_g_played,count(*) FILTER (WHERE s.minutes>0) played,coalesce(sum(s.minutes),0) mins
 FROM af_player_stats s GROUP BY 1""",con)
F=pd.read_sql("SELECT fixture_id,league,season,home,away,hg,ag,events_done FROM af_fixtures WHERE fixture_id=ANY(%s)",con,params=(list(map(int,P.fixture_id)),))
O=pd.read_sql("SELECT fixture_id,count(*) own FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail='Own Goal' GROUP BY 1",con,params=(list(map(int,P.fixture_id)),))
M=P.merge(F,on='fixture_id').merge(O,on='fixture_id',how='left'); M['own']=M.own.fillna(0); M['ft']=M.hg+M.ag; M['ok']=[goal_check(a,b,c) for a,b,c in zip(M.g,M.ft,M.own)]
print(f"\nfixtures {len(M)}; two teams {(M.teams==2).mean():.4f}; players per fixture median {M.n.median():.0f}; played per fixture median {M.played.median():.0f}; team-minutes per fixture median {M.mins.median():.0f} (11 x 90 x 2 = 1980)")
print(f"summed player goals + own goals = FT: {M.ok.mean():.4f}; events-loaded fixtures only {M[M.events_done==True].ok.mean():.4f}; mean absolute miss {(M.g+M.own-M.ft).abs().mean():.3f}; fixtures with a null goals row among players who played {(M.null_g_played>0).mean():.3f}")
print("worst leagues:"); print(M.groupby('league').agg(n=('ok','size'),ok=('ok','mean')).sort_values('ok').head(6).round(3).to_string())
Tn=pd.read_sql("SELECT DISTINCT s.fixture_id,s.team FROM af_player_stats s",con).merge(F,on='fixture_id'); Tn['match']=(Tn.team==Tn.home)|(Tn.team==Tn.away); print(f"\nteam name equals the fixture's home or away: {Tn.match.mean():.4f}; team 'unknown': {(Tn.team=='unknown').sum()}")
print(pd.read_sql("SELECT count(*) rows,count(*) FILTER (WHERE goals>=5) g5,max(goals) gmax,max(minutes) mmax,min(rating) rmin,max(rating) rmax FROM af_player_stats",con).to_string(index=False))
print(pd.read_sql("SELECT f.league,count(*) empty FROM af_player_stats_done d JOIN af_fixtures f USING (fixture_id) WHERE d.n=0 GROUP BY 1 ORDER BY 2 DESC LIMIT 5",con).to_string(index=False))
k.execute("SELECT count(*) FROM af_fixtures f LEFT JOIN af_player_stats_done d USING (fixture_id) WHERE f.season>=2024 AND f.status='FT' AND d.fixture_id IS NULL"); print("finished fixtures still to fetch:",k.fetchone()[0])
con.close()
print("\n== SURVIVORS\nnot applicable: data check, no P&L")
PY
