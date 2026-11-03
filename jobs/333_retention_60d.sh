#!/bin/bash
# 333: KEEP THE TAPE. ip_tape (all sports) and liq_sample (football, every market) were being pruned after ~5-6 days, so every
# cross-sport and tennis test ran out of sample. Find the pruning statements, back the files up, raise both windows to 60 days.
# Disk and table sizes printed first; stream_ticks (11k rows/min) stays at 3 days.
echo "== disk"; df -h / | tail -1
echo "== pruners found"; grep -rn -E "DELETE FROM (ip_tape|liq_sample)|delete from (ip_tape|liq_sample)" /root/pe-* --include=*.py --include=*.sh --include=*.sql 2>/dev/null | grep -v pe-queue/jobs | grep -v "\.bak"
for f in $(grep -rl -E "DELETE FROM (ip_tape|liq_sample)|delete from (ip_tape|liq_sample)" /root/pe-* --include=*.py --include=*.sh --include=*.sql 2>/dev/null | grep -v pe-queue/jobs | grep -v "\.bak"); do
  cp -n "$f" "$f.bak_$(date +%F)"
  python3 - "$f" <<'PY'
import re,sys
p=sys.argv[1]; s=open(p).read(); n=0
def fix(m):
    global n; n+=1; return m.group(1)+"interval '60 days'"
s2=re.sub(r"((?:DELETE FROM|delete from)\s+(?:ip_tape|liq_sample)[^;]*?)interval\s*'\d+\s*(?:day|days|hours)'",fix,s,flags=re.S)
s2=re.sub(r"((?:DELETE FROM|delete from)\s+(?:ip_tape|liq_sample)[^;]*?)INTERVAL\s*'\d+\s*(?:day|days|hours)'",fix,s2,flags=re.S)
open(p,'w').write(s2); print(f"{p}: {n} retention clause(s) set to 60 days")
PY
done
echo "== after"; grep -rn -E "DELETE FROM (ip_tape|liq_sample)|delete from (ip_tape|liq_sample)" /root/pe-* --include=*.py --include=*.sh --include=*.sql 2>/dev/null | grep -v pe-queue/jobs | grep -v "\.bak" | grep -o -E "(ip_tape|liq_sample).{0,80}" | head
echo "== note: a running pruner picks the new window up on its next loop/cron; the recorders are untouched"
