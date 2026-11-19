#!/bin/bash
# 664 (Thu 19 Nov 2026, 08:00). THE ONE MACHINE. 663 showed it already exists: sports_team.py (5 Nov) is a loop with a pre-registered
# hypothesis queue, one Verifier gate and one scoreboard. Since then I ran tests BESIDE it. From now on everything goes through it:
#  1. machine_nightly.py = hypothesis M1, every 24 h from 01:30 UTC: settles every recorded market from Betfair (book_result), tests
#     every market type x side x price band x timing x segment (internationals included) at the REAL price on offer, older half picks /
#     newer half judges, and reviews the losers of every paper rule (fix learned on older, judged on newer, adopted fixes tracked forward).
#  2. the scoreboard's proof-gate table now carries every live paper runner: bot v2.2 (was missing - it counted v2 only), small bites
#     by cell, coherence real book, v3 R1/R2, and the machine's adopted fixes. Paper money line = all runners.
# First run of machine_nightly now, by hand, to prove it works. Report: reports/machine_664.md (+ reports/machine_nightly.md).
export PGAPPNAME=batch_664
T=/root/pe-sports/team; R=/root/pe-queue/reports/machine_664.md
cat > $T/machine_nightly.py <<'MACHINE'
#!/usr/bin/env python3
"""664 THE MACHINE, nightly part. Run by the sports team loop (sports_team.py) as hypothesis M1 every 24 h; its RESULT lines go
through the same Verifier gate as everything else, and the one scoreboard shows them.
1. SETTLE: every book_snap market that has finished gets Betfair's own result (book_result).
2. REAL-PRICE CELLS: every market type x side x price band x timing (2 min / 30 min before the off) x segment (all, internationals),
   betting the REAL touch (best back or best lay with £2+ on offer - the price actually there, so no adverse tick is added) and
   holding to the result. £2, 2% COMM on winnings. Older half of match dates = in-sample, newer half = judged. control = the
   opposite side on the same runners at the same moment. Grows every night as the recorder adds data.
3. LOSER REVIEW: every paper rule with 20+ settled bets: what do the losers share? The one exclusion learned on the OLDER half is
   judged on the NEWER half; if it improves the newer half and leaves it positive it is adopted and tracked forward from that day
   (machine_filters.json, machine_lines.json -> the scoreboard's proof-gate table).
Read only towards the exchange: listMarketBook for results, nothing is placed."""
import sys, re, json, time, datetime as dt, subprocess, requests, psycopg2
import numpy as np, pandas as pd
sys.path.insert(0, '/root/pe-queue/runner'); import creds
ROOT = '/root/pe-sports/team'; REP = '/root/pe-queue/reports/machine_nightly.md'
COMM = 0.02; ST = 2.0
INTL = re.compile(r'nations league|friendl|qualif|world cup|euro 20|uefa euro|afcon|africa cup|copa america|asian cup|gold cup|international', re.I)
def pnl(side, px, won):
    g = ((px - 1) * ST if won else -ST) if side == 'BACK' else (-(px - 1) * ST if won else ST)
    return g * (1 - COMM) if g > 0 else g
assert abs(pnl('BACK', 3.0, True) - 3.92) < 1e-9 and pnl('BACK', 3.0, False) == -2 and pnl('LAY', 3.0, True) == -4 and abs(pnl('LAY', 3.0, False) - 1.96) < 1e-9
out = [f"# The machine — nightly run {dt.datetime.utcnow():%F %H:%M} UTC", ""]
con = psycopg2.connect(creds.pg_local(), sslmode='disable'); con.autocommit = True; c = con.cursor(); c.execute("SET statement_timeout='3000s'")
c.execute("CREATE TABLE IF NOT EXISTS book_result (market_id TEXT, sel_id BIGINT, status TEXT, settled_at TIMESTAMPTZ DEFAULT now(), PRIMARY KEY (market_id, sel_id))")
# ---------------- 1. settle
APP, USER, PW = creds.betfair(); TOK = None
def login():
    global TOK
    r0 = requests.post("https://identitysso.betfair.com/api/login", data={"username": USER, "password": PW}, headers={"X-Application": APP, "Accept": "application/json"}, timeout=20)
    r = r0.json()
    if r.get('status') != 'SUCCESS': raise RuntimeError(f"login {r.get('error')}")
    TOK = r['token']
