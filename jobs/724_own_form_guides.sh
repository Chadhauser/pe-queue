#!/bin/bash
# 724 (Fri 27 Nov 2026 08:40, Peter by voice: "we need to be able to figure out our own form guides for each sport ... and then
# add it to the price"; also "I still want you concentrating on the rules ... I can't believe we can't make money in racing ...
# keep on trying ... speed it up"). Adds a form-guide layer to every sport and keeps the known rules in, tested inside each type.
# Paper and trial only. No orders. Nothing deleted.
B=/root/pe-builder
form='
ADDED 27 Nov 08:45 ON PETER'"'"'S ORDER - OUR OWN FORM GUIDE FOR THIS SPORT, THEN ADD IT TO THE PRICE. Build a form rating of our own from the results and facts we hold, updated after every event, stored in a table (schema of this sport, table form_rating: who, date, rating, and the parts it is made of) and kept current by a daily job in /root/pe-mechanic/watch.list. Make it from what actually happened, not from reputation: results weighted by how recent and by the strength of the opposition; margin, not only win or lose; the conditions it happened in (course, distance, going, surface, format, home or away, rest days, travel); and the price the market gave beforehand, so the rating also records who keeps beating their price and who keeps failing at it. Fit it only on the past and test it on dates it has never seen. THEN ADD IT TO THE PRICE: for every event, our form says one thing and the market says another - measure, by the size of the disagreement, what happened, in each type of event and by money in the market. Earlier work found that before the start the big markets already hold the public facts, so do not stop at the average: look where the disagreement is largest, where the market is thin, and IN PLAY, where form tells you who comes back from behind and who folds, which the in-play price may not hold. Report under its own heading, Form guide: what it is made of in one sentence, how often the higher-rated side won against what the price said, and the £ a day where form and price disagree, at real prices.
ALSO ON PETER'"'"'S ORDER - THE KNOWN RULES STAY IN. Peter believes there is something in the rules and wants them kept at, not dropped. The rule libraries are in the project memory and /root/pe-builder (vendor systems for football, racing and tennis, and the rules already tested). Do not re-run them on the whole sport as one lump, which is how they were tested before: run each inside every type you carve and inside the thin markets, and report any that pay in one type even if it loses overall. SPEED: push a first page as soon as you have the first table, do not wait for everything.'
for s in racing golf cricket; do grep -q 'OUR OWN FORM GUIDE' $B/BRIEF_sport_$s.md || printf '%s\n' "$form" >> $B/BRIEF_sport_$s.md; done
for s in tennis racing; do mkdir -p /root/pe-sports/sports/$s; printf '%s\n' "$form" > /root/pe-sports/sports/$s/ADDED_FORM_27NOV.md; done
cat > $B/BRIEF_form_football.md <<EOF
You are a Builder on Peter Edwards' trading server: the football form-guide session, 27 Nov 2026. Read /root/pe-builder/BRIEF_league.md first; all of it applies with STANDING RULE 708. Paper and trial only; never an order endpoint; nothing deleted; credentials only through /root/pe-queue/runner/creds.py; exchanges only; no lay at 5.0 or longer. Memory: never more than about 5 GB yourself. Work in /root/pe-sports/sports/football_form; do not edit grid, the paper trader, trial.py or the goal signal (read its tables freely: shots, shots on target, expected goals and the version 3 signal are form too); add trial rules the documented way.
SPORT: football, 8 seasons, about 30 leagues, plus every lower and minor league we hold results for.
$form
REPORT /root/pe-queue/reports/form_football.md, plain English, one screen, first page as soon as the first table exists. Commit and push: cd /root/pe-queue && git add reports/form_football.md && git commit -qm "football form guide against the price" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q. Then end the session.
EOF
cat > $B/run_form_football.sh <<'SH'
#!/bin/bash
CL=$(cat /root/pe-watchman/claude_path); ts=$(date -u +%F_%H%M); mkdir -p /root/pe-sports/sports/football_form
cd /root/pe-sports/sports/football_form && timeout -k 60 21600 "$CL" -p "$(cat /root/pe-builder/BRIEF_form_football.md)" --allowedTools "Bash,Read,Write,Edit,Glob,Grep" --max-turns 500 --output-format text > /root/pe-builder/runs/${ts}_form_football.log 2>&1
echo "form football session ended $(date -u '+%F %H:%M') exit $?" >> /root/pe-builder/sessions.log
SH
chmod +x $B/run_form_football.sh
grep -q run_form_football $B/run_lane1_722.sh || echo "/root/pe-builder/run_form_football.sh" >> $B/run_lane1_722.sh
echo "724 done $(date -u +%H:%M) UTC: form guide and keep-the-rules added to racing/golf/cricket briefs ($(grep -l 'OUR OWN FORM GUIDE' $B/BRIEF_sport_{racing,golf,cricket}.md | wc -l) of 3), note left for tennis; football form session queued behind golf. Racing started before this edit: $(pgrep -fc '[r]un_sport_racing.sh') (0 = reads the new brief). Sessions running: $(pgrep -fc 'claude.* -p ') | free memory $(free -g | awk '/Mem/{print $7}') GB." >> /root/pe-queue/reports/running_now.md
cd /root/pe-queue && git add reports/running_now.md && git commit -qm "running now: 724" -q && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
