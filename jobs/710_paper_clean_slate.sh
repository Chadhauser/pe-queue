#!/bin/bash
# 710 (Sat 21 Nov 2026 18:31, Peter: "clear the slate on the paper trading and start again - none of those numbers are true and
# not part of our data led strategy"). One short session: archive the old paper record (kept, not deleted), take every old rule
# off paper, start the paper book again from zero. Paper only. No orders. Nothing deleted.
B=/root/pe-builder
cat > $B/BRIEF_slate.md <<'BRIEF'
You are the Builder on Peter Edwards' trading server, session 16. Short, careful job; light on memory (no simulations, no big loads - another session may be running). Read /root/pe-builder/BRIEF_league.md (HARD RULES: paper only, never an order endpoint, NOTHING DELETED, back up before editing) and reports/builder_handover_10.md, builder_handover_6.md, builder_handover_5.md.
PETER'S ORDER (21 Nov 18:31): clear the slate on the paper trading and start again. The paper numbers so far came from rules written first and picked on the same days they were tested on; they are not part of the data-led method and he does not want them shown as the paper record.
DO:
1. ARCHIVE, do not delete: copy grid.paper_trades, grid.paper_bank, paper_forward / paper_start / paper_end / paper_failed (whatever exists) to tables with the suffix _to_21nov in a schema 'paper_archive', and dump each to /root/pe-archive/paper_to_21nov/<table>.csv.zst. Check row counts match. Copy reports/trades_*.md, paper_forward.md and paper_breakdown.md into /root/pe-queue/reports/archive_paper_to_21nov/ (git mv is fine for the dated trades files; leave a one-line note where they were).
2. TAKE EVERY OLD RULE OFF PAPER: all rules now on paper (the 13 that stayed, and any others) are marked 'off paper - slate cleared 21 Nov 2026 on Peter's order' with the date; the paper trader places nothing for them. Their rows in the registry and the league stay.
3. START AGAIN FROM ZERO: the live paper tables are emptied ONLY after step 1 is verified (row counts and files present), so nothing is lost. The paper book and the bank book (£2,000, trades only, limits on) restart at zero with a start time of now. The running total counts from this moment only.
4. NEW ENTRY RULE written into the paper trader's own gate (and stated at the top of paper_forward.md): from now a rule goes onto paper only if (a) it names in one plain sentence who is on the other side and why they keep paying, (b) it was found on one slice of dates, checked on a second and confirmed on a third it never touched, with the pass bar raised for the number of versions tried (state the bar used), (c) it is a TRADE with a target, a stop as a percentage of the stake and a time limit, or is clearly labelled a BET, (d) it does not lay at 5.0 or longer, and (e) it is exchange only. Nothing else gets on. An empty paper book is the correct state until something passes; do not fill it.
5. FILES: trades_today.md now reads, when there are no trades: 'No paper trades today: nothing has passed the entry rule yet. Slate cleared 21 Nov 2026 18:31 UK; the earlier record is archived, not shown.' then the two total lines at £0.00. 'Trades' and the bank line count from the new start only.
6. ALSO, small and in the same files: the paper trader was killed for lack of memory three times this afternoon. Make its day load light (read only the markets of rules on paper; with none on paper it should load almost nothing) and confirm one clean cycle.
7. Friday's four-line email (friday_four.py, back it up): its paper line must say 'paper record restarted 21 Nov' and give the new total; it must not quote the archived figures as current.
WRITE /root/pe-queue/reports/paper_slate_710.md, plain English, under 15 lines: what was archived and where (tables, row counts, files), how many rules came off, the new start time, the entry rule as written, proof of one clean cycle and its memory use. Commit and push: cd /root/pe-queue && git add -A reports && git commit -qm "710: paper slate cleared; old record archived; new entry rule" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q. Then end the session.
BRIEF
cat > $B/run_builder_slate.sh <<'SH'
#!/bin/bash
CL=$(cat /root/pe-watchman/claude_path); ts=$(date -u +%F_%H%M)
cd /root/pe-sports/grid && timeout -k 60 5400 "$CL" -p "$(cat /root/pe-builder/BRIEF_slate.md)" --allowedTools "Bash,Read,Write,Edit,Glob,Grep" --max-turns 150 --output-format text > /root/pe-builder/runs/${ts}_slate.log 2>&1
echo "builder slate session ended $(date -u '+%F %H:%M') exit $?" >> /root/pe-builder/sessions.log
SH
chmod +x $B/run_builder_slate.sh
nohup setsid $B/run_builder_slate.sh > /dev/null 2>&1 < /dev/null & sleep 15
echo "slate session: $(pgrep -fc '[r]un_builder_slate.sh') | other sessions now: $(pgrep -fa 'run_(builder[a-z_]*|books|goaltrade|goalaudit|markets|fixer)\.sh' | grep -o 'run_[a-z_]*' | sort -u | tr '\n' ' ') | free memory: $(free -g | awk '/Mem/{print $7" GB of "$2}') | $(date -u +%H:%M) UTC" > /root/pe-queue/reports/running_now.md
cd /root/pe-queue && git add reports/running_now.md && git commit -qm "running now" -q && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
