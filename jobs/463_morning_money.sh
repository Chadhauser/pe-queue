#!/bin/bash
set -o pipefail
# 463 (Finder 2026-11-03, own item 15): RACING MORNING MONEY (Webb weight-of-money, morning version). racing_bsp UK/IE, WIN and PLACE.
# Signal per runner: money share s = morning_vol / race morning_vol; price share q = (1/morningwap) / sum over race (normalised).
# R = s/q: R>1 = the runner took more of the morning money than its price implies.
# Trades (risk £10; 2% commission on profit; one tick adverse both ends):
#   BACK_GREEN  back at morning WAP, lay out at BSP (hedged P&L 10*(pm/pb-1))      — 'the money is right, price shortens'
#   LAY_GREEN   lay at morning WAP (liability £10), back out at BSP                 — the reverse
#   BACK_SETTLE back at morning WAP, hold to result
# CAVEATS: morning WAP is an AVERAGE of morning trades, not one print; the full-morning volume is only known at the end of the morning,
# while the WAP spans it (mild look-ahead). Anything that passes is a CANDIDATE for a forward paper test, not a proven line.
# Halves by event-date median; distinct races per cell; races need >=5 runners with morning prices and volume.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
def tick(p):
    p=np.asarray(p,dtype=float)
    return np.select([p<2,p<3,p<4,p<6,p<10,p<20,p<30,p<50,p<100],[0.01,0.02,0.05,0.1,0.2,0.5,1,2,5],10.0)
def comm(x): return np.where(x>0,x*0.98,x)
def back_green(pm,pb):
    a=pm-tick(pm); c=pb+tick(pb); return np.where(a>1.01,comm(10*(a/c-1)),np.nan)
def lay_green(pm,pb):
    a=pm+tick(pm); s=10/(a-1); c=np.maximum(1.01,pb-tick(pb)); return comm(s*(1-a/c))
def back_settle(pm,won):
    a=pm-tick(pm); return np.where(a>1.01,comm(np.where(won,10*(a-1),-10.0)),np.nan)
