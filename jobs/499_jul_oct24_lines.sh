#!/bin/bash
set -o pipefail
# 499_jul_oct24_lines (Finder 2026-11-06, queue item 203, interim on items 147, 167): jobs/499_oct24_lines.sh unchanged except the test window (Jul-Oct 2024), the memory cap (3.5 to 2.5 GB) and one added print of item 167's line on Jul-Sep 2024 only, as Oct 2024 helped choose it. Rules pushed before these months were read. No new cuts. Printed labels saying "Oct 2024" mean Jul-Oct 2024 here. The top-10 tables are context; only 147 and 167 are scored.
SRC=/root/pe-queue/jobs/499_oct24_lines.sh
W0="T_LO,T_HI=pd.Timestamp('2024-10-01',tz='UTC').timestamp()"
C0="(3_500_000_000,3_500_000_000)"
A0='y=J.reset_index(); y=y[(y.item==163)&(y.g=='"'"'YOUTH'"'"')'
for s in "$W0" "$C0" "$A0"; do grep -qF "$s" "$SRC" || { echo "ERROR: line not found in source job: $s"; exit 1; }; done
python3 - "$SRC" "$W0" "$C0" "$A0" <<'PY' | bash
import sys
src,w0,c0,a0=sys.argv[1:]
t=open(src).read()
for s in (w0,c0,a0): assert t.count(s)==1,s
t=t.replace(w0,"T_LO,T_HI=pd.Timestamp('2024-07-01',tz='UTC').timestamp()").replace(c0,'(2_500_000_000,2_500_000_000)')
add=("_o=pd.Timestamp('2024-10-01',tz='UTC').timestamp(); _x=R[(R.item==163)&(R.w=='T')&(R.g=='WOMEN')&(R.nm=='OU25 Under')&(R.side=='B')&(R.off<_o)]\n"
     "print('\\n== item 167, the one scored line: WOMEN OU25 Under back, Jul-Sep 2024 only'); print(pd.DataFrame([tab(_x)]).round(3).to_string(index=False) if len(_x) else 'n 0')\n")
print(t.replace(a0,add+a0))
PY
