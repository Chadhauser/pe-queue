import sys,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_official import secs
pd.set_option('display.width',230); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',80)
rc=psycopg2.connect(creds.pg_railway(),sslmode='require'); rc.autocommit=True; rc.cursor().execute("SET statement_timeout='200s'")
L=psycopg2.connect(creds.pg_local()); L.autocommit=True
# ---- tennis: where does the log sit relative to the reopen?
R=pd.read_sql("SELECT ts,market_id,sel_id,secs_since_start ss,suspended_secs su,pre_ltp::float8 pre,post_back_px::float8 b,post_lay_px::float8 l,post_ltp::float8 pl FROM ip_reopen WHERE sport='tennis' AND market_type='MATCH_ODDS' AND ts<'2026-11-06' ORDER BY ts",rc)
R['tt']=secs(R.ts); mids=list(R.market_id.unique())
Z=pd.read_sql("SELECT market_id,count(*) n,count(*) FILTER (WHERE inplay) nip,min(captured_at) FILTER (WHERE inplay) a,max(captured_at) FILTER (WHERE inplay) z,max(captured_at) zz,max(market_start) ms FROM finder_tlog WHERE market_id=ANY(%s) GROUP BY 1",L,params=(mids,))
print("tennis: markets in ip_reopen",len(mids),"on log",len(Z),"with in-play rows",int((Z.nip>0).sum()))
Z['az']=(secs(Z.z)-secs(Z.a))/60; print("in-play span on log, minutes, p10 p50 p90",Z.az.quantile([.1,.5,.9]).round(1).tolist())
F=R.groupby('market_id').tt.min().rename('t0').reset_index().merge(Z,on='market_id'); F['rel_z']=(F.t0-secs(F.z))/60; F['rel_a']=(F.t0-secs(F.a))/60
print("first reopen minus log's first in-play, minutes, p10 p50 p90",F.rel_a.quantile([.1,.5,.9]).round(1).tolist(),"; minus log's last in-play",F.rel_z.quantile([.1,.5,.9]).round(1).tolist())
print("share of reopens after the log's last in-play row",round(float((F.rel_z>0).mean()),3))
print("tennis first reopen ss p10 p50 p90",R.groupby('market_id').ss.min().quantile([.1,.5,.9]).tolist())
# sample market through time
m=mids[len(mids)//2]; P=pd.read_sql("SELECT captured_at,selection_id,back_price,lay_price,last_traded,inplay FROM finder_tlog WHERE market_id=%s ORDER BY captured_at",L,params=(m,)); print("sample market",m,"rows",len(P)); print(P.groupby('inplay').captured_at.agg(['min','max','size']))
print(R[R.market_id==m].head(6)[['ts','sel_id','ss','pre','b','l','pl']].to_string())
# ---- racing: what is the first reopen?
Q="sport IN ('horse_racing','racing') AND market_type='WIN'"
A=pd.read_sql("SELECT r.ts,r.market_id,r.sel_id,r.secs_since_start ss,r.suspended_secs su,r.pre_ltp::float8 pre,r.post_ltp::float8 pl,r.post_back_px::float8 b,r.post_lay_px::float8 l FROM ip_reopen r JOIN (SELECT market_id,min(ts) t0 FROM ip_reopen WHERE "+Q+" GROUP BY 1) f ON r.market_id=f.market_id AND r.ts=f.t0 WHERE r.market_type='WIN'",rc)
W=pd.read_sql("SELECT market_id,selection_id sel_id,won,bsp::float8 bsp,market_start FROM racing_results WHERE market_id=ANY(%s)",rc,params=(list(A.market_id.unique()),))
D=A.merge(W,on=['market_id','sel_id']); D['tt']=secs(D.ts)
fav=D.sort_values('bsp').groupby('market_id').first()
print("\nracing: joined markets",D.market_id.nunique(),"BSP favourite's pre_ltp/BSP p10 p50 p90",(fav.pre/fav.bsp).quantile([.1,.5,.9]).round(2).tolist(),"post back/BSP",(fav.b/fav.bsp).quantile([.1,.5,.9]).round(2).tolist())
Wn=D[D.won==True]; print("winner's pre_ltp/BSP p10 p50 p90",(Wn.pre/Wn.bsp).quantile([.1,.5,.9]).round(2).tolist()," winner's pre_ltp p10 p50 p90",Wn.pre.quantile([.1,.5,.9]).round(2).tolist()," winner's back at reopen p10 p50 p90",Wn.b.quantile([.1,.5,.9]).round(2).tolist())
Ls=D[D.won==False]; print("loser's pre_ltp/BSP p10 p50 p90",(Ls.pre/Ls.bsp).quantile([.1,.5,.9]).round(2).tolist()," loser's back at reopen",Ls.b.quantile([.1,.5,.9]).round(2).tolist())
print("share of runners with a real book, winners",round(float(((Wn.l<=Wn.b*1.05)).mean()),3),"losers",round(float(((Ls.l<=Ls.b*1.05)).mean()),3))
# compare with the 30 s racing log around the reopen
mids=list(D.market_id.unique()); G=pd.read_sql("SELECT market_id,selection_id sel_id,captured_at,back_price::float8 bb,lay_price::float8 ll,last_traded::float8 lt,inplay FROM finder_rlog WHERE market_id=ANY(%s) AND captured_at>=market_start+interval '0 sec' ORDER BY market_id,selection_id,captured_at",L,params=(mids,)) if False else None
c=L.cursor(); c.execute("SELECT column_name FROM information_schema.columns WHERE table_name='finder_rlog'"); print([x[0] for x in c.fetchall()])
c.execute("SELECT market_id,min(captured_at) FILTER (WHERE inplay),max(captured_at) FROM finder_rlog WHERE market_id=ANY(%s) GROUP BY 1",(mids,)); H=pd.DataFrame(c.fetchall(),columns=['market_id','ip0','z'])
F=D.groupby('market_id').tt.min().rename('t0').reset_index().merge(H,on='market_id'); F=F[F.ip0.notna()]; F['s']=F.t0-secs(F.ip0); F['sz']=F.t0-secs(F.z)
print("first reopen minus racing log's first in-play row, seconds, p10 p25 p50 p75 p90",F.s.quantile([.1,.25,.5,.75,.9]).round(0).tolist(),"n",len(F))
print("minus racing log's last row",F.sz.quantile([.1,.5,.9]).round(0).tolist())
