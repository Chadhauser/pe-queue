#!/bin/bash
# 330: LIVE-ORDER SAFETY CHECK (report only). Which running processes can place real orders, and is each in dry-run?
echo "== running keepalives/bots"; ps -eo pid,etime,cmd | grep -E "live|trade_bot|bettor" | grep -v grep
for f in /root/pe-xg/lo_live.py /root/pe-ltd/*live*.py /root/pe-bot/trade_bot.py /root/pe-bot/auto_bettor*.py; do
  [ -f "$f" ] || continue; echo "--- $f"; grep -n -i -E "dry_run|DRY|live *=|LIVE_MODE|placeOrders|stake" "$f" | head -15; ls -la "$(dirname $f)"/*.env "$(dirname $f)"/config* 2>/dev/null | head -5
  for c in $(ls "$(dirname $f)"/config*.json "$(dirname $f)"/*.env 2>/dev/null); do echo "   $c:"; grep -i -E "dry|live|stake" "$c" | sed 's/\(key\|token\|pass\)[^,]*/\1=***/Ig' | head -8; done
done
echo "== orders actually placed (last 30 days, by table)"; python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
k=psycopg2.connect(DB,sslmode='require').cursor()
for t,c,d in (('lo_live_trades','dry','entered_at'),('live_positions','bot_managed','entered_at'),('ltd_live_trades','dry','entered_at')):
    try: k.execute(f"SELECT {c}, count(*), max({d}) FROM {t} WHERE {d}>now()-interval '30 days' GROUP BY 1"); print(t,k.fetchall())
    except Exception as e: k.connection.rollback(); print(t,'n/a',str(e)[:60])
k.execute("SELECT count(*) FROM lo_live_trades WHERE lay_bet_id IS NOT NULL AND NOT dry") ; print("lo_live real bet ids (not dry):",k.fetchone())
PY
