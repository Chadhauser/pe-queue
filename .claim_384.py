import sys, shutil, datetime
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local()); k = c.cursor()
k.execute("SET statement_timeout='300s'")
k.execute("select count(*) filter (where loaded_at>now()-interval '1 hour'),count(*) filter (where path like '%/2023/9/%' or path like '%/2023/Sep/%') from bf_hist_other_files where loaded_at>now()-interval '24 hours'")
n1, _ = k.fetchone()
k.execute("select split_part(path,'/',5)||'-'||split_part(path,'/',6),count(*) from bf_hist_other_files where loaded_at>now()-interval '24 hours' group by 1 order by 2 desc limit 4")
months = k.fetchall()
k.execute("select y,m,status,files,loaded from bf_hist_months where sport='Soccer' and y=2023 order by m desc limit 4")
bm = k.fetchall()
k.execute("select pg_database_size(current_database())/1e9")
db = float(k.fetchone()[0])
free = shutil.disk_usage('/').free / 1e9
print('files last hour', n1, 'per min', round(n1 / 60), 'months', months, 'bf_hist_months', bm, 'db', round(db), 'free', round(free))
now = datetime.datetime.now(datetime.timezone.utc).strftime('%H:%M')
RULE = ("384. RUNNING 2026-11-07 — (Finder's own, source a; tables stream_ticks, liq_sample, goal_timeline; job 499_tick_touch_other; from items 380 and 357) "
        "**First in-play touch of a price, football and tennis, on ticks.** Rationale: item 380 found racing runners under-priced a second after first touching 1.1 and 1.2; cricket's minute-tape version (357) was flat and no other sport has been read on ticks, 14.1M football MO, 6.3M OU25, 8.1M tennis MO in-play ticks on the box. "
        "Rule fixed now, before any price is read: football MO, football OU25, tennis MO, in-play status OPEN; ENTRY first in-play tick with back_px <= Q after a first in-play tick above Q, Q 2, 1.5, 1.3, 1.2, 1.1; bet delay D, football 6 and 10 s, tennis 5 and 10 s, as the in-play delay is longer than racing's; fill at the first tick of that runner at least D s later with a touch on that side and no more than 30 s after that, one tick adverse; a suspension between signal and fill means the bet lapses, no trade, counted; no tick in time, no trade, counted. Back and lay as separate lines, 60 in all. "
        "Result: no official results for these markets, so inferred, runner with the last OPEN back_px at or under 1.03; football MO and OU25 checked against goal_timeline final scores where the names match exactly and the agreement printed; other markets scored at last-print odds with the overround removed, and resolved-only printed beside it, as item 275 and item 357 show either can flatter. 2%, £10 risk, standard bar, t by game, halves by date median. Same 5 days, about 640 games and 590 matches, so even a pass earns an unseen re-read, not a stake.")
q = open('watchman/FINDER_QUEUE.md').read()
if '\n384. ' not in q:
    q = q.rstrip('\n') + '\n' + RULE + '\n'
line70 = f"2026-11-07 about {now} UTC: {round(n1/60)} files/min, disk {round(free)} GB, local DB {round(db)} GB; {bm[0] if bm else ''}; 18 months still LISTFAIL, 25 stale (reports/finder_2026-11-07_item384.md). "
marker = "70. TODO (recurring, every run: timeout 590 bash jobs/499_loader_progress.sh) — "
assert marker in q
if line70[:30] not in q:
    q = q.replace(marker, marker + line70, 1)
open('watchman/FINDER_QUEUE.md', 'w').write(q)
print(line70)
