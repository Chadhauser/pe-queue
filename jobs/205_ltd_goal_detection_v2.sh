#!/bin/bash
# 205: LTD BOTS — GOAL DETECTION FROM THE BOOK, NOT FROM REOPEN EVENTS OR LTP.
# Evidence (14:05): the recorder's liq_goal_depth events are a suspension->reopen heuristic; today they fired on non-goals (Vasas v Paks
# "goal" with the draw then at 1.95 -> paper exit -2.45, while the real goal came at 83' with the draw at 5.5) and missed real goals
# (Jaro 72', Jelgava 77'). LTP is unusable too: single stray trades print 28.0 against a 3.0 book (Banga) and stale 1.56 against 5.4
# (Jelgava). The real-order bot settled Banga as a win from a stale LTP. Both bots now use the draw's best BACK price with a spread
# sanity check: goal = best back >= 1.25 x the previous sample's best back AND >= 1.25 x its best lay. Settlement = last sane book
# (spread <= 20%) with minute >= 85: the runner backed at <= 1.15 is the winner; none -> UNKNOWN. Paper GOAL exits taken on the old
# signal are re-opened and re-settled under the new logic. Then the live-ladder replay (192) is re-run with the same detection so the
# family's number is honest.
set -e
cat > /root/pe-ltd/ltd_paper.py <<'PYFILE'
import sys, time, datetime, psycopg2
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
COMM=0.02; STAKE=10.0; TRIGS=((46,48),(60,62),(75,77)); JUMP=1.25
def connect():
    c=psycopg2.connect(DB,sslmode='require'); c.autocommit=True; return c
con=connect(); cur=con.cursor()
cur.execute("""CREATE TABLE IF NOT EXISTS ltd_inplay_paper (id SERIAL PRIMARY KEY, market_id TEXT, event_name TEXT, competition TEXT, trig INT, entry_ts TIMESTAMPTZ, entry_minute INT,
  lay_px NUMERIC, lay_sz NUMERIC, total_matched NUMERIC, home_ltp NUMERIC, away_ltp NUMERIC, exit_ts TIMESTAMPTZ, exit_px NUMERIC, exit_reason TEXT, pnl_per_10 NUMERIC, UNIQUE (market_id, trig));
ALTER TABLE ltd_inplay_paper ADD COLUMN IF NOT EXISTS goal_ts TIMESTAMPTZ; ALTER TABLE ltd_inplay_paper ADD COLUMN IF NOT EXISTS det TEXT;
CREATE TABLE IF NOT EXISTS ltd_heartbeat (id INT PRIMARY KEY, last_seen TIMESTAMPTZ, open_trades INT, today INT)""")
# draw samples with the previous sane sample alongside: a goal is a sane-to-sane jump of 25%+ in the best back
DRAW_JUMPS="""WITH d AS (SELECT ts, minute, back_px, lay_px, lag(back_px) OVER (ORDER BY ts) pb, lag(lay_px) OVER (ORDER BY ts) pl
                        FROM liq_sample WHERE market_id=%s AND mkt='MO' AND sel='DRAW' AND back_px IS NOT NULL AND lay_px IS NOT NULL AND lay_px<=back_px*1.2)
             SELECT ts, minute, back_px FROM d WHERE pb IS NOT NULL AND back_px>=pb*%s AND back_px>=pl*%s"""
def pnl_hedge(lay,back):
    p=STAKE*(1-lay/back); return round(p*(1-COMM) if p>0 else p,2)
def first_goal_after(mid,ts):
    cur.execute(DRAW_JUMPS+" AND ts>%s ORDER BY ts LIMIT 1",(mid,JUMP,JUMP,ts)); return cur.fetchone()
def any_goal_before(mid,ts):
    cur.execute(DRAW_JUMPS+" AND ts<=%s LIMIT 1",(mid,JUMP,JUMP,ts)); return cur.fetchone() is not None
def final_book(mid):
    cur.execute("""SELECT sel, back_px, minute FROM liq_sample s WHERE market_id=%s AND mkt='MO' AND back_px IS NOT NULL AND lay_px IS NOT NULL AND lay_px<=back_px*1.2 AND minute>=85
                   AND ts=(SELECT max(ts) FROM liq_sample WHERE market_id=%s AND mkt='MO' AND sel='DRAW' AND back_px IS NOT NULL AND lay_px IS NOT NULL AND lay_px<=back_px*1.2 AND minute>=85)""",(mid,mid))
    return {s:float(b) for s,b,_ in cur.fetchall()}
