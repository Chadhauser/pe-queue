#!/bin/bash
# 684 (Fri 20 Nov 2026, CEO chat order pasted by Peter 06:50). THE BUILDER: a Claude Code session started ONCE on this server, working
# directly on the data, so the full grid is not built through 20-minute queue round trips. It writes the grid code for the recorded
# prices, tests it, runs it, reads the result, fixes it, sets it running as an ordinary background process, and STOPS. No loop, no
# timer on the builder itself. Paper only, no orders, nothing deleted. Plus: reports/grid_progress.md rewritten every hour by a plain
# script (no AI) from the grid's tables, and pushed, so the CEO chat can read it without Peter asking.
B=/root/pe-builder; mkdir -p $B/runs /root/pe-sports/grid; R=/root/pe-queue/reports/builder_684.md
cat > $B/BRIEF.md <<'BRIEF'
You are the Builder on Peter Edwards' trading server (Contabo). You are started once. Do the job, leave ordinary background processes running, write your handover, and stop. Do not wait in idle loops; if a run takes more than a few minutes, start it with nohup in the background and move on.

THE ONE JOB: the full grid, complete by Wednesday 25 November 2026. Money is the only measure; target £10,000 a month.
Every sport held x every market type x every exchange (Betfair, Smarkets, Matchbook) x price in 10 bands (implied chance 0-10% ... 90-100%) x time (24 hours, 6 hours, 1 hour, 10 minutes, 2 minutes before the start, then in-play in thirds) x back and lay x thin / medium / deep market x price rising / falling / flat over the previous period. For each slice: bets, profit per £100 after 2% commission, first half, second half (halves by date). Keep slices with 300 or more bets that profit in both halves. Three families: (1) hold to the result; (2) in and out (enter at one time point, exit at a later one); (3) offering the price (rest an order inside the spread; count a fill only if the price trades THROUGH it) - family 3 needs real order-book rows.

WHAT EXISTS (read it first, do not rebuild it):
- /root/pe-sports/team/grid_history.py : stage 1 on the Betfair history files (tables bf_hist_other = last traded prices, bf_hist_result = results; local database). Families 1 and 2. It is RUNNING now (started 05:48 UTC 20 Nov by run_grid_history.sh) and writes grid_agg / grid_done / grid_count and /root/pe-queue/reports/grid_history.md. Leave it running. Reuse its functions (points, trades, aggregate, summarise) and its table layout: grid_agg(source, sport, market_type, point, band, side, direction, month, n, s).
- Database access: sys.path.insert(0,'/root/pe-queue/runner'); import creds; creds.pg_local() (sslmode disable). creds.pg_railway() now points at the same machine. Never print a connection string or any secret.
- Recorded prices (real offered prices with sizes), all in the local database: stream_ticks (Betfair stream: sport, mkt, sel_id, back_px, back_sz, lay_px, lay_sz, tv, inplay, secs_to_off; football, tennis, racing), ip_tape (Betfair in-play, every other sport: sport, market_type, market_start, secs_since_start, back_px/sz, lay_px/sz, total_matched), xx_tape (Smarkets and Matchbook: exchange, sport, event_name, market_name, start_ts, inplay, sel_name, back_px/sz, lay_px/sz), book_snap (Betfair football full book: back1, back1_sz, lay1, lay1_sz, mkt_matched, start_ts, inplay), liq_sample (Betfair football in-play ladder). Rows before 14 Nov 2026 are in compressed daily files under /root/pe-archive/<table>/ (csv.zst) and old copies in schema railway_final.
- Results: book_result(market_id, sel_id, status) is filled from Betfair's own settlement by /root/pe-sports/team/machine_nightly.py (listMarketBook, read only). Use the same read-only call to settle every recorded Betfair market of every sport. For Smarkets and Matchbook, settle by matching the event and selection to the Betfair result, or from the exchange's own public settled state; a market you cannot settle with certainty is left out and counted in the report as 'unsettled'.

