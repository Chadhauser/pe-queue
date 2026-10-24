#!/bin/bash
# 147: RACING — PASSIVE-FILL MODEL + LAY-FAVOURITE EVIDENCE + WOM RULE OFF.
# (a) WOM swing rule disabled (65 paper trades, 15 targets / 50 stops, -£25; 143 showed WOM level does not predict the move). The
#     1-second tape keeps recording — the bot only stops signalling. (b) From the tape: if we rest an order ONE TICK INSIDE the spread
#     (back at lay-1 tick, lay at back+1 tick) on a top-3 runner in the last 8 minutes, how often does it fill within 15/30/60 s, by
#     seconds-to-off, price band, rank and spread width — and what does the price do in the 30 s after the fill. This is the cost
#     model every passive racing strategy is scored with from now on (earning the spread instead of paying it). -> racing_fill_model.
# (c) Evidence swing: lay the favourite at -5:00, back at -0:20 (143 showed the favourite drifts +4.3% on average): per £10, by
#     price band, both halves of the tape by date. Nothing goes live from here; 148 uses the fill model.
echo "== (a) disable WOM signal, keep tape"
python3 - <<'PY'
p='/root/pe-race/race_swing.py'; s=open(p).read()
old="WOM_T=0.60;"; new="WOM_T=1.01;  # WOM rule OFF 24 Oct (65 trades -£25) — tape continues;"
if old in s: s=s.replace(old,new,1); open(p,'w').write(s); print("WOM rule disabled")
else: print("already disabled or line changed:", [l for l in s.splitlines() if l.startswith('WOM_T')])
PY
python3 -m py_compile /root/pe-race/race_swing.py && pkill -f race_swing.py; sleep 2; /root/pe-race/keepalive.sh 2>/dev/null; sleep 5; pgrep -af race_swing.py | head -2
echo "== (b) passive-fill model"
cd /root/pe-race && cat > fill_model.py <<'PYFILE'
import sys, psycopg2, psycopg2.extras, pandas as pd, numpy as np, datetime
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',250); pd.set_option('display.max_rows',300)
LAD=[(1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)]
def tick(p):
    for lo,hi,s in LAD:
        if p<hi: return s
    return 10
def rnd(p): s=tick(p); return round(round(p/s)*s,2)
def up(p): return rnd(p+tick(p)+1e-9)
def down(p): return rnd(p-tick(p-1e-9)+1e-9) if p>1.01 else 1.01
def nticks(a,b):
    n=0; p=a
    if b>a:
        while p<b-1e-9 and n<500: p=up(p); n+=1
        return n
    while p>b+1e-9 and n<500: p=down(p); n+=1
    return -n
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET statement_timeout='1800s'")
T=pd.read_sql("""SELECT ts, market_id, sel_id, rank, secs_to_off sto, ltp::float ltp, back_px::float bp, lay_px::float lp, back_sz::float bsz, lay_sz::float lsz, status
                 FROM racing_tape WHERE rank<=3 AND secs_to_off BETWEEN -5 AND 480 AND status='OPEN' AND back_px IS NOT NULL AND lay_px IS NOT NULL ORDER BY market_id, sel_id, ts""",con)
print("tape rows",len(T),"races",T.market_id.nunique(),"dates",T.ts.min(),"->",T.ts.max())
rows=[]
for (mid,sid),g in T.groupby(['market_id','sel_id'],sort=False):
    g=g.reset_index(drop=True); ts=g.ts.values.astype('datetime64[s]').astype('int64'); ltp=g.ltp.values; bp=g.bp.values; lp=g.lp.values; sto=g.sto.values
    n=len(g)
    if n<60: continue
    # sample a hypothetical order every 15 seconds
    for i in range(0,n-1,15):
        if np.isnan(bp[i]) or np.isnan(lp[i]) or bp[i]<=0 or lp[i]<=bp[i]: continue
        spread=nticks(bp[i],lp[i])
        for side in ('BACK','LAY'):
            px=down(lp[i]) if side=='BACK' else up(bp[i])
            if side=='BACK' and px<=bp[i]: px=bp[i]
            if side=='LAY' and px>=lp[i]: px=lp[i]
            inside = (side=='BACK' and px>bp[i]) or (side=='LAY' and px<lp[i])
            # fill = LTP trades at/through our price
            j=i+1; fill=None
            while j<n and ts[j]-ts[i]<=60:
                if (side=='BACK' and ltp[j]>=px-1e-9) or (side=='LAY' and ltp[j]<=px+1e-9): fill=j; break
                j+=1
            secs=(ts[fill]-ts[i]) if fill is not None else None
            # adverse move 30s after fill: for BACK, price going up (drifting) hurts; measure ticks from px to lay touch 30s later (exit price)
            after=None
            if fill is not None:
                k=fill
                while k<n and ts[k]-ts[fill]<30: k+=1
                if k<n:
                    after = -nticks(px,lp[k]) if side=='BACK' else nticks(px,bp[k])   # ticks of profit if we exited at the touch 30s after fill
            rows.append((mid,sid,int(g['rank'].iloc[0]),int(sto[i]),float(ltp[i]),spread,side,inside,secs,after))
