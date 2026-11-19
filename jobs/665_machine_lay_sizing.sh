#!/bin/bash
# 665 (Thu 19 Nov 2026, 08:15). 664's first machine run showed "edges" laying 20/1+ shots that simply had not lost yet (zero variance,
# t = 5e16). Honest sizing for lays: risk £2 of LIABILITY (backer stake 2/(price-1)), so one loser costs £2 and each win pays little;
# a cell with no variance gets t = 0 (it proves nothing). Back bets unchanged (£2 stake). Re-run the cells part to prove it.
export PGAPPNAME=batch_665
T=/root/pe-sports/team; R=/root/pe-queue/reports/machine_665.md
{ echo "# 665 — $(date -u '+%F %H:%M') UTC"; echo '```'
cp $T/machine_nightly.py $T/machine_nightly.py.bak_665
python3 - <<'PY'
p='/root/pe-sports/team/machine_nightly.py'; s=open(p).read()
old_f='''    g = ((px - 1) * ST if won else -ST) if side == 'BACK' else (-(px - 1) * ST if won else ST)
    return g * (1 - COMM) if g > 0 else g
assert abs(pnl('BACK', 3.0, True) - 3.92) < 1e-9 and pnl('BACK', 3.0, False) == -2 and pnl('LAY', 3.0, True) == -4 and abs(pnl('LAY', 3.0, False) - 1.96) < 1e-9'''
new_f='''    # 665: a lay risks £2 of LIABILITY (backer stake 2/(px-1)): one loser costs £2, a win pays 2/(px-1) less commission
    g = ((px - 1) * ST if won else -ST) if side == 'BACK' else (-ST if won else ST / (px - 1))
    return g * (1 - COMM) if g > 0 else g
assert abs(pnl('BACK', 3.0, True) - 3.92) < 1e-9 and pnl('BACK', 3.0, False) == -2 and pnl('LAY', 3.0, True) == -2 and abs(pnl('LAY', 3.0, False) - 0.98) < 1e-9
assert abs(pnl('LAY', 51.0, False) - 0.0392) < 1e-9'''
old_t="m = x.mean(); sd = x.std(ddof=1); return n, m / ST * 10, (m / (sd / np.sqrt(n)) if sd > 0 else 0.0)"
new_t="m = x.mean(); sd = x.std(ddof=1); return n, m / ST * 10, (m / (sd / np.sqrt(n)) if sd > 1e-9 else 0.0)   # 665: no variance proves nothing"
assert old_f in s and old_t in s; s=s.replace(old_f,new_f).replace(old_t,new_t); open(p,'w').write(s); print('patched')
PY
python3 -m py_compile $T/machine_nightly.py && echo compiles || { cp $T/machine_nightly.py.bak_665 $T/machine_nightly.py; echo RESTORED; }
cd $T && timeout 3000 nice -n 10 python3 -I machine_nightly.py > machine_nightly.out 2> machine_nightly.err; echo "exit $? RESULT lines $(grep -c '^RESULT' machine_nightly.out)"; grep -v Deprecation machine_nightly.err | tail -3 | cut -c1-200
echo '```'; } > $R 2>&1
cd /root/pe-queue && git add $R && git commit -qm "665: machine lay sizing" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
