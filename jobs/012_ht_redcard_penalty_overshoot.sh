#!/bin/bash
# 012: overshoot after HALF-TIME restart, RED CARDS and PENALTIES — same method as 004 (price at +30/60/120s after the
# market reopens vs the price 8-10 min later; fade at +60s, exit at 10 min; 2pct spread, 2pct comm; train 2024/25, test 2025/26).
# Half-time: found from the tape itself (the HT suspension = longest trade gap between Betfair-clock minutes 40-70).
# Red cards / penalties: ONLY if fts_advanced_results (or any table) carries them. The job checks the schema first and says
# NOT AVAILABLE if not, rather than guessing.
cd /root/pe-scan && cat > ht_overshoot.py <<'PYFILE'
import os, bz2, json, glob, re, datetime, collections, sys, psycopg2, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
ROOT='/root/bfdata'; SPREAD=0.02; COMM=0.02
def norm(s): return re.sub(r'[^a-z]','',(s or '').lower().split(' ')[0])
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor()
# ---- schema check for red cards / penalties ----
cur.execute("SELECT table_name, column_name FROM information_schema.columns WHERE table_schema='public' AND (column_name ILIKE '%red%' OR column_name ILIKE '%card%' OR column_name ILIKE '%pen%' OR column_name ILIKE '%sent%off%' OR column_name ILIKE '%event%type%')")
ev_cols=cur.fetchall()
print("columns that could hold red cards / penalties:",ev_cols)
cur.execute("SELECT table_name FROM information_schema.tables WHERE table_schema='public' AND (table_name ILIKE '%event%' OR table_name ILIKE '%card%' OR table_name ILIKE '%incident%')")
print("tables that could hold match events:",cur.fetchall())
EVENTS={}  # (date,home,away) -> list of (minute, kind, side)
for tbl,col in ev_cols:
    if tbl=='fts_advanced_results' and col in ('home_red_cards','away_red_cards','red_cards','penalties','home_pens','away_pens'):
        print("NOTE: count columns only (no minute) -> cannot time the overshoot from",tbl,col)
if not EVENTS:
    print("RED CARDS / PENALTIES: NOT AVAILABLE with minute stamps in any table. Needs an events backfill (API-Football fixtures/events or Sofascore incidents) before this can be tested.")
# ---- goals (to flag 'clean' windows) ----
cur.execute("SELECT match_date, home_team, away_team, goal_times, ft_home, ft_away FROM fts_advanced_results WHERE match_date>='2024-08-01'")
G={}
for d,h,a,gt,fh,fa in cur.fetchall():
    d=datetime.date.fromisoformat(str(d)[:10]); goals=[]
    for t in (gt or '').split('|'):
        mm=re.match(r"\s*(\d+)(?:\+(\d+))?\((H|A)\)",t)
        if mm: goals.append((int(mm.group(1))+int(mm.group(2) or 0),mm.group(3)))
    G[(d,norm(h),norm(a))]=(sorted(goals),int(fh),int(fa))
