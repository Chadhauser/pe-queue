#!/bin/bash
# 238: (a) /root/operators is a clone of Peter's GitHub todo repo — does it hold a push credential (masked)? (b) cross-exchange rerun
# with the inplay filter on the right table; (c) why does xx_tape hold no Smarkets rows while its heartbeat says ok?
echo "== operators remote (token masked):"; git -C /root/operators remote -v | sed -E 's#(https://)[^@]+@#\1***@#' | head -2; git -C /root/operators config --get credential.helper; git -C /root/operators log -1 --format='%h %ci %s' 2>/dev/null
echo "== smarkets rows ever / last:"; python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
k=psycopg2.connect(DB,sslmode='require').cursor()
k.execute("SELECT exchange, count(*), max(ts), count(DISTINCT sport) FROM xx_tape GROUP BY exchange"); print(k.fetchall())
k.execute("SELECT sport, count(*) FROM xx_tape WHERE exchange='smarkets' GROUP BY sport"); print("smarkets by sport:",k.fetchall())
PY
tail -5 /root/pe-xx/*.log 2>/dev/null | tail -12
