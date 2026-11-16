#!/bin/bash
# 601 (Mon 16 Nov 2026, 09:55). 599 and 600 source /root/operators/.env, which exports GITHUB_TOKEN (the operators repo's token); gh's
# credential helper prefers that variable, so their pushes to pe-queue got 403 and their reports sit unpushed on the server. Push them
# now without the variable, and make offbox.sh drop it after sourcing .env so the nightly run can push its manifest.
set -o pipefail
cd /root/pe-queue && git status -sb | head -2; env -u GITHUB_TOKEN git pull -q --no-rebase --no-edit; env -u GITHUB_TOKEN git push -q && echo "pushed: $(git log --oneline -1)"
grep -q "unset GITHUB_TOKEN" /root/pe-archive/offbox.sh || sed -i 's/set +a/set +a; unset GITHUB_TOKEN/' /root/pe-archive/offbox.sh; grep -n "unset GITHUB_TOKEN" /root/pe-archive/offbox.sh | head -2
ls -la /root/pe-queue/reports/offbox_probe.md 2>/dev/null && head -12 /root/pe-queue/reports/offbox_probe.md | cut -c1-200
echo "601 done"