last_hb=0
while True:
    try:
        # ---- entries: latest MO draw sample per in-play market inside a trigger window
        cur.execute("""WITH last AS (
             SELECT DISTINCT ON (market_id) market_id, event_name, competition, ts, minute, lay_px, lay_sz, total_matched, back_px
             FROM liq_sample WHERE mkt='MO' AND sel='DRAW' AND ts>now()-interval '4 minutes' ORDER BY market_id, ts DESC)
           SELECT l.*, (SELECT back_px FROM liq_sample h WHERE h.market_id=l.market_id AND h.mkt='MO' AND h.sel='HOME' AND h.ts<=l.ts AND h.back_px IS NOT NULL ORDER BY h.ts DESC LIMIT 1) hb,
                       (SELECT back_px FROM liq_sample a WHERE a.market_id=l.market_id AND a.mkt='MO' AND a.sel='AWAY' AND a.ts<=l.ts AND a.back_px IS NOT NULL ORDER BY a.ts DESC LIMIT 1) ab
           FROM last l WHERE l.lay_px BETWEEN 1.5 AND 2.5 AND coalesce(l.lay_sz,0)>=20 AND coalesce(l.total_matched,0)>=5000 AND l.back_px IS NOT NULL AND l.lay_px<=l.back_px*1.2""")
        for mid,ev,comp,ts,minute,lp,lsz,tm,bp,hb,ab in cur.fetchall():
            trig=next((t for t,(a,b) in zip((46,60,75),TRIGS) if a<=(minute or -1)<=b),None)
            if trig is None or hb is None or ab is None or min(float(hb),float(ab))<1.30: continue
            if any_goal_before(mid,ts): continue                        # not 0-0 (book jumped earlier)
            cur.execute("""INSERT INTO ltd_inplay_paper (market_id,event_name,competition,trig,entry_ts,entry_minute,lay_px,lay_sz,total_matched,home_ltp,away_ltp,det)
                           VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,'book-v2') ON CONFLICT DO NOTHING""",(mid,ev,comp,trig,ts,minute,lp,lsz,tm,hb,ab))
            if cur.rowcount: print(f"PAPER LAY DRAW {ev} [{comp}] {minute}' @ {lp} (£{lsz} avail)",flush=True)
        # ---- exits on goals (book jump), 120 s later at the draw back price
        cur.execute("SELECT id, market_id, lay_px, entry_ts FROM ltd_inplay_paper WHERE exit_ts IS NULL")
        for pid,mid,lp,ets in cur.fetchall():
            g=first_goal_after(mid,ets)
            if not g: continue
            gts=g[0]
            cur.execute("SELECT back_px, ts FROM liq_sample WHERE market_id=%s AND mkt='MO' AND sel='DRAW' AND ts>=%s+interval '120 seconds' AND back_px IS NOT NULL AND lay_px IS NOT NULL AND lay_px<=back_px*1.2 ORDER BY ts LIMIT 1",(mid,gts))
            r=cur.fetchone()
            if not r: continue
            bp,xts=r; pnl=pnl_hedge(float(lp),float(bp))
            cur.execute("UPDATE ltd_inplay_paper SET goal_ts=%s, exit_ts=%s, exit_px=%s, exit_reason='GOAL', pnl_per_10=%s, det='book-v2' WHERE id=%s",(gts,xts,bp,pnl,pid)); print(f"EXIT GOAL {mid} lay {lp} -> back {bp} = {pnl:+.2f}",flush=True)
        # ---- settle closed markets (no sample for 20 min) from the last sane book at 85'+
        cur.execute("""SELECT p.id, p.market_id, p.lay_px FROM ltd_inplay_paper p WHERE p.exit_ts IS NULL AND p.entry_ts < now()-interval '40 minutes'
                       AND NOT EXISTS (SELECT 1 FROM liq_sample s WHERE s.market_id=p.market_id AND s.ts>now()-interval '20 minutes')""")
        for pid,mid,lp in cur.fetchall():
            fin=final_book(mid)
            if not fin: continue
            w=min(fin,key=fin.get)
            if fin[w]>1.15: reason,pnl='UNKNOWN',None
            elif w=='DRAW': reason,pnl='SETTLE_LOSS',round(-STAKE*(float(lp)-1),2)
            else: reason,pnl='SETTLE_WIN',round(STAKE*(1-COMM),2)
            cur.execute("UPDATE ltd_inplay_paper SET exit_ts=now(), exit_px=%s, exit_reason=%s, pnl_per_10=%s, det='book-v2' WHERE id=%s",(fin.get('DRAW'),reason,pnl,pid))
        if time.time()-last_hb>60:
            cur.execute("INSERT INTO ltd_heartbeat VALUES (1,now(),(SELECT count(*) FROM ltd_inplay_paper WHERE exit_ts IS NULL),(SELECT count(*) FROM ltd_inplay_paper WHERE entry_ts::date=current_date)) ON CONFLICT (id) DO UPDATE SET last_seen=now(), open_trades=EXCLUDED.open_trades, today=EXCLUDED.today"); last_hb=time.time()
        time.sleep(20)
    except Exception as e:
        print("loop",repr(e)[:200],flush=True); time.sleep(20)
        try: con=connect(); cur=con.cursor()
        except Exception: pass
