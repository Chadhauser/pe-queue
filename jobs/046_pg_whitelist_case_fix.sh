#!/bin/bash
# 046: v3 placed ZERO orders on Monday. Cause: the whitelist is lower-case ('spanish segunda division') and Betfair competition
# names are Title Case ('Spanish Segunda Division') -> every goal skipped as "not in backtest". Compare lower-case. Restart.
python3 - <<'PY'
p='/root/pe-pg/pg_bot.py'; s=open(p).read()
s=s.replace("from fts_collector import LEAGUES as WL; WL=set(WL)","from fts_collector import LEAGUES as WL; WL={str(x).lower() for x in WL}")
s=s.replace("""    WL={'English Premier League',""","""    WL={x.lower() for x in {'English Premier League',""")
s=s.replace("""'Argentinian Primera Division','UEFA Champions League'}
print("whitelist leagues:",len(WL),flush=True)""","""'Argentinian Primera Division','UEFA Champions League'}}
print("whitelist leagues:",len(WL),flush=True)""")
s=s.replace("""            if (g['competition'] or '') not in WL: print("skip (league not in backtest):",g['competition'],g['event_name'],flush=True); continue""",
            """            if (g['competition'] or '').lower() not in WL: print("skip (league not in backtest):",g['competition'],g['event_name'],flush=True); continue""")
open(p,'w').write(s)
PY
python3 -m py_compile /root/pe-pg/pg_bot.py || exit 1
grep -n "lower()" /root/pe-pg/pg_bot.py | head -5
pkill -f pg_bot.py; sleep 70; pgrep -af pg_bot.py || echo NOT RUNNING; tail -3 /root/pe-pg/bot.log
