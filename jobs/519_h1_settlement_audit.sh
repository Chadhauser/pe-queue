#!/bin/bash
# 519: AUDIT before anyone believes it. H1 cells show IS win rates of 0.97-1.00 against implied 0.62-0.76 (t 50-70). Closing prices are
# not wrong by 30 points; this is a settlement or join artefact. Pull 12 FIRST_HALF_GOALS_15 markets from the 0.65-0.70 BACK cell and
# print, per runner: last pre-off row, last in-play row, number of in-play rows, market_time; plus how many runners each market has in
# pre vs in-play. Diagnostic only.
set -o pipefail
python3 - <<'PY'
import sys,psycopg2,pandas as pd; sys.path.insert(0,'/root/pe-queue/runner'); import creds
pd.set_option('display.width',250); pd.set_option('display.max_rows',200)
c=psycopg2.connect(creds.pg_local()); k=c.cursor(); k.execute("SET statement_timeout='900s'")
Q="""WITH pre AS (SELECT DISTINCT ON (market_id, sel) market_id, sel, ts pre_ts, ltp close_ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type=%s AND NOT inplay AND ltp>1 ORDER BY market_id, sel, ts DESC),
fin AS (SELECT DISTINCT ON (market_id, sel) market_id, sel, ts fin_ts, ltp last_ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type=%s AND inplay AND ltp>1 ORDER BY market_id, sel, ts DESC),
cnt AS (SELECT market_id, sel, count(*) FILTER (WHERE inplay) n_ip, count(*) FILTER (WHERE NOT inplay) n_pre, min(market_time) mt FROM bf_hist_other WHERE sport='Soccer' AND market_type=%s GROUP BY 1,2)
SELECT cnt.market_id, cnt.sel, mt, n_pre, pre_ts, close_ltp, n_ip, fin_ts, last_ltp FROM cnt LEFT JOIN pre USING (market_id, sel) LEFT JOIN fin USING (market_id, sel) ORDER BY cnt.market_id, cnt.sel"""
mt='FIRST_HALF_GOALS_15'; df=pd.read_sql(Q,c,params=(mt,mt,mt))
print("runner-rows",len(df),"markets",df.market_id.nunique())
print("runners per market (pre):",df[df.close_ltp.notna()].groupby('market_id').size().value_counts().to_dict())
print("runners per market (in-play):",df[df.last_ltp.notna()].groupby('market_id').size().value_counts().to_dict())
print("in-play row count per runner, quantiles:",df.n_ip.quantile([.1,.25,.5,.75,.9]).to_dict())
print("share of runners with NO in-play rows:",round(df.last_ltp.isna().mean(),3))
both=df[df.close_ltp.notna()&df.last_ltp.notna()]
m2=both.groupby('market_id').filter(lambda g: len(g)==2)
print("\\n== 12 random 2-runner markets with both sides priced ==")
for mid,g in list(m2.groupby('market_id'))[:12]:
    print(g[['market_id','sel','mt','n_pre','pre_ts','close_ltp','n_ip','fin_ts','last_ltp']].to_string(index=False)); print()
one=both.groupby('market_id').filter(lambda g: len(g)==1)
print("markets where only ONE runner has both pre and in-play rows:",one.market_id.nunique(),"of",both.market_id.nunique())
print(one.head(12)[['market_id','sel','close_ltp','n_ip','last_ltp']].to_string(index=False))
k.execute("select market_type, count(*) from fair_price_calib where abs(rate_is-p_mean_is)>0.15 and n_is>=300 group by 1 order by 2 desc"); print("\\ncalib cells off by >15 points, by type:",k.fetchall())
PY
