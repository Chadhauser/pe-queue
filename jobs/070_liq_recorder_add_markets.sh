#!/bin/bash
# 070: the cross-market lag test (061) showed BTTS / O-U 1.5 / O-U 3.5 / first-half lines have made only 12-27% of their eventual
# move one minute after a goal — but on LAST-TRADED prices, which in thin markets just means nobody traded. Whether the stale
# price is actually AVAILABLE is the whole question, so the football liquidity recorder now also records BOTH_TEAMS_TO_SCORE,
# OVER_UNDER_15 and OVER_UNDER_35 (full ladder, same goal snapshots at 0/30/60/120/300s). Restart via keepalive (cron), not here.
p=/root/pe-liq/liq_recorder.py
python3 - <<'PY'
p='/root/pe-liq/liq_recorder.py'; s=open(p).read()
s=s.replace("for mt in ('MATCH_ODDS','OVER_UNDER_25'):","for mt in ('MATCH_ODDS','OVER_UNDER_25','OVER_UNDER_15','OVER_UNDER_35','BOTH_TEAMS_TO_SCORE'):")
s=s.replace("'mkt':'MO' if mt=='MATCH_ODDS' else 'OU25'","'mkt':{'MATCH_ODDS':'MO','OVER_UNDER_25':'OU25','OVER_UNDER_15':'OU15','OVER_UNDER_35':'OU35','BOTH_TEAMS_TO_SCORE':'BTTS'}[mt]")
s=s.replace("    if meta['mkt']=='OU25': return 'OVER' if low.startswith('over') else 'UNDER'","    if meta['mkt'] in ('OU25','OU15','OU35'): return 'OVER' if low.startswith('over') else 'UNDER'\n    if meta['mkt']=='BTTS': return 'YES' if low.startswith('y') else 'NO'")
open(p,'w').write(s)
PY
python3 -m py_compile $p || exit 1
grep -c "BOTH_TEAMS_TO_SCORE" $p
pkill -f liq_recorder.py; echo "recorder stopped; cron keepalive restarts it within 60s with 5 market types (request weight: batches of 8 unchanged)"
