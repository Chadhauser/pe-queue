import sys,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_official import secs
pd.set_option('display.width',240); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',120)
rc=psycopg2.connect(creds.pg_railway(),sslmode='require'); rc.autocommit=True; rc.cursor().execute("SET statement_timeout='200s'")
Q="sport IN ('horse_racing','racing') AND market_type='WIN'"
A=pd.read_sql("SELECT r.ts,r.market_id,r.event_name,r.sel_id,r.sel_name,r.secs_since_start ss,r.suspended_secs su,r.pre_ltp::float8 pre,r.post_ltp::float8 pl,r.post_back_px::float8 b,r.post_lay_px::float8 l,r.total_matched::float8 tm FROM ip_reopen r JOIN (SELECT market_id,min(ts) t0 FROM ip_reopen WHERE "+Q+" GROUP BY 1) f ON r.market_id=f.market_id AND r.ts=f.t0 WHERE r.market_type='WIN'",rc)
W=pd.read_sql("SELECT market_id,selection_id sel_id,won,bsp::float8 bsp FROM racing_results WHERE market_id=ANY(%s)",rc,params=(list(A.market_id.unique()),))
D=A.merge(W,on=['market_id','sel_id']); D['tt']=secs(D.ts)
D['real']=(D.b>1)&(D.l<=D.b*1.05); D['mv']=0.5*(D.b+D.l)/D.pre-1
wc=W.assign(w=W.won.eq(True)).groupby('market_id').w.sum(); D=D[D.market_id.isin(wc[wc==1].index)]
X=D[D.real&D.pre.notna()&(D.pre>1)&D.won.notna()]
top=X.loc[X.groupby('market_id').mv.idxmax()]; dr=top[top.mv>=0.15].copy()
print("DRIFT trades",len(dr),"won",round(float(dr.won.eq(True).mean()),3),"implied",round(float((1/dr.b).mean()),3))
print("how many real-book runners in those races",X[X.market_id.isin(dr.market_id)].groupby('market_id').size().describe().round(2).to_dict())
print("drift runner: BSP median",dr.bsp.median(),"pre median",dr.pre.median(),"back median",dr.b.median(),"pl==pre share",round(float((dr.pl==dr.pre).mean()),3))
print("relation: back v BSP median",round(float((dr.b/dr.bsp).median()),3),"pre v BSP median",round(float((dr.pre/dr.bsp).median()),3))
print(dr.sort_values('tt').tail(14)[['event_name','sel_name','ss','su','pre','pl','b','l','bsp','won']].to_string(index=False))
# the contemporaneous book and what happened next, on ip_tape, a rolling window
rec=dr[dr.tt>=pd.Timestamp.now(tz='UTC').timestamp()-6*86400]
print("\nDRIFT trades inside ip_tape's rolling window",len(rec))
if len(rec):
    T=pd.read_sql("SELECT ts,market_id,sel_id,status,ltp::float8 ltp,back_px::float8 bp,back_sz::float8 bs,lay_px::float8 lp,lay_sz::float8 ls FROM ip_tape WHERE market_id=ANY(%s) AND sel_id=ANY(%s) ORDER BY ts",rc,params=(list(rec.market_id),[int(x) for x in rec.sel_id]))
    T['tt']=secs(T.ts); out=[]
    for r in rec.itertuples():
        y=T[(T.market_id==r.market_id)&(T.sel_id==r.sel_id)]
        if not len(y): out.append((r.market_id,None,None,None,None,None,None)); continue
        at=y[(y.tt>=r.tt-1)&(y.tt<=r.tt+1)]; nx=y[(y.tt>r.tt+1)&(y.tt<=r.tt+30)]
        out.append((r.market_id,r.b,float(at.bs.iloc[0]) if len(at) else None,float(nx.ltp.max()) if len(nx) else None,float(nx.bp.max()) if len(nx) else None,len(nx),str(y.status.iloc[-1])))
    O=pd.DataFrame(out,columns='m b size_at ltp_max_30s bp_max_30s rows laststatus'.split()); print(O.to_string(index=False))
    print("median back size at the row",O.size_at.median(),"share of next-30 s best back still at or above b",round(float((O.bp_max_30s>=O.b).mean()),3))
print("\nother runners in a drift race, share with a real book, won",X[X.market_id.isin(dr.market_id)].groupby('sel_id').size().shape)