TRAPS ALREADY HIT - your code must handle each, and your known-answer test must prove it:
1. Survivors: a runner with no price at the exit point is NOT dropped; the bet is held to the result (losers count).
2. Stale prices: a price point must be a fresh quote (recent relative to the point); a dead runner is not priced at an old price.
3. Real prices: on recorded data, back at the best back on offer and lay at the best lay on offer, only where at least £2 is available; stake = min(money on offer, £50); a lay is capped at £50 of liability. Report £ a month at that real stake.
4. Depth: thin / medium / deep from matched volume (tv, total_matched, mkt_matched); history files have no volume, so that split exists only on recorded prices.
5. Halves are by date, never random. A slice that has never shown a losing bet proves nothing: flag it, do not rank it.
6. Heavy queries: bf_hist_other is 68 GB; use the existing indexes (sport, market_type, market_time) and (market_id, sel, ts); never count(distinct) across a whole large table; set a statement_timeout; work in chunks by day or month; run with nice.

HOW TO WORK: put code in /root/pe-sports/grid/. Before any full run, write a small test with a hand-worked example whose answer you know (a few runners, known prices, known results) and make it pass. Then run on one day of data, read the output, fix, repeat until right. Then start the full run in the background with nohup + nice, make it resumable (a done-table per source/day), and add one line to /root/pe-mechanic/watch.list (name|pgrep pattern|log|script|restart command) so the mechanic restarts it after a crash. Write results into grid_agg with source = 'recorded:betfair', 'recorded:smarkets', 'recorded:matchbook' and extra columns only by creating your own tables (grid_agg2 etc.) if the layout cannot hold depth; keep the hourly report script (/root/pe-builder/progress.py) reading everything you add - edit that script so its totals include your tables.

HARD RULES: Paper only. Never place, cancel or change an order; never call placeOrders or any order endpoint; never touch anything named bookie, bot, live_, auto_bettor, or /root/REAL_MONEY_OFF. Never delete data, drop or truncate any table you did not create in this session, or remove files. Never change crontab except to add your own line if truly needed (prefer none). Never change credentials, /root/pe-queue/runner, the recorders (/root/pe-stream, /root/pe-liq, /root/pe-ip, /root/pe-xx, book_recorder.py) or the team loop. No email, no notifications. Never ask Peter to do anything. Keep the database responsive: one heavy query at a time.

WHEN YOU STOP (after the recorded-prices grid is running in the background and its first day of output has been checked by you), write /root/pe-queue/reports/builder_handover.md in plain English, under 40 lines: what you built (file paths), what the known-answer test checks and that it passed, what is running now and how long it should take, what is NOT done yet toward the full grid with the reason, and anything a later builder session must know. Then commit and push it: cd /root/pe-queue && git add reports/builder_handover.md && git commit -qm "builder handover" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q. Then end the session.
BRIEF
cat > $B/progress.py <<'PY'
#!/usr/bin/env python3
"""684 hourly progress, plain English, no AI. Reads the grid's own tables and writes reports/grid_progress.md."""
import sys, datetime as dt, subprocess
sys.path.insert(0, '/root/pe-queue/runner'); sys.path.insert(0, '/root/pe-sports/team')
import creds, psycopg2, pandas as pd, numpy as np, warnings; warnings.filterwarnings('ignore')
import grid_history as g
con = psycopg2.connect(creds.pg_local(), sslmode='disable'); c = con.cursor(); c.execute("SET statement_timeout='900s'")
A = pd.read_sql("SELECT source, sport, market_type, point, band, side, direction, month, n, s FROM grid_agg", con)
L = [f"# Grid progress - {dt.datetime.now(dt.timezone.utc):%A %d %B %Y, %H:%M} UTC", ""]
tot_t = tot_b = tot_w = 0; tops = []
for src, G in A.groupby('source'):
    S = g.summarise(G.drop(columns='source')); big = S[S.n >= 300]; win = big[(big.h1 > 0) & (big.h2 > 0)]
    tot_t += len(S); tot_b += len(big); tot_w += len(win)
    c.execute("SELECT count(*) FROM grid_done WHERE source=%s", (src,)); d = c.fetchone()[0]
    L.append(f"- {src}: {len(S):,} slices tested ({d} market types or days finished), {len(big):,} with 300 or more bets, {len(win):,} profitable in both halves.")
    if len(win): tops.append(win.assign(source=src))
