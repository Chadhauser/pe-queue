Q = '/root/pe-queue/watchman/FINDER_QUEUE.md'
H = '/root/pe-queue/watchman/HYPOTHESES.md'
item = ("466. RUNNING 2026-11-08 (lane A, about 21:00 UTC; every queue TODO is gated on data or a date tonight; doors checked first and closed: golf, 76 months EMPTY on bf_hist_months; breeding suffix, racing_bsp names carry none, 133,141 win runners; team handicap and odd/even, already item 266; "
        "Finder's own, source c structural, a new cut of item 3, which read the in-play take-profit by band, course, field and steam but never by trip or race code; table racing_bsp; job 499_race_trip_tp, new, from jobs/499_race_shape.sh) "
        "**Racing in-play take-profit by race code and trip: does a long chase swing more than a sprint?** Rationale: in long jump races leaders are often swallowed and fallers reshape the race, so a runner's in-play low or high may run further from BSP than in a 5f sprint; if punters overreact in running, a BSP entry with a resting take-profit should pay in one code and trip and not in another. "
        "Rule fixed now, before any price is read: racing_bsp win and place, UK/IE, runners with BSP > 1.01, ipmin, ipmax and a result; CODE from event_name: Chs CHASE, Hrd HURDLE, NHF/INHF/Bumper NHF, else FLAT; TRIP in furlongs from the name: FLAT SPRINT <= 6f, MILE 7-10f, STAY 11f+; jumps SHORT <= 18f, MID 19-23f, LONG 24f+; names with no trip counted, not traded. "
        "BACK_TP k 0.67, 0.5, 0.33: back at BSP one tick adverse (A); resting lay at L = ladder price at or under BSP x k, filled only if ipmin < L (traded through), and then priced one tick worse than L; hedged green 10 x A / L' - 10, else held to result. "
        "LAY_TP k 1.5, 2, 3: lay at BSP one tick adverse, GBP 10 liability; resting back at H = ladder price at or over BSP x k, filled only if ipmax > H, priced one tick worse; else held to result. Controls BACK and LAY at BSP to result. 2% on profit, dead heats as jobs/499_race_shape.sh. "
        "Price bands on BSP <=3, 3-6, 6-12, 12-30, 30+ and ALL; lines CODE x TRIP x band x shape; halves by date median; one entry per runner per market, many per race, so the bar's t is clustered by race as well as by runner; standard bar. ipmin and ipmax carry no time, so a pass is an upper bound and needs item 372's next door, the in-play touch on ip_tape or bf_racing_log, before it counts.")
L = open(Q).read().rstrip('\n').split('\n')
assert not any(l.startswith('466.') for l in L)
L.append(item)
open(Q, 'w').write('\n'.join(L) + '\n')
h = "2026-11-08 | c structural (racing_bsp, new cut of item 3) | in-play take-profit after a BSP entry by race code and trip, back TP 0.67/0.5/0.33, lay TP 1.5/2/3 (499_race_trip_tp, item 466) | RUNNING | -"
HL = open(H).read().rstrip('\n').split('\n')
HL.append(h)
HL.append("2026-11-08 | d census (bf_hist_months, racing_bsp) | golf on the Betfair history tape; breeding suffix (FR, IRE) in racing names | BLOCKED | golf 76 months all EMPTY, would need the loader to pull Golf files; racing_bsp names carry no suffix, would need a racecard source")
open(H, 'w').write('\n'.join(HL) + '\n')
print('ok')