rows=[]; files=0; used=0; n_ht=0
for path in glob.glob(ROOT+'/**/*.bz2',recursive=True):
    if '/ext/' in path: continue
    try: lines=bz2.open(path,'rt').read().split('\n')
    except Exception: continue
    md=None; runners={}; ltp=collections.defaultdict(list); ko=None
    for ln in lines:
        if not ln: continue
        try: o=json.loads(ln)
        except: continue
        pt=o.get('pt')
        for mc in o.get('mc',[]):
            if 'marketDefinition' in mc:
                m=mc['marketDefinition']
                if m.get('marketType') not in ('MATCH_ODDS','OVER_UNDER_25'): md=False; break
                md=m; runners.update({r['id']:r['name'] for r in m.get('runners',[])})
                if m.get('inPlay') and ko is None: ko=pt
            for rc in mc.get('rc',[]):
                if 'ltp' in rc: ltp[rc['id']].append((pt,rc['ltp']))
        if md is False: break
    if not md or ko is None: continue
    files+=1
    if files==400:
        print(f"SELF-CHECK after 400 files: {used} joined, {n_ht} HT restarts measured",flush=True)
        if used<20: sys.exit("ABORT join")
    ev=md.get('eventName',''); eid=str(md.get('eventId'))
    if ' v ' not in ev: continue
    h,a=ev.split(' v ',1)
    try: d=datetime.date.fromisoformat((md.get('openDate') or '')[:10])
    except: continue
    rec=G.get((d,norm(h),norm(a))) or G.get((d-datetime.timedelta(days=1),norm(h),norm(a)))
    if not rec: continue
    used+=1; goals,fh,fa=rec; mt=md['marketType']
    season='2024/25' if d<datetime.date(2025,7,1) else '2025/26'
    # HT restart from the tape: all trades across runners between clock minutes 40 and 70, longest gap >= 8 min
    allt=sorted(pt for s in ltp.values() for pt,p in s if ko+40*60000<=pt<=ko+70*60000)
    if len(allt)<10: continue
    gaps=[(allt[i+1]-allt[i],allt[i],allt[i+1]) for i in range(len(allt)-1)]
    gap,tend,trestart=max(gaps)
    if gap<8*60000: continue
    ht_h=sum(1 for g,s in goals if g<=45 and s=='H'); ht_a=sum(1 for g,s in goals if g<=45 and s=='A')
    later=[g for g,s in goals if 46<=g<=56]   # goal in the first 10 min of the second half
    def role(name):
        n=name.lower()
        if mt=='OVER_UNDER_25': return 'OVER' if n.startswith('over') else 'UNDER'
        if 'draw' in n: return 'DRAW'
        return 'HOME' if norm(name)==norm(h) else 'AWAY'
    for sid,name in runners.items():
        series=ltp.get(sid,[])
        pre=[p for pt,p in series if tend-240000<=pt<=tend]
        post=[(pt,p) for pt,p in series if pt>=trestart-5000]
        if not pre or not post: continue
        p0=pre[-1]; t0=post[0][0]; first=post[0][1]
        def at(sec):
            c=[p for pt,p in post if t0+sec*1000-20000<=pt<=t0+sec*1000+40000]
            return c[-1] if c else None
        settle=[p for pt,p in post if t0+480000<=pt<=t0+600000]
        if not settle: continue
        n_ht+=1
        rows.append((season,mt,role(name),f"{min(ht_h,3)}-{min(ht_a,3)}",p0,first,at(30),at(60),at(120),settle[-1],bool(later)))
    if files%3000==0: print("files",files,"joined",used,"HT rows",len(rows),flush=True)
print(f"\nfiles {files}, joined {used}, HT runner rows {len(rows)}",flush=True)
D=pd.DataFrame(rows,columns=['season','mkt','sel','ht_score','pre','first','p30','p60','p120','p10m','goal_within_10'])
D.to_csv('/root/pe-scan/ht_overshoot_rows.csv',index=False)
for c in ('first','p30','p60','p120'):
    D['os_'+c]=(D[c]-D.p10m)/(D.pre-D.p10m).replace(0,np.nan)
D['move']=(D['first']/D.pre-1)
pd.set_option('display.width',250)
print("\nHALF-TIME: size of the reopen move (first trade after the break vs last before it), median abs pct by market/sel:")
print(D.groupby(['mkt','sel','season']).move.apply(lambda x:(100*x.abs().median())).round(2).to_string())
print("\nOVERSHOOT at HT restart (share of the pre->10min move still present at +Xs; >0 reverts). Clean (no goal 46-56 min):")
C=D[~D.goal_within_10]
print(C.groupby(['mkt','sel','season'])[['os_first','os_p30','os_p60','os_p120']].median().round(3).to_string())
def fade(r):
    e=r.p60; x=r.p10m
    if pd.isna(e) or pd.isna(x) or e<=1.01 or x<=1.01 or abs(r.move)<0.03: return np.nan   # only when the restart actually moved the price 3pct+
    if e>r.pre: pnl=(e*(1-SPREAD))/(x*(1+SPREAD))-1
    else: pnl=1-(e*(1+SPREAD))/(x*(1-SPREAD))
    return pnl*(1-COMM) if pnl>0 else pnl
print("\nFADE P&L per £100 at +60s after HT restart (moves of 3pct+ only), exit at 10 min. Clean, by market/sel/HT score, train vs test:")
C=C.assign(pnl=C.apply(fade,axis=1)); C=C[C.pnl.notna()]
T=C.groupby(['mkt','sel','ht_score','season']).pnl.agg(['size','mean']).unstack('season')
T.columns=['n_tr','n_te','per100_tr','per100_te']; T[['per100_tr','per100_te']]*=100
T=T[(T.n_tr>=100)&(T.n_te>=40)].round(1)
print(T.sort_values('per100_te',ascending=False).to_string())
S=T[(T.per100_tr>2)&(T.per100_te>2)]
print(f"\nSURVIVORS positive both seasons: {len(S)} of {len(T)} cells (chance ~{int(len(T)*0.25*0.4)})")
print(S.to_string())
A=D.assign(pnl=D.apply(fade,axis=1)); A=A[A.pnl.notna()]
print("\nSame fade INCLUDING a goal in 46-56 min (honest P&L):")
print(A.groupby(['mkt','sel','season']).pnl.agg(['size','mean']).assign(mean=lambda x:(100*x['mean']).round(1)).to_string())
PYFILE
python3 ht_overshoot.py
