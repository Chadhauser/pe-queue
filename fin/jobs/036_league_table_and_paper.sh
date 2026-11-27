#!/bin/bash
# fin 036 (own runner): build the first financial league table from the test results, choose the passers that go onto the
# practice account, switch the league paper robot on (its own cron line, tagged FINQ, lowest priority; no sports line touched),
# and show everything. Paper endpoint only.
S=/root/pe-finq/state; R=/root/pe-finq/repo
ls -la $S/league/ | cut -c1-120
cd $R/fin/league && echo "offline test, league robot: $(timeout 200 python3 test_league.py 2>&1 | tail -1)" && echo "offline test, other robots: $(cd ../bots && timeout 300 python3 test_tick.py 2>&1 | tail -1)"
timeout 300 python3 table.py $S/league 2>&1 | grep -v -i warning | cut -c1-900
if cd $R/fin/league && timeout 200 python3 test_league.py >/dev/null 2>&1; then
  crontab -l > /root/crontab_before_league_$(date +%Y%m%d%H%M).txt 2>/dev/null
  if ! crontab -l | grep -q "league_bot.py"; then ( crontab -l; echo "* * * * * cd $R/fin/league && nice -n 19 ionice -c3 timeout 280 /usr/bin/python3 league_bot.py >> $S/league_bot.out 2>&1 # FINQ" ) | crontab -; fi
  echo "cron FINQ lines: $(crontab -l | grep -c '# FINQ') | league line present: $(crontab -l | grep -c league_bot.py) | total cron lines $(crontab -l | wc -l)"
else echo "league robot test failed: NOT switched on"; fi
cd $R/fin/league && timeout 250 python3 league_bot.py; tail -5 $S/league/league.log 2>/dev/null; tail -3 $S/league_bot.out 2>/dev/null
