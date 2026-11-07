#!/bin/bash
# 528: AUDIT the bookie v1 paper book before any number is believed. First 24 h: 10,031 settled, BACK fills +£1.03 each (n 4,949),
# LAY fills −£8.62 each (n 5,082) at £2 stakes. Both sides that far from zero is either adverse selection on goal crashes (a resting
# lay is hit as the price collapses through it) or a settlement/mapping error. This prints: P&L by market type x side, by pre-off vs
# in-play fill, by fill price band; the 15 worst lays with the tape 2 min either side of the fill and the runner->selection->status map.
set -o pipefail
python3 - <<'PY'
import sys,psycopg2,pandas as pd; sys.path.insert(0,'/root/pe-queue/runner'); import creds
pd.set_option('display.width',250); pd.set_option('display.max_rows',200); pd.set_option('display.max_colwidth',60)
L=psycopg2.connect(creds.pg_local()); R=psycopg2.connect(creds.pg_railway(),sslmode='require'); rc=R.cursor(); rc.execute("SET statement_timeout='120s'")
df=pd.read_sql("""select id,ts,fill_ts,start_ts,market_id,event_name,mkt,sel,side,price::float price,fill_price::float fp,mkt_back::float mb,mkt_lay::float ml,won,pnl::float pnl
                  from bookie_paper where version='v1' and coalesce(exchange,'betfair')='betfair' and status='settled'""",L)
print("settled fills:",len(df),"| pnl total",round(df.pnl.sum(),2))
df['inplay']=df.fill_ts>df.start_ts.fillna(df.fill_ts-pd.Timedelta(days=9))
df['pband']=pd.cut(df.fp,[1,1.5,2,3,5,10,1000])
print("\n== by side x market type (n, mean £ per fill, win rate)"); print(df.groupby(['side','mkt']).agg(n=('pnl','size'),mean=('pnl','mean'),win=('won','mean')).round(3).query('n>=50').to_string())
print("\n== by side x price band"); print(df.groupby(['side','pband'],observed=True).agg(n=('pnl','size'),mean=('pnl','mean'),win=('won','mean')).round(3).to_string())
print("\n== start_ts known? ", df.start_ts.notna().mean().round(3), "| by side x in-play flag"); print(df.groupby(['side','inplay']).agg(n=('pnl','size'),mean=('pnl','mean')).round(3).to_string())
print("\n== expected win rate from fill price vs actual, by side (calibration of our fills)")
df['imp']=1/df.fp; print(df.groupby('side').agg(n=('won','size'),implied=('imp','mean'),actual=('won','mean')).round(3).to_string())
print("\n== 15 worst lays with tape around the fill")
worst=df[df.side=='LAY'].nsmallest(15,'pnl')
for _,r in worst.iterrows():
    rc.execute("select to_char(ts,'HH24:MI:SS'),ltp,back_px,lay_px,minute from liq_sample where market_id=%s and sel=%s and ts between %s and %s order by ts",(r.market_id,r.sel,r.fill_ts-pd.Timedelta(minutes=2),r.fill_ts+pd.Timedelta(minutes=2))); tape=rc.fetchall(); R.commit()
    print(f"\n{r.event_name[:40]} | {r.mkt} {r.sel} | LAY @ {r.fp} (quoted {r.price}, mkt {r.mb}/{r.ml}) order {str(r.ts)[11:19]} fill {str(r.fill_ts)[11:19]} start {str(r.start_ts)[:16]} | won={r.won} pnl={r.pnl}")
    print("   tape:",[(t,float(l or 0),float(b or 0),float(y or 0),m) for t,l,b,y,m in tape][:8])
lc=L.cursor()
for _,r in worst.head(5).iterrows():
    lc.execute("select sel_id,name from liq_runners where market_id=%s",(r.market_id,)); print(f"   runners {r.market_id}:",lc.fetchall()[:6])
PY
