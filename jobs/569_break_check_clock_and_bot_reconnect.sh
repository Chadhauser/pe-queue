#!/bin/bash
# 569 (Sat 14 Nov 2026, 07:45). The 07:20 break email was the check, not the estate: "crash-looping" counted Thursday's tracebacks still in
# the bot's log, and "no bets in 6 h while football is on" fired on an overnight window. Fix: the check reads the clock — only tracebacks
# timestamped in the last 60 min count, "football on" means 40+ match-odds markets on the tape in the window, and the bot's own liveness
# line ("passed cells" every 10 min) must be present in the last 30 min. Plus the reconnect fix with the bot's real connection line:
#   L=psycopg2.connect(creds.pg_local()); L.autocommit=True; lc=L.cursor()
set -o pipefail
S=/root/pe-sports/team/break_check.sh; cp $S $S.bak_569
python3 - <<'PY'
p='/root/pe-sports/team/break_check.sh'; s=open(p).read(); assert '569' not in s
old1='''[ "$(tail -400 /root/pe-sports/bookie/bookie_v2.log 2>/dev/null | grep -c Traceback)" -ge 3 ] && B="$B bot crash-looping (3+ tracebacks in its last 400 log lines);"'''
new1='''# 569: read the clock, not the whole log
SINCE=$(date -u -d '-60 minutes' '+%Y-%m-%d %H:%M'); SINCE30=$(date -u -d '-30 minutes' '+%Y-%m-%d %H:%M')
TB=$(awk -v s="$SINCE" '$1 ~ /^20[0-9][0-9]-/ {keep=($1" "$2>=s)} keep' /root/pe-sports/bookie/bookie_v2.log 2>/dev/null | grep -c "Traceback"); [ "${TB:-0}" -ge 3 ] && B="$B bot crash-looping ($TB tracebacks in the last hour);"
ALIVE=$(awk -v s="$SINCE30" '$1 ~ /^20[0-9][0-9]-/ {keep=($1" "$2>=s)} keep' /root/pe-sports/bookie/bookie_v2.log 2>/dev/null | grep -c "passed cells"); [ "${ALIVE:-0}" = 0 ] && pgrep -f bookie_v2.py >/dev/null && B="$B bot process present but not reading its cells for 30 minutes;"'''
assert old1 in s; s=s.replace(old1,new1,1)
s=s.replace('print(f"no bot bets in 6 hours while football is on ({on} match-odds markets on the tape);" if on>=10 and bets==0 else "")',
            'print(f"no bot bets in 6 hours while football is on ({on} match-odds markets on the tape);" if on>=40 and bets==0 else "")')
open(p,'w').write(s); print("break_check: clock-based")
PY
bash -n $S && echo "break_check compiles" || { cp $S.bak_569 $S; echo RESTORED; exit 1; }
echo "== bot reconnect, real line =="
P=/root/pe-sports/bookie/bookie_v2.py; cp $P $P.bak_569
python3 - <<'PY'
p='/root/pe-sports/bookie/bookie_v2.py'; s=open(p).read()
old="L=psycopg2.connect(creds.pg_local()); L.autocommit=True; lc=L.cursor()"
assert old in s and '569' not in s
new='''L=psycopg2.connect(creds.pg_local()); L.autocommit=True
# 569: reconnecting cursor — a dropped connection is re-opened with the same settings and the statement retried once, instead of the process dying
class _ReCur:
    def __init__(self): self._c=L.cursor()
    def execute(self,*a,**k):
        global L
        try: return self._c.execute(*a,**k)
        except (psycopg2.InterfaceError, psycopg2.OperationalError) as e:
            log(f"db connection lost ({str(e)[:60]}) - reconnecting"); L=psycopg2.connect(creds.pg_local()); L.autocommit=True; self._c=L.cursor(); return self._c.execute(*a,**k)
    def __getattr__(self,n): return getattr(self._c,n)
lc=_ReCur()'''
s=s.replace(old,new,1); open(p,'w').write(s); print("bot patched")
PY
python3 -m py_compile $P && echo compiles || { cp $P.bak_569 $P; echo "RESTORED"; exit 1; }
grep -n "^def log\|^log=" $P | head -2
pkill -f "python3 bookie_v2.py"; sleep 50; pgrep -fa "bookie_v2.py" | cut -c1-80; tail -3 /root/pe-sports/bookie/bookie_v2.log | cut -c1-160
bash $S; echo "break check exit $? (no email expected)"
echo "569 done"
