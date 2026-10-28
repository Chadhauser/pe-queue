#!/bin/bash
# 277: 276 started both size books (processes + cron confirmed) but died on a 'tail -3 a b' typo before writing the report script.
# Writes mm_report.py, runs it; audit ignores VOID rows in the 'settled without pnl' check.
set -e
cat > /root/pe-race/mm_report.py <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
k=psycopg2.connect(DB,sslmode='require').cursor()
k.execute("""SELECT book, count(*) rounds, count(*) FILTER (WHERE exit_reason='CAPTURED') captured, count(*) FILTER (WHERE exit_reason IN ('STOP','FLAT_PRE_OFF') OR exit_reason LIKE 'MARKET_%') adverse,
             count(*) FILTER (WHERE exit_reason IN ('UNFILLED','PULLED')) unfilled, round(avg(ticks),2) net_ticks,
             round(sum(pnl_per_10),2) pnl_at_book_stake,
             round(sum(pnl_per_10)*10/CASE book WHEN '50through' THEN 50 WHEN '200through' THEN 200 ELSE 10 END,2) pnl_per_10_equiv,
             round(avg(pnl_per_10)*10/CASE book WHEN '50through' THEN 50 WHEN '200through' THEN 200 ELSE 10 END,3) per_round_per_10
             FROM racing_mm_stream WHERE exit_reason IS NOT NULL GROUP BY 1 ORDER BY 1"""); print("book | rounds | captured | adverse | unfilled | net ticks | pnl@stake | pnl per £10 equiv | per round"); [print(r) for r in k.fetchall()]
PY
python3 /root/pe-race/mm_report.py
pgrep -af race_mm_size.py | head -3; crontab -l | grep -c keepalive_mm_size | sed 's/^/cron lines for size books: /'
tail -n 3 /root/pe-race/mm_size200.log || true
python3 - <<'PY'
p='/root/pe-push/integrity.py'; s=open(p).read()
old="""pnl_per_10 IS NULL AND coalesce(exit_reason,'')<>'UNKNOWN'"""
new="""pnl_per_10 IS NULL AND coalesce(exit_reason,'') NOT LIKE 'UNKNOWN%' AND coalesce(exit_reason,'') NOT LIKE 'VOID%'"""
assert old in s; open(p,'w').write(s.replace(old,new)); print("audit: VOID excluded")
PY
python3 -m py_compile /root/pe-push/integrity.py
