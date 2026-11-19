#!/bin/bash
# 675 (Thu 19 Nov 2026, CEO chat 14:53: recorded prices start at exactly 00:00 on 14 Nov - "if a delete is running, stop it today").
# The nightly archive job runs with KEEP_DAYS=5: it writes older rows to compressed files, then removes them from the database.
# The server now has 870 GB free and the full grid needs the rows in the database, so the trim stops today: KEEP_DAYS=5 -> 3650.
# The file archive itself keeps running. Also READ ONLY: what the archive holds (oldest and newest file per table) and whether the
# off-box copy is still uploading, so the older rows can be loaded back for the grid.
R=/root/pe-queue/reports/trim_675.md
{ echo "# 675 - $(date -u '+%F %H:%M') UTC"; echo '```'
crontab -l > /root/crontab.bak_675
echo "before:"; crontab -l | grep -n "archive_tape" | cut -c1-170
crontab -l | sed '/archive_tape\.py/ s/KEEP_DAYS=[0-9]*/KEEP_DAYS=3650/' | crontab -
echo "after:"; crontab -l | grep -n "archive_tape" | cut -c1-170
echo "== how the archive job uses KEEP_DAYS"; grep -n "KEEP_DAYS\|DELETE\|TRUNCATE\|DROP" /root/pe-archive/archive_tape.py | cut -c1-200 | head -20
echo "== any other job that deletes from the price tapes"; crontab -l | grep -v '^#' | grep -iE "retention|delete|purge|trim|KEEP" | cut -c1-170
grep -lE "DELETE FROM (stream_ticks|xx_tape|ip_tape|liq_sample|book_snap)" /root/pe-*/*.py /root/pe-*/*/*.py 2>/dev/null | head -10
echo "== archive files: per table, count, oldest, newest, size"
for d in /root/pe-archive/*/; do n=$(ls "$d" 2>/dev/null | wc -l); [ "$n" -gt 0 ] && echo "$(basename $d): $n files | $(ls "$d" | sort | head -1) .. $(ls "$d" | sort | tail -1) | $(du -sh "$d" | cut -f1)"; done
ls /root/pe-archive | head -30
echo "== archive log tail"; tail -6 /root/pe-archive/archive.log 2>&1 | cut -c1-220
echo "== off-box log tail"; tail -4 /root/pe-archive/offbox.log 2>&1 | cut -c1-220; tail -3 /root/pe-queue/reports/archive_offbox.md 2>&1 | cut -c1-200
echo '```'; } > $R 2>&1
cd /root/pe-queue && git add $R; git commit -qm "675: stop the five-day trim" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