PYFILE
python3 -m py_compile /root/pe-ltd/ltd_paper.py
echo "== re-open paper exits taken on the old goal signal"
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require'); c.autocommit=True; k=c.cursor()
k.execute("ALTER TABLE ltd_inplay_paper ADD COLUMN IF NOT EXISTS goal_ts TIMESTAMPTZ; ALTER TABLE ltd_inplay_paper ADD COLUMN IF NOT EXISTS det TEXT")
k.execute("UPDATE ltd_inplay_paper SET exit_ts=NULL, exit_px=NULL, exit_reason=NULL, pnl_per_10=NULL, det='reopened-v2' WHERE exit_reason IN ('GOAL','SETTLE_WIN','SETTLE_LOSS','UNKNOWN') AND coalesce(det,'')<>'book-v2'"); print("re-opened:",k.rowcount)
PY
pkill -f ltd_paper.py || true; sleep 2; /root/pe-ltd/keepalive.sh
echo "== real-order bot: book-based goal detection + settlement from all runners"
python3 - <<'PY'
p='/root/pe-ltd/ltd_live.py'; s=open(p).read(); n=0
old1="            prev=dstate.get(mid); dstate[mid]=(ltp,b.get('status'),now)\n            goal_now = prev is not None and ltp and prev[0] and (ltp>=prev[0]*1.25)\n"
new1="""            dbk=bk[0]['price'] if bk else None; dly=ly[0]['price'] if ly else None
            sane = dbk is not None and dly is not None and dly<=dbk*1.2
            prev=dstate.get(mid)
            if sane: dstate[mid]=(dbk,dly,now)
            goal_now = sane and prev is not None and dbk>=prev[0]*1.25 and dbk>=prev[1]*1.25
            if sane:
                fb={}
                for s_,r_ in rs.items():
                    bb=(r_.get('ex',{}).get('availableToBack') or [{}])[0].get('price'); ll=(r_.get('ex',{}).get('availableToLay') or [{}])[0].get('price')
                    if bb and ll and ll<=bb*1.2: fb[s_]=bb
                if len(fb)==3 and minute>=85: lastbook[mid]=fb
"""
if old1 in s: s=s.replace(old1,new1,1); n+=1
old2="""                    won=(ltp is not None and ltp<=1.1)
                    pnl=round((-t['lay_size']*(t['lay_px']-1)) if won else t['lay_size']*(1-COMM),2)
                    cur.execute("UPDATE ltd_live_trades SET exited_at=%s, exit_reason=%s, pnl=%s, status='CLOSED' WHERE id=%s",(now,'SETTLE_LOSS' if won else 'SETTLE_WIN',pnl,t['id'])); open_tr.pop(key)
"""
new2="""                    fb=lastbook.get(mid,{})
                    if not fb: reason,pnl='UNKNOWN',None
                    else:
                        wsel=min(fb,key=fb.get)
                        if fb[wsel]>1.15: reason,pnl='UNKNOWN',None
                        elif wsel==meta['draw']: reason,pnl='SETTLE_LOSS',round(-t['lay_size']*(t['lay_px']-1),2)
                        else: reason,pnl='SETTLE_WIN',round(t['lay_size']*(1-COMM),2)
                    cur.execute("UPDATE ltd_live_trades SET exited_at=%s, exit_reason=%s, pnl=%s, status='CLOSED' WHERE id=%s",(now,reason,pnl,t['id'])); open_tr.pop(key)
"""
if old2 in s: s=s.replace(old2,new2,1); n+=1
if "lastbook={}" not in s: s=s.replace("open_tr={}; last_cat=0; cat={}; last_hb=0; dstate={}","open_tr={}; last_cat=0; cat={}; last_hb=0; dstate={}; lastbook={}",1); n+=1
# a goal before entry: the draw's best back jumped 25%+ between two sane reads earlier in this process -> remember per market
old3="            cur.execute(\"SELECT 1 FROM liq_goal_depth WHERE market_id=%s AND mkt='MO' LIMIT 1\",(mid,))\n            if cur.fetchone(): continue                      # a goal already happened\n"
new3="""            if goal_now or mid in goaled: goaled.add(mid); continue   # a goal already happened (book jump seen by this process)
            cur.execute(\"\"\"WITH d AS (SELECT back_px, lag(back_px) OVER (ORDER BY ts) pb, lag(lay_px) OVER (ORDER BY ts) pl FROM liq_sample WHERE market_id=%s AND mkt='MO' AND sel='DRAW' AND back_px IS NOT NULL AND lay_px IS NOT NULL AND lay_px<=back_px*1.2)
                           SELECT 1 FROM d WHERE pb IS NOT NULL AND back_px>=pb*1.25 AND back_px>=pl*1.25 LIMIT 1\"\"\",(mid,))
            if cur.fetchone(): goaled.add(mid); continue              # a goal already happened (recorder's book history)
"""
if old3 in s: s=s.replace(old3,new3,1); n+=1
if "goaled=set()" not in s: s=s.replace("lastbook={}","lastbook={}; goaled=set()",1); n+=1
if "if goal_now: goaled.add(mid)" not in s:
    s=s.replace("            key=mid\n","            key=mid\n            if goal_now: goaled.add(mid)\n",1); n+=1
