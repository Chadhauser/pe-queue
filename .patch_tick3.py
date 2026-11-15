p = '/root/pe-queue/jobs/499_tick_touch_level.sh.wip'
s = open(p).read()
for old, new in (
    ("rows.append((m,tb,q,d,'back',pb,won,v,mv))", "rows.append((m,tb,q,d,'back',pb,won,v,mv,int(sel)))"),
    ("rows.append((m,tl,q,d,'lay',pl,won,ly(pl,won),mv))", "rows.append((m,tl,q,d,'lay',pl,won,ly(pl,won),mv,int(sel)))"),
    ("columns='m t q d side px won v mv'.split())", "columns='m t q d side px won v mv sel'.split())"),
):
    assert old in s
    s = s.replace(old, new)
tail = '''# ITEM 382: stream_ticks rolls, so every run saves its entries to a local table, one row per race, runner, level, delay and side, and pools them. Only rows after the rule date are unseen. Re-running adds no duplicates.
from psycopg2.extras import execute_values
cur.execute("CREATE TABLE IF NOT EXISTS finder_touch_entries (market_id text,sel bigint,q float8,d float8,side text,t float8,px float8,won boolean,v float8,mv boolean,PRIMARY KEY (market_id,sel,q,d,side))")
execute_values(cur,"INSERT INTO finder_touch_entries VALUES %s ON CONFLICT DO NOTHING",[(r.m,int(r.sel),float(r.q),float(r.d),r.side,float(r.t),float(r.px),bool(r.won),float(r.v),bool(r.mv)) for r in R.itertuples()])
RULE=pd.Timestamp('2026-11-07 09:00',tz='UTC').timestamp()
P_=pd.read_sql("SELECT market_id m,q,d,side,t,px,won,v,mv FROM finder_touch_entries",con)
print(f"\\n== ITEM 382: saved entries {len(P_):,}, races {P_.m.nunique()}, unseen races since the rule {P_[P_.t>=RULE].m.nunique()}",flush=True)
pk=[]
for (q,d) in ((1.1,1.0),(1.2,1.0),(1.1,3.0),(1.2,3.0)):
    x=P_[(P_.q==q)&(P_.d==d)&(P_.side=='back')]
    for lab,y in (('ALL',x),('UNSEEN',x[x.t>=RULE])):
        if len(y)>=2: pk.append(tab(y,q=q,delay=d,side='back',start=lab))
print(pd.DataFrame(pk).round(3).to_string(index=False) if pk else "none yet",flush=True)
'''
i = s.index('# ITEM 381: can the two best lines')
s = s[:i] + tail + s[i:]
open(p, 'w').write(s)
print('ok')
