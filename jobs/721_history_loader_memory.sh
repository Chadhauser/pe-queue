#!/bin/bash
# 721 (Fri 27 Nov 2026 08:27, Peter: "Yes" to fix the history loader). Small fixer session. Nothing deleted. No orders.
mkdir -p /root/pe-fixer/runs
cat > /root/pe-fixer/BRIEF_loader.md <<'BRIEF'
You are the Fixer on Peter Edwards' trading server. One small job, then stop. HARD RULES: never an order endpoint; nothing deleted (no rows, tables or files); back up any file before editing (.bak_721); credentials only through /root/pe-queue/runner/creds.py; do not touch the recorders, the trial loop, the paper trader or the scorecard. Do not write any wait check of the form pgrep -f run_scorecard.sh.
FAULT (found by the fixer on 26 Nov): the history loader (/root/pe-hist/loader.py, kept alive by keepalive_hist.sh) has every owned month loaded ("ALL OWNED MONTHS LOADED, months still to load: 0"), yet each hour it still runs count(DISTINCT market_id) over bf_hist_other (about 282 million rows). That grows to about 4 GB of memory, 3 GB of swap and 15 GB of temp files on an 18 GB server, and was itself killed for memory at 18:44 UTC on 26 Nov. It competes with the trial loop and the recorders.
FIX: when there is nothing to load, the loader must do no heavy query at all: keep a small state file or table of months already loaded and their counts (written once, from the figures it already has; if a count is needed take it once from the table's statistics or a per-month stored figure, never a full distinct count each hour), check the owned-months list against it cheaply, and sleep. It should still pick up a newly owned month by itself and load only that month. Prove: one idle cycle's peak memory and seconds before and after; no temp files left; the loaded-months list unchanged. Also make the watchman's and the integrity suite's 'history loader advanced in the last 2 hours' check read 'nothing to load' as a pass, not a fail (back up first).
REPORT /root/pe-queue/reports/loader_721.md, plain English, under 8 lines: what it was doing, what it does now, memory and seconds before and after, proof the loaded months are unchanged. Commit and push: cd /root/pe-queue && git add reports/loader_721.md && git commit -qm "721: history loader idles without a heavy query" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q. Then end the session.
BRIEF
cat > /root/pe-fixer/run_fixer_loader.sh <<'SH'
#!/bin/bash
CL=$(cat /root/pe-watchman/claude_path); ts=$(date -u +%F_%H%M)
cd /root/pe-hist && timeout -k 60 5400 "$CL" -p "$(cat /root/pe-fixer/BRIEF_loader.md)" --allowedTools "Bash,Read,Write,Edit,Glob,Grep" --max-turns 120 --output-format text > /root/pe-fixer/runs/${ts}_loader.log 2>&1
echo "fixer loader session ended $(date -u '+%F %H:%M') exit $?" >> /root/pe-fixer/sessions.log
SH
chmod +x /root/pe-fixer/run_fixer_loader.sh
nohup setsid /root/pe-fixer/run_fixer_loader.sh > /dev/null 2>&1 < /dev/null & sleep 10; echo "loader fixer started: $(pgrep -fc '[r]un_fixer_loader.sh')"
