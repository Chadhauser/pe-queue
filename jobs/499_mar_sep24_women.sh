#!/bin/bash
set -o pipefail
# 499_mar_sep24_women (Finder 2026-11-06, queue item 258, interim on item 167): jobs/499_oct24_lines.sh unchanged except the test window (from 1 Mar 2024), the memory cap (3.5 to 2.5 GB) and one added print of item 167's line, Mar-Sep 2024 and Mar-Jun apart. Oct 2024 helped choose the line, so it is left out of the scored read. Wrapper as jobs/499_jul_oct24_lines.sh. Rule pushed (7bf813f) before these months were read. No new cuts. Printed labels saying "Oct 2024" mean Mar-Oct 2024 here; those other lines are context, the one scored line is item 167's. Read only.
SRC=/root/pe-queue/jobs/499_oct24_lines.sh
W0="T_LO,T_HI=pd.Timestamp('2024-10-01',tz='UTC').timestamp()"
C0="(3_500_000_000,3_500_000_000)"
A0='out=[]'
for s in "$W0" "$C0" "$A0"; do grep -qF "$s" "$SRC" || { echo "ERROR: line not found in source job: $s"; exit 1; }; done
python3 - "$SRC" "$W0" "$C0" "$A0" <<'PY' | bash
import sys
src,w0,c0,a0=sys.argv[1:]
t=open(src).read()
for s in (w0,c0,a0): assert t.count(s)==1,s
t=t.replace(w0,"T_LO,T_HI=pd.Timestamp('2024-03-01',tz='UTC').timestamp()").replace(c0,'(2_500_000_000,2_500_000_000)')
# FIX 2026-11-06: the first run hit the 2.5 GB cap on all 24,911 events (MemoryError at 288 s). The scored line is women's only, so load WOMEN and YOUTH games only; YOUTH keeps the source job's closing print of item 147 working. No change to the rule or the line.
k0="MK=MK[MK.w.notna()]"; assert t.count(k0)==1
t=t.replace(k0,k0+"; MK=MK[[isinstance(group(e_),str) for e_ in MK.ev]]; print('WOMEN and YOUTH games only:',MK.event_id.nunique(),flush=True)")
add=("_o=pd.Timestamp('2024-10-01',tz='UTC').timestamp(); _j=pd.Timestamp('2024-07-01',tz='UTC').timestamp(); _x=R[(R.item==163)&(R.w=='T')&(R.g=='WOMEN')&(R.nm=='OU25 Under')&(R.side=='B')&(R.off<_o)]\n"
     "print('\\n== item 258, the one scored line: WOMEN OU25 Under back, Mar-Sep 2024'); print(pd.DataFrame([tab(_x)]).round(3).to_string(index=False) if len(_x) else 'n 0')\n"
     "print('\\n== of which Mar-Jun 2024, new months'); print(pd.DataFrame([tab(_x[_x.off<_j])]).round(3).to_string(index=False) if len(_x[_x.off<_j]) else 'n 0')\n")
# REPAIR 2026-11-06 (queue item 258): the scored print moved to straight after R and tab() exist, before the per-item loop whose spearmanr crashes on women's and youth games alone. Nothing else changed, and a crash after the print does not lose the result.
print(t.replace(a0,add+a0))
PY
