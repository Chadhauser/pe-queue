#!/bin/bash
set -o pipefail
# 460 (Finder, queue item 00 part 3/4): RE-SETTLE EVERY goal_alerts ROW SINCE 27 OCT AT THE REAL TOUCH.
# goal_alerts carries a target band, not a price, and pnl_paper is at a £50 stake inside that band. Here each alert is priced
# from liq_sample (real Betfair touch, live key; retention starts 29 Oct 03:33 UTC) by name-token match of the fixture to the
# recorder event (as jobs/300) and the nearest OU sample within 90 s of sent_at (also an at-or-before-only variant: no
# look-ahead at all). Entry = back_px minus one tick, £10 back stake, 2% commission on winnings, settled on ft_score.
# Alerts with no real price (line not recorded: Over 4.5/5.5/6.5; sent before the recorder's retention; no event match;
# no sample within 90 s) are COUNTED and reported with their paper result — never silently dropped.
# Writes goal_alerts_real (created by this job; re-runs replace it only if it carries this job's marker comment) and
# watchman/GOAL_SIGNAL_LIVE.txt (strategy_ids passing the standard test; empty if none).
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,re,unicodedata,psycopg2,psycopg2.extras,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET statement_timeout='2400s'")
A=pd.read_sql("""SELECT id alert_id, sent_at, strategy_id, fixture, minute, score, action, target_price_min::float tmin, target_price_max::float tmax,
  stake_gbp::float stake, settled, ft_score, ft_total, outcome, pnl_paper::float pnl_paper FROM goal_alerts WHERE sent_at>='2026-10-27' ORDER BY sent_at""",con)
print(f"goal_alerts since 27 Oct: {len(A)} | settled {int(A.settled.sum())} | strategies {A.strategy_id.nunique()} | {A.sent_at.min()} .. {A.sent_at.max()}",flush=True)
cur.execute("SELECT min(ts), max(ts) FROM liq_sample"); L0,L1=cur.fetchone(); print(f"liq_sample range: {L0} .. {L1}")
def mapact(a):
    m=re.match(r"BACK (Over|Under) (\d)\.5 Goals",a or "")
    if not m: return None,None,None
    side,k=m.group(1),int(m.group(2)); line=k+0.5
    if k==2: return 'OU25',side.upper(),line
    if k in (1,3): return f'OU{k}5',f"{side.upper()} {k}.5 GOALS",line
    return None,None,line
A[['mkt','sel','line']]=A.action.apply(lambda a: pd.Series(mapact(a)))
def ft(s):
    try: h,a=str(s).split('-'); return int(h)+int(a)
    except Exception: return None
A['ft_tot']=A.ft_score.apply(ft)
bad=A[A.ft_tot.notna()&A.ft_total.notna()&(A.ft_tot!=A.ft_total)]; print("ft_score vs ft_total disagreements:",len(bad))
A['won']=np.where(A.ft_tot.isna(),np.nan,np.where(A.action.str.contains('Over'),A.ft_tot>A.line,A.ft_tot<A.line).astype(float))
# recorder samples for the needed markets in +-3h windows around every alert (event matching), then nearest within 90 s
need=A[A.mkt.notna()&(A.sent_at>=L0)]
L=[]
for r in need.itertuples():
    L.append(pd.read_sql("""SELECT %(id)s alert_id, ts, event_name, sel, back_px::float back_px, lay_px::float lay_px FROM liq_sample
      WHERE mkt=%(m)s AND sel=%(s)s AND ts BETWEEN %(t)s - interval '150 seconds' AND %(t)s + interval '150 seconds'""",con,params=dict(id=int(r.alert_id),m=r.mkt,s=r.sel,t=r.sent_at)))
