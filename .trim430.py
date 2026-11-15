p = '/root/pe-queue/reports/finder_2026-11-07_item430.md'
s = open(p).read()
drop = [
    "| FIRST lay, equaliser was the underdog | 850 | +0.725 | 2.29 | +0.789 | +0.669 | 0.300 | 0.340 |\n",
    "| EQ back, all | 1,682 | +0.999 | 1.58 | +0.599 | +1.358 | 0.286 | 0.270 |\n",
    "| DRAW lay, all | 1,698 | -0.592 | -2.49 | -0.851 | -0.359 | | |\n",
    "| PRICED, 3 ticks | 1,140 | +0.292 | 1.82 | +0.245 | +0.334 |\n",
    "| L6 less top 1% | 1,528 | -0.009 | -0.06 | | |\n",
    "| ITEM FIRST lay, all prints | 1,284 | +0.143 | 0.92 | -0.055 | +0.365 | 0.215 | 0.243 | +0.048 |\n",
    "| ITEM DRAW back, all prints | 571 | +1.636 | 2.99 | +1.485 | +1.805 | 0.573 | 0.517 |\n",
]
for d in drop:
    assert s.count(d) == 1, d
    s = s.replace(d, '')
s = s.replace("| L6 (t = E+6) | 1,544 | +0.812 | 1.96 | +1.400 | +0.299 |\n", "| L6 (t = E+6); less top 1% -0.009 | 1,544 | +0.812 | 1.96 | +1.400 | +0.299 |\n")
s = s.replace("Next door: item 431 (new, below): PRICED FIRST lay, rule fixed tonight, on games this read never saw (bf_hist_other MO 2023-04 to 2024-10 and 2026-05 to 09, af_events goal minutes, games not in af_price_map); first read 8 Nov.\n",
              "Next door: item 431, read below.\n")
s = s.replace("\n\n## Item 70 (recurring)\n266 files/min", "\n\n## Item 70 (recurring)\n266 files/min")
open(p, 'w').write(s)
print(len(s.split('\n')))
