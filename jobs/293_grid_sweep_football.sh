#!/bin/bash
# 293: THE GRID — breadth testing by machine. Every mapped API-Football game (af_price_map, 291) x every 5-minute entry point x
# every observable state (score diff, total goals, red cards, pre-match favourite band, league) x every market/selection on the
# tape (MO, OU15, OU25, OU35, BTTS) x back AND lay x four exits (hold to settle, next goal, +15 min, half-time). Prices one tick
# adverse at entry and exit, 2% commission, risk £10 per trade. Season 2024 = half 1, season 2025 = half 2 (true hold-out).
# Output: grid_cells (sums per cell per season) + grid_survivors. The log prints SURVIVORS ONLY (n>=600, t>=3.5, both seasons >0,
# mean >= +£0.15 per £10) at five roll-up levels; everything else stays in the table.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,math,psycopg2,psycopg2.extras,pandas as pd,numpy as np
from collections import defaultdict
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET statement_timeout='3000s'")
try: cur.execute("SELECT count(*) FROM af_price_map"); nmap=cur.fetchone()[0]
except Exception: print("map missing — waiting for 291"); sys.exit(75)
if nmap<1000: print("map too small",nmap); sys.exit(75)
G=pd.read_sql("""SELECT m.event_id, f.fixture_id, f.season, f.league, f.hg, f.ag FROM af_price_map m
 JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL""",con)
print("games:",len(G),"| seasons:",G.season.value_counts().to_dict(),flush=True)
EV=pd.read_sql("""SELECT fixture_id, coalesce(minute,0) minute, is_home, type, detail FROM af_events
 WHERE fixture_id = ANY(%s) AND ((type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal')) OR (type='Card' AND detail='Red Card'))""",con,params=(list(map(int,G.fixture_id)),))
goals=defaultdict(list); reds=defaultdict(list)
for r in EV.itertuples():
    if r.type=='Goal':
        side = ('h' if r.is_home else 'a') if r.detail!='Own Goal' else ('a' if r.is_home else 'h')
        goals[r.fixture_id].append((int(r.minute),side))
    else: reds[r.fixture_id].append((int(r.minute),'h' if r.is_home else 'a'))
for d in (goals,reds):
    for k in d: d[k].sort()
def tick(p): return 0.01 if p<2 else 0.02 if p<3 else 0.05 if p<4 else 0.1 if p<6 else 0.2 if p<10 else 0.5 if p<20 else 1 if p<30 else 2 if p<50 else 5 if p<100 else 10
MK={'MO':('HOME','DRAW','AWAY'),'OU15':('OVER','UNDER'),'OU25':('OVER','UNDER'),'OU35':('OVER','UNDER'),'BTTS':('YES','NO')}
def settled(mkt,sel,hg,ag):
    tot=hg+ag
    if mkt=='MO': return (hg>ag) if sel=='HOME' else (hg<ag) if sel=='AWAY' else hg==ag
    if mkt=='BTTS': return (hg>0 and ag>0)==(sel=='YES')
    line=float(mkt[2]+'.'+mkt[3]); return (tot>line)==(sel=='OVER')
def pnl(side,p,q,won):
    # risk £10. back: stake 10. lay: liability 10. q=None -> settle. one tick adverse both ends. 2% commission on profit.
    if side=='B':
        p=p-tick(p)
        if p<=1.01: return None
        if q is None: r=10*(p-1) if won else -10.0
        else: q=q+tick(q); r=10*(p/q-1)
    else:
        p=p+tick(p); s=10/(p-1)
        if q is None: r=s if not won else -10.0
        else: q=max(1.01,q-tick(q)); r=s*(1-p/q)
    return r*0.98 if r>0 else r
