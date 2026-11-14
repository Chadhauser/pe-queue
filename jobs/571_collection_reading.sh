#!/bin/bash
# 571 (Sat 14 Nov 2026, 08:50). CEO correction of 08:38: collect every sport, delete nothing unarchived, restore or justify the 17 dropped
# tables, give the disk fill date. This job READS and writes reports/collection_2026-11-14.md; the build job (572) acts on it.
#  1. Which sports each tape covers now (last 24 h and last 7 days), against the sports Peter named; what the stream recorder subscribes to.
#  2. The 02:35 UTC archive job: what it archives, proof (file per day, rows, verified before delete — the code path), archive.log tail,
#     the stale "tape_archive" watermark explained (the removed Railway copier's table, not the archive).
#  3. The 17 dropped tables: dump file, size, rows (from the 554 log), what it held.
#  4. Disk: used/free now, growth over the last days from the archive sizes and DB size, the fill date at this rate.
set -o pipefail
R=/root/pe-queue/reports/collection_2026-11-14.md
{
echo "# Collection reading — $(date -u '+%F %H:%M') UTC (job 571)"; echo
python3 - <<'PY'
import sys,psycopg2,subprocess,os,glob,datetime; sys.path.insert(0,'/root/pe-queue/runner'); import creds
con=psycopg2.connect(creds.pg_local(),sslmode='disable'); c=con.cursor(); c.execute("SET statement_timeout='600s'")
def q(sql):
    try: c.execute(sql); return c.fetchall()
    except Exception as e: con.rollback(); return [('ERR',str(e)[:120])]
def cols(t): return [r[0] for r in q(f"select column_name from information_schema.columns where table_name='{t}'")]
print("## 1. Sports on each tape\n")
WANT=['Soccer','Tennis','Cricket','Horse Racing','Golf','American Football','Baseball','Basketball','Greyhound Racing','Rugby Union','Snooker','Darts','Ice Hockey','Esports']
for t,tscol in [('liq_sample','ts'),('stream_ticks','ts_recv'),('ip_tape','ts'),('xx_tape','ts')]:
    cl=cols(t); sc=next((k for k in ('sport','event_type','event_type_name','sport_name') if k in cl),None)
    print(f"### {t} (sport column: {sc})")
    if sc:
        print("| sport | rows last 24 h | rows last 7 d | markets 7 d |\n|---|---|---|---|")
        for s,a,b,m in q(f"select coalesce({sc},'?'), count(*) filter (where {tscol}>now()-interval '24 hours'), count(*), count(distinct market_id) from {t} where {tscol}>now()-interval '7 days' group by 1 order by 3 desc"): print(f"| {s} | {a} | {b} | {m} |")
    else: print("no sport column — rows 24 h:", q(f"select count(*) from {t} where {tscol}>now()-interval '24 hours'")[0][0])
    print()
print("Betfair event types with markets on the exchange this week (from bf_hist_other / catalogue tables if present):", q("select distinct sport from bf_hist_other where market_time>now()-interval '7 days' order by 1")[:30])
print("\n## 2. Archive (the 02:35 UTC job)\n")
print("Code path (archive_tape.py, job 548): per table per day — COPY to zstd file, count lines in the file, DELETE only if file rows == table rows, else keep rows and remove the file. Nothing is deleted unverified.\n")
for t in ('liq_sample','ip_tape','stream_ticks'):
    fs=sorted(glob.glob(f'/root/pe-archive/{t}/*.csv.zst')); tot=sum(os.path.getsize(f) for f in fs)/1e9
    print(f"- {t}: {len(fs)} daily files, {tot:.1f} GB, {os.path.basename(fs[0]) if fs else '-'} .. {os.path.basename(fs[-1]) if fs else '-'}")
print("\narchive.log tail:"); print(subprocess.run("tail -12 /root/pe-archive/archive.log",shell=True,capture_output=True,text=True).stdout)
print("crontab archive lines:"); print(subprocess.run("crontab -l | grep -i 'archive\\|prune\\|delete' ",shell=True,capture_output=True,text=True).stdout)
print("Oldest row still in each tape (KEEP window):", q("select (select min(ts)::date from liq_sample), (select min(ts)::date from ip_tape), (select min(ts_recv)::date from stream_ticks)"))
print("\nThe 'tape_archive_wm' watermark the Watchman reports as stuck at 12 Nov belongs to tape_archive.py — the hourly Railway-to-local copier removed in job 553 because source and destination became the same table. It is not the archive above.")
print("\n## 3. The 17 dropped tables (dumps in /root/pe-archive/tables)\n")
print("| table | dump size MB | restorable | what it held |\n|---|---|---|---|")
WHAT={'bf_price_log':'pre-off price log, old recorder (pre stream)','bf_racing_log':'racing price log, old recorder','bf_tennis_log':'tennis price log, old recorder','bfsp_history':'Betfair SP history (racing)','goal_live_predictions':'goal engine predictions (RESTORED 13 Nov)','goal_timeline':'goal engine timeline (RESTORED)','racing_tape':'racing in-play tape, old recorder','runners':'racing runners','af_events':'API-Football events (RESTORED)','af_stats':'API-Football match stats','fd_matches':'football-data results','af_fixtures':'API-Football fixtures (RESTORED)','m1_alerts':'M1 alerts (RESTORED)','goal_alerts':'goal alerts (RESTORED)','real_trades':'real trades log'}
for f in sorted(glob.glob('/root/pe-archive/tables/*.sql.zst')):
    t=os.path.basename(f).replace('public.','').replace('.sql.zst',''); present=q(f"select to_regclass('public.{t}')")[0][0] is not None
    print(f"| {t} | {os.path.getsize(f)/1e6:.0f} | {'present now' if present else 'dropped'} | {WHAT.get(t,'')} |")
print("\n## 4. Disk\n")
st=os.statvfs('/'); free=st.f_bavail*st.f_frsize/1e9; total=st.f_blocks*st.f_frsize/1e9
print(f"Disk: {total:.0f} GB total, {free:.1f} GB free. Database: {q('select pg_database_size(current_database())/1e9')[0][0]:.1f} GB. Archive files: {sum(os.path.getsize(f) for f in glob.glob('/root/pe-archive/**/*.zst',recursive=True))/1e9:.1f} GB.")
print("\nDaily growth (archive file sizes per day, i.e. what one day of tape costs on disk once compressed):")
for t in ('liq_sample','ip_tape','stream_ticks'):
    fs=sorted(glob.glob(f'/root/pe-archive/{t}/*.csv.zst'))[-5:]
    print(f"- {t}: "+", ".join(f"{os.path.basename(f)[:10]} {os.path.getsize(f)/1e6:.0f} MB" for f in fs))
print("\nUncompressed in the database, per day (last full day):")
for t,tscol in [('liq_sample','ts'),('ip_tape','ts'),('stream_ticks','ts_recv'),('xx_tape','ts')]:
    r=q(f"select pg_total_relation_size('{t}')/1e9, count(*) from {t}")[0]; n24=q(f"select count(*) from {t} where {tscol}>now()-interval '24 hours'")[0][0]
    print(f"- {t}: {r[0]:.1f} GB for {r[1]} rows -> about {r[0]/max(1,r[1])*n24:.2f} GB per day at today's {n24} rows/day")
PY
echo; echo "## Disk history (df, from the Watchman reports in the repo)"; grep -h "GB free" /root/pe-queue/reports/watchman_2026-11-1[0-4]_*.md 2>/dev/null | grep -o "[0-9.]* GB free" | head -40 | tr '\n' ' '
echo; echo "## Stream recorder subscription"; grep -i "event_type\|eventType\|EVENT_TYPES\|sports" /root/pe-stream/stream_client.py | head -8 | cut -c1-200
} > $R 2>&1
cd /root/pe-queue && git add reports/collection_2026-11-14.md && git commit -q -m "571: collection reading" && git pull -q --no-edit && git push -q && echo pushed
echo "571 done"
