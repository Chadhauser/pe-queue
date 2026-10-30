#!/bin/bash
# 294: THE RACING GRID — breadth testing on racing_bsp (Betfair daily BSP files: BSP, pre-play WAP/min/max, in-play min/max,
# volumes, result). Every runner x price band x course x field-size x market (WIN/PLACE) x steam/drift state (morning WAP and
# pre-play WAP vs BSP) x five trade shapes: back at BSP to settle; lay at BSP to settle; back at BSP with an in-play take-profit
# at -10/-20/-30/-50% (fills if ipmin reached it, else settles); lay at BSP with an in-play stop at +25/+50/+100% (hit if ipmax
# reached it). 2% commission, risk £10 per trade, BSP taken as-is (no adverse tick — BSP is the fill). Halves by date (median).
# Output: rgrid_cells + rgrid_survivors; log prints SURVIVORS ONLY (n>=400 per side, t>=3.5, both halves >0, mean >= +£0.15/£10).
# In-play fills are UNVERIFIED (a touch at ipmin is not a guaranteed fill); the settle-only shapes are exact.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,math,psycopg2,psycopg2.extras,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET statement_timeout='3000s'")
try: cur.execute("SELECT count(*), min(event_dt), max(event_dt) FROM racing_bsp WHERE bsp IS NOT NULL"); n,d0,d1=cur.fetchone()
except Exception as e: print("racing_bsp missing:",e); sys.exit(0)
print("runners:",n,"|",d0,"->",d1,flush=True)
if n<5000: print("too few rows for a grid"); sys.exit(0)
D=pd.read_sql("""SELECT country, market, event_id, menu_hint course, event_name, event_dt, selection_name, win_lose::int won,
  bsp::float bsp, ppwap::float ppwap, morningwap::float mwap, ipmin::float ipmin, ipmax::float ipmax, pp_vol::float ppv, ip_vol::float ipv
  FROM racing_bsp WHERE bsp IS NOT NULL AND bsp>1.01 AND bsp<1000 AND country IN ('GB','IE','UK')""",con)
D['market']=D.market.fillna('WIN').str.upper().str.replace(r'.*PLACE.*','PLACE',regex=True); D.loc[~D.market.isin(['WIN','PLACE']),'market']='WIN'
D['field']=D.groupby(['event_id','market']).selection_name.transform('size')
D['fband']=pd.cut(D.field,[0,6,9,13,40],labels=['<=6','7-9','10-13','14+'])
D['band']=pd.cut(D.bsp,[1,2,3,5,8,12,20,40,1000],labels=['<2','2-3','3-5','5-8','8-12','12-20','20-40','40+'])
D['steam']=pd.cut(D.mwap/D.bsp,[0,0.8,0.95,1.05,1.25,100],labels=['drift20+','drift5-20','flat','steam5-20','steam20+'])
D['pp']=pd.cut(D.ppwap/D.bsp,[0,0.9,0.98,1.02,1.1,100],labels=['late-drift10+','late-drift','flat','late-steam','late-steam10+'])
D['course']=D.course.fillna('').str.replace(r'\s+\d.*','',regex=True).str.strip()
D['half']=D.event_dt>D.event_dt.median()
rows=[]
won=D.won.values==1; bsp=D.bsp.values; ipmin=D.ipmin.values; ipmax=D.ipmax.values
def comm(x): return np.where(x>0,x*0.98,x)
shapes={}
shapes['BACK_SETTLE']=comm(np.where(won,10*(bsp-1),-10.0))
lays=10/(bsp-1)  # lay stake for £10 liability
shapes['LAY_SETTLE']=comm(np.where(won,-10.0,lays))
for X in (0.10,0.20,0.30,0.50):
    tgt=bsp*(1-X); hit=(~np.isnan(ipmin))&(ipmin<=tgt)
    shapes[f'BACK_TP{int(X*100)}']=comm(np.where(hit,10*(bsp/tgt-1),np.where(won,10*(bsp-1),-10.0)))
