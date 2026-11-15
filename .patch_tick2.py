p = '/root/pe-queue/jobs/499_tick_touch_level.sh.wip'
s = open(p).read()
assert "con.close()\nR=pd.DataFrame(rows" in s
s = s.replace("con.close()\nR=pd.DataFrame(rows", "R=pd.DataFrame(rows")
old = "lay_px::float8 lay_px FROM stream_ticks WHERE sport='racing'"
assert old in s
s = s.replace(old, "lay_px::float8 lay_px,back_sz::float8 back_sz FROM stream_ticks WHERE sport='racing'")
tail = '''# ITEM 381: can the two best lines be sized, and who lost. No new line, no new price rule: same entries as item 380, delay 1 s.
print("\\n== ITEM 381: the back at Q 1.1 and 1.2, delay 1 s: size on show at the fill, time left, losers",flush=True)
SZ="""WITH f AS (SELECT DISTINCT ON (market_id,sel_id) market_id,sel_id,back_px st FROM tmp_t WHERE back_px IS NOT NULL ORDER BY market_id,sel_id,t),
  h AS (SELECT market_id,sel_id,min(t) tt FROM tmp_t WHERE back_px<=%(q)s GROUP BY 1,2), e AS (SELECT market_id,max(t) te FROM tmp_t GROUP BY 1)
SELECT h.market_id,h.sel_id,f.st,h.tt,b.t,b.back_px,b.back_sz,e.te FROM h JOIN f USING (market_id,sel_id) JOIN e USING (market_id)
  JOIN LATERAL (SELECT x.t,x.back_px,x.back_sz FROM tmp_t x WHERE x.market_id=h.market_id AND x.sel_id=h.sel_id AND x.t>=h.tt+1.0 AND x.back_px IS NOT NULL ORDER BY x.t LIMIT 1) b ON true
WHERE f.st>%(q)s"""
for q in (1.1,1.2):
    cur.execute(SZ,dict(q=q)); E=pd.DataFrame(cur.fetchall(),columns='m sel st tt tb pb sz te'.split()); E=E[E.m.isin(truth)].copy(); E['won']=[truth[m]==int(x) for m,x in zip(E.m,E.sel)]
    E['v']=[bk(p,w) for p,w in zip(E.pb,E.won)]; E=E[E.v==E.v]; E['left']=E.te-E.tb
    print(f"  Q {q}: n {len(E)}, won {E.won.mean():.3f}, median fill {E.pb.median():.2f}; size on show: known {E.sz.notna().mean():.2f}, median £{E.sz.median():.0f}, share >= £10 {(E.sz>=10).mean():.2f}, >= £50 {(E.sz>=50).mean():.2f}, >= £200 {(E.sz>=200).mean():.2f}; seconds to the race's last tick, median {E.left.median():.0f}; start price median {E.st.median():.1f}",flush=True)
    print("  losers:",E[~E.won][['st','pb','left','sz']].round(1).to_dict('records'),flush=True)
    v10=np.minimum(E.sz.fillna(0),10)/10*E.v; print(f"  per £10 taking the lesser of £10 and the size on show, mean {v10.mean():+.3f}; up to £100 at the size on show, sum over the sample {(np.minimum(E.sz.fillna(0),100)/10*E.v).sum():+.0f}",flush=True)
con.close()
'''
i = s.index('print(f"total {time.time()-T0:.0f}s")\nPY')
s = s[:i] + tail + s[i:]
open(p, 'w').write(s)
print('ok')
