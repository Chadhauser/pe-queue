#!/bin/bash
set -o pipefail
# 499_btts_cheap_older (Finder 2026-11-07, queue item 137): jobs/499_btts_cheap_unseen.sh unchanged except the months, Jun 2023 to Jul 2024, before the tape item 132 read. Interim read: the item scores once n >= 300. First 300 games by kick-off are burn-in, as written. Read only.
J=/root/pe-queue/jobs
python3 - "$J/499_btts_cheap_unseen.sh" <<'PY' | bash
import sys
t=open(sys.argv[1]).read()
for a,b in (
 ("kickoff>='2026-05-31' AND kickoff<'2026-10-02'","kickoff>='2023-05-31' AND kickoff<'2024-08-02'"),
 ("(('2026-05-31','2026-07-01'),('2026-07-01','2026-08-01'),('2026-08-01','2026-09-01'),('2026-09-01','2026-10-02'))",
  "(('2023-06-01','2023-08-01'),('2023-08-01','2023-09-01'),('2023-09-01','2023-10-01'),('2023-10-01','2023-11-01'),('2023-11-01','2023-12-01'),('2023-12-01','2024-01-01'),('2024-01-01','2024-02-01'),('2024-02-01','2024-03-01'),('2024-03-01','2024-04-01'),('2024-04-01','2024-05-01'),('2024-05-01','2024-06-01'),('2024-06-01','2024-08-01'))"),
):
    assert a in t, "window text not found: "+a
    t=t.replace(a,b)
print(t)
PY
echo "== SURVIVORS: item 137 reads CHEAP BACK Yes only, interim until n >= 300"
