#!/bin/bash
# 150: Sunday 25 Oct fixes. (a) RACING TAPE DEAD since 16:30 Sat: heartbeat stopped a minute before 147 ran; keepalive did not revive
#     it (hung process still matches pgrep). Print the log tail, kill -9, restart, prove heartbeat moves. (b) CLV back+6 paper took
#     BOTH sides of the same match (Junior v Aguilas: away AND draw "6% edge") in thin leagues — that is Betfair's wide lay side, not
#     value. New filter: >= £20k matched, lay/back spread <= 5%, and if two sides of one market qualify both are junk. Existing rows
#     re-labelled so the book is clean. (c) ORACLE CAPTURE TEST WAS BIASED: 146 measured fixed exits only on entries hindsight had
#     already chosen as winners (the perfect back->lay trades), so "+£23.66 per £10" is survivorship, not a strategy. Honest version:
#     EVERY goal, scorer = side whose price fell at the draw jump, enter at goal+2 min, both directions (back scorer = oracle hint,
#     lay scorer = M1), fixed exits +5/+10/+15 min, 2% spread each way, 2% comm, train/test halves by date. This decides M1's direction.
echo "== (a) racing recorder"
tail -15 /root/pe-race/race.log; pgrep -af race_swing.py
pkill -9 -f race_swing.py; sleep 2; /root/pe-race/keepalive.sh; sleep 60
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require').cursor(); c.execute("SELECT last_seen, now()-last_seen AS age, live_markets FROM racing_heartbeat"); print("racing heartbeat after restart:",c.fetchall())
PY
pgrep -af race_swing.py; tail -5 /root/pe-race/race.log
echo "== (b) CLV filter"
python3 - <<'PY'
p='/root/pe-clv/clv_bot.py'; s=open(p).read()
old="                if band:\n"
new="                if band and tm>=20000 and l[0]['price']/b[0]['price']-1<=0.05:\n"
assert old in s and new not in s, "pattern"
s=s.replace(old,new,1)
# after each market's runners: if two sides qualified as back+6, junk both
anchor="            done.add(mid)"
assert anchor in s
s=s.replace(anchor,"            cur.execute(\"UPDATE clv_paper SET band='junk' WHERE market_id=%s AND band='back+6' AND (SELECT count(*) FROM clv_paper c2 WHERE c2.market_id=%s AND c2.band='back+6')>1\",(mid,mid))\n"+anchor,1)
open(p,'w').write(s); print("clv filter patched")
PY
python3 -m py_compile /root/pe-clv/clv_bot.py && pkill -f clv_bot.py; sleep 2; /root/pe-clv/keepalive.sh 2>/dev/null; sleep 5; pgrep -af clv_bot.py | head -1
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require'); c.autocommit=True; cur=c.cursor()
cur.execute("""UPDATE clv_paper p SET band='junk' WHERE band='back+6' AND (
   (SELECT count(*) FROM clv_paper c2 WHERE c2.market_id=p.market_id AND c2.band='back+6')>1
   OR EXISTS (SELECT 1 FROM clv_tape t WHERE t.market_id=p.market_id AND t.side=p.side AND (coalesce(t.total_matched,0)<20000 OR t.bf_lay/t.bf_back-1>0.05)))"""); print("back+6 rows junked:",cur.rowcount)
cur.execute("SELECT band, count(*), count(pnl_per_10), round(sum(pnl_per_10)::numeric,2) FROM clv_paper GROUP BY 1 ORDER BY 1"); print("CLV book now:",cur.fetchall())
PY
echo "== (c) honest post-goal capture test (both directions)"
cd /root/pe-factory && cat > goal_capture.py <<'PYFILE'
import sys, datetime, psycopg2, psycopg2.extras, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',250); pd.set_option('display.max_rows',200)
COMM=0.02; SPREAD=0.02
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET statement_timeout='3000s'")
cur.execute("SELECT DISTINCT event_id FROM bf_hist_price WHERE mkt='MO'"); evs=[r[0] for r in cur.fetchall()]; print("games:",len(evs),flush=True)
rows=[]
def px_at(s,m):   # first print at/after minute m
    idx=s.index[s.index>=m]
    return (int(idx.min()),float(s[idx.min()])) if len(idx) else (None,None)
