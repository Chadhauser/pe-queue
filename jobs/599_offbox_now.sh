#!/bin/bash
# 599 (Mon 16 Nov 2026, 09:00). The Contabo panel now shows Object Storage EU 7981 as Ready, 250 GB. Run the off-box upload now and
# write the result to reports/offbox_now.md; print only the first 4 characters of the key so it can be compared with the panel.
set -o pipefail
cd /root/operators && set -a && . ./.env && set +a
R=/root/pe-queue/reports/offbox_now.md
{ echo "# Off-box upload attempt $(date -u '+%F %H:%M') UTC"; echo '```'; echo "endpoint $ARCHIVE_S3_ENDPOINT bucket $ARCHIVE_S3_BUCKET key starts ${ARCHIVE_S3_KEY:0:4} (len ${#ARCHIVE_S3_KEY}) secret len ${#ARCHIVE_S3_SECRET}"
  timeout 1500 python3 /root/pe-archive/offbox.py 2>&1 | grep -v -i "secret" | tail -25 | cut -c1-200; echo "offbox exit ${PIPESTATUS[0]}"; echo '```'; } > $R
cd /root/pe-queue && git add reports/offbox_now.md && git commit -qm "offbox attempt" && git pull -q --no-rebase --no-edit && git push -q && echo pushed
echo "599 done"
