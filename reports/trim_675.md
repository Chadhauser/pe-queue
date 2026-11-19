# 675 - 2026-11-19 15:18 UTC
```
before:
134:35 3 * * * KEEP_DAYS=5 timeout 7000 /usr/bin/python3 /root/pe-archive/archive_tape.py >> /root/pe-archive/archive.log 2>&1
after:
134:35 3 * * * KEEP_DAYS=3650 timeout 7000 /usr/bin/python3 /root/pe-archive/archive_tape.py >> /root/pe-archive/archive.log 2>&1
== how the archive job uses KEEP_DAYS
1:# archive_tape (548): move tape rows older than KEEP_DAYS into compressed daily files, verify counts, delete, vacuum. Re-runnable; daily cron.
4:KEEP_DAYS=int(os.environ.get('KEEP_DAYS','10'))
8:    c.execute(f'SELECT min("{col}")::date, (now()-interval \'{KEEP_DAYS} days\')::date FROM "{t}"'); lo,hi=c.fetchone()
9:    if lo is None or lo>=hi: print(f"{t}: nothing older than {KEEP_DAYS} days"); continue
20:                c.execute(f'DELETE FROM "{t}" WHERE "{col}">=%s AND "{col}"<%s',(d,d+datetime.timedelta(days=1))); print(f"{t} {d}: {n} rows -> {f} ({os.path.getsize(f)/1e6:.0f} MB), deleted")
== any other job that deletes from the price tapes
* * * * * /root/pe-liq/keepalive.sh
* * * * * /root/pe-ip/keepalive.sh
* * * * * /root/pe-xx/keepalive.sh
* * * * * /root/pe-stream/keepalive.sh
@reboot nohup /root/pe-hist/keepalive_hist.sh >/dev/null 2>&1 &
*/10 * * * * pgrep -f '[k]eepalive_hist.sh' >/dev/null || nohup /root/pe-hist/keepalive_hist.sh >/dev/null 2>&1 &
35 3 * * * KEEP_DAYS=3650 timeout 7000 /usr/bin/python3 /root/pe-archive/archive_tape.py >> /root/pe-archive/archive.log 2>&1
/root/pe-watchman/wm_1109_05s.py
== archive files: per table, count, oldest, newest, size
__pycache__: 2 files | archive_tape.cpython-312.pyc .. offbox.cpython-312.pyc | 16K
ip_tape: 14 files | 2026-10-31.csv.zst .. 2026-11-13.csv.zst | 205M
liq_sample: 14 files | 2026-10-31.csv.zst .. 2026-11-13.csv.zst | 514M
stream_ticks: 12 files | 2026-11-02.csv.zst .. 2026-11-13.csv.zst | 1.3G
tables: 17 files | public.af_events.sql.zst .. public.xx_ip_331.sql.zst | 687M
xx_tape: 11 files | 2026-11-03.csv.zst .. 2026-11-13.csv.zst | 165M
__pycache__
archive.log
archive_readback.sh
archive_tape.py
ip_tape
liq_sample
offbox.log
offbox.py
offbox.py.bak_580
offbox.sh
offbox_manual.log
stream_ticks
tables
xx_tape
== archive log tail
ip_tape 2026-11-13: 2953845 rows -> /root/pe-archive/ip_tape/2026-11-13.csv.zst (14 MB), deleted
ip_tape: vacuumed
liq_sample 2026-11-13: 2849417 rows -> /root/pe-archive/liq_sample/2026-11-13.csv.zst (34 MB), deleted
liq_sample: vacuumed
xx_tape 2026-11-13: 3297024 rows -> /root/pe-archive/xx_tape/2026-11-13.csv.zst (18 MB), deleted
xx_tape: vacuumed
== off-box log tail
files 64 | uploaded now 4 | verified on bucket 64 | problems 0 | 2.8 GB local
/root/pe-archive/offbox.py:31: DeprecationWarning: datetime.datetime.utcnow() is deprecated and scheduled for removal in a future version. Use timezone-aware objects to represent datetimes in UTC: datetime.datetime.now(d
  open('/root/pe-queue/reports/archive_offbox.md','a').write(f"- {datetime.datetime.utcnow():%F %H:%M} UTC: {ok} files verified on {B}, {up} uploaded this run, {len(bad)} problems\n")
files 68 | uploaded now 4 | verified on bucket 68 | problems 0 | 2.9 GB local
- 2026-11-17 03:20 UTC: 60 files verified on pe-archive, 4 uploaded this run, 0 problems
- 2026-11-18 03:17 UTC: 64 files verified on pe-archive, 4 uploaded this run, 0 problems
- 2026-11-19 03:20 UTC: 68 files verified on pe-archive, 4 uploaded this run, 0 problems
```
