# Memory check 2026-11-16 08:30 UTC
```
== memory ==
               total        used        free      shared  buff/cache   available
Mem:            7941        3864        1317        1587        4737        4076
MemTotal:        8131768 kB
4
cpus above
== dmidecode (RAM slots) ==
	Size: 8 GB
== uptime / last reboot ==
2026-10-19 12:29:08
 09:30:10 up 27 days, 22:01,  1 user,  load average: 1.70, 2.03, 2.15
== disk ==
/dev/sda1       145G  128G   17G  89% /
== cloud-init / contabo product hints ==
Standard PC (i440FX + PIIX, 1996)
== bot bets by sport, last 24h ==
cols: ['id', 'ts', 'market_id', 'event_name', 'mkt', 'sel', 'side', 'price', 'fair', 'mkt_back', 'mkt_lay', 'stake', 'status', 'fill_ts', 'fill_price', 'fill_kind', 'won', 'pnl', 'settled_ts', 'start_ts', 'version', 'exchange', 'bf_market_id']
bets 24h by mkt : [('OVER_UNDER_45', 4), ('FIRST_GOAL_SCORER', 3), ('WIN', 3), ('BOTH_TEAMS_TO_SCORE', 2), ('HALF_TIME', 1), ('MATCH_ODDS', 1)]
taker settled, pnl: (55, Decimal('-4.3448'))
== goal monitor ==
467944 /bin/bash /root/pe-brain/run_monitor_ht.sh
1487488 /root/pe-brain/venv/bin/python -u brain/monitor_ht.py
```
