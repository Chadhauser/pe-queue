#!/bin/bash
set -o pipefail
# 499_fh3_settle_check (Finder 2026-11-05, queue item 138): is Aug 2026's jump in three-plus first-half goals real, or a settlement artefact of the goal_timeline HT row? Compares that row with af_fixtures ht_hg/ht_ag on the same fixture_id, by month. Read only, no prices.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,warnings,psycopg2,pandas as pd,numpy as np
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); import creds
con=psycopg2.connect(creds.pg_local()); cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='600s'")
G=pd.read_sql("""SELECT DISTINCT ON (fixture_id) fixture_id,captured_at,home_team,away_team,score_home h,score_away a FROM goal_timeline WHERE captured_at>='2026-06-01' AND captured_at<'2026-10-03' AND status='HT' AND score_home IS NOT NULL AND score_away IS NOT NULL ORDER BY fixture_id,captured_at DESC""",con)
G['mo']=pd.to_datetime(G.captured_at,utc=True).dt.strftime('%Y-%m'); G['tot']=G.h.astype(int)+G.a.astype(int); G['g3']=G.tot>=3; G['unq']=(G.h.astype(int)>2)|(G.a.astype(int)>2)
print("== goal_timeline HT rows by month: games, mean HT goals, share 3+, share Any Unquoted")
print(G.groupby('mo').agg(n=('tot','size'),mean=('tot','mean'),g3=('g3','mean'),unq=('unq','mean')).round(3).to_string())
A=pd.read_sql("SELECT fixture_id,home,away,ht_hg,ht_ag FROM af_fixtures WHERE ht_hg IS NOT NULL AND kickoff>='2026-05-31' AND kickoff<'2026-10-03'",con)
M=G.merge(A,on='fixture_id',how='inner'); M['same']=(M.h.astype(int)==M.ht_hg.astype(int))&(M.a.astype(int)==M.ht_ag.astype(int)); M['af3']=(M.ht_hg.astype(int)+M.ht_ag.astype(int))>=3
print("\n== fixture_id overlap with af_fixtures, by month: joined, same HT score, share 3+ on each source")
print(M.groupby('mo').agg(n=('same','size'),same=('same','mean'),feed3=('g3','mean'),af3=('af3','mean')).round(3).to_string())
print("\n== sample of joined rows, to confirm the ids are the same game (first 4 per month)")
for k,x in M.groupby('mo'):
    for r in x.head(4).itertuples(): print(f"  {k} {r.home_team} v {r.away_team} | af {r.home} v {r.away} | feed {r.h}-{r.a} af {int(r.ht_hg)}-{int(r.ht_ag)}")
print("\n== SURVIVORS: not a price test, none")
PY
