#!/bin/bash
# 559 (Thu 12 Nov 2026, 19:05). THE PROOF GATE, Peter's correction to order 2: no real money on any rule until it has 100 settled forward
# paper bets, profit after commission overall AND in each half of the 100, in line with the backtest — and Peter says yes in chat.
# The scoreboard's Settled table now shows, per rule: settled n / 100, £ overall, first-half £, second-half £, and GATE: PASS / n more.
# Nothing else changes (order 1: no gate rewrites — this is the report line Peter asked for, not the integrity suite).
set -o pipefail
export PYTHONDONTWRITEBYTECODE=1
cd /root/pe-sports/team && cp sports_team.py sports_team.py.bak_559 && python3 - <<'PY'
p='/root/pe-sports/team/sports_team.py'; s=open(p).read()
assert 'def settled_lines' in s and 'PROOF GATE' not in s
i=s.index('def settled_lines'); j=s.index('\ndef caught_24h')
new='''def settled_lines():
    """PROOF GATE (Peter, 12 Nov): per rule, settled n/100, £ after commission, each half of the settled run, PASS or n more."""
    rows=[]
    def add(label,sql):
        try:
            pn=[float(x) for (x,) in q('local',sql)]   # pnl per settled bet, oldest first
            n=len(pn); tot=sum(pn); h=n//2; a=sum(pn[:h]); b=sum(pn[h:]); per100=None
            try: stk=float(q('local',sql.replace('select pnl','select sum(stake)').split(' order by')[0])[0][0] or 0)
            except Exception: stk=0
            if stk: per100=tot/stk*100
            gate='PASS' if (n>=100 and tot>0 and a>0 and b>0) else (f'{100-n} more' if n<100 else 'FAIL (a half is negative)')
            rows.append((label,n,tot,per100,a,b,gate))
        except Exception as e: rows.append((label,0,0.0,None,0.0,0.0,'no table'))
    add('bot TAKER — all passed cells',"select pnl from bookie_paper where version='v2' and status='settled' and fill_kind='taker' order by settled_ts")
    try:
        for (mt,side) in q('local',"select distinct mkt, side from bookie_paper where version='v2' and fill_kind='taker' and status='settled'"):
            add(f'  taker cell {mt} {side}',f"select pnl from bookie_paper where version='v2' and status='settled' and fill_kind='taker' and mkt='{mt}' and side='{side}' order by settled_ts")
    except Exception: pass
    add('desk FADE (lay scorer +2m, out +10m)',"select pnl from desk_calls where line='FADE' and status='closed' order by exit_ts")
    add('desk HT11 (1-1 HT, back O2.5)',"select pnl from desk_calls where line='HT11' and status='settled' order by exit_ts")
    add('desk CELL (in-play cells)',"select pnl from desk_calls where line='CELL' and status='settled' order by exit_ts")
    add('H0 fade forward paper (m1_alerts)',"select pnl_paper as pnl from m1_alerts where pnl_paper is not null and sent_at>='2026-10-09' order by sent_at")
    return rows
'''
s=s[:i]+new+s[j:]
old="""        L.insert(3,""); L.insert(4,"## Settled — £ per £100 after commission (the number that matters)"); L.insert(5,"| line | settled n | £ | £ per £100 | n 7d | £ 7d |"); L.insert(6,"|---|---|---|---|---|---|")
        for i,(lab,n,pnl,per100,n7,p7) in enumerate(settled_lines()): L.insert(7+i,f"| {lab} | {n} | {pnl:+.2f} | {'n/a' if per100 is None else f'{per100:+.2f}'} | {n7} | {p7:+.2f} |")"""
new2="""        L.insert(3,""); L.insert(4,"## PROOF GATE — 100 settled paper bets, profit after commission overall and in each half, in line with the backtest; then Peter says yes"); L.insert(5,"| rule | settled / 100 | £ after commission | £ per £100 | first half £ | second half £ | gate |"); L.insert(6,"|---|---|---|---|---|---|---|")
        for i,(lab,n,pnl,per100,a,b,gate) in enumerate(settled_lines()): L.insert(7+i,f"| {lab} | {n} / 100 | {pnl:+.2f} | {'n/a' if per100 is None else f'{per100:+.2f}'} | {a:+.2f} | {b:+.2f} | {gate} |")"""
assert s.count(old)==1, "render anchor"; s=s.replace(old,new2)
open(p,'w').write(s); print("scoreboard: proof-gate table")
PY
python3 -m py_compile sports_team.py && echo compiles || { cp sports_team.py.bak_559 sports_team.py; echo RESTORED; exit 1; }
pkill -f sports_team.py; sleep 2; nohup /root/pe-sports/team/run_team.sh >/dev/null 2>&1 & disown; sleep 90
sed -n 1,20p /root/pe-sports/team/scoreboard.md
echo "559 done"
