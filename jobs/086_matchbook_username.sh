#!/bin/bash
# 086: Matchbook login uses the USERNAME (Peter, 15 Oct: chadhauser), not the email that was pasted. Keep the existing password line.
cp /root/pe-logger/.env /root/pe-logger/.env.$(date +%Y%m%d%H%M).bak
sed -i -E 's/^MATCHBOOK_USERNAME=.*/MATCHBOOK_USERNAME=chadhauser/' /root/pe-logger/.env
grep -c '^MATCHBOOK_USERNAME=chadhauser' /root/pe-logger/.env
pkill -f xx_recorder.py; sleep 80; tail -4 /root/pe-xx/recorder.log
python3 -c "import psycopg2,sys; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB; c=psycopg2.connect(DB,sslmode='require').cursor(); c.execute(\"SELECT exchange,to_char(last_seen,'HH24:MI'),live_markets,left(note,50) FROM xx_heartbeat\"); print(c.fetchall())"
