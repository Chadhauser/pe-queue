#!/bin/bash
# 647 (Tue 17 Nov 2026, 14:25). Stream tape lost 2 h 35 m this morning (06:33-09:08 UTC). Two faults in stream_client.py:
#  1. Betfair's login page returned non-JSON for 2.5 h and the client only logged "JSONDecodeError" - now it logs the HTTP status and
#     the first 120 characters of the reply, so the next outage says why.
#  2. After each reconnect the market list was empty until the main loop's 60-second refresh, so Betfair closed the connection as
#     "not subscribed and idle 15000 ms" and it looped. Now the client fetches the market list right after logging in, before it
#     opens the stream, so it subscribes within seconds.
# Restart via its keepalive; prove it subscribes. Report: reports/stream_647.md
R=/root/pe-queue/reports/stream_647.md; S=/root/pe-stream/stream_client.py
{ echo "# 647 — $(date -u '+%F %H:%M') UTC"; echo '```'
cp $S $S.bak_647
python3 - "$S" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read(); n=0
E=[('    r=requests.post("https://identitysso.betfair.com/api/login",data={"username":USER,"password":PW},headers={"X-Application":APP_KEY,"Accept":"application/json"},timeout=15).json()\n',
    '    r0=requests.post("https://identitysso.betfair.com/api/login",data={"username":USER,"password":PW},headers={"X-Application":APP_KEY,"Accept":"application/json"},timeout=15)\n'
    '    try: r=r0.json()\n'
    '    except ValueError: raise RuntimeError(f"LOGIN non-JSON reply HTTP {r0.status_code}: {r0.text[:120]!r}")   # 647\n'),
   ("            tok=login(); state['tok']=tok\n",
    "            tok=login(); state['tok']=tok\n"
    "            if not universe:   # 647: have markets ready so the subscription goes out inside Betfair's 15 s idle limit\n"
    "                u=refresh_universe(tok); universe.update(u or {}); print('universe before connect',len(universe),flush=True)\n")]
for old,new in E:
    if new in s: n+=1; continue
    if s.count(old)==1: s=s.replace(old,new); n+=1
    else: print("anchor not found once:", old[:60].replace("\n","\\n"), s.count(old))
if n==len(E): open(p,'w').write(s); print(f"patched {n}/{len(E)}")
else: print(f"only {n}/{len(E)} - NOT changed")
PY
python3 -m py_compile $S && echo compiles || { cp $S.bak_647 $S; echo "compile failed - restored"; }
pkill -f stream_client.py; sleep 100
echo "stream processes: $(pgrep -f stream_client.py | wc -l)"
tail -8 /root/pe-stream/stream.log | cut -c1-160
echo '```'; } > $R 2>&1
cd /root/pe-queue && git add $R && git commit -qm "647: stream re-login fix" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
