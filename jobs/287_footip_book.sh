#!/bin/bash
# 287: FOOTBALL IN-PLAY QUOTE BOOK 'footip10' on the generic engine. Rules that make an in-play book survivable: quote only while
# status is OPEN (the engine already stops on SUSPENDED/CLOSED via MM_OKST), pull/flatten on suspension, no NEW quote for 90 s
# after a market re-opens, no quotes after 88' (ESPN minute where matched, else 95 min after KO). Both top-2 runners by price.
set -e
python3 - <<'PY'
p='/root/pe-race/race_mm_size.py'; s=open(p).read(); o=s
# reopen guard: remember last non-OPEN status time per market; refuse new quotes within REOPEN_WAIT seconds of it
s=s.replace("OKST=os.environ.get('MM_OKST','OPEN').split(',');","OKST=os.environ.get('MM_OKST','OPEN').split(','); REOPEN_WAIT=int(os.environ.get('MM_REOPEN_WAIT','0')); MAXMIN=int(os.environ.get('MM_MAXMIN','0')); last_bad={};",1)
old="            if st not in OKST or sto>WINDOW or sto<=FLAT_AT+5: continue\n"
new="""            if st not in OKST: last_bad[mid]=ts
            if st not in OKST or sto>WINDOW or sto<=FLAT_AT+5: continue
            if REOPEN_WAIT and mid in last_bad and (ts-last_bad[mid]).total_seconds()<REOPEN_WAIT: continue
            if MAXMIN and (-sto)/60.0>MAXMIN: continue
"""
assert old in s, "quote-gate anchor missing"; s=s.replace(old,new,1); open(p,'w').write(s); print("reopen guard + max minute added")
PY
python3 -m py_compile /root/pe-race/race_mm_size.py
python3 - <<'PY'
p='/root/pe-race/race_mm_size.py'; s=open(p).read()
s=s.replace("'tennis10':5,'footpre10':6}","'tennis10':5,'footpre10':6,'footip10':7}",1); open(p,'w').write(s)
PY
python3 -m py_compile /root/pe-race/race_mm_size.py
grep -q footip10 /root/pe-race/keepalive_mm_size.sh || echo 'pgrep -f "race_mm_size.py footip10" >/dev/null || MM_SPORT=football MM_MKT=MO MM_OKST=INPLAY MM_WINDOW=100000000 MM_FLAT=-100000000 MM_RANK=2 MM_REOPEN_WAIT=90 MM_MAXMIN=95 nohup python3 race_mm_size.py footip10 >> mm_footip.log 2>&1 &' >> /root/pe-race/keepalive_mm_size.sh
pkill -f race_mm_size.py || true; sleep 2; /root/pe-race/keepalive_mm_size.sh; sleep 60; echo "processes (expect 6):"; pgrep -af race_mm_size.py; tail -n 3 /root/pe-race/mm_footip.log || true
