# Builds the one financial league table from every universe's results, picks which passing ways go onto the practice account,
# and writes: league.md (the table), live_rules.json (what the paper executor trades), liquid_symbols.json.
import os, sys, json, hashlib, pandas as pd
S = sys.argv[1] if len(sys.argv) > 1 else '/root/pe-finq/state/league'; R = os.path.join(os.path.dirname(S), 'research')
PAPER_STAKE = 2500.0; MAX_LIVE = 12; MAX_OVERNIGHT = 5
def facts_text(f):
    f = {k: v for k, v in f.items() if k != 'always'}
    return ' and '.join(f"{k} is \"{v}\"" for k, v in f.items()) if f else 'on every one, no condition'
rows = []; tested = {}; passing = {}
def meta(n): return json.load(open(f'{S}/league_{n}.json')) if os.path.exists(f'{S}/league_{n}.json') else dict(tested=0, passing=0, note='not run')
# A: shares and funds
mA = meta('A'); tested['big shares and funds'] = mA['tested']; A = pd.read_csv(f'{S}/league_A.csv') if os.path.exists(f'{S}/league_A.csv') and os.path.getsize(f'{S}/league_A.csv') > 5 else pd.DataFrame()
passing['big shares and funds'] = len(A)
for _, r in A.iterrows():
    f = json.loads(r.facts); usd = r.usd_month * PAPER_STAKE / r.stake
    rows.append(dict(src='A', usd=usd, sentence=f"At {r['at']} New York time, {'buy' if r['do'] == 'BUY' else 'sell short'} any of the 105 big shares and funds where {facts_text(f)}; hold {r['hold']}.",
                     trades_month=r.trades_month, net=r.net_bps, h1=r.half1, h2=r.half2, t=r.t, days=r.days, stake=PAPER_STAKE, spec=dict(at=r['at'], facts=f, do=r['do'], hold=r['hold'])))
# B: small companies (daily data map, already run with the same test)
pB = f'{R}/data_map_small.csv'; B = pd.read_csv(pB) if os.path.exists(pB) else pd.DataFrame(); tested['small companies'] = 4685; passing['small companies'] = len(B)
ON = {'opening gap: gap up 5%+': 'already on paper as the gap fade (sell side)', 'last 20 days: up 25%+ + traded value: $30m+': 'already on paper as the five-day sell rule'}
for _, r in B.iterrows():
    rows.append(dict(src='B', usd=r.gbp_month / 0.77, sentence=f"Small companies, {r['when']}: {'buy' if r['do'] == 'BUY' else 'sell short'} where {r['what'].replace(' + ', ' and ')}; hold {r['hold']}." + (f" ({ON[r['what']]})" if r['what'] in ON and r['do'] == 'SELL SHORT' else ''),
                     trades_month=round(r.per_day * r.days / 1474 * 21, 1), net=r.net_bps, h1=r.half1, h2=r.half2, t=r.t, days=r.days, stake=500.0, spec=None))
# C: crypto, D: currencies and gold
mC = meta('C'); tested['crypto'] = mC['tested']; passing['crypto'] = mC['passing']
mD = meta('D'); tested['currencies and gold'] = mD['tested']; D = pd.read_csv(f'{S}/league_D.csv') if os.path.exists(f'{S}/league_D.csv') and os.path.getsize(f'{S}/league_D.csv') > 5 else pd.DataFrame(); passing['currencies and gold'] = len(D)
for _, r in D.iterrows():
    f = json.loads(r.facts); w = f.pop('which', None)
    rows.append(dict(src='D', usd=r.usd_month, sentence=f"At {r['at']}, {'buy' if r['do'] == 'BUY' else 'sell'} {w or 'any of the five currencies and gold'} when {facts_text(f)}; hold {r['hold']}. (no practice account connected for currencies yet)",
                     trades_month=r.trades_month, net=r.net_bps, h1=r.half1, h2=r.half2, t=r.t, days=r.days, stake=r.stake, spec=None))
T = pd.DataFrame(rows).sort_values('usd', ascending=False).reset_index(drop=True) if rows else pd.DataFrame()
# ---- which shares-and-funds ways go on paper: best per (time, way out), frequent first, never dropping one already live
old = json.load(open(f'{S}/live_rules.json')) if os.path.exists(f'{S}/live_rules.json') else []; live = list(old); have = {(r['at'], r['hold'], r['do']) for r in live}
def rid(sp): return 'L' + hashlib.md5(json.dumps(sp, sort_keys=True).encode()).hexdigest()[:6]
cand = T[(T.src == 'A') & (T.trades_month >= 60)] if len(T) else T
for _, r in cand.iterrows():
    if len(live) >= MAX_LIVE: break
    sp = r.spec; key = (sp['at'], sp['hold'], sp['do']); night = sp['hold'].startswith('overnight') or sp['hold'].startswith('to the next day')
    if key in have or any(x['at'] == sp['at'] and x['do'] != sp['do'] for x in live): continue
    if night and sum(1 for x in live if x['hold'].startswith('overnight') or x['hold'].startswith('to the next day')) >= MAX_OVERNIGHT: continue
    if sum(1 for x in live if x['at'] == sp['at']) >= 2: continue
    live.append(dict(id=rid(sp), sentence=r.sentence, stake=PAPER_STAKE, maxn=10, test=dict(net_bps=r.net, half1=r.h1, half2=r.h2, t=r.t, trades_month=r.trades_month, usd_month=round(r.usd)), **sp)); have.add(key)
json.dump(live, open(f'{S}/live_rules.json', 'w'), indent=1)
json.dump(sorted(s for s in os.listdir('/root/pe-data/alpaca') if 'USD' not in s), open(f'{S}/liquid_symbols.json', 'w'))
liveids = {json.dumps(dict(at=x['at'], facts=x['facts'], do=x['do'], hold=x['hold']), sort_keys=True) for x in live}
tt = sum(tested.values()); tp = sum(passing.values())
L = ['# Financial league table', '', f'Ways of earning tested: {tt:,} | passing: {tp:,} | on the practice account from this table: {len(live)} (plus the 8 earlier rules)', '',
     'One test for all: real prices, entry two minutes after the signal, real costs, profit after costs in both halves of history, 200+ separate days.', '',
     '| universe | ways tested | passing |', '|---|---|---|'] + [f'| {k} | {tested[k]:,} | {passing[k]:,} |' for k in tested] + ['',
     'Stake per trade: big shares and funds $2,500 (up to 10 a day per way); small companies $500 (up to 30 a day); currencies $20,000.', '',
     '| rank | the way of earning, in one sentence | $ a month | trades a month | kept per trade after costs | first half / second half | on paper |', '|---|---|---|---|---|---|---|']
for i, r in T.head(60).iterrows():
    onp = 'yes' if (r.spec and json.dumps(r.spec, sort_keys=True) in liveids) else ('yes (earlier rule)' if 'already on paper' in r.sentence else 'no')
    L.append(f"| {i + 1} | {r.sentence} | {r.usd:,.0f} | {r.trades_month:.0f} | {r.net / 100:.2f}% | {r.h1 / 100:.2f}% / {r.h2 / 100:.2f}% | {onp} |")
open(f'{S}/league.md', 'w').write('\n'.join(L) + '\n'); print('\n'.join(L[:70])); print('\nLIVE RULES'); [print(' ', x['id'], x['sentence'], x['test']) for x in live]
