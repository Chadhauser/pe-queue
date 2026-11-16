#!/bin/bash
# 605 (Mon 16 Nov 2026, 10:45). Two loose ends the Watchman noted: (1) /root/pe-archive/offbox.sh is missing (579 died before writing it),
# so the 04:15 daily off-box cron points at nothing — write it; (2) the 583 edit to runner/runner.sh sits uncommitted in the checkout and
# could collide with a pull — commit and push it.
set -o pipefail
cat > /root/pe-archive/offbox.sh <<'SH'
#!/bin/bash
# daily off-box copy of the archive to Contabo object storage (579/605). Exit 75 while the storage refuses the key.
cd /root/operators && set -a && . ./.env && set +a; unset GITHUB_TOKEN
timeout 7000 python3 /root/pe-archive/offbox.py >> /root/pe-archive/offbox.log 2>&1; rc=$?
cd /root/pe-queue && git add reports/archive_offbox.md 2>/dev/null && git commit -qm "offbox manifest" 2>/dev/null; git pull -q --no-rebase --no-edit 2>/dev/null; git push -q 2>/dev/null
exit $rc
SH
chmod +x /root/pe-archive/offbox.sh; bash -n /root/pe-archive/offbox.sh && ( crontab -l | grep -v "pe-archive/offbox"; echo "15 4 * * * /root/pe-archive/offbox.sh" ) | crontab - && crontab -l | grep offbox
ls -la /root/pe-archive/offbox.py | awk '{print $5,$6,$7,$8,$9}'; grep -c "OpenSSL" /root/pe-archive/offbox.py
cd /root/pe-queue && git status --porcelain runner/ | head; git add runner/runner.sh && git -c user.name=desk -c user.email=peter@edwardsbros.co.uk commit -qm "583: runner self-healing pull (committed from the server checkout)" && env -u GITHUB_TOKEN git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q && echo "runner.sh committed and pushed"
echo "605 done"
