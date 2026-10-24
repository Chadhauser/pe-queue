#!/bin/bash
# 143: Saturday fixes. (a) tennis outsider lay paper was taking junk prices (ITF/doubles markets with £0-£70 matched, 3-5 lay on
#     both runners) — now singles only, >= £5k matched, back/lay within 8pct. Junk rows re-labelled band='junk' so the book is clean.
#     (b) in-play factory (136) booked nothing on the 23rd — print its cron log and the matched-game count it should have seen.
#     (c) racing swing: 65 paper trades, 15 targets / 50 stops, -£25. Measure from the 1-second tape what actually predicts the
#     last-5-minute move (WOM level, WOM persistence, rank, price band, seconds to off) so the rule is rewritten from evidence.
echo "== (a) tennis dog filter"
python3 - <<'PY'
p='/root/pe-tennis2/dog_paper.py'; s=open(p).read()
old="lp=ly[0]['price']; band='3-5' if 3.0<=lp<=5.0 else ('5-10' if 5.0<lp<=10.0 else None)"
new="lp=ly[0]['price']; bp_=bk[0]['price']; ok=((b.get('totalMatched') or 0)>=5000 and '/' not in m['event']['name'] and lp<=bp_*1.08); band=('3-5' if 3.0<=lp<=5.0 else ('5-10' if 5.0<lp<=10.0 else None)) if ok else None"
assert old in s; s=s.replace(old,new); open(p,'w').write(s); print("filter added")
PY
python3 -m py_compile /root/pe-tennis2/dog_paper.py && pkill -f dog_paper.py
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require'); c.autocommit=True; cur=c.cursor()
cur.execute("UPDATE tennis_dog_paper SET band='junk' WHERE band IN ('3-5','5-10') AND (coalesce(total_matched,0)<5000 OR event_name LIKE '%/%' OR lay_px>back_px*1.08)"); print("junk rows relabelled:",cur.rowcount)
cur.execute("SELECT band, count(*), count(pnl_per_10), coalesce(sum(pnl_per_10),0) FROM tennis_dog_paper WHERE band IS NOT NULL GROUP BY 1"); print("clean book:",cur.fetchall())
PY
echo "== (b) in-play factory"; tail -30 /root/pe-factory/inplay_factory.log 2>/dev/null || echo "no log"
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require').cursor()
c.execute("SELECT count(DISTINCT market_id), count(DISTINCT sofa_id) FROM ip_stats WHERE market_id IS NOT NULL AND ts>now()-interval '2 days'"); print("matched markets / games last 2 days:",c.fetchone())
c.execute("SELECT count(*) FROM ip_stats s WHERE market_id IS NOT NULL AND ts>now()-interval '2 days' AND EXISTS (SELECT 1 FROM liq_sample l WHERE l.market_id=s.market_id AND l.mkt='MO' LIMIT 1)"); print("stats rows whose market has MO ladder rows:",c.fetchone())
PY
cd /root/pe-factory && python3 inplay_factory.py 2>&1 | grep -v -E "UserWarning|pd.read_sql" | tail -25
echo "== (c) racing: what predicts the move"
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys, math, psycopg2, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require')
T=pd.read_sql("SELECT market_id, sel_id, rank, secs_to_off, ltp::float ltp, wom::float wom, back_sz::float bsz, lay_sz::float lsz FROM racing_tape WHERE rank<=3 AND secs_to_off BETWEEN -5 AND 600 ORDER BY market_id, sel_id, ts",con)
print("tape rows",len(T),"races",T.market_id.nunique())
rows=[]
for (mid,sid),g in T.groupby(['market_id','sel_id']):
    g=g.dropna(subset=['ltp','wom'])
    if len(g)<120: continue
    def at(s): d=g[g.secs_to_off<=s]; return d.iloc[0] if len(d) else None
    a5=at(300); a2=at(120); a1=at(60); off=at(10)
    if a5 is None or off is None or a2 is None or a1 is None: continue
    w5=g[(g.secs_to_off<=330)&(g.secs_to_off>=270)].wom; w2=g[(g.secs_to_off<=150)&(g.secs_to_off>=90)].wom
    rows.append(dict(rank=int(g['rank'].iloc[0]),p5=a5.ltp,p2=a2.ltp,p1=a1.ltp,poff=off.ltp,wom5=a5.wom,wom5_mean=w5.mean(),wom5_min=w5.min(),wom5_max=w5.max(),wom2=a2.wom,wom2_mean=w2.mean(),
                     mv5=off.ltp/a5.ltp-1,mv2=off.ltp/a2.ltp-1,mv1=off.ltp/a1.ltp-1,pre=a2.ltp/a5.ltp-1))
R=pd.DataFrame(rows); print("runner-races",len(R))
def tab(col,bins,target,label):
    R['b']=pd.cut(R[col],bins); g=R.groupby('b',observed=True)[target].agg(['count','mean','median'])
    g['pct_down']=R.groupby('b',observed=True)[target].apply(lambda s:(s<-0.02).mean()); g['pct_up']=R.groupby('b',observed=True)[target].apply(lambda s:(s>0.02).mean())
    print(f"\n{label}:\n",g.round(3).to_string())
tab('wom5_mean',[0,0.3,0.4,0.5,0.6,0.7,1.0],'mv5','WOM (mean over 5:30-4:30 before off) -> price move from -5:00 to the off')
tab('wom2_mean',[0,0.3,0.4,0.5,0.6,0.7,1.0],'mv2','WOM (mean over 2:30-1:30) -> move from -2:00 to the off')
R['persist']=((R.wom5_min>=0.6)|(R.wom5_max<=0.4)).astype(int); print("\npersistent one-sided WOM (whole minute >=0.6 or <=0.4) vs not:\n",R.groupby('persist').mv5.agg(['count','mean']).round(4).to_string())
R['momentum']=np.sign(R.pre)*np.sign(R.wom5_mean-0.5); print("\nWOM agrees with the prior 3-min move (+1) vs disagrees (-1):\n",R.groupby('momentum').mv2.agg(['count','mean']).round(4).to_string())
tab('rank',[0,1,2,3],'mv5','by market rank'); tab('p5',[1,2,3,5,8,15,100],'mv5','by price at -5:00')
PY
