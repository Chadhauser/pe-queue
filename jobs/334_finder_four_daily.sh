#!/bin/bash
# 334: Finder runs four times a day (02:40, 08:40, 14:40, 20:40). A second lane (FINDER_LANE=B) runs 40 minutes later each time and
# takes items from the BOTTOM of the queue so the two never collide (flock per lane). Same brief, same rules.
sed -i 's#exec 9>/root/pe-finder/.lock#exec 9>/root/pe-finder/.lock${FINDER_LANE:-}#' /root/pe-finder/run.sh
grep -q 'FINDER_LANE' /root/pe-queue/watchman/FINDER.md || true
( crontab -l 2>/dev/null | grep -v pe-finder/run.sh; echo "40 2,8,14,20 * * * /root/pe-finder/run.sh"; echo "20 3,9,15,21 * * * FINDER_LANE=B /root/pe-finder/run.sh" ) | crontab -
echo "finder cron:"; crontab -l | grep pe-finder
