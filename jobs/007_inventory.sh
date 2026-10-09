#!/bin/bash
# 007 (rerun of 002): STAGE 1 INVENTORY — join results+goal times+form+pre-match price (fts_advanced_results) with tape (bf_hist_price) by match
cd /root/pe-scan && cat > inventory.py <<'PYFILE'
import re, datetime, collections, glob, os, psycopg2, pandas as pd, sys
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
def norm(s): return re.sub(r'[^a-z]','',(s or '').lower().split(' ')[0])
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor()
cur.execute("SELECT match_date, competition, season, home_team, away_team, goal_times, hf_gp, mo_home_back, p6_match_xg FROM fts_advanced_results")
F=pd.DataFrame(cur.fetchall(),columns=['d','league','season','h','a','gt','hf_gp','px','xg'])
F['d']=pd.to_datetime(F.d).dt.date; F['k']=F.d.astype(str)+'|'+F.h.map(norm)+'|'+F.a.map(norm)
F['has_px']=F.px.notna()&(F.px!=''); F['has_form']=pd.to_numeric(F.hf_gp,errors='coerce').fillna(0)>0; F['has_goals']=F['gt'].notna()
cur.execute("SELECT event_id, hw, aw, min(m)::date d, bool_or(mkt='MO') mo, bool_or(mkt='OU25') ou25, count(*) rows, max(calibrated::int) cal FROM bf_hist_price GROUP BY event_id,hw,aw")
T=pd.DataFrame(cur.fetchall(),columns=['eid','hw','aw','d','mo','ou25','rows','cal'])
T['hw']=T.hw.map(norm); T['aw']=T.aw.map(norm)
keys=set(F.k)
def joined(r):
    for off in (0,-1,1):
        if f"{r.d+datetime.timedelta(days=off)}|{r.hw}|{r.aw}" in keys: return True
    return False
T['joined']=T.apply(joined,axis=1)
print("STAGE 1 — INVENTORY\n")
print(f"Pre-match/results/goal-times/form table (fts_advanced_results): {len(F)} matches, {F.league.nunique()} leagues, {F.d.min()} to {F.d.max()}")
print(f"  with 7am Betfair price {F.has_px.sum()}, with form {F.has_form.sum()}, with goal times {F.has_goals.sum()}")
print(f"Tape (bf_hist_price, minute LTP): {len(T)} events, {T.d.min()} to {T.d.max()}; MO {T.mo.sum()}, OU2.5 {T.ou25.sum()}, half-time offset calibrated {int(T.cal.sum())}")
print(f"Correct Score: raw files only (not loaded) — 37,364 files, 9,953 joined to goal data in the 8 Oct run")
print(f"\nFULLY JOINED (tape MO+OU2.5 AND results/goals/price/form): {int(T.joined.sum())} of {len(T)} tape events")
Fj=F[F.k.isin({f'{r.d}|{r.hw}|{r.aw}' for r in T[T.joined].itertuples()}|{f'{r.d+datetime.timedelta(days=1)}|{r.hw}|{r.aw}' for r in T[T.joined].itertuples()}|{f'{r.d-datetime.timedelta(days=1)}|{r.hw}|{r.aw}' for r in T[T.joined].itertuples()})]
Fj=Fj.assign(tapeseason=Fj.d.map(lambda x: '2024/25' if x<datetime.date(2025,7,1) else '2025/26'))
print("\nJOINED MATCHES BY LEAGUE AND TAPE SEASON (Aug 2024 - Jun 2026):")
print(Fj.groupby(['league','tapeseason']).size().unstack(fill_value=0).to_string())
print("\nPRE-MATCH-ONLY MATCHES BY LEAGUE AND SEASON (no tape before Aug 2024):")
print(F.groupby(['league','season']).size().unstack(fill_value=0).to_string())
print("\nTAPE EVENTS NOT JOINED, by month (leagues outside the 28, or name mismatch):")
nj=T[~T.joined]; print(nj.groupby(pd.to_datetime(nj.d).dt.to_period('M')).size().to_string())
print("\nSample unjoined tape names:", list(nj.sample(min(15,len(nj)),random_state=1).apply(lambda r:f"{r.hw} v {r.aw} {r.d}",axis=1)))
print("\nMISSING / GAPS:")
print(" - tape covers 2 seasons only (Aug 2024-Jun 2026); pre-match covers 5.5. Validation on tape = train 2024/25, test 2025/26, not 5+3")
print(" - tape markets: MO, OU2.5 loaded; CS raw only; OU1.5/OU3.5/BTTS/FH goals NOT downloaded (pull written, blocked on expired Betfair token)")
print(" - Basic tier: no volume, LTP only; sub-minute ticks exist in raw files (used for goal overshoot job), minute table otherwise")
print(" - no in-play stats (shots/xG) historically; forward collection only")
PYFILE
raw=$(ls /root/bfdata 2>/dev/null | wc -l); echo "raw file top-level entries: $raw"
python3 inventory.py
