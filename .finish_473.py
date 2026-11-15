import re
r='reports/finder_2026-11-08_items473-476.md'; s=open(r).read()
res=("Same rule, only unseen games whose home and away names both appear in the 29-league tape (444 club names). 73,179 unseen events read, rule fixed before reading.\n\n"
"| line | n | per £10 | t | h1 | h2 | won | implied |\n|---|---|---|---|---|---|---|---|\n"
"| LATE back leader (scored) | 277 | +0.098 | 0.42 | +0.134 | +0.061 | 0.881 | 0.859 |\n"
"| CTRL first goal 65-93 min wall | 1,097 | -0.002 | -0.01 | +0.126 | -0.130 | 0.754 | 0.744 |\n"
"| LATE price < 1.2 | 195 | +0.335 | 1.75 | +0.298 | +0.374 | 0.938 | 0.897 |\n"
"| LATE home leads | 150 | +0.296 | 1.16 | +0.230 | +0.362 | 0.920 | 0.881 |\n"
"| LATE by year | 2022 n 48 +0.377, 2023 n 144 +0.069, 2024 n 74 -0.227, 2026 n 11 +1.443 | | | | | | |\n\n"
"On the top-league clubs the lean is the right way in both halves but small, n under 300 and t 0.42; it is a top-league effect if it is anything, and price < 1.2 carries it.")
s=s.replace('RESULT_476',res)
s=s.replace('RESULT_VERDICT_476',"On unseen games it is fair-priced across all countries (475 n 900 -0.099) and leans positive only on the same clubs (476 n 277 +0.098 t 0.42; under 1.2 n 195 +0.335 t 1.75, both halves positive), short of the bar.")
old1="What it does support: backing the leader at short prices (< 1.2) after a late first goal is about break-even on 678 unseen games (+0.008), so the market is fair there and not an edge."
new1="What it does support: NOT YET. The one place it is positive is the 29-league clubs at prices under 1.2 after a late first goal (n 195 +0.335 unseen, n 253 +0.786 in-sample at all prices); elsewhere the price is fair."
old2="Next door, dated: item 477 (queued TODO) rests a back on the 1-0 leader one tick above the touch after a goal at 76'+ on local liq_sample, so the trade earns the spread instead of paying it. First look 22 Nov 2026, when liq_sample holds about four weeks of real books."
new2="Next doors, dated: item 476 re-reads as loader 347 clears the LISTFAIL months Nov 2024 to Apr 2026 (more top-league games, first look 1 Dec 2026); item 477 (queued TODO) rests a back one tick above the touch on the late 1-0 leader under 1.2 on local liq_sample, earning the spread instead of paying it, first look 22 Nov 2026."
assert old1 in s and old2 in s
s=s.replace(old1,new1).replace(old2,new2)
assert 'RESULT_' not in s
open(r,'w').write(s); print(len(s.splitlines()),'report lines')
q='watchman/FINDER_QUEUE.md'; t=open(q).read()
st={473:"DONE 2026-11-08 — nothing passes; 0 of 69 lines; V2 BACK_M ALL n 137 -0.816 t -0.87 h1 -1.265 h2 -0.347, PAIR n 137 -1.003; the bound breaks on stale prints only; first run VOID after a fix of two biases (map guard on the final price, goal-minute entries dropped), its C5 T>60 n 754 +1.023 t 3.41 fell to n 584 +0.425 t 1.22; jobs/499_under_bound.sh, reports/finder_2026-11-08_items473-476.md",
474:"DONE 2026-11-08 — in-sample, cannot pass; G61+ n 3,294 +0.108 t 0.91 after the same fix (+0.337 t 2.97 before); G76+ g1 n 253 +0.786 t 4.44 h1 +0.522 h2 +1.075 taken to 475; G<=45 n 9,217 -0.239; jobs/499_post_goal_back.sh, same report",
475:"DONE 2026-11-08 — nothing passes; LATE back leader n 900 -0.099 t -0.75 h1 -0.071 h2 -0.127, won 0.872 v implied 0.870 on 72,855 unseen events, all countries; CTRL n 3,215 -0.419 t -3.90; jobs/499_late_lead_unseen.sh, same report",
476:"DONE 2026-11-08 — nothing passes; LATE n 277 +0.098 t 0.42 h1 +0.134 h2 +0.061; under 1.2 n 195 +0.335 t 1.75 both halves positive; re-read when the LISTFAIL months clear, first look 1 Dec 2026; jobs/499_late_lead_unseen_top.sh, same report"}
for k,v in st.items():
    t,n=re.subn(r'(?m)^%d\. RUNNING [^(]*'%k, '%d. %s '%(k,v), t, count=1); assert n==1,k
t=t.rstrip('\n')+'\n'+("477. TODO (re-check 22 Nov 2026, when local liq_sample holds about four weeks of MO books from 27 Oct; first count games 0-0 to a first goal at 76' or later with a real MO touch in the 6 min after; "
"Finder's own, source c, next door of items 474-476; tables liq_sample (MATCH_ODDS, real touch with sizes), goal_timeline; job 499_late_lead_rest to write from jobs/499_late_lead_unseen_top.sh and jobs/499_xx_rest.sh) "
"**Rest a back one tick above the best back on the 1-0 leader under 1.2, 3-6 min after a late first goal, held to the result.** Rationale: at prints the late leader is fair across all countries (475 n 900 -0.099, won 0.872 v 0.870) "
"and leans positive on the 29-league clubs under 1.2 (476 n 195 +0.335 t 1.75); paying a tick at 1.15 costs about 13% of the win, so a resting fill may be the difference; count fills honestly (a fill only when the lay side trades through the price), unfilled orders scored 0, filled ones held to the result.\n")
open(q,'w').write(t)
h='watchman/HYPOTHESES.md'; u=open(h).read()
rep={'(499_under_bound, item 473) | RUNNING | -':'(499_under_bound, item 473) | DONE | nothing passes; V2 BACK_M n 137 -0.816; bound breaks on stale prints only; first run VOID (two biases fixed)',
'(499_post_goal_back, item 474) | RUNNING | -':'(499_post_goal_back, item 474) | DONE | in-sample; G61+ n 3,294 +0.108 t 0.91; G76+ g1 n 253 +0.786 t 4.44 taken to 475',
'(499_late_lead_unseen, item 475) | RUNNING | -':'(499_late_lead_unseen, item 475) | DONE | nothing passes; n 900 -0.099 t -0.75, won 0.872 v implied 0.870',
'(499_late_lead_unseen_top, item 476) | RUNNING | -':'(499_late_lead_unseen_top, item 476) | DONE | nothing passes; n 277 +0.098 t 0.42; under 1.2 n 195 +0.335 t 1.75; re-read 1 Dec'}
for a,b in rep.items():
    assert a in u,a; u=u.replace(a,b)
u=u.rstrip('\n')+'\n'+"2026-11-08 | c structural (liq_sample, from 474-476) | rest a back one tick above the touch on the late 1-0 leader under 1.2, 3-6 min after a first goal at 76'+ (item 477) | TODO (re-check 22 Nov) | 476 under 1.2 n 195 +0.335 t 1.75 at prints\n"
open(h,'w').write(u); print('ok')
