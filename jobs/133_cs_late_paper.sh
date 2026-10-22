#!/bin/bash
# 133: LATE CORRECT-SCORE PAPER BOOK (the strongest CSM shape from the 8 Oct test: enter 55-70' on CS selections priced 12-30 that
# are ONE goal away from the live score; green when the goal lands; +16..+54 per £100 at 12-20, +80..+260 at 20-30, both seasons).
# CS ladders have been on tape since 18 Oct (liq_sample). Nightly 03:10: for every game with CS rows, at the first sample in the
# 58-62' window: live score = CS selection with the lowest lay price; candidates = (h+1,a) and (h,a+1) with back price 12-30;
# paper BACK £10 each at the back price; if a later goal makes the candidate the live score, exit at its lay price 2 minutes after
# the goal (hedged green = 10*(back/lay-1)*0.98); otherwise -£10 at FT. -> cs_late_paper. Verdict after 60 legs; then £5/leg live.
mkdir -p /root/pe-cs && cat > /root/pe-cs/cs_late_paper.py <<'PYFILE'
import sys, re, datetime, psycopg2, psycopg2.extras, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
STAKE=10.0; COMM=0.02
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("""CREATE TABLE IF NOT EXISTS cs_late_paper (id SERIAL PRIMARY KEY, play_date DATE, market_id TEXT, event_name TEXT, competition TEXT, entry_min INT, live_score TEXT, leg TEXT,
  back_px NUMERIC, landed_min INT, lay_px NUMERIC, pnl NUMERIC, cs_matched NUMERIC, recorded_at TIMESTAMPTZ DEFAULT now(), UNIQUE (market_id, leg))""")
cur.execute("SELECT DISTINCT mkt FROM liq_sample WHERE ts>now()-interval '2 days'"); mk=[r[0] for r in cur.fetchall()]
CS=[m for m in mk if 'CORRECT' in m.upper() or m.upper()=='CS']
if not CS: print("no CS market rows on tape yet; mkts seen:",mk); sys.exit(0)
CS=CS[0]
def score(s):
    m=re.match(r'\s*(\d+)\s*-\s*(\d+)',str(s)); return (int(m.group(1)),int(m.group(2))) if m else None
cur.execute("SELECT DISTINCT market_id, event_name, competition FROM liq_sample WHERE mkt=%s AND minute BETWEEN 50 AND 95 AND ts>now()-interval '3 days'",(CS,))
games=cur.fetchall(); print("games with CS tape 50'+ in last 3 days:",len(games),flush=True)
rows=[]
for mid,ev,comp in games:
    S=pd.read_sql("SELECT ts, minute, sel, back_px::float back_px, lay_px::float lay_px, total_matched::float tm FROM liq_sample WHERE market_id=%s AND mkt=%s AND minute>=55 ORDER BY ts",con,params=(mid,CS))
    if S.empty: continue
    S=S[S.sel.map(score).notna()]
    ent=S[(S.minute>=58)&(S.minute<=62)]
    if ent.empty: continue
    t0=ent.ts.iloc[0]; snap=S[S.ts==t0]
    lv=snap[snap.lay_px.notna()].sort_values('lay_px')
    if lv.empty: continue
    live=score(lv.sel.iloc[0]); h,a=live
    cands=[f"{h+1} - {a}",f"{h} - {a+1}"]
    # live-score timeline after entry: at each ts the sel with the lowest lay price
    piv=S[S.ts>t0].pivot_table(index='ts',columns='sel',values='lay_px',aggfunc='last').ffill()
    live_series=piv.idxmin(axis=1) if not piv.empty else pd.Series(dtype=object)
    for leg in cands:
        row=snap[snap.sel.map(lambda x: score(x)==score(leg))]
        if row.empty or pd.isna(row.back_px.iloc[0]): continue
        bp=float(row.back_px.iloc[0])
        if not (12<=bp<=30): rows.append((datetime.date.today(),mid,ev,comp,int(ent.minute.iloc[0]),f"{h}-{a}",leg,bp,None,None,None,float(snap.tm.max() or 0))); continue
        hit=live_series[live_series.map(lambda x: score(x)==score(leg))]
        if hit.empty: pnl=-STAKE; lm=None; lp=None
        else:
            tg=hit.index[0]; lm=int(S[S.ts==tg].minute.iloc[0]) if not S[S.ts==tg].empty else None
            later=S[(S.ts>=tg+pd.Timedelta(minutes=2))&(S.sel.map(lambda x: score(x)==score(leg)))&S.lay_px.notna()]
            if later.empty: pnl=-STAKE; lp=None   # landed but no exit price (late goal, market closed)
            else:
                lp=float(later.lay_px.iloc[0]); g=STAKE*(bp/lp-1); pnl=g*(1-COMM) if g>0 else g
        rows.append((datetime.date.today(),mid,ev,comp,int(ent.minute.iloc[0]),f"{h}-{a}",leg,bp,lm,lp,round(pnl,2),float(snap.tm.max() or 0)))
if rows:
    psycopg2.extras.execute_values(cur,"INSERT INTO cs_late_paper (play_date,market_id,event_name,competition,entry_min,live_score,leg,back_px,landed_min,lay_px,pnl,cs_matched) VALUES %s ON CONFLICT (market_id,leg) DO NOTHING",rows)
cur.execute("SELECT count(*) legs, count(*) FILTER (WHERE pnl IS NOT NULL) priced_12_30, count(*) FILTER (WHERE landed_min IS NOT NULL) landed, round(sum(pnl)::numeric,2) pnl, round(avg(pnl)::numeric,2) per_leg FROM cs_late_paper")
print("LATE CS paper to date (legs, in 12-30 band, landed, total P&L per £10 legs, per leg):",cur.fetchone())
cur.execute("SELECT event_name, live_score, leg, back_px, landed_min, lay_px, pnl FROM cs_late_paper WHERE recorded_at>now()-interval '1 hour' AND pnl IS NOT NULL ORDER BY pnl DESC LIMIT 25")
for r in cur.fetchall(): print("  ",r)
PYFILE
python3 -m py_compile /root/pe-cs/cs_late_paper.py || exit 1
( crontab -l 2>/dev/null | grep -v cs_late_paper ; echo "10 3 * * * cd /root/pe-cs && python3 cs_late_paper.py >> cs_late_paper.log 2>&1" ) | crontab -
cd /root/pe-cs && python3 cs_late_paper.py 2>&1 | grep -v -E "UserWarning|pd.read_sql"
