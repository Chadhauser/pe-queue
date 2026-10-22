#!/bin/bash
# 124: Peter 22 Oct 03:09 — "why is it still placing bets, I have lost another 9, it bet on Urawa". That is the PG bot (J-League is
# on its whitelist, live £2). With Betfair credentials possibly exposed in the Railway breach, real-money bots go to paper until he
# has changed the password and the evidence pass (123) is clean. Everything keeps recording; nothing new is staked.
python3 - <<'PY'
import sys, psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("UPDATE pg_control SET dry_run=true, note=concat(coalesce(note,''),' | PAPER from 22 Oct 03:10 (Railway breach, Peter)') WHERE id=1"); print("pg_control.dry_run = true")
cur.execute("UPDATE tennis_config SET value='true' WHERE key='dry_run'"); print("tennis dry_run =",cur.rowcount and 'true')
cur.execute("SELECT table_name FROM information_schema.tables WHERE table_name LIKE 'pg_%'"); print("pg tables:",[r[0] for r in cur.fetchall()])
for t in ('pg_trades','pg_positions','pg_bets'):
    try:
        cur.execute(f"SELECT count(*) FILTER (WHERE closed_at IS NULL OR status IN ('OPEN','open')) FROM {t}"); print(t,"open:",cur.fetchone()[0]); break
    except Exception as e: con.rollback() if not con.autocommit else None
# last 24h PG results, so Peter sees exactly what the £9 was
try:
    cur.execute("SELECT string_agg(column_name,',') FROM information_schema.columns WHERE table_name='pg_trades'"); print("pg_trades cols:",cur.fetchone()[0][:300])
    cur.execute("SELECT * FROM pg_trades WHERE opened_at>now()-interval '24 hours' ORDER BY opened_at DESC LIMIT 20")
    for r in cur.fetchall(): print("  ",r)
except Exception as e: print("pg_trades listing:",repr(e)[:120])
PY
echo "M1 pushes stay on (they are instructions to Peter, not bets). Recorders unchanged."
