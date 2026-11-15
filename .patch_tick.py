p = '/root/pe-queue/jobs/499_tick_touch_level.sh.wip'
s = open(p).read()
# helpers and their checks go; the logic moves to SQL and is checked on a small known table instead
a = s.index('def touch_index(bp,q):')
b = s.index('def bk(p,w):')
s = s[:a] + '''SQL_TOUCH="""WITH f AS (SELECT DISTINCT ON (market_id,sel_id) market_id,sel_id,back_px st FROM {tab} WHERE back_px IS NOT NULL ORDER BY market_id,sel_id,t),
  h AS (SELECT market_id,sel_id,min(t) tt FROM {tab} WHERE back_px<=%(q)s GROUP BY 1,2)
SELECT h.market_id,h.sel_id,f.st,b.t,b.back_px,l.t,l.lay_px FROM h JOIN f USING (market_id,sel_id)
  LEFT JOIN LATERAL (SELECT x.t,x.back_px FROM {tab} x WHERE x.market_id=h.market_id AND x.sel_id=h.sel_id AND x.t>=h.tt+%(d)s AND x.back_px IS NOT NULL ORDER BY x.t LIMIT 1) b ON true
  LEFT JOIN LATERAL (SELECT x.t,x.lay_px FROM {tab} x WHERE x.market_id=h.market_id AND x.sel_id=h.sel_id AND x.t>=h.tt+%(d)s AND x.lay_px IS NOT NULL ORDER BY x.t LIMIT 1) l ON true
WHERE f.st>%(q)s"""
''' + s[b:]
a = s.index("n_=np.nan\n_t=np.array")
b = s.index("assert abs(bk(2.0,True)")
s = s[:a] + s[b:]
s = s.replace('''cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
cur.execute("""SELECT market_id,extract(epoch from pt)::float8,sel_id,back_px::float8,lay_px::float8 FROM stream_ticks WHERE sport='racing' AND mkt='WIN' AND inplay AND status='OPEN' AND pt IS NOT NULL""")
A=pd.DataFrame(cur.fetchall(),columns='market_id t sel bp lp'.split()); con.close(); print(f"ticks {len(A):,}, markets {A.market_id.nunique()}, {pd.to_datetime(A.t.min(),unit='s')} to {pd.to_datetime(A.t.max(),unit='s')}, {time.time()-T0:.0f}s",flush=True)
''', '''cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
# In SQL on a temp table: the first run hit this job's 1.5 GB cap fetching the ticks, on a box with about 1 GB free. Checked first on a small table worked by hand.
cur.execute("CREATE TEMP TABLE tmp_k (market_id text,sel_id bigint,t float8,back_px float8,lay_px float8)")
_r=[('m',1,0.,3.0,3.1),('m',1,.5,2.5,2.6),('m',1,1.,2.0,2.1),('m',1,2.,1.9,None),('m',1,4.,None,1.9),('m',1,6.,1.7,1.8),('m',2,0.,1.5,1.6),('m',2,5.,1.4,1.5)]
cur.executemany("INSERT INTO tmp_k VALUES (%s,%s,%s,%s,%s)",_r)
def kq(q,d):
    cur.execute(SQL_TOUCH.format(tab='tmp_k'),dict(q=q,d=d)); return cur.fetchall()
assert kq(2.0,1.0)==[('m',1,3.0,2.0,1.9,4.0,1.9)]      # touched at t=1; back at t=2, 1.9; t=2 has no lay, so lay at t=4; runner 2 started under Q
assert kq(2.0,3.0)==[('m',1,3.0,6.0,1.7,4.0,1.9)]      # at least 3 s on: t=4 has no back, so back at t=6
assert kq(1.0,1.0)==[] and kq(3.0,1.0)==[]              # never touched; already there at the first tick
assert kq(2.0,9.0)==[('m',1,3.0,None,None,None,None)]   # no later tick
cur.execute("DROP TABLE tmp_k"); print("sql checks: OK",flush=True)
cur.execute("""CREATE TEMP TABLE tmp_t AS SELECT market_id,sel_id,extract(epoch from pt)::float8 t,back_px::float8 back_px,lay_px::float8 lay_px FROM stream_ticks WHERE sport='racing' AND mkt='WIN' AND inplay AND status='OPEN' AND pt IS NOT NULL""")
cur.execute("CREATE INDEX ON tmp_t (market_id,sel_id,t)"); cur.execute("ANALYZE tmp_t")
cur.execute("SELECT count(*),count(DISTINCT market_id),min(t),max(t) FROM tmp_t"); nt,nm,t_lo,t_hi=cur.fetchone(); print(f"ticks {nt:,}, markets {nm}, {pd.to_datetime(t_lo,unit='s')} to {pd.to_datetime(t_hi,unit='s')}, {time.time()-T0:.0f}s",flush=True)
cur.execute("SELECT DISTINCT market_id FROM tmp_t"); MK=[r[0] for r in cur.fetchall()]
''')
s = s.replace("(list(A.market_id.unique()),))", "(MK,))")
s = s.replace('no result {A.market_id.nunique()-len(W)}', 'no result {nm-len(W)}')
a = s.index("A=A[A.market_id.isin(truth)].sort_values(")
b = s.index("R=pd.DataFrame(rows,columns='m t q d side px won v mv'.split())")
s = s[:a] + '''cur.execute("SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY g),percentile_cont(0.9) WITHIN GROUP (ORDER BY g) FROM (SELECT t-lag(t) OVER (PARTITION BY market_id,sel_id ORDER BY t) g FROM tmp_t) z WHERE g IS NOT NULL"); print("seconds between ticks of one runner, median and p90",[round(x,2) for x in cur.fetchone()],flush=True)
rows=[]; nof=0
for q in (3,2,1.5,1.3,1.2,1.1):
    for d in (1.0,3.0):
        cur.execute(SQL_TOUCH.format(tab='tmp_t'),dict(q=q,d=d)); got=cur.fetchall(); print(f"  q {q} d {d}: touched {len(got)} | {time.time()-T0:.0f}s",flush=True)
        for m,sel,st,tb,pb,tl,pl in got:
            if m not in truth: continue
            won=truth[m]==int(sel); mv=st>=1.5*q
            if pb is None and pl is None: nof+=1
            if pb is not None:
                v=bk(pb,won)
                if v==v: rows.append((m,tb,q,d,'back',pb,won,v,mv))
            if pl is not None: rows.append((m,tl,q,d,'lay',pl,won,ly(pl,won),mv))
con.close()
''' + s[b:]
open(p, 'w').write(s)
print('ok')