for b in range(0,len(evs),1500):
    D=pd.read_sql("SELECT event_id, event_name, country, m, minute, sel, ltp::float ltp FROM bf_hist_price WHERE mkt='MO' AND event_id = ANY(%s) AND minute BETWEEN 0 AND 95 ORDER BY event_id, sel, minute",con,params=(evs[b:b+1500],))
    for eid,g in D.groupby('event_id',sort=False):
        S={sel:s.drop_duplicates('minute').set_index('minute').ltp for sel,s in g.groupby('sel')}
        if 'DRAW' not in S or len(S['DRAW'])<30: continue
        dr=S['DRAW']; dv=dr.values; dm=dr.index.values
        goals=[int(dm[i]) for i in range(1,len(dv)) if dv[i]>=dv[i-1]*1.20 and dm[i]>=2]
        gl=[]
        for gm in goals:
            if not gl or gm-gl[-1]>=4: gl.append(gm)
        for k,gm in enumerate(gl):
            # scorer = side whose price fell most between gm-1 and gm+1
            ratios={}; pres={}
            for side in ('HOME','AWAY'):
                if side not in S: continue
                s=S[side]; pre=s[s.index<=gm-1]; post=s[s.index>=gm+1]
                if pre.empty or post.empty: continue
                ratios[side]=post.iloc[0]/pre.iloc[-1]; pres[side]=float(pre.iloc[-1])
            if not ratios: continue
            scorer=min(ratios,key=ratios.get)
            if ratios[scorer]>0.90: continue          # no clear scorer (own goal/odd data)
            s=S[scorer]; em,e=px_at(s,gm+2)
            if e is None or e<=1.01 or em>gm+4: continue
            nxt=gl[k+1] if k+1<len(gl) else 999
            rec=dict(eid=eid,country=g.country.iloc[0],mt=pd.Timestamp(g.m.iloc[0]),gm=gm,goal_no=k+1,scorer=scorer,e=e,pre=pres[scorer],drop=ratios[scorer])
            for h in (5,10,15):
                xm,x=px_at(s,gm+2+h)
                if x is None or xm>gm+2+h+3: rec[f'b{h}']=None; rec[f'l{h}']=None; continue
                if nxt<=xm: x_eff=None  # next goal before exit: use price at next goal minute-1 (we would be stopped by the goal); approximate with print at nxt-1
                xm2,x2=(px_at(s,nxt-1) if nxt<=xm else (xm,x))
                if x2 is None: rec[f'b{h}']=None; rec[f'l{h}']=None; continue
                eb=e*(1-SPREAD); xb=x2*(1+SPREAD)      # back at worse (lower) price, lay out at worse (higher) price
                pb=10*(eb/xb-1); rec[f'b{h}']=pb*(1-COMM) if pb>0 else pb
                el=e*(1+SPREAD); xl=x2*(1-SPREAD)      # lay at worse (higher) price, back out at worse (lower) price
                pl=10*(1-el/xl); rec[f'l{h}']=pl*(1-COMM) if pl>0 else pl
            rows.append(rec)
    print(" processed",min(b+1500,len(evs)),flush=True)
R=pd.DataFrame(rows); R=R.sort_values('mt'); R['half']=np.where(np.arange(len(R))<len(R)//2,'H1','H2')
print(f"\n=== EVERY GOAL, scorer identified by the price fall, entry at goal+2 min, per £10, 2% spread each way, 2% comm | goals {len(R)} | {R.mt.min().date()} -> {R.mt.max().date()} ===")
def line(df,lab):
    out=[]
    for h in (5,10,15):
        for d,c in (('BACK scorer',f'b{h}'),('LAY scorer',f'l{h}')):
            x=df[c].dropna();
            if len(x)<50: continue
            t=x.mean()/(x.std()/np.sqrt(len(x)))
            out.append(dict(rule=f"{d} exit +{h}m",n=len(x),mean=round(x.mean(),3),pos=round((x>0).mean(),3),t=round(t,2),
                            h1=round(df[df.half=='H1'][c].dropna().mean(),3),h2=round(df[df.half=='H2'][c].dropna().mean(),3)))
    print(f"\n{lab}:\n",pd.DataFrame(out).to_string(index=False))
line(R,"ALL goals")
line(R[R.goal_no==1],"FIRST goal only")
line(R[R.e<=1.5],"scorer price at entry <= 1.5")
line(R[(R.e>1.5)&(R.e<=2.5)],"scorer 1.5-2.5")
line(R[R.e>2.5],"scorer > 2.5")
line(R[R.gm<=30],"goal before 30'"); line(R[R.gm>=60],"goal after 60'")
line(R[R.drop<=0.6],"big drop (scorer price fell >=40%)")
line(R[R.drop>0.75],"small drop (fell <25%)")
print("\nby country (BACK scorer +5m mean / LAY scorer +5m mean / n):\n",R.groupby('country').agg(back5=('b5','mean'),lay5=('l5','mean'),n=('b5','count')).round(3).sort_values('n',ascending=False).to_string())
cur.execute("CREATE TABLE IF NOT EXISTS goal_capture (run_date DATE, event_id TEXT, country TEXT, mt TIMESTAMPTZ, gm INT, goal_no INT, scorer TEXT, entry NUMERIC, drop NUMERIC, b5 NUMERIC, b10 NUMERIC, b15 NUMERIC, l5 NUMERIC, l10 NUMERIC, l15 NUMERIC)")
cur.execute("DELETE FROM goal_capture WHERE run_date=current_date")
def f(v): return None if v is None or pd.isna(v) else float(round(v,3))
psycopg2.extras.execute_values(cur,"INSERT INTO goal_capture VALUES %s",[(datetime.date.today(),r.eid,r.country,r.mt,int(r.gm),int(r.goal_no),r.scorer,f(r.e),f(r.drop),f(r.b5),f(r.b10),f(r.b15),f(r.l5),f(r.l10),f(r.l15)) for r in R.itertuples()],page_size=2000)
print("stored goal_capture rows:",len(R))
PYFILE
python3 -m py_compile goal_capture.py || exit 1
timeout 3400 python3 goal_capture.py 2>&1 | grep -v -E "UserWarning|pd.read_sql"
