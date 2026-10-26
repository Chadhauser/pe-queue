#!/bin/bash
# 237: results-to-Claude pipeline, step 0 — does the server already hold any GitHub credential (names only, never values)?
for f in /root/pe-logger/.env /root/pe-bot/.env /root/.env; do [ -f "$f" ] && { echo "== $f keys:"; grep -oE '^[A-Z_]+' "$f" | sort -u | tr '\n' ' '; echo; }; done
echo "== git credential helpers / stores:"; git config --global --get credential.helper; ls -la /root/.git-credentials 2>/dev/null | awk '{print $1,$5,$9}'; ls /root/.config/gh 2>/dev/null
echo "== gh cli:"; which gh && gh auth status 2>&1 | head -3
echo "== remotes in pe-queue:"; cd /root/pe-queue && git remote -v | head -1
echo "== other repos on the box:"; ls -d /root/*/.git 2>/dev/null