for Y in (0.25,0.50,1.00):
    stp=bsp*(1+Y); hit=(~np.isnan(ipmax))&(ipmax>=stp)
    shapes[f'LAY_STOP{int(Y*100)}']=comm(np.where(hit,lays*(1-bsp/stp),np.where(won,-10.0,lays)))
cells=[]
for name,p in shapes.items():
    D['pnl']=p
    for dims in (['market','band'],['market','band','fband'],['market','band','steam'],['market','band','pp'],['market','band','course'],['market','band','steam','pp'],['market','band','fband','steam']):
        g=D.groupby(dims+['half'],observed=True).pnl.agg(n='size',s='sum',ss=lambda x:(x*x).sum()).reset_index()
        g['shape']=name; g['level']='+'.join(dims)
        for c in ('fband','steam','pp','course'):
            if c not in g: g[c]=None
        cells.append(g[['shape','level','market','band','fband','steam','pp','course','half','n','s','ss']])
C=pd.concat(cells,ignore_index=True)
for c in ('market','band','fband','steam','pp','course'): C[c]=C[c].astype(object).where(C[c].notna(),None)
cur.execute("DROP TABLE IF EXISTS rgrid_cells; CREATE TABLE rgrid_cells (shape TEXT, level TEXT, market TEXT, band TEXT, fband TEXT, steam TEXT, pp TEXT, course TEXT, half BOOLEAN, n INT, s DOUBLE PRECISION, ss DOUBLE PRECISION)")
psycopg2.extras.execute_values(cur,"INSERT INTO rgrid_cells VALUES %s",[tuple(r) for r in C.itertuples(index=False)],page_size=5000)
A=C.groupby(['shape','level','market','band','fband','steam','pp','course'],dropna=False).agg(n=('n','sum'),s=('s','sum'),ss=('ss','sum'),
   n1=('n',lambda x:x[~C.loc[x.index,'half']].sum()),s1=('s',lambda x:x[~C.loc[x.index,'half']].sum()),
   n2=('n',lambda x:x[C.loc[x.index,'half']].sum()),s2=('s',lambda x:x[C.loc[x.index,'half']].sum())).reset_index()
A['mean']=A.s/A.n; A['sd']=np.sqrt(np.maximum(A.ss/A.n-A['mean']**2,1e-9)); A['t']=A['mean']/(A.sd/np.sqrt(A.n))
A['h1']=A.s1/A.n1.replace(0,np.nan); A['h2']=A.s2/A.n2.replace(0,np.nan)
S=A[(A.n1>=400)&(A.n2>=400)&(A.t>=3.5)&(A.h1>0)&(A.h2>0)&(A['mean']>=0.15)].sort_values('t',ascending=False)
cur.execute("DROP TABLE IF EXISTS rgrid_survivors; CREATE TABLE rgrid_survivors (run_date DATE DEFAULT current_date, shape TEXT, level TEXT, market TEXT, band TEXT, fband TEXT, steam TEXT, pp TEXT, course TEXT, n INT, mean NUMERIC, t NUMERIC, h1 NUMERIC, h2 NUMERIC)")
for r in S.to_dict('records'):
    cur.execute("INSERT INTO rgrid_survivors (shape,level,market,band,fband,steam,pp,course,n,mean,t,h1,h2) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",
      (r['shape'],r['level'],r['market'],r['band'],r.get('fband'),r.get('steam'),r.get('pp'),r.get('course'),int(r['n']),round(r['mean'],3),round(r['t'],2),round(r['h1'],3),round(r['h2'],3)))
print(f"\n==== RACING GRID: {len(A)} cells, {len(D)} runners, {D.event_id.nunique()} races | SURVIVORS: {len(S)} ====")
if len(S)==0: print("no survivors this run")
else: print(S[['shape','level','market','band','fband','steam','pp','course','n','mean','t','h1','h2']].head(60).round(3).to_string(index=False))
PY