def api(ep, body):
    for attempt in (1, 2):
        if TOK is None: login()
        r = requests.post(f"https://api.betfair.com/exchange/betting/rest/v1.0/{ep}/", json=body, headers={"X-Application": APP, "X-Authentication": TOK, "Content-Type": "application/json"}, timeout=30)
        try:
            j = r.json()
            if isinstance(j, dict) and ('faultcode' in j or 'detail' in j): raise ValueError(str(j)[:120])
            return j
        except ValueError:
            if attempt == 2: raise
            login()
c.execute("""SELECT DISTINCT market_id FROM book_snap b WHERE start_ts < now() - interval '4 hours'
             AND NOT EXISTS (SELECT 1 FROM book_result r WHERE r.market_id = b.market_id)""")
todo = [r[0] for r in c.fetchall()]; done = 0; still_open = 0
for i in range(0, len(todo), 40):
    try: books = api('listMarketBook', {"marketIds": todo[i:i + 40]})
    except Exception as e: out.append(f"settle batch {i}: {e!r}"[:160]); continue
    for b in books:
        if b.get('status') != 'CLOSED': still_open += 1; continue
        for r in b.get('runners', []):
            c.execute("INSERT INTO book_result (market_id, sel_id, status) VALUES (%s,%s,%s) ON CONFLICT DO NOTHING", (b['marketId'], r['selectionId'], r.get('status')))
        done += 1
c.execute("SELECT count(DISTINCT market_id) FROM book_result"); nres = c.fetchone()[0]
out += ["## 1. Results", "", f"Markets to settle tonight {len(todo)}: settled {done}, not closed yet {still_open}. Markets with a result in total: {nres}.", ""]
# ---------------- 2. real-price cells
E = pd.read_sql("""SELECT DISTINCT ON (s.market_id, s.sel_id, s.w) s.market_id, s.sel_id, s.market_type, s.competition, s.country, s.start_ts, s.w,
                          s.back1::float8 b, s.back1_sz::float8 bs, s.lay1::float8 l, s.lay1_sz::float8 ls, r.status res
                   FROM (SELECT *, CASE WHEN ts BETWEEN start_ts - interval '5 min' AND start_ts - interval '1 min' THEN '2min'
                                        WHEN ts BETWEEN start_ts - interval '35 min' AND start_ts - interval '25 min' THEN '30min' END w
                         FROM book_snap WHERE NOT inplay AND market_type <> 'ASIAN_HANDICAP') s
                   JOIN book_result r ON r.market_id = s.market_id AND r.sel_id = s.sel_id
                   WHERE s.w IS NOT NULL AND r.status IN ('WINNER', 'LOSER')
                   ORDER BY s.market_id, s.sel_id, s.w, s.ts DESC""", con)
out += ["## 2. Real-price cells (bet the price actually on offer, held to the result)", ""]
results = []
if E.empty:
    out.append("No settled recorded markets yet.")
