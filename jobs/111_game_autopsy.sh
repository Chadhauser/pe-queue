#!/bin/bash
# 111: GAME AUTOPSY — Peter 19 Oct: "look at games end to end ... see where money can be made, the gap between laying and backing
# a correct score or match odds or over or anything else". For a recorded match: every market we hold on tape (MO, OU15/25/35,
# BTTS, CS from 18 Oct), per selection: pre-match price, every goal (minute, price before -> +60s -> +5m -> +10m), the best
# back->lay and lay->back windows in the game (entry/exit price, minute, hedged profit per £10, money available at the touch),
# and for each window whether a REPEATABLE trigger was present (goal within 2 min / HT / price level) or hindsight only.
# Runs now on Leeds v Man Utd and Udinese v Lecce; then nightly 23:55 on the 3 biggest games of the day -> game_autopsy table.
mkdir -p /root/pe-autopsy && cat > /root/pe-autopsy/autopsy.py <<'PYFILE'
import sys, math, datetime, psycopg2, psycopg2.extras, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
COMM=0.02; STAKE=10.0
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("""CREATE TABLE IF NOT EXISTS game_autopsy (run_at TIMESTAMPTZ DEFAULT now(), play_date DATE, event_name TEXT, mkt TEXT, sel TEXT, kind TEXT, entry_min INT, entry_px NUMERIC, exit_min INT, exit_px NUMERIC,
  profit_per_10 NUMERIC, size_at_touch NUMERIC, trigger TEXT, note TEXT)""")
pd.set_option('display.width',250)
def hedged(kind,e,x):   # per £10 stake, 2pct comm on profit
    p=(e/x-1)*STAKE if kind=='back->lay' else (1-e/x)*STAKE
    return p*(1-COMM) if p>0 else p