def favband(f): return '<1.5' if f<1.5 else '1.5-2' if f<2 else '2-3' if f<3 else '3+'
ENTRIES=list(range(0,90,5)); EXITS=('SETTLE','NEXTGOAL','T15','HT')
cells=defaultdict(lambda:[0,0.0,0.0]); lcells=defaultdict(lambda:[0,0.0,0.0]); t0=time.time(); ng=0; ntr=0
for i in range(0,len(G),1500):
    sub=G.iloc[i:i+1500]
    P=pd.read_sql("SELECT event_id, minute, mkt, sel, ltp::float ltp FROM bf_hist_price WHERE mkt IN ('MO','OU15','OU25','OU35','BTTS') AND event_id = ANY(%s) AND minute BETWEEN 0 AND 95 AND ltp>1.01 AND ltp<200",con,params=(list(sub.event_id),))
    P=P.sort_values(['event_id','mkt','sel','minute'])
    px={}
    for (eid,mkt,sel),g in P.groupby(['event_id','mkt','sel'],sort=False):
        arr=np.full(97,np.nan); arr[g.minute.values]=g.ltp.values
        # forward fill (last known price up to 3 minutes old)
        last=np.nan; age=99
        for m in range(97):
            if not np.isnan(arr[m]): last=arr[m]; age=0
            else:
                age+=1
                if age<=3: arr[m]=last
        px.setdefault(eid,{})[(mkt,sel)]=arr
    for g in sub.itertuples():
        book=px.get(g.event_id)
        if not book: continue
        mo_h=book.get(('MO','HOME')); mo_a=book.get(('MO','AWAY'))
        if mo_h is None or mo_a is None or np.isnan(mo_h[1]) or np.isnan(mo_a[1]): continue
        fav=min(mo_h[1],mo_a[1]); fb=favband(fav); favside='H' if mo_h[1]<=mo_a[1] else 'A'
        gl=goals.get(g.fixture_id,[]); rl=reds.get(g.fixture_id,[]); hg,ag=int(g.hg),int(g.ag); ng+=1
        lg=g.league; season=int(g.season)
        for t in ENTRIES:
            h=sum(1 for m,s in gl if m<=t and s=='h'); a=sum(1 for m,s in gl if m<=t and s=='a')
            diff=max(-2,min(2,h-a)); tot=min(3,h+a)
            red='none'
            for m,s in rl:
                if m<=t: red=s
            nxt=next((m for m,s in gl if m>t),None)
            exits={'SETTLE':None,'NEXTGOAL':(nxt+1 if nxt is not None and nxt+1<=95 else None),'T15':(t+16 if t+16<=90 else None),'HT':(46 if t<45 else 'skip')}
            for (mkt,sel),arr in book.items():
                p=arr[t+1]
                if np.isnan(p) or p>50: continue
                won=settled(mkt,sel,hg,ag)
                for ex,qm in exits.items():
                    if qm=='skip': continue
                    q=None
                    if qm is not None:
                        q=arr[qm]
                        if np.isnan(q): continue
                    for side in ('B','L'):
                        r=pnl(side,p,q,won)
                        if r is None: continue
                        ntr+=1
                        c=cells[(mkt,sel,side,ex,t//10*10,diff,tot,red,fb,season)]; c[0]+=1; c[1]+=r; c[2]+=r*r
                        c=lcells[(mkt,sel,side,ex,t//15*15,diff,fb,lg,season)]; c[0]+=1; c[1]+=r; c[2]+=r*r
    print(f"  {min(i+1500,len(G))}/{len(G)} games | {ng} priced | trades {ntr} | cells {len(cells)} | {int(time.time()-t0)}s",flush=True)
cur.execute("""DROP TABLE IF EXISTS grid_cells; CREATE TABLE grid_cells (mkt TEXT, sel TEXT, side TEXT, exit TEXT, tband INT, diff INT, tot INT, red TEXT, fav TEXT, season INT, n INT, s DOUBLE PRECISION, ss DOUBLE PRECISION);
DROP TABLE IF EXISTS grid_cells_league; CREATE TABLE grid_cells_league (mkt TEXT, sel TEXT, side TEXT, exit TEXT, tband INT, diff INT, fav TEXT, league TEXT, season INT, n INT, s DOUBLE PRECISION, ss DOUBLE PRECISION)""")
psycopg2.extras.execute_values(cur,"INSERT INTO grid_cells VALUES %s",[k+tuple(v) for k,v in cells.items()],page_size=5000)
psycopg2.extras.execute_values(cur,"INSERT INTO grid_cells_league VALUES %s",[k+tuple(v) for k,v in lcells.items()],page_size=5000)
print(f"stored {len(cells)} cells + {len(lcells)} league cells from {ng} games, {ntr} trades",flush=True)
# ---- roll-ups and survivors
def rollup(table,dims):
    d=",".join(dims)
    q=f"""WITH a AS (SELECT {d}, season, sum(n) n, sum(s) s, sum(ss) ss FROM {table} GROUP BY {d}, season)
    SELECT {d}, sum(n) n, sum(s)/sum(n) mean,
      (sum(s)/sum(n)) / NULLIF(sqrt(GREATEST(sum(ss)/sum(n) - power(sum(s)/sum(n),2),1e-9)/sum(n)),0) t,
      sum(s) FILTER (WHERE season=2024)/NULLIF(sum(n) FILTER (WHERE season=2024),0) h1,
      sum(s) FILTER (WHERE season=2025)/NULLIF(sum(n) FILTER (WHERE season=2025),0) h2,
      sum(n) FILTER (WHERE season=2025) n2
    FROM a GROUP BY {d} HAVING sum(n)>=600"""
    r=pd.read_sql(q,con); r['level']='+'.join(dims[4:]) if len(dims)>4 else 'base'
    return r
levels=[('grid_cells',['mkt','sel','side','exit','tband']),('grid_cells',['mkt','sel','side','exit','tband','diff']),
        ('grid_cells',['mkt','sel','side','exit','tband','diff','tot']),('grid_cells',['mkt','sel','side','exit','tband','diff','fav']),
        ('grid_cells',['mkt','sel','side','exit','tband','diff','red']),('grid_cells',['mkt','sel','side','exit','tband','diff','tot','fav']),
        ('grid_cells_league',['mkt','sel','side','exit','tband','diff','league']),('grid_cells_league',['mkt','sel','side','exit','tband','diff','fav','league'])]
allr=[];
for tb,dims in levels:
    r=rollup(tb,dims); allr.append(r)
R=pd.concat(allr,ignore_index=True)
S=R[(R.t>=3.5)&(R.h1>0)&(R.h2>0)&(R['mean']>=0.15)&(R.n2>=200)].sort_values('t',ascending=False)
cur.execute("DROP TABLE IF EXISTS grid_survivors; CREATE TABLE grid_survivors (run_date DATE DEFAULT current_date, level TEXT, mkt TEXT, sel TEXT, side TEXT, exit TEXT, tband INT, diff INT, tot INT, red TEXT, fav TEXT, league TEXT, n INT, mean NUMERIC, t NUMERIC, h1 NUMERIC, h2 NUMERIC)")
for r in S.to_dict('records'):
    def v(k,cast=None):
        x=r.get(k); 
        if x is None or (isinstance(x,float) and math.isnan(x)): return None
        return cast(x) if cast else x
    cur.execute("INSERT INTO grid_survivors (level,mkt,sel,side,exit,tband,diff,tot,red,fav,league,n,mean,t,h1,h2) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",
      (r['level'],r['mkt'],r['sel'],r['side'],r['exit'],v('tband',int),v('diff',int),v('tot',int),v('red'),v('fav'),v('league'),int(r['n']),round(float(r['mean']),3),round(float(r['t']),2),round(float(r['h1']),3),round(float(r['h2']),3)))
print(f"\n==== GRID: {len(R)} cells tested at n>=600 across {len(levels)} levels | SURVIVORS: {len(S)} ====")
if len(S)==0: print("no survivors this run")
else:
    cols=['level','mkt','sel','side','exit','tband','diff','tot','red','fav','league','n','mean','t','h1','h2']
    print(S[[c for c in cols if c in S.columns]].head(60).round(3).to_string(index=False))
PY
