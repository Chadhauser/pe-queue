#!/bin/bash
# 700 (Sat 21 Nov 2026 11:22, Peter: "Analyse the losses and come up with how to profit from them in the future").
# Builder session 9, after any running builder session: who took our money, and can we stand where they stood.
# New rows in the same test, nothing else. Paper only. No orders. Nothing deleted.
B=/root/pe-builder
cat > $B/BRIEF_losses.md <<'BRIEF'
You are the Builder on Peter Edwards' trading server, session 9. Started once. Do the job, write one page, stop. Read /root/pe-queue/reports/builder_handover_6.md, reports/paper_breakdown.md, reports/exits_why.md if present, and /root/pe-builder/BRIEF_league.md first (HARD RULES unchanged: paper only, never an order endpoint, nothing deleted, back up before editing). Reuse onetest.py; add rows through ways.py.
PETER'S ORDER: analyse the losses and come up with how to profit from them in future. Every pound the paper book lost was won by whoever was on the other side. Find out who that was and whether we can stand there. Use ALL recorded days (31 Oct to today), not only the three paper days, and judge on both halves by date; the three paper days are only where the question came from.
1. WHERE THE LOSSES SIT, counted once per bet, over the paper days and then the same cut over all recorded days through the one test: by sport, market type, side, entry price band, time of entry, whether the exit filled. Separate three things that look alike: (a) loss from the gap between back and lay plus commission (cost of trading: the other side is whoever offers prices); (b) loss from the price itself being wrong on average (the outcome happens less or more often than the price says: the other side is whoever took the opposite bet); (c) loss from not getting out (the other side is whoever offered the only exit, or nobody). Give £ for each.
2. THE OTHER SIDE, as rows in the same test, each a TRADE with a target, a stop and a time limit where it is a trade, or clearly marked BET where it is held: 
 - the straight mirror of each of the twenty worst rules (lay where we backed, back where we laid, same moments), entering by TAKING the price and separately by OFFERING at the price we would have taken;
 - being the one who offers: where our rules paid the gap, rest the opposite order a tick or two away in the same markets at the same moments and close the same way; 
 - being the exit: in the markets and moments where our exits failed (racing in running and the last minutes before the off above all), rest orders well away from the price for people who must get out, small stake, and say what filled and what it made, with the worst single loss shown;
 - long shots: if backing them loses by more than the costs across ALL days, laying them (liability capped at £50) and laying them only when the market is deep enough to get out; show price bands separately and the worst day.
3. HONESTY: a mirror only makes money if the original lost by MORE than the gap and commission, on both halves. Three days of long shots not winning is luck until all the days agree. For every row that looks good: orders, £ kept per £100 on each half, the result without its best day and three biggest winners, the worst day, and the largest single loss. Rows that survive go onto paper like any other, with a stop if they are trades.
WRITE /root/pe-queue/reports/losses_to_profit.md, plain English, one screen: line 1 = of the paper loss, £ from costs, £ from wrong prices, £ from not getting out; line 2 = which 'other side' rows hold up on all days and both halves, each in one sentence with £ kept per £100 and orders, or 'none yet' with the nearest; then the table. Commit and push: cd /root/pe-queue && git add reports/losses_to_profit.md reports/league_table.md 2>/dev/null; git commit -qm "losses to profit" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q. Then end the session.
BRIEF
cat > $B/run_builder_losses.sh <<'SH'
#!/bin/bash
CL=$(cat /root/pe-watchman/claude_path); ts=$(date -u +%F_%H%M)
cd /root/pe-sports/grid && timeout -k 60 14400 "$CL" -p "$(cat /root/pe-builder/BRIEF_losses.md)" --allowedTools "Bash,Read,Write,Edit,Glob,Grep" --max-turns 400 --output-format text > /root/pe-builder/runs/${ts}_losses.log 2>&1
echo "builder losses session ended $(date -u '+%F %H:%M') exit $?" >> /root/pe-builder/sessions.log
SH
chmod +x $B/run_builder_losses.sh
if pgrep -f '[r]un_builder_exits' >/dev/null; then echo "exits session still running - waiting for it (its page is an input)"; exit 75; fi
nohup setsid $B/run_builder_losses.sh > /dev/null 2>&1 < /dev/null & sleep 20; echo "losses session started: $(pgrep -fc '[r]un_builder_losses.sh')"
