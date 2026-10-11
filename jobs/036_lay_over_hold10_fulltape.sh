#!/bin/bash
# 036: CROSS-CHECK. 031/034 found "lay Over 2.5 at level score, minutes 20-75, exit goal+3 or +10 min" at +7/+16 per £100 on the 689-match
# xG subset — and in EVERY xG quartile, so xG is not the driver. Before believing it: the identical trade on the FULL tape (37k matches,
# two seasons, no xG filter), same costs, same exits, honest exit accounting. If the full tape says ~0, the subset number is a dataset artefact.
cd /root/pe-scan && cat > lay_over_hold10.py <<'PYFILE'
import re, sys, math, datetime, collections, psycopg2, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
SPREAD=0.02; COMM=0.02
def norm(s): return re.sub(r'[^a-z]','',(s or '').lower().split(' ')[0])
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor()
cur.execute("SELECT match_date, competition, home_team, away_team, goal_times, mo_home_back FROM fts_advanced_results WHERE match_date>='2024-08-01'")
TOP={'English Premier League','Spanish Primera Division','Italian Serie A','German Bundesliga','French Ligue 1'}
G={}
for d,lg,h,a,gt,ph in cur.fetchall():
    d=datetime.date.fromisoformat(str(d)[:10]); goals=[]
    for t in (gt or '').split('|'):
        mm=re.match(r"\s*(\d+)(?:\+(\d+))?\((H|A)\)",t)
        if mm: goals.append((int(mm.group(1))+int(mm.group(2) or 0),mm.group(3)))
    G[(d,norm(h),norm(a))]=(sorted(goals),'tier1' if lg in TOP else 'tier2')
con_s=psycopg2.connect(DB,sslmode='require'); scur=con_s.cursor(name='tape'); scur.itersize=50000
scur.execute("SELECT event_id,hw,aw,m,minute,sel,ltp FROM bf_hist_price WHERE ht_offset IS NOT NULL AND mkt='OU25' AND sel='OVER' ORDER BY event_id,m")
rows=[]; n_seen=0; n_j=0
def tp_lay(e,x): p=1-(e*(1+SPREAD))/(x*(1-SPREAD)); return p*(1-COMM) if p>0 else p
def process(rs):
    global n_seen,n_j
    n_seen+=1
    hw,aw=norm(rs[0][1]),norm(rs[0][2]); d=rs[0][3].date()
    rec=G.get((d,hw,aw)) or G.get((d-datetime.timedelta(days=1),hw,aw)) or G.get((d+datetime.timedelta(days=1),hw,aw))
    if n_seen==300:
        print(f"SELF-CHECK after 300 events: {n_j} joined",flush=True)
        if n_j<30: sys.exit("ABORT join")
    if not rec: return
    n_j+=1; goals,tier=rec; gl=[g for g,_ in goals]
    px={int(r[4]):float(r[6]) for r in rs if r[6] and r[6]>1.0}
    season='2024/25' if d<datetime.date(2025,7,1) else '2025/26'
    for t in range(20,76,5):
        if any(0<=t-g<3 for g in gl): continue
        sh=sum(1 for g,s in goals if g<=t and s=='H'); sa=sum(1 for g,s in goals if g<=t and s=='A')
        if sh!=sa: continue
        e=px.get(t)
        if not e or e<1.2 or e>8: continue
        nxt=[g for g in gl if g>t]; gw=bool(nxt and nxt[0]<=t+10); xt=(nxt[0]+3) if gw else t+10
        x=None; how='none'
        for k in range(xt-2,xt+4):
            if k in px: x=px[k]; how='fresh'; break
        if x is None:
            win=[px[k] for k in range(xt,xt+16) if k in px]
            if win: x=min(win); how='worst15'
        rows.append((season,tier,t,sh+sa,e,x,gw,how,tp_lay(e,x) if x else np.nan))
buf=[]; last=None
for r in scur:
    if last is not None and r[0]!=last: process(buf); buf=[]
    buf.append(r); last=r[0]
if buf: process(buf)
D=pd.DataFrame(rows,columns=['season','tier','t','goals','entry','exit','goal_in_10','how','pnl'])
print(f"events {n_seen}, joined {n_j}, trades {len(D)}")
pd.set_option('display.width',250)
print("\nexit accounting:"); print(pd.crosstab([D.season,D.goal_in_10],D.how).to_string())
V=D[D.pnl.notna()]
def show(by,title):
    T=V.groupby(by+['season']).pnl.agg(['size','mean']).unstack('season'); T.columns=[f"{a}_{b}" for a,b in T.columns]
    for c in [c for c in T.columns if c.startswith('mean')]: T[c]=(100*T[c]).round(1)
    print(f"\n{title} (lay Over 2.5 at level score, exit goal+3 or +10 min; P&L per £100 stake)"); print(T.to_string())
print("\nOVERALL:"); print(V.groupby('season').pnl.agg(['size','mean']).assign(mean=lambda x:(100*x['mean']).round(1), goal10=V.groupby('season').goal_in_10.mean().round(3)).to_string())
show(['tier'],'by tier'); show(['t'],'by entry minute'); show(['goals'],'by goals so far'); V['pxb']=pd.cut(V.entry,[1.2,1.5,1.8,2.2,3,4,8]); show(['pxb'],'by Over price')
print("\nIf this is ~0 on the full tape, the +7/+16 on the xG subset was a dataset artefact (the backfill's fixtures/minutes are not a random sample).")
PYFILE
python3 lay_over_hold10.py
