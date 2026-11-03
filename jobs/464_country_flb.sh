#!/bin/bash
set -o pipefail
# 464 (Finder 2026-11-03, own item 16): KICK-OFF FAVOURITE-LONGSHOT BIAS BY COUNTRY on the WHOLE bf_hist_price MO tape (~37k events;
# earlier fair-price work (job 320) used only the ~12k af-mapped games). Entry: first REAL print in tape minutes 0..2 for each MO selection
# (kick-off price), BACK and LAY, risk £10, one tick adverse, 2% commission, hold to settle.
# Result: inferred from the tape — the one selection whose LAST print at tape minute >= 88 is <= 1.10 while every other selection's last
# print is >= 5. Events without a clean inference are UNKNOWN; reported two ways: known-only, and UNKNOWN = loss for the side (conservative).
# Inference accuracy is measured against af_fixtures on the af-mapped games and printed. Halves by date median. One entry per event per
# selection per side (HOME/DRAW/AWAY of one event are mechanically linked — cells are per selection so no event appears twice in a cell).
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
def tick(p):
    p=np.asarray(p,dtype=float)
    return np.select([p<2,p<3,p<4,p<6,p<10,p<20,p<30,p<50,p<100],[0.01,0.02,0.05,0.1,0.2,0.5,1,2,5],10.0)
def comm(x): return np.where(x>0,x*0.98,x)
def back(p,won):
    q=p-tick(p); return np.where(q>1.01,comm(np.where(won,10*(q-1),-10.0)),np.nan)
def lay(p,won):
    q=p+tick(p); s=10/(q-1); return comm(np.where(won,-10.0,s))
b=lambda v: np.array([v],dtype=float)
# known answers: back 2.0 (tick .02 -> 1.98) won 9.8*0.98=9.604; lay 2.0 (2.02, stake 10/1.02=9.803922) not won 9.607843, won -10
assert abs(back(b(2.0),b(1)==1)[0]-9.604)<1e-9 and back(b(2.0),b(0)==1)[0]==-10
assert abs(lay(b(2.0),b(0)==1)[0]-10/1.02*0.98)<1e-9 and lay(b(2.0),b(1)==1)[0]==-10
print("P&L unit checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor(); cur.execute("SET statement_timeout='2400s'")
K=pd.read_sql("""SELECT DISTINCT ON (event_id, sel) event_id, country, sel, minute, ltp::float ltp, m FROM bf_hist_price
  WHERE mkt='MO' AND minute BETWEEN 0 AND 2 AND ltp>=1.01 AND ltp<1000 ORDER BY event_id, sel, minute, m""",con)
L=pd.read_sql("""SELECT DISTINCT ON (event_id, sel) event_id, sel, minute, ltp::float lastp FROM bf_hist_price
  WHERE mkt='MO' AND minute>=88 AND ltp>=1.01 ORDER BY event_id, sel, minute DESC, m DESC""",con)
print(f"kick-off prints {len(K)} ({K.event_id.nunique()} events) | late prints {len(L)} ({L.event_id.nunique()} events)",flush=True)
Lw=L.pivot_table(index='event_id',columns='sel',values='lastp',aggfunc='last')
res={}
for eid,r in Lw.iterrows():
    v=r.dropna()
    if len(v)<2: continue
    w=v[v<=1.10]
    if len(w)==1 and (v.drop(w.index)>=5).all(): res[eid]=w.index[0]
print(f"events with a clean inferred result: {len(res)}",flush=True)
M=pd.read_sql("""SELECT m.event_id, CASE WHEN f.hg>f.ag THEN 'HOME' WHEN f.hg<f.ag THEN 'AWAY' ELSE 'DRAW' END res FROM af_price_map m
  JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL""",con)
M['inf']=M.event_id.map(res); mm=M[M.inf.notna()]
print(f"inference check vs af_fixtures: {len(mm)} mapped games with inference, agreement {(mm.inf==mm.res).mean():.4f}; af-mapped games with no inference {M.inf.isna().mean():.3f}",flush=True)
K['res']=K.event_id.map(res); K['known']=K.res.notna(); K['won']=K.sel==K.res
med=K.m.median(); K['half']=K.m>med
K['band']=pd.cut(K.ltp,[1,1.5,2.2,3.5,6,12,1000],labels=['<1.5','1.5-2.2','2.2-3.5','3.5-6','6-12','12+'])
won=K.won.values
K['B']=back(K.ltp.values,won); K['L']=lay(K.ltp.values,won)
K['Bc']=np.where(K.known,K.B,np.where(K.ltp-tick(K.ltp)>1.01,-10.0,np.nan)); K['Lc']=np.where(K.known,K.L,-10.0)   # unknown = loss
print(f"date median {med} | known share {K.known.mean():.3f}",flush=True)
rows=[]
for keys in (['sel','band'],['country','sel','band'],['country','band']):
    for side,col,colc in (('BACK','B','Bc'),('LAY','L','Lc')):
        for k,x in K.groupby(keys,observed=True):
            xk=x[x.known&x[col].notna()]
            if len(xk)<50: continue
            v=xk[col]; n=len(v); mu=v.mean(); sd=v.std(ddof=0) or 1e-9
            a=xk[~xk.half][col]; c=xk[xk.half][col]
            rows.append(dict(side=side,cell=' '.join(map(str,k if isinstance(k,tuple) else (k,))),n=n,events=xk.event_id.nunique(),mean=mu,t=mu/(sd/np.sqrt(n)),
                n1=len(a),h1=a.mean(),n2=len(c),h2=c.mean(),mean_unk_loss=x[colc].mean(),n_all=int(x[colc].notna().sum())))
R=pd.DataFrame(rows)
R['PASS']=(R.n>=300)&(R.n1>=150)&(R.n2>=150)&(R.t>=3.5)&(R.h1>0)&(R.h2>0)&(R['mean']>=0.15)&(R.mean_unk_loss>=0.15)
print("\n== all countries, selection x band")
print(R[(R.cell.str.count(' ')==1) & R.cell.str.match(r'^(HOME|DRAW|AWAY) ')].round(3).to_string(index=False))
print(f"\n== {len(R)} cells; top 15 by t (n>=300, known results)")
print(R[R.n>=300].sort_values('t',ascending=False).head(15).round(3).to_string(index=False))
S=R[R.PASS].sort_values('t',ascending=False)
print(f"\n== SURVIVORS: {len(S)} (must also be >= +0.15 with UNKNOWN results counted as losses)")
print(S.round(3).to_string(index=False) if len(S) else "none")
PY