else:
    E['won'] = E.res == 'WINNER'; E['seg'] = np.where(E.competition.fillna('').str.contains(INTL) | E.country.isna(), 'intl', 'club')
    E = E[(E.b > 1) & (E.l > 1) & (E.l < 1000)].copy(); E['mid'] = (E.b + E.l) / 2; E['band'] = np.floor((1 / E.mid) / 0.05) * 0.05
    E['pb'] = [pnl('BACK', b, w) if s >= 2 else np.nan for b, s, w in zip(E.b, E.bs, E.won)]
    E['pl'] = [pnl('LAY', l, w) if s >= 2 else np.nan for l, s, w in zip(E.l, E.ls, E.won)]
    E['day'] = pd.to_datetime(E.start_ts, utc=True).dt.date; split = sorted(E.day.unique())[len(E.day.unique()) // 2]
    out.append(f"Runner prices at a real touch: {len(E):,} on {E.market_id.nunique():,} settled markets, {E.day.min()} to {E.day.max()}; older half before {split}, newer half from it.")
    def st(x):
        x = np.asarray(x, float); x = x[~np.isnan(x)]; n = len(x)
        if n < 2: return n, 0.0, 0.0
        m = x.mean(); sd = x.std(ddof=1); return n, m / ST * 10, (m / (sd / np.sqrt(n)) if sd > 0 else 0.0)
    rows = []
    for seg in ('all', 'intl'):
        S = E if seg == 'all' else E[E.seg == 'intl']
        for (mt, w, band), g in S.groupby(['market_type', 'w', 'band']):
            for side, col, ctl in (('BACK', 'pb', 'pl'), ('LAY', 'pl', 'pb')):
                n, m10, t = st(g[col])
                if n < 30: continue
                o = g[g.day < split]; nw = g[g.day >= split]
                ni, mi, ti = st(o[col]); no, mo, to = st(nw[col]); _, _, tc = st(g[ctl])
                rows.append(dict(name=f"M1 {mt} {w} {side} p{band:.2f}-{band + .05:.2f} {seg}", n=n, mean_per10=round(m10, 3), t=round(t, 2),
                                 is_mean=round(mi, 3), is_t=round(ti, 2), oos_mean=round(mo, 3), oos_t=round(to, 2), control_t=round(tc, 2), n_old=ni, n_new=no,
                                 pnl=round(float(np.nansum(g[col])), 2)))
    R = pd.DataFrame(rows)
    if R.empty: out.append("No cell has 30 priced bets yet - this grows every night.")
    else:
        both = R[(R.is_mean > 0) & (R.oos_mean > 0)].sort_values('t', ascending=False)
        out += [f"Cells with 30+ bets: {len(R)}. Profitable on both halves: {len(both)}. (The Verifier gate decides WORKS: n 300+, t 3.5+.)", "",
                "| cell | bets | £ at £2 | £ per £10 | t | older n / £10 | newer n / £10 | control t |", "|---|---|---|---|---|---|---|---|"]
        for r in both.head(25).itertuples():
            out.append(f"| {r.name[3:]} | {r.n} | {r.pnl:+.2f} | {r.mean_per10:+.3f} | {r.t} | {r.n_old} / {r.is_mean:+.3f} | {r.n_new} / {r.oos_mean:+.3f} | {r.control_t} |")
        for r in R.to_dict('records'):
            print("RESULT " + json.dumps({k: (float(v) if isinstance(v, (np.floating, np.integer)) else v) for k, v in r.items()}))
out.append("")
# ---------------- 3. loser review
out += ["## 3. Loser review (what the losers share; the fix is learned on the older half and judged on the newer half)", ""]
def pband(p):
    for hi, lab in ((1.5, '<1.5'), (2, '1.5-2'), (3, '2-3'), (5, '3-5'), (10, '5-10')):
        if p < hi: return lab
    return '10+'
RULES = {
 'bot v2.2 taker': ("""SELECT settled_ts t, mkt, side, price::float8 price, extract(hour from start_ts)::int hr, CASE WHEN mkt='WIN' THEN 'racing' ELSE 'football' END sport,
                       pnl::float8 pnl FROM bookie_paper WHERE version='v2.2' AND status='settled' AND fill_kind='taker' ORDER BY settled_ts""", ['mkt', 'side', 'pband', 'hr', 'sport']),
 'small bites': ("""SELECT exit_min t, cell, mkt, liq, side, entry_px::float8 price, pnl::float8 pnl FROM small_bites_paper WHERE pnl IS NOT NULL ORDER BY exit_min""", ['cell', 'mkt', 'liq', 'side', 'pband']),
 'coherence paper': ("""SELECT placed_ts t, cell, side, price::float8 price, pnl::float8 pnl FROM coherence_paper WHERE pnl IS NOT NULL ORDER BY placed_ts""", ['cell', 'side', 'pband']),
}
try: FILT = json.load(open(f'{ROOT}/machine_filters.json'))
except Exception: FILT = {}
lines = []
for rule, (sql, attrs) in RULES.items():
    try: D = pd.read_sql(sql, con)
    except Exception as e: out.append(f"- {rule}: could not read ({e!r})"[:160]); continue
    if len(D) < 20: out.append(f"- {rule}: {len(D)} settled, review starts at 20."); continue
    D['pband'] = D.price.map(pband); D['t'] = pd.to_datetime(D.t, utc=True); h = len(D) // 2; O = D.iloc[:h]; N = D.iloc[h:]
    out.append(f"- **{rule}**: {len(D)} settled, £{D.pnl.sum():+.2f} (older half £{O.pnl.sum():+.2f}, newer half £{N.pnl.sum():+.2f}).")
    worst = []
    for a in attrs:
        for v, g in D.groupby(a):
            if len(g) >= 5 and g.pnl.sum() < 0: worst.append((g.pnl.sum(), a, v, len(g)))
    for s, a, v, n in sorted(worst)[:3]: out.append(f"  - losers share {a} = {v}: {n} bets, £{s:+.2f}")
    best = None
    for a in attrs:
        for v, g in O.groupby(a):
            if len(g) >= 5 and g.pnl.sum() < 0:
                keep = O.pnl.sum() - g.pnl.sum()
                if best is None or keep > best[0]: best = (keep, a, v)
    if best:
        keep_o, a, v = best; Nk = N[N[a] != v]
        ok = keep_o > 0 and Nk.pnl.sum() > N.pnl.sum() and Nk.pnl.sum() > 0
        out.append(f"  - fix learned on older half: drop {a} = {v} -> older £{O.pnl.sum():+.2f} to £{keep_o:+.2f}; JUDGED on newer half £{N.pnl.sum():+.2f} to £{Nk.pnl.sum():+.2f} -> {'ADOPTED on paper' if ok else 'not adopted'}")
        if ok and rule not in FILT: FILT[rule] = dict(attr=a, value=(v.item() if hasattr(v, 'item') else v), adopted=dt.datetime.utcnow().isoformat()[:16])
    else: out.append("  - no loser group of 5+ in the older half to drop.")
    if rule in FILT:
        f = FILT[rule]; F = D[(D.t >= pd.Timestamp(f['adopted'], tz='UTC')) & (D[f['attr']].astype(str) != str(f['value']))]
        lines.append(dict(label=f"{rule} without {f['attr']}={f['value']} (forward from {f['adopted'][:10]})", pnl=[round(float(x), 4) for x in F.pnl]))
json.dump(FILT, open(f'{ROOT}/machine_filters.json', 'w'), indent=1); json.dump(lines, open(f'{ROOT}/machine_lines.json', 'w'), indent=1)
out += ["", f"Adopted fixes tracked forward on the scoreboard: {len(lines)}."]
open(REP, 'w').write("\n".join(out) + "\n")
subprocess.run("cd /root/pe-queue && git add reports/machine_nightly.md && git commit -qm 'machine nightly' && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q", shell=True)
print("\n".join(out[:6]), file=sys.stderr)
MACHINE
cat > $T/patch_664.py <<'PATCH'
import sys, json, datetime
p = '/root/pe-sports/team/sports_team.py'; s = open(p).read()
anchor = "    add('desk FADE (lay scorer +2m, out +10m)'"
ins = '''    # 664: every live paper runner on the one proof-gate table (v2.2 bot, small bites, coherence real book, v3) + the machine's adopted fixes
    add('bot v2.2 TAKER (blocklist + filters, from 17 Nov)',"select pnl from bookie_paper where version='v2.2' and status='settled' and fill_kind='taker' order by settled_ts")
    add('small bites forward paper (all cells)',"select pnl from small_bites_paper where pnl is not null order by exit_min")
    try:
        for (cl,) in q('local',"select distinct cell from small_bites_paper where pnl is not null order by 1"):
            add(f'  small bites {cl}',f"select pnl from small_bites_paper where pnl is not null and cell='{cl}' order by exit_min")
    except Exception: pass
    add('coherence forward paper, real order book (all cells)',"select pnl from coherence_paper where pnl is not null order by placed_ts")
    add('v3 R1 home LAY 2% vs Pinnacle fair',"select pnl from v3_paper where rule like 'R1%' and pnl is not null order by start_ts")
    add('v3 R2 home BACK 5% vs Pinnacle fair',"select pnl from v3_paper where rule like 'R2%' and pnl is not null order by start_ts")
    try:
        for L in json.load(open(f'{ROOT}/machine_lines.json')):
            pn=[float(x) for x in L['pnl']]; n=len(pn); tot=sum(pn); h=n//2; a=sum(pn[:h]); b=sum(pn[h:])
            gate='PASS' if (n>=100 and tot>0 and a>0 and b>0) else (f'{100-n} more' if n<100 else 'FAIL (a half is negative)')
            rows.append(('machine fix: '+L['label'],n,tot,(tot/(2*n)*100 if n else None),a,b,gate))
    except Exception: pass
'''
old_money = "try: m['paper_month']=float(q('local',\"select coalesce(sum(pnl),0) from bookie_paper where status='settled' and version='v2' and ts>=date_trunc('month',now())\")[0][0])"
new_money = "try: m['paper_month']=float(q('local',\"select (select coalesce(sum(pnl),0) from bookie_paper where status='settled' and version like 'v2%' and ts>=date_trunc('month',now())) + (select coalesce(sum(pnl),0) from small_bites_paper where pnl is not null and created>=date_trunc('month',now())) + (select coalesce(sum(pnl),0) from coherence_paper where pnl is not null and placed_ts>=date_trunc('month',now()))\")[0][0])   # 664: all paper runners"
if '# 664:' in s: print('already patched')
else:
    assert s.count(anchor) == 1, 'anchor'
    s = s.replace(anchor, ins + anchor)
    if old_money in s: s = s.replace(old_money, new_money); print('money patched')
    else: print('MONEY LINE NOT FOUND - left as is')
    open(p, 'w').write(s); print('settled_lines patched')
# register M1 (sports_team is stopped while this runs)
R = '/root/pe-sports/team/hypotheses.json'; reg = json.load(open(R))
for h in reg['hypotheses']:
    if h.get('status') == 'running': h['status'] = 'proposed'; print('reset running ->', h['id'][:50])
if not any(h['id'].startswith('M1 ') for h in reg['hypotheses']):
    tomorrow = (datetime.datetime.utcnow() + datetime.timedelta(days=1)).strftime('%Y-%m-%dT01:30:00')
    reg['hypotheses'].insert(0, {"id": "M1 the machine nightly: settle the recorder, real-price cells, loser review", "script": "/root/pe-sports/team/machine_nightly.py",
        "status": "proposed", "kind": "sweep", "pre_registered_sign": "a cell that beats its price on the older half keeps doing it on the newer half",
        "next_door": "Friday: passing cells go onto paper automatically", "timeout": 5400, "repeat_hours": 24, "not_before": tomorrow, "note": "664: THE machine (Peter 18 Nov: one and only)"})
    print('M1 registered, first loop run', tomorrow)
json.dump(reg, open(R, 'w'), indent=1)
PATCH
{ echo "# 664 — $(date -u '+%F %H:%M') UTC"; echo '```'
python3 -m py_compile $T/machine_nightly.py && echo "machine compiles"
pkill -f '[s]ports_team.py'; sleep 3; echo "team loop stopped: $(pgrep -fc '[s]ports_team.py') left"
cp $T/sports_team.py $T/sports_team.py.bak_664; cp $T/hypotheses.json $T/hypotheses.json.bak_664
python3 $T/patch_664.py
python3 -m py_compile $T/sports_team.py && echo "team loop compiles" || { cp $T/sports_team.py.bak_664 $T/sports_team.py; echo "COMPILE FAILED - restored"; }
echo "== first machine run"
cd $T && timeout 3000 nice -n 10 python3 -I machine_nightly.py > machine_nightly.out 2> machine_nightly.err; echo "exit $?"
echo "RESULT lines: $(grep -c '^RESULT' machine_nightly.out)"; tail -8 machine_nightly.err | cut -c1-250
cat $T/machine_filters.json; echo; python3 -c "import json;print([(l['label'],len(l['pnl'])) for l in json.load(open('$T/machine_lines.json'))])"
M0=$(stat -c %Y $T/scoreboard.md); cd $T && pgrep -f "[s]ports_team.py" >/dev/null || nohup setsid ./run_team.sh >/dev/null 2>&1 < /dev/null & sleep 5; echo "team loop running: $(pgrep -fc '[s]ports_team.py')"
echo "== wait for the running loop to rewrite the scoreboard (max 10 min)"
for i in $(seq 60); do [ $(stat -c %Y $T/scoreboard.md) -gt $M0 ] && break; sleep 10; done
tail -3 $T/team.log | cut -c1-200
sed -n '/PROOF GATE/,/Data health/p' $T/scoreboard.md | cut -c1-200; head -3 $T/scoreboard.md
echo '```'; } > $R 2>&1
cd /root/pe-queue && git add $R reports/machine_nightly.md 2>/dev/null; git commit -qm "664: the one machine" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
