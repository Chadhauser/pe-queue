# 661 — 2026-11-19 07:00 UTC
```
== proof of the bug and the fix
OLD pattern: FOUND a process that does not exist (the bug)
NEW pattern: not found (correct)
NEW pattern on running recorder: found (correct)
keepalive lines fixed: 11
crontab installed
== keepalive lines now
*/5 * * * * pgrep -f duka_loop.sh > /dev/null || (cd /root/pe-fin && nohup ./duka_loop.sh > /dev/null 2>&1 &)
*/10 * * * * pgrep -f '[k]eepalive_hist.sh' >/dev/null || nohup /root/pe-hist/keepalive_hist.sh >/dev/null 2>&1 &
#PAUSED-543 */10 * * * * pgrep -f '[k]eepalive_player.sh' >/dev/null || nohup /root/pe-player/keepalive_player.sh >/dev/null 2>&1 &
*/10 * * * * pgrep -f '[s]ports_team.py' >/dev/null || nohup /root/pe-sports/team/run_team.sh &
*/5 * * * * pgrep -f '[d]esk.py' >/dev/null || nohup /root/pe-sports/desk/run_desk.sh >/dev/null 2>&1 &
*/5 * * * * pgrep -f '[b]ookie_v2.py' >/dev/null || nohup /root/pe-sports/bookie/run_bookie_v2.sh >/dev/null 2>&1 &
*/5 * * * * pgrep -f '[b]rain/monitor_ht.py' >/dev/null || nohup /root/pe-brain/run_monitor_ht.sh >/dev/null 2>&1 &
*/5 * * * * pgrep -f '[b]rain/stats_collector.py' >/dev/null || nohup /root/pe-brain/run_stats_collector.sh >/dev/null 2>&1 &
*/5 * * * * pgrep -f '[s]mall_bites_live.py' >/dev/null || nohup /root/pe-sports/team/run_small_bites_live.sh >/dev/null 2>&1 &   # 626 small bites forward paper
*/5 * * * * pgrep -f '[v]3_recorder.py' >/dev/null || nohup /root/pe-sports/team/run_v3_recorder.sh >/dev/null 2>&1 &   # 649 v3 forward paper recorder
*/5 * * * * pgrep -f '[c]oherence_paper.py' >/dev/null || nohup /root/pe-sports/team/run_coherence_paper.sh >/dev/null 2>&1 &   # 654 coherence forward paper
*/5 * * * * pgrep -f '[b]ook_recorder.py' >/dev/null || nohup /root/pe-sports/team/run_book_recorder.sh >/dev/null 2>&1 &   # 655 THE recorder
== run every keepalive line once by hand: nothing should double-start
sh: 1: NUMBERING.md: not found
book_recorder: 1 process(es)
small_bites_live: 1 process(es)
coherence_paper: 1 process(es)
v3_recorder: 1 process(es)
monitor_ht: 1 process(es)
bookie_v2: 1 process(es)
```