# the real-order bot also settles Banga-style stale wins: re-open today's SETTLE rows for re-settlement is not possible (no book kept) -> mark them
open(p,'w').write(s); print("live bot patches:",n)
PY
python3 -m py_compile /root/pe-ltd/ltd_live.py
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require'); c.autocommit=True; k=c.cursor()
k.execute("UPDATE ltd_live_trades SET note='settled from stale LTP (v1) - disregard' WHERE exit_reason IN ('SETTLE_WIN','SETTLE_LOSS') AND entered_at<now()"); print("live-dry settle rows marked:",k.rowcount)
PY
pkill -f ltd_live.py || true; sleep 2; /root/pe-ltd/keepalive_live.sh
sleep 60; pgrep -af "ltd_paper|ltd_live" | head; tail -4 /root/pe-ltd/ltd.log
echo "== live-ladder replay v3 with book-based goals (same markets as 192)"
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys, psycopg2, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',220); COMM=0.02; JUMP=1.25
con=psycopg2.connect(DB,sslmode='require')
mk=pd.read_sql("SELECT market_id FROM liq_sample WHERE mkt='MO' GROUP BY market_id HAVING min(minute)<=5 AND max(minute)>=88",con); mids=list(mk.market_id); print("markets:",len(mids))
S=pd.read_sql("SELECT market_id, event_name, competition, ts, minute, sel, back_px::float bp, lay_px::float lp, lay_sz::float lsz, total_matched::float tm FROM liq_sample WHERE mkt='MO' AND market_id = ANY(%s) AND back_px IS NOT NULL AND lay_px IS NOT NULL AND lay_px<=back_px*1.2 ORDER BY market_id, ts",con,params=(mids,))
rows=[]
for mid,g in S.groupby('market_id',sort=False):
    d=g[g.sel=='DRAW'].copy(); h=g[g.sel=='HOME']; a=g[g.sel=='AWAY']
    if len(d)<10 or h.empty or a.empty: continue
    d['pb']=d.bp.shift(); d['pl']=d.lp.shift(); jumps=d[(d.bp>=d.pb*JUMP)&(d.bp>=d.pl*JUMP)].ts.tolist()
    late=g[g.minute>=85]
    if late.empty: continue
    lt=late.ts.max(); fin={r.sel:r.bp for r in late[late.ts==lt].itertuples()}
    if len(fin)<3: continue
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
