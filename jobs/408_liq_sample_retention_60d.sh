#!/bin/bash
# 333: KEEP THE TAPE. ip_tape (all sports) and liq_sample (football, every market) were being pruned after ~5-6 days, so every
# cross-sport and tennis test ran out of sample. Find the pruning statements, back the files up, raise both windows to 60 days.
# 408 (watchman fix of 333): 333's grep looked for "DELETE FROM liq_sample" but /root/pe-report/retention.py line 4 says "DELETE FROM {t}", so it found nothing and the 5-day prune went on (suite FAIL "tape pruned since last run", 2,968,899 rows).
# 408 changes liq_sample only, 5 to 60 days, and leaves ip_tape and xx_tape as they are. HELD: this prune was the guard from the 18 Oct disk emergency (job 108, 96% of 50 GB), Railway is now 54.6 GB with its limit unknown, and this adds about 0.48 GB a day. Exits 75 until Peter's yes creates the marker below.
F="${RET_FILE:-/root/pe-report/retention.py}"
MARK="${APPROVE_FILE:-/root/pe-watchman/approve_408}"
if [ ! -e "$MARK" ]; then echo "held: waiting for Peter's yes ($MARK)"; exit 75; fi
[ -e "$F.bak_408" ] || cp "$F" "$F.bak_408" || exit 1
python3 - "$F" <<'PY' || exit 1
import sys
p=sys.argv[1]; s=open(p).read()
old_loop="for t in ('ip_tape','xx_tape','liq_sample'):\n"
new_loop="for t,days in (('ip_tape',5),('xx_tape',5),('liq_sample',60)):\n"
old_del="interval '5 days'\"); print(t,cur.rowcount)"
new_del="interval '{days} days'\"); print(t,cur.rowcount)"
if new_loop in s and new_del in s: print("already applied"); sys.exit(0)
if s.count(old_loop)!=1 or s.count(old_del)!=1: print("retention.py is not the expected text, nothing changed"); sys.exit(1)
open(p,'w').write(s.replace(old_loop,new_loop).replace(old_del,new_del)); print("liq_sample window set to 60 days")
PY
python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$F" || { cp "$F.bak_408" "$F"; echo "syntax check failed, backup restored"; exit 1; }
echo "== read back"; sed -n 3,4p "$F"
echo "== not run here; takes effect at the next nightly prune (04:30 box time)"
