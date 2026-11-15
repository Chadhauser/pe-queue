import sys,psycopg2,pandas as pd,numpy as np,time
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_official import secs
pd.set_option('display.width',240); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',120)
rc=psycopg2.connect(creds.pg_railway(),sslmode='require'); rc.autocommit=True; k=rc.cursor(); k.execute("SET statement_timeout='200s'")
k.execute("SELECT column_name,data_type FROM information_schema.columns WHERE table_name='stream_ticks' ORDER BY ordinal_position"); print('stream_ticks',[f"{a}:{b[:5]}" for a,b in k.fetchall()])
k.execute("SELECT column_name FROM information_schema.columns WHERE table_name='ip_tape' ORDER BY ordinal_position"); print('ip_tape',[a[0] for a in k.fetchall()])
A=pd.read_sql("SELECT ts,market_id m,event_name ev,sel_id sel,sel_name nm,pre_ltp::float8 pre,post_ltp::float8 pl,post_back_px::float8 b,post_lay_px::float8 l,total_matched::float8 tm FROM ip_reopen WHERE sport='horse_racing' AND market_type='WIN' AND ts>=now()-interval '5.5 days' AND pre_ltp<=1.2 AND post_lay_px<=post_back_px*1.05 AND (post_back_px+post_lay_px)/2>=pre_ltp*1.15 ORDER BY ts",rc)
A['t']=secs(A.ts); print("WINNER-type rows in the window",len(A),"post_ltp v back median",round(float((A.pl/A.b).median()),3),"share post_ltp within 2% of back",round(float(((A.pl/A.b-1).abs()<.02).mean()),3))
T=pd.read_sql("SELECT ts,market_id m,sel_id sel,status,ltp::float8 ltp,back_px::float8 bp,back_sz::float8 bs,lay_px::float8 lp,lay_sz::float8 ls,total_matched::float8 tm FROM ip_tape WHERE market_id=ANY(%s) AND sel_id=ANY(%s) ORDER BY ts",rc,params=(list(A.m.unique()),[int(x) for x in A.sel.unique()]))
T['t']=secs(T.ts); o=[]
for r in A.itertuples():
    y=T[(T.m==r.m)&(T.sel==r.sel)]
    b4=y[(y.t<r.t-0.5)&(y.t>=r.t-60)]; af=y[(y.t>r.t+0.5)&(y.t<=r.t+60)]; at=y[(y.t>=r.t-0.5)&(y.t<=r.t+0.5)]
    o.append(dict(ev=r.ev[:16],nm=r.nm[:14],pre=r.pre,pl=r.pl,b=r.b,sz=float(at.bs.iloc[0]) if len(at) else np.nan,tm_before=float(b4.tm.iloc[-1]) if len(b4) else np.nan,tm_at=r.tm,tm_after=float(af.tm.iloc[-1]) if len(af) else np.nan,st_before=b4.status.iloc[-1] if len(b4) else None,st_after=af.status.iloc[-1] if len(af) else None,nrows_after=len(af),ltp_after_max=float(af.ltp.max()) if len(af) else np.nan,ltp_after_min=float(af.ltp.min()) if len(af) else np.nan))
O=pd.DataFrame(o); print(O.round(2).to_string(index=False))
d=(O.tm_at/O.tm_before-1).dropna(); print("\ntotal matched across the reopen, at over before: median",round(float(d.median()),3),"share falling",round(float((d<0).mean()),3),"n",len(d))
d2=(O.tm_after/O.tm_at-1).dropna(); print("total matched after over at, up to 60 s: median",round(float(d2.median()),3),"share rising",round(float((d2>0).mean()),3),"n",len(d2))
A.to_pickle('/tmp/a399.pkl')
