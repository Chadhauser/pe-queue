#!/bin/bash
# 103: TENNIS LAY BOT -> PAPER ONLY, and the paper book re-scored with real hedge P&L. Finding (18 Oct): tennis_lay_paper scored
# GREEN as +0.40 and STOP as -0.12 (price-move units), not hedged profit. True hedged P&L per £1 stake = 1 - lay_at/exit_price
# (x0.98 on profit): since 3 Oct 813 trades = +0.0004 per £ staked (zero). Live 68 trades -£11.66. Nothing more goes on it.
python3 - <<'PY'
import sys, psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("UPDATE tennis_config SET value='true' WHERE key='dry_run'"); print("tennis bot dry_run=true rows",cur.rowcount)
cur.execute("ALTER TABLE tennis_lay_paper ADD COLUMN IF NOT EXISTS pnl_hedged_per_stake NUMERIC")
cur.execute("""UPDATE tennis_lay_paper SET pnl_hedged_per_stake = CASE WHEN exit_price>0 THEN (CASE WHEN 1-lay_at/exit_price>0 THEN (1-lay_at/exit_price)*0.98 ELSE 1-lay_at/exit_price END) END WHERE outcome IN ('GREEN','STOP')""")
print("paper rows re-scored",cur.rowcount)
cur.execute("SELECT count(*), round(avg(pnl_hedged_per_stake)::numeric,4), round(avg(pnl_per_1_liability)::numeric,4) FROM tennis_lay_paper WHERE outcome IN ('GREEN','STOP')"); print("paper: n, true per stake, old units:",cur.fetchone())
cur.execute("SELECT key,value FROM tennis_config ORDER BY 1"); print(cur.fetchall())
PY
# make the nightly paper writer score correctly from now on
f=$(grep -l "pnl_per_1_liability" /root/pe-*/*.py 2>/dev/null | head -1); echo "paper writer: $f"; [ -n "$f" ] && grep -n "pnl_per_1_liability\|0\.40\|0\.12\|green_pct\|stop_pct" "$f" | head -12
