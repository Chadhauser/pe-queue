#!/bin/bash
# 004: STAGE 2b — goal overshoot. From the raw Basic files (sub-minute LTP), for every goal: the price of each MO/OU2.5
# selection at +30s/+60s/+120s after the first post-goal trade vs the price 8-10 minutes later. Overshoot = early price
# relative to settled price. Also the P&L of fading the move: trade at +Xs, exit at the 10-min price. 2pct spread, 2pct comm.
cd /root/pe-scan && cat > goal_overshoot.py <<'PYFILE'
import os, bz2, json, glob, re, datetime, collections, sys, psycopg2, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
ROOT='/root/bfdata'; SPREAD=0.02; COMM=0.02
def norm(s): return re.sub(r'[^a-z]','',(s or '').lower().split(' ')[0])
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor()
cur.execute("SELECT event_id, max(ht_offset) FROM bf_hist_price GROUP BY event_id"); HTO=dict(cur.fetchall())
cur.execute("SELECT match_date, home_team, away_team, goal_times, ft_home, ft_away FROM fts_advanced_results WHERE match_date>='2024-08-01'")
G={}
for d,h,a,gt,fh,fa in cur.fetchall():
    d=datetime.date.fromisoformat(str(d)[:10]); goals=[]
    for t in (gt or '').split('|'):
        mm=re.match(r"\s*(\d+)(?:\+(\d+))?\((H|A)\)",t)
        if mm: goals.append((int(mm.group(1))+int(mm.group(2) or 0),mm.group(3)))
    G[(d,norm(h),norm(a))]=(sorted(goals),int(fh),int(fa))
rows=[]; files=0; used=0; n_goals=0
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
        print(f"SELF-CHECK after 400 files: {used} joined, {n_goals} goals measured",flush=True)
        if used<20: sys.exit("ABORT join")
    ev=md.get('eventName',''); eid=str(md.get('eventId'))
    if ' v ' not in ev: continue
    h,a=ev.split(' v ',1)
    try: d=datetime.date.fromisoformat((md.get('openDate') or '')[:10])
    except: continue
    rec=G.get((d,norm(h),norm(a))) or G.get((d-datetime.timedelta(days=1),norm(h),norm(a)))
    if not rec: continue
    used+=1; goals,fh,fa=rec; hto=HTO.get(eid) or 19.5; mt=md['marketType']
    season='2024/25' if d<datetime.date(2025,7,1) else '2025/26'
    def role(name):
        n=name.lower()
        if mt=='OVER_UNDER_25': return 'OVER' if n.startswith('over') else 'UNDER'
        if 'draw' in n: return 'DRAW'
        return 'HOME' if norm(name)==norm(h) else 'AWAY'
    for gi,(g,side) in enumerate(goals):
        bfmin=g if g<=45 else g+hto
        tg=ko+bfmin*60000
        sh=sum(1 for x,s in goals[:gi+1] if s=='H'); sa=sum(1 for x,s in goals[:gi+1] if s=='A')
        for sid,name in runners.items():
            series=ltp.get(sid,[])
            pre=[p for pt,p in series if tg-240000<=pt<tg-30000]          # last trades 0.5-4 min BEFORE the goal (clock error tolerance)
            post=[(pt,p) for pt,p in series if pt>=tg-30000]
            if not pre or not post: continue
            # first post-goal trade = first trade after the goal where price moved >=10 pct vs pre (suspension reopen)
            p0=pre[-1]; first=None
            for pt,p in post:
                if abs(p/p0-1)>=0.10: first=(pt,p); break
            if first is None or first[0]>tg+300000: continue
            t0=first[0]
            def at(sec):
                c=[p for pt,p in post if t0+sec*1000-20000<=pt<=t0+sec*1000+40000]
                return c[-1] if c else None
            p30,p60,p120=at(30),at(60),at(120)
            settle=[p for pt,p in post if t0+480000<=pt<=t0+600000]
            if not settle: continue
            ps=settle[-1]
            later=[x for x,s in goals if g<x<=g+10]
            n_goals+=1
            rows.append((season,mt,role(name),side,f"{min(sh,3)}-{min(sa,3)}",g,p0,first[1],p30,p60,p120,ps,bool(later)))
    if files%3000==0: print("files",files,"joined",used,"goal-runner rows",len(rows),flush=True)
print(f"\nfiles {files}, joined {used}, goal-runner rows {len(rows)}",flush=True)
D=pd.DataFrame(rows,columns=['season','mkt','sel','scorer','score_after','minute','pre','first','p30','p60','p120','p10m','goal_within_10'])
D.to_csv('/root/pe-scan/goal_overshoot_rows.csv',index=False)
# overshoot = how far the early price is from the 10-min price, as a fraction of the move from pre to 10-min
for c in ('first','p30','p60','p120'):
    D['os_'+c]=(D[c]-D.p10m)/(D.pre-D.p10m).replace(0,np.nan)
D['scorer_sel']=np.where(((D.sel=='HOME')&(D.scorer=='H'))|((D.sel=='AWAY')&(D.scorer=='A')),'scoring_team',np.where(D.sel.isin(['HOME','AWAY']),'conceding_team',D.sel))
pd.set_option('display.width',250)
print("\nOVERSHOOT (price at +Xs minus 10-min price, as share of the pre->10min move; >0 = overshoot that reverts, <0 = under-reaction). Clean goals only (no further goal within 10 min).")
C=D[~D.goal_within_10]
print(C.groupby(['mkt','scorer_sel','season'])[['os_first','os_p30','os_p60','os_p120']].median().round(3).to_string())
print("\nFADE P&L per £100: at +60s, trade AGAINST the move (if price rose: back; if fell: lay), exit at the 10-min price. Clean goals; by market/role/score/minute band; train 2024/25 vs test 2025/26")
def fade(r):
    e=r.p60; x=r.p10m
    if pd.isna(e) or pd.isna(x) or e<=1.01 or x<=1.01: return np.nan
    if e>r.pre:  # price rose -> back at e, lay at x
        pnl=(e*(1-SPREAD))/(x*(1+SPREAD))-1
    else:        # price fell -> lay at e, back at x
        pnl=1-(e*(1+SPREAD))/(x*(1-SPREAD))
    return pnl*(1-COMM) if pnl>0 else pnl
C=C.assign(pnl=C.apply(fade,axis=1)); C=C[C.pnl.notna()]
C['mb']=pd.cut(C.minute,[0,30,60,75,120],labels=['1-30','31-60','61-75','76+'])
T=C.groupby(['mkt','scorer_sel','score_after','mb','season'],observed=True).pnl.agg(['size','mean']).unstack('season')
T.columns=['n_tr','n_te','per100_tr','per100_te']; T[['per100_tr','per100_te']]*=100
T=T[(T.n_tr>=150)&(T.n_te>=50)].round(1)
print(T.sort_values('per100_te',ascending=False).to_string())
S=T[(T.per100_tr>2)&(T.per100_te>2)]
print(f"\nSURVIVORS positive both seasons: {len(S)} of {len(T)} cells (chance ~{int(len(T)*0.25*0.4)})")
print(S.to_string())
# also: INCLUDING goals within 10 min (the real risk of fading)
A=D.assign(pnl=D.apply(fade,axis=1)); A=A[A.pnl.notna()]
print("\nSame fade INCLUDING cases where another goal came within 10 min (the honest P&L):")
print(A.groupby(['mkt','scorer_sel','season']).pnl.agg(['size','mean']).assign(mean=lambda x:(100*x['mean']).round(1)).to_string())
PYFILE
python3 goal_overshoot.py
