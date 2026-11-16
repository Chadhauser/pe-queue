#!/bin/bash
# 692: one-time bootstrap of the SEGREGATED fin lane (Peter's order 16 Nov 14:54: once reports/post_upgrade.md shows the upgrade,
# treat it as "restart fin segregated"). post_upgrade.md landed 15:00 UTC: 968 GB disk, 839 GB free, 17 GB memory.
# Runs fin/DEPLOY.sh once (about a minute): own clone /root/pe-finq/repo, own runner cron (nice/ionice, 30-min cap, 25 GB floor),
# Alpaca PAPER bot tick only. After this the shared runner never runs fin work again. No Wine/MT5, no research loop, no data pulls.
unset GITHUB_TOKEN
timeout 900 bash /root/pe-queue/fin/DEPLOY.sh
