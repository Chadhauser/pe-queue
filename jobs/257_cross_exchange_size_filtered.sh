#!/bin/bash
# 257: CROSS-EXCHANGE, SIZE-FILTERED (Monday list). Run 4 (242) found Matchbook laying below Betfair's back 32% of samples but the
# "arbs" were £3 phantoms. This test only counts a cross-book edge when BOTH sides show >= £20 at the price within 60 s of each
# other, Betfair side from the 1-minute recorder (football MO), other side from xx_tape, Betfair 2% commission, other 2%.
# Two directions: back Betfair / lay elsewhere, and lay Betfair / back elsewhere. Output: count, mean edge, hours of day, leagues.
set -e
python3 - <<'PY'
import sys,psycopg2,pandas as pd,re,unicodedata; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require')
xx=pd.read_sql("""SELECT ts, exchange, event_name, sel_name, back_px::float back_px, back_sz::float back_sz, lay_px::float lay_px, lay_sz::float lay_sz
                  FROM xx_tape WHERE sport ILIKE '%%soccer%%' OR sport ILIKE '%%football%%' OR market_name ILIKE '%%match odds%%' OR market_name ILIKE '%%winner%%'
                  """ + " AND ts>now()-interval '3 days' AND inplay AND back_px IS NOT NULL AND lay_px IS NOT NULL",con)
bf=pd.read_sql("""SELECT ts, event_name, competition, sel, back_px::float back_px, back_sz::float back_sz, lay_px::float lay_px, lay_sz::float lay_sz
                  FROM liq_sample WHERE mkt='MO' AND ts>now()-interval '3 days' AND back_px IS NOT NULL AND lay_px IS NOT NULL AND lay_px<=back_px*1.2""",con)
print("xx rows",len(xx),"betfair rows",len(bf))
def norm(s): return re.sub(r'[^a-z0-9 ]','',unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower().replace(' vs ',' v ')).strip()
xx['ev']=xx.event_name.map(norm); bf['ev']=bf.event_name.map(norm)
def side(row):
    ev=row['ev']; n=norm(row['sel_name'])
    if 'draw' in n: return 'DRAW'
    parts=ev.split(' v ')
    if len(parts)!=2: return None
    if n==parts[0] or n in parts[0] or parts[0] in n: return 'HOME'
    if n==parts[1] or n in parts[1] or parts[1] in n: return 'AWAY'
    return None
xx['sel']=xx.apply(side,axis=1); xx=xx.dropna(subset=['sel'])
common=set(xx.ev)&set(bf.ev); print("common in-play games (3 days):",len(common))
xx=xx[xx.ev.isin(common)].sort_values('ts'); bf=bf[bf.ev.isin(common)].sort_values('ts')
if xx.empty or bf.empty: print("no overlap"); sys.exit(0)
m=pd.merge_asof(bf,xx,on='ts',by=['ev','sel'],tolerance=pd.Timedelta('60s'),direction='nearest',suffixes=('_bf','_xx')).dropna(subset=['back_px_xx'])
print("matched samples (same game, same runner, within 60 s):",len(m))
C=0.02
# A: back on Betfair at back_px_bf, lay elsewhere at lay_px_xx. Profit per £10 back if runner wins: 10*(bf-1)*(1-C) - 10*(lay-1)... use equal-stake arb margin:
m['edge_A']=(m.back_px_bf*(1-C))/(m.lay_px_xx*(1+C)) - 1       # >0 means back Betfair / lay other locks profit
m['edge_B']=(m.back_px_xx*(1-C))/(m.lay_px_bf*(1+C)) - 1       # >0 means back other / lay Betfair
big=m[(m.back_sz_bf>=20)&(m.lay_sz_xx>=20)]; bigB=m[(m.back_sz_xx>=20)&(m.lay_sz_bf>=20)]
for name,d,col in [('A back Betfair / lay other',big,'edge_A'),('B back other / lay Betfair',bigB,'edge_B')]:
    a=d[d[col]>0]; print(f"\n{name}: size>=£20 both sides samples {len(d)} | positive-edge samples {len(a)} ({100*len(a)/max(len(d),1):.1f}%) | mean edge when positive {100*a[col].mean():.2f}% | median size £{a[['back_sz_bf','lay_sz_xx'] if col=='edge_A' else ['back_sz_xx','lay_sz_bf']].min(axis=1).median() if len(a) else 0:.0f}")
    if len(a):
        a=a.assign(h=a.ts.dt.hour); print(" by hour:",a.groupby('h')[col].agg(['size']).T.to_dict('records')[0])
        print(" by exchange:",a.groupby('exchange').size().to_dict()); print(" top leagues:",a.groupby('competition').size().sort_values(ascending=False).head(6).to_dict())
        print(" distinct games with an edge:",a.ev.nunique(), "| samples per game median", a.groupby('ev').size().median())
        print(" persistence: share of edge samples where the SAME runner still shows edge 2 samples later:",
              round(a.sort_values('ts').groupby(['ev','sel'])[col].apply(lambda s:(s.shift(-2)>0).mean()).mean(),2))
PY
