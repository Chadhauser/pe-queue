#!/bin/bash
# 680 (Thu 19 Nov 2026). The full grid (679) crashed writing its first report: with no survivors yet the table had no "£ a month"
# column to sort by. Fix that line, and make the report unable to stop the grid again (a report error is logged, the grid carries on).
# Then restart the grid in the background. It resumes where it stopped.
T=/root/pe-sports/team; R=/root/pe-queue/reports/grid_680.md
{ echo "# 680 - $(date -u '+%F %H:%M') UTC"; echo '```'
pkill -f '[r]un_grid_history.sh'; pkill -f '[g]rid_history.py'; sleep 2
cp $T/grid_history.py $T/grid_history.py.bak_680
python3 - <<'PY'
p='/root/pe-sports/team/grid_history.py'; s=open(p).read()
old="enumerate(win.sort_values('per_month_at_10', ascending=False).head(20).itertuples(), 1)"
new="enumerate((win.sort_values('per_month_at_10', ascending=False).head(20) if len(win) else win).itertuples(), 1)"
print('sort line:', 'fixed' if old in s else ('already fixed' if new in s else 'NOT FOUND')); s=s.replace(old,new)
old2="        print(f\"{dt.datetime.now():%H:%M} {sport} {mt}: {seen:,} markets\", flush=True); report(con, REP)\n"
new2="        print(f\"{dt.datetime.now():%H:%M} {sport} {mt}: {seen:,} markets\", flush=True)\n        try: report(con, REP)\n        except Exception as e: con.rollback(); print('report error (grid carries on):', repr(e)[:200], flush=True)\n"
print('report guard:', 'added' if old2 in s else ('already there' if new2 in s else 'NOT FOUND')); s=s.replace(old2,new2)
open(p,'w').write(s)
PY
python3 -m py_compile $T/grid_history.py && echo compiles || { cp $T/grid_history.py.bak_680 $T/grid_history.py; echo "COMPILE FAILED - restored"; }
nohup setsid $T/run_grid_history.sh > /dev/null 2>&1 < /dev/null &
sleep 150; echo "running: $(pgrep -fc '[g]rid_history.py')"; tail -6 $T/grid_history.log | cut -c1-200
echo '```'; echo; head -12 /root/pe-queue/reports/grid_history.md 2>&1; } > $R 2>&1
cd /root/pe-queue && git add $R reports/grid_history.md 2>/dev/null; git commit -qm "680: grid report fix, restarted" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
