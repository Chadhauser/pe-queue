#!/bin/bash
# 706 (Sat 21 Nov 2026 16:04, Peter: "No bookmakers, exchanges only. You start winning on bookmakers you are banned almost
# instantly"). Stops the bookmaker session and restarts it trimmed to exchanges only: the existing goal signal's honest test
# (unchanged) and Betfair against Smarkets and Matchbook. Paper only. No orders. Nothing deleted.
for p in $(pgrep -f '[r]un_books.sh'); do s=$(ps -o sid= -p $p | tr -d ' '); [ -n "$s" ] && pkill -TERM -s "$s"; done; sleep 5
B=/root/pe-builder/BRIEF_books.md; cp $B $B.bak_706
python3 - <<'PY'
p='/root/pe-builder/BRIEF_books.md'; t=open(p).read()
a=t.index('PART A - BOOKMAKERS'); c=t.index('PART C - THE GOAL SIGNAL'); w=t.index('WRITE /root/pe-queue/reports/books_and_goal_signal.md')
new_ab='''PETER'S RULING (21 Nov 16:04): EXCHANGES ONLY. No bookmakers - a winning bookmaker account is closed almost at once. Do NOT test betting at bookmakers and do NOT build a bookmaker price collector. If an earlier run of this session left a bookmaker collector or timer running, stop it (comment its line with '#STOPPED-706'), keep its files.
PART A - THE THREE EXCHANGES AGAINST EACH OTHER (Peter has Betfair, Smarkets and Matchbook). From the recorded prices (stream_ticks, xx_tape and archives; say honestly what the polling interval of each allows): (1) crossed prices - moments a BACK on one exchange is higher than the LAY on another by enough to lock a profit after each exchange's own commission (Betfair 2%, Smarkets 2%, Matchbook as recorded in the project, state the rates used) and with at least £10 on offer on both sides: how many a day, how long they last, £ locked per £100, by sport and by minutes to the start / in play, first half of the dates against the second; (2) lead and lag - when Betfair moves, how many seconds until Smarkets and Matchbook follow, and the reverse; the result of backing on the slow exchange at its stale price right after Betfair has shortened, closing there or on Betfair, with a stop and a time limit, backs first, no lay at 5.0 or longer; (3) offering on the quiet exchange at Betfair's price plus a margin and closing on Betfair when filled (the bookmaker's seat, across exchanges) - only if trades on the quiet exchange can be inferred; if not, say what is missing. If the 24-second polling of the other exchanges makes (2) untestable, measure exactly what polling interval would be needed and whether their free feeds allow it, and start recording at that rate tonight if they do.
'''
neww='''WRITE /root/pe-queue/reports/books_and_goal_signal.md, plain English, one screen, answer first: line 1 = crossed prices between the exchanges: how many a day, £ locked per £100, how long they last; line 2 = lead and lag between the exchanges and whether trading it pays, both halves; line 3 = goal signal: running yes/no, predicts goals yes/no with the uplift, beats the price yes/no with £ per £100. Then the tables. Push a first version within 90 minutes and again at the end: cd /root/pe-queue && git add reports/books_and_goal_signal.md && git commit -qm "exchanges against each other; goal signal test" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q. Then end the session.
'''
partc=t[c:w].replace("a bookmaker's over price left stale after an alert","the over price on Smarkets or Matchbook left stale after an alert")
t2=t[:a]+new_ab+partc+neww
t2=t2.replace("So be faster than THEM.","Peter has since ruled bookmakers out; the same idea applies between exchanges: Betfair is the busiest, the other two follow.")
open(p,'w').write(t2)
PY
grep -c "EXCHANGES ONLY" $B
nohup setsid /root/pe-builder/run_books.sh > /dev/null 2>&1 < /dev/null & sleep 15; echo "exchanges session restarted: $(pgrep -fc '[r]un_books.sh')"
