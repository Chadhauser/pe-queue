"""Item 424: build the touch job from 499_jump_up_ticks, and fix its rule in the queue before it reads a price."""
J = '/root/pe-queue/jobs/'
s = open(J + '499_jump_up_ticks.sh').read()
subs = [
    ("# 499_jump_up_ticks (Finder 2026-11-07, queue item 415, Finder's own, source a; results from jobs/499_tick_touch_clean.sh): item 414 on the stream: where does the book sit when the first in-play print is 2 to 4 points over the last pre-off print, and what does a back get? Pilot, cannot reach the bar.",
     "# 499_jump_up_delay_touch (Finder 2026-11-07, queue item 424, from item 423; job 499_jump_up_ticks with later entries added): item 414's signal on the stream, entered at back_px 5 and 10 minutes on. Pilot, cannot reach the bar."),
    ("s.pt<=o.off+interval '320 seconds' ORDER BY s.market_id,s.sel_id,s.pt", "s.pt<=o.off+interval '860 seconds' ORDER BY s.market_id,s.sel_id,s.pt"),
    ("    d['vR']=score(lt,prob) if rest_fill(tk,i,lt) else np.nan",
     "    for lab,de in (('v300',300.),('v600',600.)):\n        x=touch_at(tk,t,de,span=60)\n        d[lab]=np.nan if x is None or x[1]>50 else score(x[1],prob)\n        d['b'+lab[1:]]=np.nan if x is None else x[1]\n        d['l'+lab[1:]]=np.nan if x is None or x[2] is None else x[2]\n    d['vR']=score(lt,prob) if rest_fill(tk,i,lt) else np.nan"),
    ("('v10','back_px 10 s on'),", "('v10','back_px 10 s on'),('v300','back_px 5 min on *'),('v600','back_px 10 min on'),"),
    ('print(f"age of the pre-off print, median {Z.age.median():.0f} s")',
     'print(f"age of the pre-off print, median {Z.age.median():.0f} s")\nfor q in ("300","600"):\n    y=Z[Z["b"+q].notna()&Z["l"+q].notna()&(Z["l"+q]>Z["b"+q])]; print(f"book {q} s on, n {len(y)}: spread median {(100*(1/y["b"+q]-1/y["l"+q])).median():.2f} points; lay within 5% of back {(y["l"+q]<=y["b"+q]*1.05).mean():.3f}")'),
]
for a, b in subs:
    assert s.count(a) == 1, a
    s = s.replace(a, b)
open(J + '499_jump_up_delay_touch.sh.wip', 'w').write(s)
Q = '/root/pe-queue/watchman/FINDER_QUEUE.md'
q = open(Q).read().rstrip('\n')
assert '\n424. ' not in q
q += """
424. RUNNING 2026-11-07 (Finder's own, source a, item 423's pass-on read; tables stream_ticks, liq_sample, Railway goal_timeline; job 499_jump_up_delay_touch) **Item 423's later entry at the real touch.** Rationale: item 423's audit on prints read D5 n 1,214 +1.076 t 2.36, controls negative, so it earned this read; item 415 read the taker at the signal only, seconds after it. Rule fixed before this job reads a later price: item 415's signal, results and game list unchanged; entry the first tick with a back price from 300 s after the signal print to 360 s, one tick adverse, over 50 not traded, no suspension filter, as item 423 has no goal filter. 600 s printed the same way. Pilot, cannot reach the bar; a negative read here does not close it at this n.
"""
open(Q, 'w').write(q)
H = '/root/pe-queue/watchman/HYPOTHESES.md'
h = open(H).read().rstrip('\n')
h += "\n2026-11-07 | a (stream_ticks, from item 423) | item 423's 5-minute entry at back_px on the stream, rule fixed | RUNNING (item 424, 499_jump_up_delay_touch) | -\n"
open(H, 'w').write(h)
print('ok')
