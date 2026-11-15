p='/root/pe-queue/reports/finder_2026-11-08_item456.md'
s=open(p).read()
def sub(a,b):
    global s
    assert s.count(a)==1, a[:60]
    s=s.replace(a,b)
sub("""- Entry: the last print of a runner in [KO-W-1h, KO-W], with W = 24, 6 or 2 h.
- Exit: the last pre-off print of the same runner in [KO-30m, KO+10m].
- If there is no such print, the exit falls back to the runner's first in-play print within 10 min of the market's first in-play print. Failing that, the trade settles at the official MO result.
""","""- Entry: last print of a runner in [KO-W-1h, KO-W], W = 24, 6 or 2 h. Exit: its last pre-off print in [KO-30m, KO+10m]; else its first in-play print within 10 min; else the official MO result.
""")
sub("""- Exits: 399,746 at a pre-off print, 4,123 in play, 1,437 at the result.
  - 1,683 had no exit print and no official result, so they are unscored (0.4%).
  - 32 backs at the ladder floor were not traded.
""","""- Exits: 399,746 pre-off, 4,123 in play, 1,437 at the result; 1,683 unscored (no exit, no result, 0.4%); 32 backs at the ladder floor not traded.
""")
sub("""| W24 1.6-2.5 back | 7,865 | -0.131 | -11.59 | -0.104 | -0.168 |
| W2 8-20 back | 5,360 | -0.508 | -12.49 | -0.571 | -0.442 |
| W6 8-20 lay | 3,922 | -0.069 | -14.81 | -0.068 | -0.069 |
| W24 2.5-4 lay | 8,258 | -0.097 | -14.84 | -0.109 | -0.081 |
| W24 1.6-2.5 lay | 7,863 | -0.174 | -15.07 | -0.200 | -0.138 |
| W6 8-20 back | 3,918 | -0.599 | -15.08 | -0.612 | -0.584 |
| W2 8-20 lay | 5,369 | -0.078 | -15.78 | -0.071 | -0.086 |

The other 18 lines run from -0.097 to -0.456, with t from -18 to -44.
""","""| W6 8-20 lay | 3,922 | -0.069 | -14.81 | -0.068 | -0.069 |

The other 24 lines run from -0.078 to -0.508, with t from -11.6 to -44.
""")
sub("""- The median is 0.000 in 13 of 15 cells.
- The mean is +0.4% to +3% in most cells.
- The 8-20 runners drift out the most: +3.2% from 2 h out, +4.9% from 6 h, +10.3% from 24 h.
- Short prices (1.01-1.6) barely move: +0.1% to +0.7%.
""","""- Median 0.000 in 13 of 15 cells. 8-20 runners drift out most: +3.2% from 2 h, +4.9% from 6 h, +10.3% from 24 h; 1.01-1.6 move +0.1% to +0.7%.
""")
sub("""- The halves split at the game median, but trades per game differ by line, so n1 and n2 are uneven on W24.
- The partly loaded Nov 2022 is in item 456. Whether or not a month is complete does not bias a drift read.
""","""- Halves split at the game median, so n1 and n2 are uneven on W24; the part-loaded Nov 2022 is in, which does not bias a drift read.
""")
open(p,'w').write(s); print(len(s.splitlines()))
