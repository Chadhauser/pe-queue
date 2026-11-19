# 676 - 2026-11-19 15:26 UTC
```
== 1. small bites off
459:#STOPPED-676 */5 * * * * pgrep -f '[s]mall_bites_live.py' >/dev/null || nohup /root/pe-sports/team/run_small_bites_live.sh >/dev/null 2>&1 &   # 6
processes left: 0
== 2. remote login settings (read only)
port 22
maxauthtries 6
permitrootlogin yes
pubkeyauthentication yes
passwordauthentication yes
keys allowed to log in as root: 0
0
-- successful logins, last 14 days (count, method, address)
     49 password 195.180.33.58
      2 password 51.219.246.98
      1 password 158.220.81.221
-- last successful logins with dates
root     pts/0        195.180.33.58    Wed Nov 18 11:21:55 2026 - Wed Nov 18 13:37:59 2026  (02:16)
root     pts/1        195.180.33.58    Mon Nov 16 15:36:57 2026 - crash                     (00:18)
root     pts/1        195.180.33.58    Mon Nov 16 14:55:42 2026 - Mon Nov 16 15:03:40 2026  (00:07)
root     pts/1        195.180.33.58    Mon Nov 16 14:53:57 2026 - Mon Nov 16 14:55:16 2026  (00:01)
root     pts/0        195.180.33.58    Mon Nov 16 13:44:19 2026 - crash                     (02:11)
root     pts/0        195.180.33.58    Mon Nov 16 11:08:58 2026 - Mon Nov 16 13:24:03 2026  (02:15)
root     pts/0        195.180.33.58    Sun Nov 15 16:16:37 2026 - Sun Nov 15 16:19:33 2026  (00:02)
root     pts/1        195.180.33.58    Sun Nov 15 11:10:36 2026 - Sun Nov 15 13:28:16 2026  (02:17)
root     pts/0        195.180.33.58    Sun Nov 15 10:10:16 2026 - Sun Nov 15 12:45:40 2026  (02:35)
root     pts/0        195.180.33.58    Sun Nov 15 10:06:56 2026 - Sun Nov 15 10:09:36 2026  (00:02)
root     pts/0        195.180.33.58    Fri Nov 13 17:08:24 2026 - Fri Nov 13 17:09:42 2026  (00:01)
root     pts/0        51.219.246.98    Fri Nov 13 14:48:22 2026 - Fri Nov 13 15:42:08 2026  (00:53)
-- failed password attempts, last 24 hours: 2826
-- logged in right now
-- blocking of repeat attempts
active
Status for the jail: sshd
|- Filter
|  |- Currently failed:	3
|  |- Total failed:	4367
|  `- Journal matches:	_SYSTEMD_UNIT=sshd.service + _COMM=sshd
`- Actions
   |- Currently banned:	1
   |- Total banned:	446
0
Status: inactive
```