b=lambda v: np.array([v],dtype=float)
# known answers: back 5.0 (fill 4.9) lay out at BSP 4.0 (fill 4.1): 10*(4.9/4.1-1)=1.951220 -> *0.98=1.912195
# lay 5.0 (fill 5.1, stake 10/4.1=2.439024) back out at BSP 6.0 (tick 0.2, fill 5.8): 2.439024*(1-5.1/5.8)=0.294365 -> *0.98=0.288478
# back 5.0 settle lost -10; won 39*0.98=38.22
assert abs(back_green(b(5.0),b(4.0))[0]-1.912195)<1e-6
assert abs(lay_green(b(5.0),b(6.0))[0]-0.288478)<1e-6
assert back_settle(b(5.0),b(0)==1)[0]==-10 and abs(back_settle(b(5.0),b(1)==1)[0]-38.22)<1e-9
print("P&L unit checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor(); cur.execute("SET statement_timeout='1200s'")
D=pd.read_sql("""SELECT market, event_id, event_dt, selection_id, win_lose won, bsp::float pb, NULLIF(morningwap,0)::float pm, morning_vol::float mv
  FROM racing_bsp WHERE lower(country) IN ('uk','ire') AND bsp>1.01 AND bsp<1000 AND win_lose IS NOT NULL""",con)
D=D.drop_duplicates(['event_id','selection_id'])
D=D[D.pm.notna()&(D.pm>1.01)&(D.pm<1000)&D.mv.notna()&(D.mv>0)]
D['nr']=D.groupby('event_id').selection_id.transform('size'); D=D[D.nr>=5]
D['s']=D.mv/D.groupby('event_id').mv.transform('sum')
D['q0']=1/D.pm; D['q']=D.q0/D.groupby('event_id').q0.transform('sum'); D['R']=D.s/D.q
D['Rb']=pd.cut(D.R,[0,0.5,0.8,1.25,2,4,1e9],labels=['<0.5','0.5-0.8','0.8-1.25','1.25-2','2-4','4+'])
D['band']=pd.cut(D.pm,[1,3,6,12,30,1000],labels=['<3','3-6','6-12','12-30','30+'])
med=D.event_dt.median(); D['half']=D.event_dt>med
won=D.won.values==1
D['BACK_GREEN']=back_green(D.pm.values,D.pb.values); D['LAY_GREEN']=lay_green(D.pm.values,D.pb.values); D['BACK_SETTLE']=back_settle(D.pm.values,won)
D['drift']=np.log(D.pm/D.pb)
print(f"runners {len(D)} | races {D.event_id.nunique()} | {D.event_dt.min()} -> {D.event_dt.max()} | median {med}",flush=True)
print("\n== mean log(morningWAP/BSP) (>0 = shortened into the off) and share shortening, by market x R band")
print(D.groupby(['market','Rb'],observed=True).agg(n=('drift','size'),mean_logmove=('drift','mean'),pct_shorter=('drift',lambda x:(x>0).mean())).round(4).to_string())
rows=[]
for shape in ('BACK_GREEN','LAY_GREEN','BACK_SETTLE'):
    for keys in (['market','Rb'],['market','Rb','band']):
        for k,x in D[D[shape].notna()].groupby(keys,observed=True):
            v=x[shape]; n=len(v); mu=v.mean(); sd=v.std(ddof=0) or 1e-9
            a=x[~x.half][shape]; c=x[x.half][shape]
            rows.append(dict(shape=shape,cell=' '.join(map(str,k)),n=n,races=x.event_id.nunique(),mean=mu,t=mu/(sd/np.sqrt(n)),n1=len(a),h1=a.mean(),n2=len(c),h2=c.mean()))
R=pd.DataFrame(rows)
R['PASS']=(R.n>=300)&(R.n1>=150)&(R.n2>=150)&(R.t>=3.5)&(R.h1>0)&(R.h2>0)&(R['mean']>=0.15)
print(f"\n== {len(R)} cells; market x R band")
print(R[R.cell.str.count(' ')==1].round(3).to_string(index=False))
print("\n== top 15 by t (n>=300)")
print(R[R.n>=300].sort_values('t',ascending=False).head(15).round(3).to_string(index=False))
S=R[R.PASS].sort_values('t',ascending=False)
def shift(p,k,up):
    p=np.asarray(p,dtype=float).copy()
    for _ in range(k): p=p+tick(p) if up else p-tick(p)
    return p
print("\n== spread sensitivity for numeric passes: mean per £10 when the morning entry is k ticks adverse (k=1 is the table above).")
print("   A thin morning book is often several ticks wide; the real lay (back) price sits above (below) the WAP.")
sens=[]
for r in S.itertuples():
    parts=r.cell.split(' '); m=(D.market==parts[0])&(D.Rb.astype(str)==parts[1])
    if len(parts)>2: m&=(D.band.astype(str)==parts[2])
    E=D[m]; row={'shape':r.shape,'cell':r.cell,'n':len(E)}
    for k in (1,2,3,5,8):
        if r.shape=='LAY_GREEN':
            a=shift(E.pm.values,k,True); s_=10/(a-1); c=np.maximum(1.01,E.pb.values-tick(E.pb.values)); v=comm(s_*(1-a/c))
        else:
            a=shift(E.pm.values,k,False); c=E.pb.values+tick(E.pb.values); v=np.where(a>1.01,comm(10*(a/c-1)),np.nan)
        row[f'k{k}']=np.nanmean(v)
    sens.append(row)
if sens: print(pd.DataFrame(sens).round(3).to_string(index=False))
print(f"\n== NUMERIC PASSES: {len(S)} — but the entry is the morning WAP, NOT a real print (honesty rule 1), so none can PASS.")
print(S.round(3).to_string(index=False) if len(S) else "none")
print("\n== SURVIVORS: 0 (real-print rule; morning touch not recorded on this box — stream_ticks racing starts ~12 min before the off)")
PY
