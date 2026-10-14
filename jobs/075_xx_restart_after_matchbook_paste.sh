#!/bin/bash
# 075: Matchbook login re-pasted 14 Oct 13:54 UK — restart the cross-exchange recorder so it reads the new credentials; keepalive brings it back within 60s.
pkill -f xx_recorder.py; sleep 75; tail -4 /root/pe-xx/recorder.log; python3 -c "import psycopg2,sys; sys.path.insert(0,\"/root/pe-bot\"); from bot_core import DB; c=psycopg2.connect(DB,sslmode=\"require\").cursor(); c.execute(\"SELECT exchange,last_seen,live_markets,left(note,60) FROM xx_heartbeat\"); print(c.fetchall())"
