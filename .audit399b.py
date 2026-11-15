import sys,psycopg2,pandas as pd,numpy as np,time
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_official import secs,bk,ly
pd.set_option('display.width',240); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',80)
rc=psycopg2.connect(creds.pg_railway(),sslmode='require'); rc.autocommit=True; k=rc.cursor(); k.execute("SET statement_timeout='280s'")
k.execute("SELECT column_name FROM information_schema.columns WHERE table_name='stream_ticks' ORDER BY ordinal_position"); print('stream_ticks',[a[0] for a in k.fetchall()])
k.execute("SELECT column_name FROM information_schema.columns WHERE table_name='liq_sample' ORDER BY ordinal_position"); print('liq_sample',[a[0] for a in k.fetchall()])
L=psycopg2.connect(creds.pg_local()); c=L.cursor()
c.execute("SELECT column_name FROM information_schema.columns WHERE table_name='finder_touch_entries' ORDER BY ordinal_position"); print('finder_touch_entries',[a[0] for a in c.fetchall()])
# 1. which reopens are rewinds, by sport, on ip_tape's window. Only ip_tape rows written while OPEN or SUSPENDED before the reopen count as the high-water mark.
for sport,mt in (('horse_racing','WIN'),('tennis','MATCH_ODDS'),('cricket','MATCH_ODDS'),('basketball','MATCH_ODDS')):
    A=pd.read_sql("SELECT DISTINCT ON (market_id,ts) ts,market_id m,total_matched::float8 tm FROM ip_reopen WHERE sport=%s AND market_type=%s AND ts>=now()-interval '5.5 days' ORDER BY market_id,ts",rc,params=(sport,mt))
    if not len(A): print(sport,'no rows'); continue
    T=pd.read_sql("SELECT market_id m,ts,total_matched::float8 tm FROM ip_tape WHERE sport=%s AND market_type=%s AND market_id=ANY(%s) AND total_matched IS NOT NULL",rc,params=(sport,mt,list(A.m.unique())))
    T=T.drop_duplicates(['m','ts']); T['t']=secs(T.ts); A['t']=secs(A.ts); G={k_:v.sort_values('t') for k_,v in T.groupby('m',sort=False)}; o=[]
    for r in A.itertuples():
        y=G.get(r.m)
        if y is None: o.append(np.nan); continue
        b=y[y.t<r.t-0.5]
        o.append(np.nan if not len(b) else r.tm/b.tm.max()-1)
    A['d']=o; z=A.d.dropna(); print(f"{sport}: reopens {len(A)}, with a prior tape row {len(z)}, total matched below the earlier high {float((z<-0.001).mean()):.3f}, median change {float(z.median()):.4f}, below by over 1% {float((z<-0.01).mean()):.3f}")
    A[['m','t','d']].to_pickle(f'/tmp/rw_{sport}.pkl')
# 2. racing: read item 396 and 399's lines on reopens that are NOT rewinds, window only
A=pd.read_sql("SELECT ts,market_id m,sel_id,pre_ltp::float8 pre,post_back_px::float8 b,post_lay_px::float8 l FROM ip_reopen WHERE sport='horse_racing' AND market_type='WIN' AND ts>=now()-interval '5.5 days'",rc)
W=pd.read_sql("SELECT market_id m,selection_id sel_id,won FROM racing_results WHERE market_id=ANY(%s)",rc,params=(list(A.m.unique()),))
A['t']=secs(A.ts); RW=pd.read_pickle('/tmp/rw_horse_racing.pkl'); A=A.merge(RW,on=['m','t']).merge(W,on=['m','sel_id'])
A=A[(A.l<=A.b*1.05)&(A.b>1)&A.pre.notna()&(A.pre>1)&A.won.notna()&A.d.notna()]; A['mv']=0.5*(A.b+A.l)/A.pre-1; A['won']=A.won.astype(bool); A['rw']=A.d<-0.001
A['vb']=[bk(b,w) for b,w in zip(A.b,A.won)]
for nm,x in (('REWIND',A[A.rw]),('NOT REWIND',A[~A.rw])):
    print(nm,"rows",len(x),"races",x.m.nunique())
    for g,y in (('moved up 15%',x[x.mv>=.15]),('moved down 15%',x[x.mv<=-.15]),('flat 5%',x[x.mv.abs()<.05])):
        if len(y): print(f"   {g}: n {len(y)} back per10 {y.vb.astype(float).mean():.3f} won {y.won.mean():.3f} implied {(1/y.b).mean():.3f}")
# 3. does the same rewind reach other recorders? total_matched falling on the 30 s racing log, and on liq_sample
c.execute("""SELECT count(*),sum(CASE WHEN d<-0.001 THEN 1 ELSE 0 END),sum(CASE WHEN d<-0.001 AND inplay THEN 1 ELSE 0 END),sum(CASE WHEN inplay THEN 1 ELSE 0 END) FROM (SELECT inplay,total_matched/NULLIF(max(total_matched) OVER (PARTITION BY market_id ORDER BY captured_at ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),0)-1 d FROM (SELECT DISTINCT ON (market_id,captured_at) market_id,captured_at,inplay,total_matched::float8 total_matched FROM finder_rlog WHERE captured_at>='2026-11-01' ORDER BY market_id,captured_at) q) x"""); print("finder_rlog 1 Nov on, rows, falling, falling in play, in play:",c.fetchone())
c.execute("SELECT count(*) FROM finder_touch_entries"); print("finder_touch_entries rows",c.fetchone())
