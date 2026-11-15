import re, sys, datetime as d, psycopg2, pandas as pd
from dateutil.easter import easter
sys.path.insert(0, '/root/pe-queue/runner'); import creds
con = psycopg2.connect(creds.pg_local()); cur = con.cursor()
cur.execute("SELECT event_name,count(DISTINCT market_id) FROM bf_hist_other WHERE sport='Cricket' AND market_type='MATCH_ODDS' AND market_time>='2024-09-01' GROUP BY 1")
E = cur.fetchall()
hit = re.compile(r'(^|\s)(W|Women)(\s|$)')
miss = [(e, n) for e, n in E if re.search(r'women|\(w\)|\bladies\b', e, re.I) and not hit.search(e)]
print('women by job regex', sum(n for e, n in E if hit.search(e)), 'other women-looking names missed', sum(n for e, n in miss), miss[:10])
false = [e for e, n in E if hit.search(e) and not re.search(r'\bW\b.*\bW\b|women', e, re.I)]
print('one-sided W names', len(false), false[:10])
cur.execute("SELECT min(market_time),max(market_time),count(DISTINCT market_id) FROM bf_hist_other WHERE sport='Cricket' AND market_type='MATCH_ODDS'")
print(cur.fetchall())
cur.execute("SELECT status,count(*) FROM bf_hist_months WHERE sport='Soccer' GROUP BY 1")
print('soccer months', cur.fetchall())
W = pd.read_sql("SELECT DISTINCT country,event_id,event_dt,menu_hint FROM racing_bsp WHERE market='win' AND bsp>1", con)
con.close()
FEST = [('Cheltenham', (3, 10), (3, 20)), ('Aintree', (4, 1), (4, 15)), ('Punchestown', (4, 20), (5, 10)), ('Epsom', (6, 1), (6, 10)), ('Ascot', (6, 14), (6, 25)), ('Goodwood', (7, 25), (8, 6)), ('Galway', (7, 25), (8, 6)), ('York', (8, 15), (8, 30)), ('Doncaster', (9, 8), (9, 16)), ('Kempton', (12, 26), (12, 27)), ('Leopardstown', (12, 26), (12, 29))]
def nm(y, m, n):
    x = d.date(y, m, 1); x += d.timedelta(days=(7 - x.weekday()) % 7); return x + d.timedelta(days=7 * (n - 1))
def lm(y, m):
    x = d.date(y, m + 1, 1) - d.timedelta(days=1); return x - d.timedelta(days=x.weekday())
def hol(y, c):
    e = easter(y); h = {d.date(y, 12, 26), d.date(y, 12, 27), d.date(y, 1, 1), e - d.timedelta(days=2), e + d.timedelta(days=1), nm(y, 5, 1), lm(y, 5)}
    h |= {nm(y, 8, 1), nm(y, 6, 1), lm(y, 10)} if c == 'ire' else {lm(y, 8)}
    return h
W['day'] = pd.to_datetime(W.event_dt, utc=True).dt.tz_convert('Europe/London').dt.date
H = W[[x in hol(x.year, c) for x, c in zip(W.day, W.country)]]
def fest(h, x):
    s = re.sub(r'^[A-Z]+\s*/\s*', '', str(h)); md = (x.month, x.day)
    return any(s.startswith(k) and a <= md <= b for k, a, b in FEST)
F = H[[fest(a, b) for a, b in zip(H.menu_hint, H.day)]]
print('holiday races', len(H), 'days', H.day.nunique(), 'in festival list', len(F), F.menu_hint.value_counts().head(6).to_dict())
print('by year', pd.Series([x.year for x in H.day]).value_counts().sort_index().to_dict())
