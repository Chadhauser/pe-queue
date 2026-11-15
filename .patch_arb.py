p = '/root/pe-queue/jobs/499_alt_line_arb.sh.wip'
s = open(p).read()
a = s.index("    D=pd.read_sql(f\"SELECT sport,market_id")
b = s.index("con.close()\nV=pd.concat(ALL")
new = '''    # Done in SQL with a temp table on disk: the box had about 1 GB free, and 3M+ rows a day in pandas could threaten the recorders.
    cur.execute("DROP TABLE IF EXISTS tmp_alt")
    cur.execute(f"""CREATE TEMP TABLE tmp_alt AS
      SELECT sport,market_id,market_type,ts,sel_id,back_px,back_sz,lay_px,lay_sz,
             (row_number() OVER f)-1 j, lag(back_px) OVER f bp0, lag(lay_px) OVER f lp0, lag(back_sz) OVER f bs0, lag(lay_sz) OVER f ls0
      FROM ip_tape WHERE ts>=%s AND ts<%s AND sport IN {SPORTS} AND market_type IN ('HANDICAP','COMBINED_TOTAL') AND status='OPEN'
      WINDOW f AS (PARTITION BY market_id,ts,sel_id ORDER BY ctid)""",(d.to_pydatetime(),d2.to_pydatetime()))
    cur.execute("SELECT count(*),count(DISTINCT market_id) FROM tmp_alt"); nr,nm=cur.fetchone()
    if not nr: continue
    cur.execute("""CREATE TEMP TABLE tmp_dir AS SELECT market_id,sel_id,count(*) FILTER (WHERE back_px>bp0) n_up,count(*) FILTER (WHERE back_px<bp0) n_dn,count(*) FILTER (WHERE back_px=bp0) n_eq FROM tmp_alt WHERE bp0 IS NOT NULL AND back_px IS NOT NULL GROUP BY 1,2""")
    cur.execute("SELECT coalesce(sum(greatest(n_up,n_dn)+n_eq),0)::float8/nullif(sum(n_up+n_dn+n_eq),0) FROM tmp_dir"); agree=cur.fetchone()[0]
    V=pd.read_sql("""SELECT w.sport,w.market_id,w.market_type,extract(epoch from w.ts)::float8 t,w.sel_id,w.j,
          CASE WHEN x.n_up>x.n_dn THEN w.bp0 ELSE w.back_px END::float8 a, CASE WHEN x.n_up>x.n_dn THEN w.lay_px ELSE w.lp0 END::float8 b,
          CASE WHEN x.n_up>x.n_dn THEN w.bs0 ELSE w.back_sz END::float8 sa, CASE WHEN x.n_up>x.n_dn THEN w.lay_sz ELSE w.ls0 END::float8 sb
        FROM tmp_alt w JOIN tmp_dir x USING (market_id,sel_id)
        WHERE (x.n_up>x.n_dn AND w.bp0>w.lay_px) OR (x.n_dn>x.n_up AND w.back_px>w.lp0)""",con)
    V=V[(V.a<=50)&(V.b<=50)]
    ST.append(dict(day=str(d.date()),rows=nr,markets=nm,order_agrees=round(agree,4) if agree is not None else None,crossed=len(V)))
    ALL.append(V); print(ST[-1],f"{time.time()-T0:.0f}s",flush=True)
    cur.execute("DROP TABLE tmp_alt; DROP TABLE tmp_dir")
'''
s = s[:a] + new + s[b:]
s = s.replace("(5_000_000_000,5_000_000_000)", "(1_500_000_000,1_500_000_000)")
s = s.replace("cur.execute(\"SET work_mem='128MB'; SET statement_timeout='2400s'\")", "cur.execute(\"SET work_mem='64MB'; SET statement_timeout='2400s'\")")
open(p, 'w').write(s)
print('patched')
