J = '/root/pe-queue/jobs/499_jump_up_delay_touch.sh.wip'
s = open(J).read()
subs = [
    ("s.pt<=o.off+interval '860 seconds' ORDER BY s.market_id,s.sel_id,s.pt", "s.pt<=o.off+interval '320 seconds' ORDER BY s.market_id,s.sel_id,s.pt"),
    ("rows=[]\nfor m,(g,s,i,pt,pl) in best.items():\n",
     "cn=psycopg2.connect(creds.pg_local()); cu=cn.cursor(); cu.execute(\"SET work_mem='64MB'; SET statement_timeout='2400s'\"); LT=defaultdict(list)\n"
     "for m in best:\n"
     "    s_=best[m][1]; cu.execute(\"SELECT extract(epoch from pt)::float8,back_px::float8,lay_px::float8 FROM stream_ticks WHERE sport='football' AND mkt='MO' AND inplay AND status='OPEN' AND market_id=%s AND sel_id=%s AND pt>=to_timestamp(%s)+interval '290 seconds' AND pt<=to_timestamp(%s)+interval '670 seconds' ORDER BY pt\",(m,s_,TK[(m,s_)][best[m][2]][0],TK[(m,s_)][best[m][2]][0]))\n"
     "    LT[(m,s_)]=[(t_,b_,l_,None,None) for t_,b_,l_ in cu.fetchall()]\n"
     "cn.close(); print('later ticks',sum(len(v) for v in LT.values()),f'{time.time()-T0:.0f}s',flush=True)\n"
     "rows=[]\nfor m,(g,s,i,pt,pl) in best.items():\n"),
    ("        x=touch_at(tk,t,de,span=60)\n", "        x=touch_at(LT[(m,s)],t,de,span=60)\n"),
    ("Pilot, cannot reach the bar.", "Pilot, cannot reach the bar. FIX 2026-11-07, first run hit the 2 GB cap loading 860 s of every runner: later ticks are now read for signal runners only; no rule changed."),
]
for a, b in subs:
    assert s.count(a) == 1, a
    s = s.replace(a, b)
open(J, 'w').write(s)
print('ok')
