#!/bin/bash
# 730 (Sat 28 Nov 2026 14:05, Peter: "Are we all set for this afternoon's football, I don't want anything being broken before
# the 3pm kick offs"). Health snapshot now, then the reconnect fix for the three programs still failing since the database
# restart of 27 Nov 05:47 (coherence_paper, v3_recorder, desk). Places nothing. Nothing deleted.
B=/root/pe-builder
cat > $B/BRIEF_3pm.md <<'EOF'
You are a Builder on Peter Edwards' trading server. It is Saturday 28 Nov, about 14:10 UK; the big block of football kicks off at 15:00 UK. Peter asked: "Are we all set for this afternoon's football, I don't want anything being broken before the 3pm kick offs." Read /root/pe-builder/BRIEF_league.md first. Never an order call; do not touch /root/REAL_MONEY_OFF, /root/pe-real/placer.py or the dry runner (it is mid-test: do not restart it); nothing deleted; archive copy before any edit; no secrets written anywhere. You have 35 minutes in all. Be quick and careful: a restart that goes wrong at 14:50 is worse than leaving a thing as it is.
STEP 1 (finish in 6 minutes, then push): write /root/pe-queue/reports/pre3pm.md, plain English, phone length. Line 1: "READY" or "NOT READY: <what>". Then one line each, with the time of the last row written and OK or FAILING: Betfair price stream; Betfair order book recorder; in-play tape; Smarkets tape; Matchbook tape; the second recorder for the 38 extra football market types; live match facts (shots, goals) and the goal signal version 3 recorder; results and settling; the trial loop (trial_today.md age) and T1 orders today; the dry runner (alive, last decision, matched so far); the mechanic; free memory and what is using it (name the big ones), disk free; how many football matches kick off 14:55-15:05 UK and whether the stream's market cap (200) or anything else will stop us recording all of them. Push: cd /root/pe-queue && git add reports/pre3pm.md && git commit -qm "ready for 3pm: snapshot" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
STEP 2 (only if it can be proved done by 14:45 UK; otherwise skip and say so): coherence_paper.py and v3_recorder.py (/root/pe-sports/team) and desk.py (/root/pe-sports/desk) have failed with "cursor already closed" since the database restart at 05:47 UTC on 27 Nov. Apply the same reconnect fix already made and proved in book_recorder.py this morning (see /root/pe-queue/reports/safe_path_727.md, 28 Nov section), restart only those processes one at a time, and show each writing rows again. If one does not come back, put its original back and restart that.
STEP 3: if free memory is under 4 GB or the 15:00 load is likely to push it there, say which research session is the biggest and pause it with a stop signal it can be resumed from (kill -STOP, note the process number in the report so it can be continued after 17:00 with kill -CONT); do not kill anything. If the stream cap would drop markets, say which are dropped and why; do not change the cap in the last 20 minutes before kick-off.
STEP 4 (by 14:50 UK): update pre3pm.md - line 1 final, what you fixed with proof, what you left alone and why - and push again the same way. Then end the session.
EOF
cat > $B/run_3pm.sh <<'SH'
#!/bin/bash
CL=$(cat /root/pe-watchman/claude_path); ts=$(date -u +%F_%H%M)
cd /root && timeout -k 30 2400 "$CL" -p "$(cat /root/pe-builder/BRIEF_3pm.md)" --allowedTools "Bash,Read,Write,Edit,Glob,Grep" --max-turns 150 --output-format text > /root/pe-builder/runs/${ts}_3pm.log 2>&1
echo "3pm session ended $(date -u '+%F %H:%M') exit $?" >> /root/pe-builder/sessions.log
SH
chmod +x $B/run_3pm.sh
nohup setsid $B/run_3pm.sh > /dev/null 2>&1 < /dev/null &