R=pd.DataFrame(rows,columns=['mid','sid','rank','sto','ltp','spread','side','inside','secs','after30'])
print("hypothetical orders",len(R))
R['f15']=(R.secs<=15); R['f30']=(R.secs<=30); R['f60']=(R.secs<=60)
R['sto_b']=pd.cut(R.sto,[-5,20,60,120,240,480],labels=['0-20s','20-60s','1-2m','2-4m','4-8m'])
R['px_b']=pd.cut(R.ltp,[1,2,3,5,8,15,1000],labels=['<2','2-3','3-5','5-8','8-15','15+'])
R['sp_b']=pd.cut(R.spread,[0,1,2,3,100],labels=['1 tick','2','3','4+'])
def show(by,label):
    g=R.groupby(by,observed=True).agg(n=('f60','size'),fill15=('f15','mean'),fill30=('f30','mean'),fill60=('f60','mean'),after30_ticks=('after30','mean')).round(3)
    print(f"\n{label}:\n",g.to_string()); return g
show(['side','sto_b'],"fill probability one tick inside, by side x seconds-to-off")
show(['side','px_b'],"by side x price band")
show(['side','sp_b'],"by side x spread width at order time (1 tick = we join the touch)")
show(['side','rank'],"by side x market rank")
cur.execute("""CREATE TABLE IF NOT EXISTS racing_fill_model (run_date DATE, side TEXT, sto_band TEXT, px_band TEXT, spread_band TEXT, n INT, fill15 NUMERIC, fill30 NUMERIC, fill60 NUMERIC, after30_ticks NUMERIC)""")
cur.execute("DELETE FROM racing_fill_model WHERE run_date=current_date")
G=R.groupby(['side','sto_b','px_b','sp_b'],observed=True).agg(n=('f60','size'),fill15=('f15','mean'),fill30=('f30','mean'),fill60=('f60','mean'),after30=('after30','mean')).reset_index()
G=G[G.n>=30]
psycopg2.extras.execute_values(cur,"INSERT INTO racing_fill_model VALUES %s",[(datetime.date.today(),r.side,str(r.sto_b),str(r.px_b),str(r.sp_b),int(r.n),float(round(r.fill15,3)),float(round(r.fill30,3)),float(round(r.fill60,3)),None if pd.isna(r.after30) else float(round(r.after30,3))) for r in G.itertuples()])
print("\nfill model cells stored:",len(G))
# headline for the report
h=R[(R.sto>=60)&(R.sto<=480)&(R.inside)]
print(f"\nHEADLINE (1-8 min out, order one tick inside, n {len(h)}): fills within 30s BACK {h[h.side=='BACK'].f30.mean():.0%} LAY {h[h.side=='LAY'].f30.mean():.0%}; mean ticks if exited at touch 30s after fill: BACK {h[h.side=='BACK'].after30.mean():+.2f} LAY {h[h.side=='LAY'].after30.mean():+.2f}")
PYFILE
python3 -m py_compile fill_model.py || exit 1
timeout 1700 python3 fill_model.py 2>&1 | grep -v -E "UserWarning|pd.read_sql"
echo "== (c) lay favourite -5:00 -> back -0:20"
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys, psycopg2, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require')
T=pd.read_sql("SELECT market_id, sel_id, rank, ts::date d, secs_to_off sto, back_px::float bp, lay_px::float lp FROM racing_tape WHERE rank=1 AND secs_to_off BETWEEN 15 AND 330 AND status='OPEN' AND back_px IS NOT NULL ORDER BY market_id, ts",con)
rows=[]
for mid,g in T.groupby('market_id'):
    e=g[(g.sto<=300)&(g.sto>=285)]; x=g[(g.sto<=25)&(g.sto>=18)]
    if e.empty or x.empty: continue
    # favourite may change: use the runner that was rank 1 at -5:00
    sid=e.sel_id.iloc[0]; x=x[x.sel_id==sid]
    if x.empty: continue
    lay_at=e.lp.iloc[0]; back_at=x.bp.iloc[-1]     # lay at the lay touch (pay spread), back at the back touch (pay spread) = worst case
    lay_in=e.bp.iloc[0]; back_in=x.lp.iloc[-1]      # passive both ways = best case
    pnl_w=(1-lay_at/back_at)*10*0.98 if back_at>lay_at else (1-lay_at/back_at)*10
    pnl_b=(1-lay_in/back_in)*10*0.98 if back_in>lay_in else (1-lay_in/back_in)*10
    rows.append((mid,g.d.iloc[0],lay_at,back_at,pnl_w,pnl_b))
R=pd.DataFrame(rows,columns=['mid','d','lay_at','back_at','pnl_worst','pnl_best']); R=R.sort_values('d')
print("races",len(R),"dates",R.d.min(),"->",R.d.max())
R['band']=pd.cut(R.lay_at,[1,1.5,2,3,5,100],labels=['<1.5','1.5-2','2-3','3-5','5+']); R['half']=np.where(np.arange(len(R))<len(R)//2,'H1','H2')
print("\nlay fav -5:00 -> back -0:20, per £10 lay stake, by band (worst = pay both spreads, best = passive both sides):")
print(R.groupby('band',observed=True).agg(n=('pnl_worst','size'),worst=('pnl_worst','mean'),best=('pnl_best','mean'),win_worst=('pnl_worst',lambda s:(s>0).mean())).round(3).to_string())
print("\nby half of the tape:\n",R.groupby('half').agg(n=('pnl_worst','size'),worst=('pnl_worst','mean'),best=('pnl_best','mean')).round(3).to_string())
t=R.pnl_worst.mean()/(R.pnl_worst.std()/np.sqrt(len(R))) if len(R)>2 else float('nan'); print(f"\nworst-case total £{R.pnl_worst.sum():+.2f} over {len(R)} races, t={t:.2f} | best-case total £{R.pnl_best.sum():+.2f}")
PY