L=pd.concat(L,ignore_index=True) if L else pd.DataFrame(columns=['alert_id','ts','event_name','sel','back_px','lay_px'])
L['ts']=pd.to_datetime(L.ts,utc=True); A['sent_at']=pd.to_datetime(A.sent_at,utc=True)
print("recorder samples pulled:",len(L),flush=True)
def norm(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
    s=re.sub(r"\b(fc|cf|afc|sc|ac|as|ss|us|sv|vfb|vfl|tsg|fk|club|de|the|athletic|atletico|sporting|real|cd|ud|sd|rcd|calcio|women|w|u21|u23|ii|b|if|bk|ff|aif|is|kv|sk|fsv)\b"," ",s)
    return set(w for w in re.sub(r"[^a-z0-9 ]"," ",s).split() if len(w)>2)
def sim(a,b): X,Y=norm(a),norm(b); return len(X&Y)/max(1,len(X|Y))
def tick_below(p):
    for hi,t in ((2,.01),(3,.02),(4,.05),(6,.1),(10,.2),(20,.5),(30,1),(50,2),(100,5),(1001,10)):
        if p<=hi+1e-9: return round(p-t,2)
rows=[]
for r in A.itertuples():
    d=dict(alert_id=int(r.alert_id),strategy_id=r.strategy_id,sent_at=r.sent_at,fixture=r.fixture,event_name=None,sample_ts=None,back_px=None,lay_px=None,
           real_price=None,real_price_pre=None,in_band=None,pnl_real=None,pnl_real_pre=None,status='priced')
    if not isinstance(r.mkt,str): d['status']='no_line_on_recorder'
    elif r.sent_at<L0: d['status']='before_recorder_retention'
    elif pd.isna(r.won): d['status']='no_ft_score'
    else:
        g=L[L.alert_id==r.alert_id]
        fh,fa=(r.fixture.split(' v ',1)+[''])[:2]
        sc={}
        for ev in g.event_name.dropna().unique():
            if ' v ' in ev: h,a=ev.split(' v ',1); sc[ev]=sim(fh,h)+sim(fa,a)
        top=sorted(sc.items(),key=lambda x:-x[1])
        if not top or top[0][1]<1.0 or (len(top)>1 and top[0][1]-top[1][1]<0.3): d['status']='no_event_match'
        else:
            d['event_name']=top[0][0]; g=g[(g.event_name==top[0][0])&(g.back_px>1.01)&g.lay_px.notna()].copy()
            g['dt']=(g.ts-r.sent_at).dt.total_seconds()
            near=g[g.dt.abs()<=90].sort_values('dt',key=abs); pre=g[(g.dt<=0)&(g.dt>=-90)].sort_values('dt',ascending=False)
            if len(near)==0: d['status']='no_sample_within_90s'
            else:
                s=near.iloc[0]; p=tick_below(s.back_px)
                d.update(sample_ts=s.ts,back_px=s.back_px,lay_px=s.lay_px,real_price=p,in_band=bool(r.tmin<=s.back_px<=r.tmax) if pd.notna(r.tmin) else None,
                         pnl_real=round(10*(p-1)*0.98,2) if r.won==1 else -10.0)
                if len(pre):
                    q=tick_below(pre.iloc[0].back_px); d['real_price_pre']=q; d['pnl_real_pre']=round(10*(q-1)*0.98,2) if r.won==1 else -10.0
    d['paper10']=None if pd.isna(r.pnl_paper) or not r.stake else round(r.pnl_paper/r.stake*10,2); d['won']=r.won
    rows.append(d)
R=pd.DataFrame(rows)
cur.execute("SELECT to_regclass('goal_alerts_real')::text"); exists=cur.fetchone()[0]
mark=None
if exists: cur.execute("SELECT obj_description('goal_alerts_real'::regclass)"); mark=cur.fetchone()[0]
if exists and mark!='finder job 460':
    print("goal_alerts_real exists and is NOT this job's table — not touching it; aborting write"); sys.exit(1)
cur.execute("""DROP TABLE IF EXISTS goal_alerts_real; CREATE TABLE goal_alerts_real (alert_id BIGINT PRIMARY KEY, strategy_id TEXT, sent_at TIMESTAMPTZ,
  fixture TEXT, event_name TEXT, sample_ts TIMESTAMPTZ, back_px NUMERIC, lay_px NUMERIC, real_price NUMERIC, real_price_pre NUMERIC, in_band BOOLEAN,
  won BOOLEAN, pnl_real NUMERIC, pnl_real_pre NUMERIC, paper_per10 NUMERIC, status TEXT); COMMENT ON TABLE goal_alerts_real IS 'finder job 460'""")
def py(v):
    if v is None or (not isinstance(v,str) and pd.isna(v)): return None
    if isinstance(v,pd.Timestamp): return v.to_pydatetime()
    if isinstance(v,(np.bool_,bool)): return bool(v)
    if isinstance(v,np.integer): return int(v)
    if isinstance(v,np.floating): return float(v)
    return v
psycopg2.extras.execute_values(cur,"INSERT INTO goal_alerts_real VALUES %s",[tuple(py(v) for v in (x.alert_id,x.strategy_id,x.sent_at,x.fixture,x.event_name,x.sample_ts,x.back_px,x.lay_px,x.real_price,
  x.real_price_pre,x.in_band,None if pd.isna(x.won) else bool(x.won),x.pnl_real,x.pnl_real_pre,x.paper10,x.status)) for x in R.itertuples()])
print("goal_alerts_real rows written:",len(R))
print("\n== pricing status (every alert accounted for; paper per £10 shown so a pricing gap cannot hide a selection bias)")
print(R.groupby('status').agg(n=('alert_id','size'),paper_per10=('paper10','mean'),win_rate=('won','mean')).round(2).to_string())
P=R[R.status=='priced'].copy()
if len(P)==0: print("nothing priced"); sys.exit(0)
med=P.sent_at.median(); P['half']=np.where(P.sent_at<=med,'h1','h2')
print(f"\nhalves split at median sent_at {med}")
def t(x): x=x.dropna(); return x.mean()/(x.std(ddof=1)/len(x)**0.5) if len(x)>1 and x.std(ddof=1)>0 else 0.0
def summ(G):
    return G.agg(n=('pnl_real','size'),games=('event_name','nunique'),per10=('pnl_real','mean'),t=('pnl_real',t),
                 h1=('pnl_real',lambda x:x[P.loc[x.index,'half']=='h1'].mean()),n1=('pnl_real',lambda x:(P.loc[x.index,'half']=='h1').sum()),
                 h2=('pnl_real',lambda x:x[P.loc[x.index,'half']=='h2'].mean()),n2=('pnl_real',lambda x:(P.loc[x.index,'half']=='h2').sum()),
                 pre_per10=('pnl_real_pre','mean'),paper_per10=('paper10','mean'),in_band=('in_band','mean'),avg_px=('real_price','mean')).round(2)
S=summ(P.groupby('strategy_id')).reset_index(); P['all']='ALL'; T=summ(P.groupby('all')).reset_index().rename(columns={'all':'strategy_id'})
S=pd.concat([S,T],ignore_index=True).sort_values('t',ascending=False)
S['PASS']=(S.n>=300)&(S.n1>=150)&(S.n2>=150)&(S.t>=3.5)&(S.h1>0)&(S.h2>0)&(S.per10>=0.15)
print("\n== per strategy at the REAL touch (per £10 back; pre = at-or-before-only price; paper = goal_alerts pnl_paper rescaled to £10)")
print(S.to_string(index=False))
print(f"\nmean |real - target band| : real back_px inside the alert's target band on {P.in_band.mean():.0%} of priced alerts; mean real {P.back_px.mean():.2f} vs band mid {((A.tmin+A.tmax)/2).mean():.2f}")
ids=S[S.PASS&(S.strategy_id!='ALL')].strategy_id.tolist()
open('/root/pe-queue/watchman/GOAL_SIGNAL_LIVE.txt','w').write(''.join(i+'\n' for i in ids))
print(f"\n== SURVIVORS: {len(ids)}"); print('\n'.join(ids) if ids else "none (GOAL_SIGNAL_LIVE.txt written empty)")
PY
