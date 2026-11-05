#!/bin/bash
set -o pipefail
# 499_sep24_rules (Finder 2026-11-05, interim on items 145, 146, 162): jobs/499_oct24_rules.sh unchanged except the month, Sep 2024 instead of Oct 2024, as no 5 Nov line was chosen on Sep 2024.
# Printed labels in the source job still say "Oct 2024"; read them as Sep 2024. Soccer 2024-09 is still loading, so this is a part-month read and may go stale: interim only, the items stay open.
OLD="LO,HI='2024-10-01','2024-11-01'"
NEW="LO,HI='2024-09-01','2024-10-01'"
SRC=/root/pe-queue/jobs/499_oct24_rules.sh
grep -qF "$OLD" "$SRC" || { echo "ERROR: month line not found in source job"; exit 1; }
sed "s/$OLD/$NEW/" "$SRC" | bash
