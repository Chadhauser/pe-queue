J = '/root/pe-queue/jobs/499_jump_up_delay.sh.wip'
s = open(J).read()
for a, b in [
    ("T['v3']=[bk3(p,w) for p,w in zip(T.pb,T.won)]", "T['vt3']=[bk3(p,w) for p,w in zip(T.pb,T.won)]"),
    ("row('MAY23 ONE E3 three ticks',M,'v3')", "row('MAY23 ONE E3 three ticks',M,'vt3')"),
    ("def row(nm,x,col):\n", "assert not T['vt3'].equals(T['v3'])\ndef row(nm,x,col):\n"),
    ("Prints only, so a pass is an upper bound.\n", "Prints only, so a pass is an upper bound.\n# FIX 2026-11-07, first run: the three-tick column v3 was overwritten by the D=3 column, so E3 printed D3's numbers (n 116 -0.177). Renamed vt3; no rule changed, nothing else moves.\n"),
]:
    assert s.count(a) == 1, a
    s = s.replace(a, b)
open(J, 'w').write(s)
R = '/root/pe-queue/jobs/499_may23_rereads.sh.wip'
r = open(R).read()
a = r[r.index('echo "== JOB 499_cup_ties'):r.index('echo "== SURVIVORS')]
r = r.replace(a, '')
r = r.replace("Item 137 is left out, as its first 300 games are burn-in and one month is all burn-in. Read only.",
              "Item 137 is left out, as its first 300 games are burn-in and one month is all burn-in. Item 292 was removed after one run: cup_ties needs league history from the 60 days before a game, and the tape starts May 2023, so 967 games had no league class, no DIVS game was read, and the job's table step fell over on the empty line. Read only.")
open(R, 'w').write(r)
print('ok')
