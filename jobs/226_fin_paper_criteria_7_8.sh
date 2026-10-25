#!/bin/bash
# 226: re-evaluate criteria 7 and 8 from job 224 (test harness bug: autocommit set mid-transaction) and remove the self-test rows.
cd /root/pe-fin || exit 1
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); sys.path.insert(0,'/root/pe-fin'); from bot_core import DB
import fin_paper as fp
P=lambda k,ok,ev: print(f"  {k}: {'PASS' if ok else 'FAIL'} — {ev}")
c=psycopg2.connect(DB,sslmode='require'); c.autocommit=True; cur=c.cursor()
cur.execute("UPDATE fin_config SET value='5.0' WHERE key='risk_pct'"); v=fp.cfg(cur)['risk_pct']; P('7 risk_pct 5.0 clamped to hard cap 1.0',v==1.0,v); cur.execute("UPDATE fin_config SET value='0.5' WHERE key='risk_pct'")
cur.execute("UPDATE fin_config SET value='false' WHERE key='dry_run'"); v=fp.cfg(cur)['dry_run']; P('8 dry_run=false refused (no live path)',v is True,v); cur.execute("UPDATE fin_config SET value='true' WHERE key='dry_run'")
cur.execute("UPDATE fin_config SET value='20' WHERE key='max_open'"); v=fp.cfg(cur)['max_open']; P('9 max_open 20 clamped to 8',v==8,v); cur.execute("UPDATE fin_config SET value='5' WHERE key='max_open'")
cur.execute("SELECT id FROM fin_strategies WHERE tier='selftest'"); ids=[r[0] for r in cur.fetchall()]
for i in ids: cur.execute("DELETE FROM fin_paper_daily WHERE strategy_id=%s",(i,)); cur.execute("DELETE FROM fin_paper_positions WHERE strategy_id=%s",(i,))
cur.execute("DELETE FROM fin_strategies WHERE tier='selftest'"); print('  selftest strategies removed:',ids)
cur.execute("SELECT id,config,asset,tier,enabled,last_bar,last_pos,equity FROM fin_strategies ORDER BY id"); print('  strategies now:',cur.fetchall())
cur.execute("SELECT key,value FROM fin_config ORDER BY key"); print('  config:',cur.fetchall())
PY
