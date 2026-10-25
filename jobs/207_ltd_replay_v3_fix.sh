#!/bin/bash
# 207: 205's replay found no trades because the final-book step demanded a sane spread on all three runners at 85'+ (losers' lay side
# is 1000 at the death, so they were filtered and the result was never resolved). Result now comes from the last sane DRAW sample's
# timestamp with every runner's best back at that time. Same fix in the paper bot's settlement. Replay re-run.
set -e
python3 - <<'PY2'
p='/root/pe-ltd/ltd_paper.py'; s=open(p).read()
old='''    cur.execute("""SELECT sel, back_px, minute FROM liq_sample s WHERE market_id=%s AND mkt='MO' AND back_px IS NOT NULL AND lay_px IS NOT NULL AND lay_px<=back_px*1.2 AND minute>=85
                   AND ts=(SELECT max(ts) FROM liq_sample WHERE market_id=%s AND mkt='MO' AND sel='DRAW' AND back_px IS NOT NULL AND lay_px IS NOT NULL AND lay_px<=back_px*1.2 AND minute>=85)""",(mid,mid))'''
new='''    cur.execute("""SELECT sel, back_px, minute FROM liq_sample s WHERE market_id=%s AND mkt='MO' AND back_px IS NOT NULL
                   AND ts=(SELECT max(ts) FROM liq_sample WHERE market_id=%s AND mkt='MO' AND sel='DRAW' AND back_px IS NOT NULL AND lay_px IS NOT NULL AND lay_px<=back_px*1.2 AND minute>=85)""",(mid,mid))'''
assert old in s; s=s.replace(old,new,1); open(p,'w').write(s); print("paper settle fixed")
PY2
python3 -m py_compile /root/pe-ltd/ltd_paper.py; pkill -f ltd_paper.py || true; sleep 2; /root/pe-ltd/keepalive.sh; sleep 30; pgrep -af ltd_paper.py | head -1
echo "== live-ladder replay v3 with book-based goals (same markets as 192)"
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys, psycopg2, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',220); COMM=0.02; JUMP=1.25
con=psycopg2.connect(DB,sslmode='require')
mk=pd.read_sql("SELECT market_id FROM liq_sample WHERE mkt='MO' GROUP BY market_id HAVING min(minute)<=5 AND max(minute)>=88",con); mids=list(mk.market_id); print("markets:",len(mids))
ALL=pd.read_sql("SELECT market_id, event_name, competition, ts, minute, sel, back_px::float bp, lay_px::float lp, lay_sz::float lsz, total_matched::float tm FROM liq_sample WHERE mkt='MO' AND market_id = ANY(%s) AND back_px IS NOT NULL ORDER BY market_id, ts",con,params=(mids,))
S=ALL[ALL.lp.notna()&(ALL.lp<=ALL.bp*1.2)]
rows=[]
for mid,g in S.groupby('market_id',sort=False):
    d=g[g.sel=='DRAW'].copy(); h=g[g.sel=='HOME']; a=g[g.sel=='AWAY']
    if len(d)<10 or h.empty or a.empty: continue
    d['pb']=d.bp.shift(); d['pl']=d.lp.shift(); jumps=d[(d.bp>=d.pb*JUMP)&(d.bp>=d.pl*JUMP)].ts.tolist()
    late=d[d.minute>=85]
    if late.empty: continue
    lt=late.ts.max(); fin={r.sel:r.bp for r in ALL[(ALL.market_id==mid)&(ALL.ts==lt)].itertuples() if pd.notna(r.bp)}
    if not fin: continue
    wsel=min(fin,key=fin.get); winner=wsel if fin[wsel]<=1.15 else None
    for trig in (46,60,75):
        e=d[(d.minute>=trig)&(d.minute<=trig+2)]
        if e.empty: continue
        r0=e.iloc[0]
        if any(t<=r0.ts for t in jumps): continue
        hh=h[h.ts<=r0.ts]; aa=a[a.ts<=r0.ts]
        if hh.empty or aa.empty or min(hh.iloc[-1].bp,aa.iloc[-1].bp)<1.30: continue
        lay=r0.lp
        if not (1.5<=lay<=2.5) or (r0.lsz or 0)<20 or (r0.tm or 0)<5000: continue
        nxt=[t for t in jumps if t>r0.ts]
        if nxt:
            x=d[d.ts>=nxt[0]+pd.Timedelta(seconds=120)]
            if x.empty: continue
            back=x.iloc[0].bp; p=10*(1-lay/back); p=p*(1-COMM) if p>0 else p; how='goal'
        else:
            if winner is None: continue
            p=(-10*(lay-1)) if winner=='DRAW' else 10*(1-COMM); how='settle'
        rows.append(dict(event=g.event_name.iloc[0],comp=g.competition.iloc[0],trig=trig,lay=lay,how=how,p=round(p,2)))
R=pd.DataFrame(rows); print("\nLIVE LADDER v3 (book-based goals) — lay draw 1.5-2.5 in a level game at 46/60/75, exit 2 min after the next goal:")
if len(R):
    print(R.groupby('trig').p.agg(n='size',mean='mean',win=lambda s:(s>0).mean(),total='sum').round(2).to_string())
    x=R.p; print("\nall:",len(R),"| mean per £10",round(x.mean(),2),"| win",f"{(x>0).mean():.0%}","| total £",round(x.sum(),1),"| t",round(x.mean()/(x.std(ddof=1)/np.sqrt(len(x))),2),"| 192 (reopen events) said +1.46, 58%")
    print("exit type:",R.how.value_counts().to_dict())
    print("\nby competition (n>=6):\n",R.groupby('comp').p.agg(['size','mean']).query('size>=6').round(2).sort_values('mean',ascending=False).to_string())
else: print("no trades")
PY
