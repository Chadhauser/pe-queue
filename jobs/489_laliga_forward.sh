#!/bin/bash
set -o pipefail
# 489_laliga_forward (Finder 2026-11-04, items 36 and 39): the only La Liga data untouched by the line: season 2026-27 from goal_timeline, 15 Aug to now. RESULTS ONLY: no price for these games was looked at (liq_sample starts 30 Oct, and the Betfair historical tables were not searched).
# Test: 0-0 at the first feed row at or after minute T (30, 35), then did the final total reach 2? Against the two-season implied of jobs/489_laliga_checks.sh: 0.544 at 30', 0.506 at 35', won 0.625 and 0.598. The market may have moved since, so this is a test of goals, not of P&L.
# Feed rows flash phantom goals (item 0g), so a game counts as 0-0 only if the score is 0-0 on that row, and the final is taken from the last row, known only if status is FT or the minute reached 88. Control: Segunda (141), Serie A (135), Premier League (39), same feed window.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,math,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',200)
def z_one(k,n,p): return (k/n-p)/math.sqrt(p*(1-p)/n)
# known answer: 60 of 100 against 0.5: (0.6-0.5)/0.05 = 2.0
assert abs(z_one(60,100,0.5)-2.0)<1e-9
def game(g,T):
    # g sorted by time; returns (at_0_0, final_total, known)
    m=pd.to_numeric(g.minute,errors='coerce'); w=g[m>=T]
    if not len(w): return None
    r=w.iloc[0]; last=g.iloc[-1]; lm=pd.to_numeric(pd.Series([last.minute]),errors='coerce').iloc[0]
    known=str(last.status) in ('FT','AET','PEN','Match Finished','FINISHED') or (pd.notna(lm) and lm>=88)
    return (int(r.score_home)==0 and int(r.score_away)==0, int(last.score_home)+int(last.score_away), known)
t_=pd.DataFrame(dict(minute=[10,31,90],score_home=[0,0,2],score_away=[0,0,0],status=['1H','1H','FT']))
assert game(t_,30)==(True,2,True) and game(t_,95) is None
print("checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'"); cur.execute("SET statement_timeout='600s'")
IMP={30:(0.544,0.625),35:(0.506,0.598)}
for lg,nm in ((140,'La Liga'),(141,'Segunda'),(135,'Serie A'),(39,'Premier League')):
    D=pd.read_sql("SELECT fixture_id,captured_at,minute,score_home,score_away,status FROM goal_timeline WHERE league_id=%s AND score_home IS NOT NULL AND score_away IS NOT NULL AND captured_at>='2026-08-01' ORDER BY fixture_id,captured_at",con,params=(lg,))
    print(f"{nm}: {D.fixture_id.nunique()} fixtures, {D.captured_at.min()} .. {D.captured_at.max()}",flush=True)
    for T in (30,35):
        r=[game(g,T) for _,g in D.groupby('fixture_id')]; r=[x for x in r if x is not None]
        z=[x for x in r if x[0]]; kn=[x for x in z if x[2]]; k=sum(1 for x in kn if x[1]>=2); n=len(kn)
        if n==0: print(f"  T {T}: no games"); continue
        s=f"  T {T}: games reaching T {len(r)}, 0-0 {len(z)} ({len(z)/len(r):.3f}), known {n}, Over 1.5 won {k} = {k/n:.3f}, se {math.sqrt(k/n*(1-k/n)/n) if 0<k<n else 0:.3f}"
        if lg==140: s+=f" | v implied {IMP[T][0]}: z {z_one(k,n,IMP[T][0]):+.2f}; v two-season won {IMP[T][1]}: z {z_one(k,n,IMP[T][1]):+.2f}"
        print(s,flush=True)
PY
