import sys,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_official import secs
pd.set_option('display.width',230)
rc=psycopg2.connect(creds.pg_railway(),sslmode='require'); rc.autocommit=True; rc.cursor().execute("SET statement_timeout='200s'")
L=psycopg2.connect(creds.pg_local())
for sport,tb,col,flt in (('tennis','finder_tlog','selection_id',"sport='tennis' AND market_type='MATCH_ODDS'"),('racing','finder_rlog','selection_id',"sport IN ('horse_racing','racing') AND market_type='WIN'")):
    R=pd.read_sql(f"SELECT ts,market_id,sel_id,pre_ltp::float8 pre,post_ltp::float8 pl,post_back_px::float8 b,post_lay_px::float8 l FROM ip_reopen WHERE {flt} AND ts<'2026-11-06' ORDER BY market_id,sel_id,ts",rc)
    R=R.dropna(subset=['pre','pl']); R['tt']=secs(R.ts)
    R['prev_pre']=R.groupby(['market_id','sel_id']).pre.shift(1)
    x=R[R.prev_pre.notna()&(R.prev_pre!=R.pre)]
    print(sport,"rows",len(R),"; where pre changed since the last row, share post_ltp equals the LAST row's pre",round(float((x.pl==x.prev_pre).mean()),3),"; equals THIS row's pre",round(float((x.pl==x.pre).mean()),3),"n",len(x))
    mids=list(R.market_id.drop_duplicates().sample(min(400,R.market_id.nunique()),random_state=1))
    G=pd.read_sql(f"SELECT market_id,{col} sel_id,captured_at,back_price::float8 bb,lay_price::float8 ll,last_traded::float8 lt FROM {tb} WHERE market_id=ANY(%s) AND inplay ORDER BY captured_at",L,params=(mids,))
    G['tt']=secs(G.captured_at); out=[]
    gg={k:v for k,v in G.groupby(['market_id','sel_id'],sort=False)}
    for r in R[R.market_id.isin(mids)].itertuples():
        y=gg.get((r.market_id,r.sel_id))
        if y is None: continue
        t=y.tt.values; i=np.searchsorted(t,r.tt)
        if i==0 or i>=len(t) or t[i]-t[i-1]>60: continue
        before,after=y.iloc[i-1],y.iloc[i]
        if r.pre<=1 or r.pl<=1 or before.lt!=before.lt or after.lt!=after.lt: continue
        out.append((abs(np.log(r.pre/before.lt)),abs(np.log(r.pre/after.lt)),abs(np.log(r.pl/before.lt)),abs(np.log(r.pl/after.lt)),(t[i]-r.tt)))
    O=pd.DataFrame(out,columns='pre_v_logbefore pre_v_logafter post_v_logbefore post_v_logafter gap'.split())
    print("  rows matched to the log",len(O),"median abs log gap, and share within 1%:\n",O.drop(columns='gap').agg(['median',lambda s:float((s<.01).mean())]).round(4).to_string())
