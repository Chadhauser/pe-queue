#!/bin/bash
# 327: the Finder runs twice a day (02:40 and 14:40) and now generates its own hypotheses each run (brief updated in the repo).
( crontab -l 2>/dev/null | grep -v pe-finder/run.sh; echo "40 2,14 * * * /root/pe-finder/run.sh" ) | crontab -
echo "finder cron: $(crontab -l | grep pe-finder)"