def autopsy(event, day=None, store=True):
    q="SELECT ts, mkt, sel, minute, ltp::float ltp, back_px::float back_px, back_sz::float back_sz, lay_px::float lay_px, lay_sz::float lay_sz, total_matched::float tm, competition FROM liq_sample WHERE event_name=%s"
    args=[event]
    if day: q+=" AND ts::date BETWEEN %s::date - 1 AND %s::date + 1"; args+=[day,day]
    S=pd.read_sql(q+" ORDER BY ts",con,params=args)
    if S.empty: print("no tape for",event); return
    G=pd.read_sql("SELECT goal_ts, minute, sel, pre_ltp::float pre, ltp::float post FROM liq_goal_depth WHERE event_name=%s AND mkt='MO' AND offset_s=0 ORDER BY goal_ts",con,params=(event,))
    comp=S.competition.iloc[0]; day=S.ts.iloc[0].date()
    # goals: dedupe reopen bursts (within 4 min), scorer = non-draw sel that shortened most
    goals=[]
    for gts,g in G.groupby('goal_ts'):
        if goals and (gts-goals[-1][0]).total_seconds()<240: continue
        teams=g[~g.sel.isin(['DRAW'])&g.pre.notna()&g.post.notna()]
        if teams.empty: continue
        r=teams.loc[(teams.post/teams.pre).idxmin()]
        if r.post/r.pre>0.97: continue
        goals.append((gts,int(g.minute.iloc[0]) if pd.notna(g.minute.iloc[0]) else None,r.sel))
    print(f"\n================ {event} — {comp} — {day} ================")
    print("GOALS (deduped):",[(m,s) for _,m,s in goals] or "none recorded")
    rows=[]
    for (mkt,sel),d in S.groupby(['mkt','sel']):
        d=d[d.back_px.notna()&d.lay_px.notna()].copy()
        if len(d)<20: continue
        d['min']=d.minute.fillna(-1).astype(int)
        pre=d[d['min']<=0]; ip=d[d['min']>0]
        if ip.empty: continue
        pre_px=pre.back_px.iloc[-1] if not pre.empty else None
        # goal table for this selection
        gl=[]
        for gts,m,sc in goals:
            b=d[d.ts<gts]; a60=d[(d.ts>=gts+pd.Timedelta(seconds=55))&(d.ts<=gts+pd.Timedelta(seconds=90))]; a5=d[(d.ts>=gts+pd.Timedelta(minutes=5))&(d.ts<=gts+pd.Timedelta(minutes=6))]; a10=d[(d.ts>=gts+pd.Timedelta(minutes=10))&(d.ts<=gts+pd.Timedelta(minutes=11))]
            gl.append((m,sc,b.ltp.iloc[-1] if len(b) else None,a60.lay_px.iloc[0] if len(a60) else None,a5.ltp.iloc[0] if len(a5) else None,a10.back_px.iloc[0] if len(a10) else None))
        # best windows: back->lay = back at back_px(t1), lay at lay_px(t2>t1): maximise back_px/lay_px ; lay->back = lay at lay_px(t1), back at back_px(t2): maximise back_px(t2)/lay_px(t1)
        ipv=ip.reset_index(drop=True); bp=ipv.back_px.values; lp=ipv.lay_px.values; mins=ipv['min'].values; ts=ipv.ts.values
        # running max of back_px ahead for lay->back ; running min of lay_px ahead for back->lay
        best_bl=(None,-1e9); best_lb=(None,-1e9)
        sufmin_lp=np.minimum.accumulate(lp[::-1])[::-1]; sufmin_idx=None
        sufmax_bp=np.maximum.accumulate(bp[::-1])[::-1]
        for i in range(0,len(ipv)-1,max(1,len(ipv)//600)):
            j=i+1+int(np.argmin(lp[i+1:])); p=hedged('back->lay',bp[i],lp[j])
            if p>best_bl[1]: best_bl=((i,j),p)
            k=i+1+int(np.argmax(bp[i+1:])); p2=hedged('lay->back',lp[i],bp[k])
            if p2>best_lb[1]: best_lb=((i,k),p2)
        def trig(i):
            t=ts[i]; near=[(m,sc) for gts,m,sc in goals if 0<=(t-np.datetime64(gts)).astype('timedelta64[s]').astype(int)<=180]
            if near: return f"goal {near[0][0]}' {near[0][1]} (within 3 min)"
            if 44<=mins[i]<=47: return "half-time"
            return "hindsight only"
        for kind,(ij,p) in (('back->lay',best_bl),('lay->back',best_lb)):
            if ij is None: continue
            i,j=ij; e=bp[i] if kind=='back->lay' else lp[i]; x=lp[j] if kind=='back->lay' else bp[j]
            sz=ipv.back_sz.iloc[i] if kind=='back->lay' else ipv.lay_sz.iloc[i]
            rows.append((day,event,mkt,sel,kind,int(mins[i]),round(float(e),2),int(mins[j]),round(float(x),2),round(float(p),2),round(float(sz or 0),0),trig(i),f"pre-match {pre_px}"))
        print(f"\n--- {mkt} / {sel}: pre-match {pre_px} | in-play range {ip.ltp.min():.2f}-{ip.ltp.max():.2f} | matched £{ip.tm.max():,.0f}")
        for m,sc,before,l60,m5,b10 in gl:
            if before: print(f"    goal {m}' ({sc}): before {before} -> lay at +60s {l60} -> +5m {m5} -> +10m back {b10}"+(f"  | fade P&L/£10 {hedged('lay->back',l60,b10):+.2f}" if l60 and b10 else ""))
        for r in rows[-2:]:
            print(f"    best {r[4]:9s}: {r[5]}' @ {r[6]} -> {r[7]}' @ {r[8]} = {r[9]:+.2f}/£10 | £{r[10]:.0f} at touch | trigger: {r[11]}")
    if store and rows: psycopg2.extras.execute_values(cur,"INSERT INTO game_autopsy (play_date,event_name,mkt,sel,kind,entry_min,entry_px,exit_min,exit_px,profit_per_10,size_at_touch,trigger,note) VALUES %s",rows)
    R=pd.DataFrame(rows,columns=['day','event','mkt','sel','kind','emin','epx','xmin','xpx','p10','sz','trigger','note'])
    if len(R):
        print("\nSUMMARY — best windows with a REPEATABLE trigger (goal/HT) vs hindsight-only:")
        print(R.assign(triggered=~R.trigger.str.contains('hindsight')).groupby('triggered').p10.agg(['count','sum','mean']).round(2).to_string())
        print(R.sort_values('p10',ascending=False).head(8)[['mkt','sel','kind','emin','epx','xmin','xpx','p10','sz','trigger']].to_string(index=False))
if __name__=='__main__':
    if len(sys.argv)>1:
        for ev in sys.argv[1:]: autopsy(ev)
    else:   # nightly: 3 biggest MO markets of the day by matched
        cur.execute("SELECT event_name, max(total_matched) FROM liq_sample WHERE ts::date=current_date AND mkt='MO' AND minute>0 GROUP BY 1 ORDER BY 2 DESC LIMIT 3")
        for ev,_ in cur.fetchall(): autopsy(ev)
PYFILE
python3 -m py_compile /root/pe-autopsy/autopsy.py || exit 1
( crontab -l 2>/dev/null | grep -v pe-autopsy ; echo "55 23 * * * cd /root/pe-autopsy && python3 autopsy.py >> autopsy.log 2>&1" ) | crontab -
cd /root/pe-autopsy && python3 autopsy.py "Leeds v Man Utd" "Udinese v Lecce" "Strasbourg v Paris St-G"