running = subprocess.run("pgrep -fa 'grid' | grep -v pgrep | grep -c python", shell=True, capture_output=True, text=True).stdout.strip()
L[1:1] = ["", f"Slices tested: {tot_t:,}. Slices surviving (300 or more bets, profit after commission in both halves): {tot_w:,}. Grid programs running now: {running}.",
          "History figures are at the last traded price and are candidates only; recorded-price figures are at the real price on offer. Nothing here is real money; no rule has passed the proof gate until the scoreboard says so.", "", "## By source"]
band = lambda b: f"{b * 10}-{b * 10 + 10}% chance"
L += ["", "## Top 20 surviving slices by £ a month (at £10 a bet on history; at the real stake on recorded prices)", "", "| # | source | sport | market | when | price | side | price move | bets | £ per £100 | first half | second half | £ a month |", "|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
if tops:
    T = pd.concat(tops).sort_values('per_month_at_10', ascending=False).head(20)
    for i, r in enumerate(T.itertuples(), 1):
        L.append(f"| {i} | {r.source} | {r.sport} | {r.market_type} | {r.point} | {band(r.band)} | {r.side} | {r.direction} | {r.n:,} | {r.per100:+.2f} | {r.h1:+.2f} | {r.h2:+.2f} | £{r.per_month_at_10:,.0f} |")
else: L.append("| - | none yet | | | | | | | | | | | |")
open('/root/pe-queue/reports/grid_progress.md', 'w').write("\n".join(L) + "\n")
PY
cat > $B/progress.sh <<'SH'
#!/bin/bash
cd /root/pe-builder && nice -n 10 timeout 1500 python3 progress.py >> progress.log 2>&1
cd /root/pe-queue && git add reports/grid_progress.md reports/builder_handover.md 2>/dev/null; git commit -qm "grid progress $(date -u +%H:%M)" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
SH
cat > $B/run_builder.sh <<'SH'
#!/bin/bash
CL=$(cat /root/pe-watchman/claude_path); ts=$(date -u +%F_%H%M)
cd /root/pe-sports/grid && timeout -k 60 14400 "$CL" -p "$(cat /root/pe-builder/BRIEF.md)" --allowedTools "Bash,Read,Write,Edit,Glob,Grep" --max-turns 400 --output-format text > /root/pe-builder/runs/$ts.log 2>&1
echo "builder session ended $(date -u '+%F %H:%M') exit $?" >> /root/pe-builder/sessions.log
/root/pe-builder/progress.sh
SH
chmod +x $B/progress.sh $B/run_builder.sh
{ echo "# 684 - $(date -u '+%F %H:%M') UTC"; echo '```'
python3 -m py_compile $B/progress.py && echo "progress script compiles"
CL=$(cat /root/pe-watchman/claude_path 2>/dev/null); echo "claude code: $([ -x "$CL" ] && echo present || echo MISSING) $($CL --version 2>&1 | head -1)"
crontab -l > /root/crontab.bak_684
( crontab -l | grep -v 'pe-builder/progress.sh'; echo "7 * * * * /root/pe-builder/progress.sh >/dev/null 2>&1   # 684 hourly grid progress file (plain script, no AI)" ) | crontab -
crontab -l | grep -n "pe-builder" | cut -c1-120
/root/pe-builder/progress.sh; echo "first progress file: $(ls -la --time-style=+%H:%M /root/pe-queue/reports/grid_progress.md 2>&1 | awk '{print $6, $7}')"; tail -3 $B/progress.log 2>/dev/null | cut -c1-200
pgrep -f '[r]un_builder.sh' >/dev/null && echo "builder already running" || { nohup setsid $B/run_builder.sh > /dev/null 2>&1 < /dev/null & sleep 45; echo "builder started: $(pgrep -fc '[r]un_builder.sh') session(s); claude processes: $(pgrep -fc 'claude')"; ls -la --time-style=+%H:%M $B/runs | tail -1; }
echo '```'; echo; head -12 /root/pe-queue/reports/grid_progress.md 2>&1; } > $R 2>&1
cd /root/pe-queue && git add $R reports/grid_progress.md 2>/dev/null; git commit -qm "684: the builder started, hourly progress file" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
