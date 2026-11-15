import sys,psycopg2,pandas as pd
sys.path.insert(0,'/root/pe-queue/runner'); import creds
pd.set_option('display.width',220); pd.set_option('display.max_columns',20)
rc=psycopg2.connect(creds.pg_railway(),sslmode='require'); rc.autocommit=True; rc.cursor().execute("SET statement_timeout='200s'")
P=pd.read_sql("""WITH t AS (SELECT ts,market_id,sel_id,ltp::float8 ltp,total_matched::float8 tm,max(total_matched::float8) OVER (PARTITION BY market_id ORDER BY ts ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) hi FROM cricket_fav_tape)
SELECT p.rule,p.event_name,p.entry_px::float8 en,p.exit_px::float8 ex,p.exit_reason,p.result,p.pnl_per_10::float8 pnl,p.settled_at,x.ltp,x.tm,x.hi,x.ts FROM cricket_fav_paper p LEFT JOIN LATERAL (SELECT * FROM t WHERE t.market_id=p.market_id AND t.sel_id=p.sel_id AND t.ts<=p.settled_at ORDER BY t.ts DESC LIMIT 1) x ON true WHERE p.settled_at IS NOT NULL ORDER BY p.settled_at""",rc)
P['replay']=P.tm<P.hi*0.999
print(P.groupby(['rule','exit_reason']).agg(n=('pnl','size'),pnl=('pnl','mean'),replay=('replay','sum')).round(3).to_string())
print(P[['rule','en','ex','exit_reason','pnl','ltp','replay']].to_string(index=False))
print('total',len(P),'replay at the exit',int(P.replay.sum()),'pnl all',round(P.pnl.mean(),3),'pnl clean',round(P[~P.replay].pnl.mean(),3))
