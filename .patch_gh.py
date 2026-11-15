p = '/root/pe-queue/jobs/499_greyhound_sex_sire.sh.wip'
s = open(p).read()
a = s.index('F=[]\nfor a,b in')
b = s.index("if len(use)<1000:")
new = '''# CORRECTED before any line was used: the first run built the race from runners with a print in the T-20 to T-5 window, so a race survived only if its winner had printed there, and every band read about +£2 back at t 8 with the control the same. The market's runners now come from every pre-off print; the T-5 price joins on afterwards.
F=[];W_=[]
for a,b in (('2026-05-01','2026-06-01'),('2026-06-01','2026-07-01'),('2026-07-01','2026-08-01'),('2026-08-01','2026-09-01'),('2026-09-01','2026-10-01'),('2026-10-01','2026-11-05')):
    cur.execute("""SELECT DISTINCT market_id,event_name,market_time,sel FROM bf_hist_other WHERE sport='Greyhound Racing' AND market_type='WIN' AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND market_time>=%s AND market_time<%s""",(a,b))
    x=pd.DataFrame(cur.fetchall(),columns='market_id event_name market_time sel'.split()); F.append(x)
    cur.execute("""SELECT DISTINCT ON (market_id,sel) market_id,sel,ltp::float8 FROM bf_hist_other WHERE sport='Greyhound Racing' AND market_type='WIN' AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND market_time>=%s AND market_time<%s AND ts>=market_time-interval '20 minutes' AND ts<=market_time-interval '5 minutes' ORDER BY market_id,sel,ts DESC""",(a,b))
    y=pd.DataFrame(cur.fetchall(),columns='market_id sel ltp'.split()); W_.append(y); print(f"  {a} runners {len(x)}, priced at T-5 {len(y)} | {time.time()-T0:.0f}s",flush=True)
con.close(); P=pd.concat(F,ignore_index=True); W_=pd.concat(W_,ignore_index=True); del F; P['mt']=pd.to_datetime(P.market_time,utc=True)
P['tk']=P.event_name.map(track); P['d']=P.sel.map(dog); P['date']=P.mt.dt.tz_convert('Europe/London').dt.date
J=P.merge(C[['date','tk','d','race_id','finish_position','sex','colour','sire','dam','reserve']],on=['date','tk','d'],how='left').merge(W_,on=['market_id','sel'],how='left')
hit=J.dropna(subset=['race_id']); pr=hit.groupby('market_id').race_id.nunique(); hit=hit[hit.market_id.isin(pr[pr==1].index)]
wn=hit[hit.finish_position==1].groupby('market_id').d.nunique(); one=set(wn[wn==1].index); miss=set(J[J.market_id.isin(one)&J.race_id.isna()].market_id.unique()); use=one-miss
print(f"tape markets {P.market_id.nunique()}; one winner {len(one)}; dead heats {int((wn>1).sum())}; tape runner off the card {len(miss)}; scored races {len(use)}; item 233 read about 4,500",flush=True)
'''
s = s[:a] + new + s[b:]
s = s.replace("R=J[J.market_id.isin(use)].copy(); R['won']=R.finish_position==1; R['p']=R.ltp; R['bd']=R.p.map(band); R=R[R.bd.notna()].copy()",
              "R=J[J.market_id.isin(use)].copy(); R['won']=R.finish_position==1; nop=int(R.ltp.isna().sum()); R=R[R.ltp.notna()].copy(); R['p']=R.ltp; R['bd']=R.p.map(band); R=R[R.bd.notna()].copy(); print('runners with no T-5 print',nop,flush=True)")
assert "nop=int(R.ltp" in s
open(p, 'w').write(s)
print('ok')
