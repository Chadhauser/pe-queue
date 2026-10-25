#!/bin/bash
# 210: DUAL-MARKET SWEEP — two legs in two markets placed together as one position, settled at FT, on the true-goal engine (3,440 games,
# Understat goal minutes, in-play Match Odds + Over/Under 2.5 prices, 2% spread + 2% commission). States at 55'-75': 0-0, 1-1, one-goal
# lead (leader known). Pairs:
#   LD+BU  lay draw + back Under 2.5        (the classic LTD insurance)      LD+LO  lay draw + lay Over 2.5   (both survivors' direction)
#   LD+BO  lay draw + back Over 2.5         (needs goals for both)           BD+BO  back draw + back Over 2.5 (anti-correlated hedge)
#   LL+BO  lay leader + back Over 2.5       (lead state only)                BL+BU  back leader + back Under 2.5 (lead state only)
# Leg B stake ratio 0.5 / 1 / 2 x leg A (£10). Cells land in v4_stats_results as fam DUAL<pair>_<state>, dir r<ratio>, band = leg-A price.
cd /root/pe-factory/v4 && python3 - <<'PY'
p='stats_sweep.py'; s=open(p).read()
anchor="                if hg==0 and ag==0: emit(f'LEVEL00@{m}','MO','DRAW','lay',m)\n"
add="""                if m>=55 and book_ok(m):
                    st='00' if (hg==0 and ag==0) else ('11' if (hg==1 and ag==1) else ('L1' if abs(hg-ag)==1 else None))
                    if st is not None:
                        ldr='HOME' if hg>ag else 'AWAY'
                        def leg_ft(mkt,sel,direction):
                            prices=Pm[sel] if mkt=='MO' else Po[sel]; winf=win_mo if mkt=='MO' else win_ou25
                            em,e=px_at(prices,m,1)
                            if e is None or e>12: return None
                            return e,pnl(direction,e,win=winf(sel))
                        pairs=[('LD+BU','MO','DRAW','lay','OU25','UNDER','back'),('LD+LO','MO','DRAW','lay','OU25','OVER','lay'),('LD+BO','MO','DRAW','lay','OU25','OVER','back'),('BD+BO','MO','DRAW','back','OU25','OVER','back')]
                        if st=='L1': pairs+=[('LL+BO','MO',ldr,'lay','OU25','OVER','back'),('BL+BU','MO',ldr,'back','OU25','UNDER','back')]
                        for tag,m1,s1,d1,m2,s2,d2 in pairs:
                            A=leg_ft(m1,s1,d1); B=leg_ft(m2,s2,d2)
                            if A is None or B is None: continue
                            for ratio in (0.5,1.0,2.0):
                                T.append((f'DUAL{tag}_{st}@{m}',f'{m1} {s1}+{m2} {s2}',f'r{ratio}','FT',band(A[0]),date,round(A[1]+ratio*B[1],3)))
"""
if 'DUAL' in s: print("already")
else:
    assert anchor in s, "anchor missing"; s=s.replace(anchor,add+anchor,1); open(p,'w').write(s); print("dual family added")
PY
python3 -m py_compile stats_sweep.py || exit 1
timeout 3300 python3 stats_sweep.py 2>&1 | grep -E "SWEEP:|stored" | head -4
python3 - <<'PY'
import sys,psycopg2,pandas as pd; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',220); pd.set_option('display.max_rows',200); c=psycopg2.connect(DB,sslmode='require')
d=pd.read_sql("SELECT fam, sel, dir, band, n, round(mean,2) mean, round(t,2) t, round(h1,2) h1, round(h2,2) h2 FROM v4_stats_results WHERE run_date=current_date AND fam LIKE 'DUAL%%' AND n>=100 ORDER BY t DESC",c)
print("=== DUAL-MARKET CELLS (per £10 leg A; pooled 55'-75') — top 25 ===\n",d.head(25).to_string(index=False))
print("\n=== bottom 10 ===\n",d.tail(10).to_string(index=False))
print("\n=== by pair/state: mean t, % positive cells ===\n",d.assign(ps=d.fam.str.replace(r'@\\d+','',regex=True)).groupby('ps').agg(cells=('t','size'),mean_t=('t','mean'),pct_pos=('mean',lambda x:(x>0).mean()),best=('mean','max')).round(2).to_string())
s=d[(d.t>=3)&(d.h1>0)&(d.h2>0)]; print("\n=== DUAL survivors (t>=3, both halves) ===\n",s.to_string(index=False) if len(s) else " none")
m=pd.read_sql("SELECT fam, dir, band, minute, n, round(mean,2) mean, round(t,2) t FROM v4_stats_minute WHERE run_date=current_date AND fam LIKE 'DUAL%%' AND t>=2.5 ORDER BY t DESC LIMIT 20",c); print("\n=== best DUAL minute cells (t>=2.5) ===\n",m.to_string(index=False))
PY
