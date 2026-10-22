#!/bin/bash
# 128: THE FTS ULTIMATE BATTERY (Peter 22 Oct: "they must be making money off his tools so we need to see if anything is good for us").
# /root/pe-factory/fts_ultimate.csv = FTS Ultimate database, 22,624 matches Aug 2020 -> Mar 2026: Betfair 8am odds, 5-min-pre-KO
# back AND lay odds, FTS model odds, ELO odds, form colours, HT/FT scores, O/U 1.5/2.5/3.5 prices, HT correct-score lay price.
# Loads it (COPY) into fts_ultimate, then every building block FTS sells, with OUR accounting (per £1, 2pct comm, train/test halves,
# survivor = both halves >1 per £100 with t>=2 both, n>=100):
#   V1 FTS value: back/lay H/D/A at 5-min price by (FTS odds vs BF) edge band      V2 ELO value: same with ELO odds
#   S1 steam/drift 8am->5min: back steamers / lay drifters at 5-min, settle         S2 PRE-MATCH TRADE: back at 8am, lay at 5-min (hedged) by what predicted it
#   F1 form colours: lay/back by home/away colour pair                              G1 O/U 1.5/2.5/3.5 back & lay by price band
#   H1 HT correct-score lay at the FTS HT CS price                                  L1 everything above by league for survivors
# Results -> strategy_results sport='FTS' and printed. Daily re-run not needed (static file) — re-run when Peter drops a new CSV.
cd /root/pe-factory && cat > fts_battery.py <<'PYFILE'
import sys, math, datetime, psycopg2, psycopg2.extras, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
COMM=0.02; today=datetime.date.today()
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
pd.set_option('display.width',250); pd.set_option('display.max_rows',500)
cols=["c%d"%i for i in range(103)]
cur.execute("DROP TABLE IF EXISTS fts_ultimate; CREATE TABLE fts_ultimate ("+",".join(c+" text" for c in cols)+")")
with open('/root/pe-factory/fts_ultimate.csv') as f: cur.copy_expert("COPY fts_ultimate FROM STDIN WITH (FORMAT csv, HEADER true)",f)
cur.execute("SELECT count(*) FROM fts_ultimate"); print("loaded rows:",cur.fetchone()[0],flush=True)
D=pd.read_sql("SELECT * FROM fts_ultimate",con)
num=lambda c: pd.to_numeric(D[c],errors='coerce')
X=pd.DataFrame({'mt':pd.to_datetime(D.c2,errors='coerce'),'league':D.c4,'home':D.c5,'away':D.c6,'lt':D.c0,
    'fh':num('c7'),'fw':num('c8'),'fave':num('c12'),'aave':num('c18'),'ch':D.c19,'ca':D.c20,
    'h8':num('c21'),'d8':num('c22'),'a8':num('c23'),'fh_':num('c25'),'fd_':num('c26'),'fa_':num('c27'),'dfh':num('c28'),'dfd':num('c29'),'dfa':num('c30'),
    'elo_m':num('c34'),'eh':num('c35'),'ed':num('c36'),'ea':num('c37'),'deh':num('c38'),'ded':num('c39'),'dea':num('c40'),
    'ht':D.c42,'ft':D.c43,'hb5':num('c54'),'db5':num('c56'),'ab5':num('c58'),'hl5':num('c60'),'dl5':num('c62'),'al5':num('c64'),
    'mvh':num('c66'),'mvd':num('c67'),'mva':num('c68'),
    'u15b':num('c70'),'u15l':num('c72'),'o15b':num('c74'),'o15l':num('c76'),'u25b':num('c78'),'u25l':num('c80'),'o25b':num('c82'),'o25l':num('c84'),'u35b':num('c86'),'u35l':num('c88'),'o35b':num('c90'),'o35l':num('c92'),
    'htcs':num('c94'),'htcs_ret':num('c95')})
sc=X.ft.str.extract(r'(\d+)\s*-\s*(\d+)'); X['hg']=pd.to_numeric(sc[0],errors='coerce'); X['ag']=pd.to_numeric(sc[1],errors='coerce')
X=X[X.hg.notna()&X.mt.notna()].copy(); X['res']=np.where(X.hg>X.ag,'H',np.where(X.hg<X.ag,'A','D')); X['tg']=X.hg+X.ag
print("settled matches:",len(X),"| leagues:",X.league.nunique(),"| ",X.mt.min().date(),"->",X.mt.max().date(),flush=True)
print("5-min price coverage:",X.hb5.notna().mean().round(3),"| HT CS price coverage:",X.htcs.notna().mean().round(3))
def tstat(x): x=pd.Series(x,dtype=float).dropna(); return float(x.mean()/(x.std(ddof=1)/math.sqrt(len(x)))) if len(x)>2 and x.std(ddof=1)>0 else 0.0
def prof(p): return p*(1-COMM) if p>0 else p
def back(px,won): return np.where(won,(px-1)*(1-COMM),-1.0)
def lay(px,won): return np.where(won,-(px-1),1.0*(1-COMM))          # per £1 stake (liability px-1)
def hedge_back(e,x): p=e/x-1; return np.where(p>0,p*(1-COMM),p)     # back at e, lay at x, per £1
out=[]; surv_rows=[]
def emit(strat,df,col,bandcol='band',quiet=False):
    df=df[df[col].notna()]
    if len(df)<100: return
    df=df.copy(); med=df.mt.median(); df['half']=np.where(df.mt<med,1,2)
    lines=[]
    for band,g in df.groupby(bandcol,observed=True):
        a=g[g.half==1][col]; b=g[g.half==2][col]
        if len(a)<40 or len(b)<40: continue
        p1,p2=a.mean()*100,b.mean()*100; t1,t2=tstat(a),tstat(b); surv=bool(p1>1 and p2>1 and t1>=2 and t2>=2 and len(g)>=100)
        lines.append((band,len(g),p1,t1,p2,t2,surv))
        out.append((today,'FTS',strat,str(band),int(len(g)),int(len(a)),float(round(p1,2)),float(round(t1,2)),int(len(b)),float(round(p2,2)),float(round(t2,2)),float(round(g[col].mean()*100,2)),surv,f"{df.mt.min():%Y-%m}->{df.mt.max():%Y-%m}"))
        if surv: surv_rows.append((strat,str(band),len(g),p1,p2,t1,t2))
    if not quiet and lines:
        print(f"\n== {strat}: n {len(df)} | per £100 {df[col].mean()*100:+.1f} | t {tstat(df[col]):.1f}")
        for band,n,p1,t1,p2,t2,s in lines: print(f"   {str(band):28s} n {n:5d} | h1 {p1:+6.1f} (t {t1:4.1f}) | h2 {p2:+6.1f} (t {t2:4.1f}) {'SURVIVOR' if s else ''}")
# ---------- V1 FTS value & V2 ELO value at 5-min prices
for side,bp,lp,dfts,delo in (('H','hb5','hl5','dfh','deh'),('D','db5','dl5','dfd','ded'),('A','ab5','al5','dfa','dea')):
    won=(X.res==side)
    for nm,dcol in (('FTS',dfts),('ELO',delo)):
        d=X[X[bp].notna()&X[dcol].notna()].copy(); won_=(d.res==side)
        d['band']=pd.cut(d[dcol],[-100,-20,-10,-5,0,5,10,20,100]); d['pnl']=back(d[bp],won_); emit(f'V {nm} value: BACK {side} at 5-min by (model minus BF) pct',d,'pnl')
        d['pnl']=lay(d[lp],won_); emit(f'V {nm} value: LAY {side} at 5-min by (model minus BF) pct',d,'pnl')
# ---------- S1 steam/drift 8am -> 5min, settle at 5-min price ; S2 pre-match trade back 8am -> lay 5min
for side,b8,bp,lp,mv in (('H','h8','hb5','hl5','mvh'),('D','d8','db5','dl5','mvd'),('A','a8','ab5','al5','mva')):
    d=X[X[bp].notna()&X[mv].notna()].copy(); won_=(d.res==side)
    d['band']=pd.cut(d[mv],[-100,-15,-8,-3,3,8,15,100]); d['pnl']=back(d[bp],won_); emit(f'S1 BACK {side} at 5-min by 8am->5min move pct (neg = steamed)',d,'pnl')
    d['pnl']=lay(d[lp],won_); emit(f'S1 LAY {side} at 5-min by 8am->5min move pct',d,'pnl')
    d['tr']=hedge_back(d[b8],d[lp])   # back at 8am, lay out at 5-min lay price
    d['band']=pd.cut(d['dfh' if side=='H' else 'dfd' if side=='D' else 'dfa'],[-100,-20,-10,-5,0,5,10,20,100]); emit(f'S2 PRE-MATCH TRADE {side}: back 8am, lay 5-min, by FTS-vs-BF pct',d,'tr')
    d['band']=pd.cut(d['deh' if side=='H' else 'ded' if side=='D' else 'dea'],[-100,-20,-10,-5,0,5,10,20,100]); emit(f'S2 PRE-MATCH TRADE {side}: back 8am, lay 5-min, by ELO-vs-BF pct',d,'tr')
    d['band']=pd.cut(d[b8],[1,1.5,2,3,5,10,1000]); emit(f'S2 PRE-MATCH TRADE {side}: back 8am, lay 5-min, by 8am price',d,'tr')
# ---------- F1 form colours
d=X[X.hb5.notna()].copy(); d['band']=d.ch.astype(str)+'/'+d.ca.astype(str)
for side,bp,lp in (('H','hb5','hl5'),('D','db5','dl5'),('A','ab5','al5')):
    won_=(d.res==side); d['pnl']=back(d[bp],won_); emit(f'F1 form colours (home/away): BACK {side} at 5-min',d,'pnl')
    d['pnl']=lay(d[lp],won_); emit(f'F1 form colours (home/away): LAY {side} at 5-min',d,'pnl')
# ---------- G1 over/under
for line,ub,ul,ob,ol in ((1.5,'u15b','u15l','o15b','o15l'),(2.5,'u25b','u25l','o25b','o25l'),(3.5,'u35b','u35l','o35b','o35l')):
    d=X[X[ob].notna()].copy(); over=(d.tg>line)
    d['band']=pd.cut(d[ob],[1,1.4,1.6,1.8,2.0,2.3,2.7,3.5,20]); d['pnl']=back(d[ob],over); emit(f'G1 BACK over {line} by price',d,'pnl'); d['pnl']=lay(d[ol],over); emit(f'G1 LAY over {line} by price',d,'pnl')
    d['band']=pd.cut(d[ub],[1,1.4,1.6,1.8,2.0,2.3,2.7,3.5,20]); d['pnl']=back(d[ub],~over); emit(f'G1 BACK under {line} by price',d,'pnl'); d['pnl']=lay(d[ul],~over); emit(f'G1 LAY under {line} by price',d,'pnl')
    d['band']=pd.cut(d.fave.fillna(0)+d.aave.fillna(0),[-1,1.5,2.5,3.5,4.5,10]); d['pnl']=back(d[ob],over); emit(f'G1 BACK over {line} by form points (home ave + away ave)',d,'pnl')
# ---------- H1 HT correct-score lay (lay the HT score in FT CS market at HT; wins if the score changes)
d=X[X.htcs.notna()&X.ht.notna()].copy(); changed=(d.ht.str.replace(' ','')!=d.ft.str.replace(' ',''))
d['pnl']=lay(d.htcs,~changed); d['band']=pd.cut(d.htcs,[1,1.5,2,2.5,3,4,6,10,100]); emit('H1 HT CS LAY by lay price',d,'pnl')
d['band']=d.ht.str.replace(' ',''); emit('H1 HT CS LAY by HT score',d,'pnl')
d['band']=d.league; emit('H1 HT CS LAY by league',d,'pnl',quiet=True)
print("\nFTS own HT CS return column total:",round(float(d.htcs_ret.sum()),1),"vs ours:",round(float(d.pnl.sum()),1))
# ---------- write + survivors summary
cur.execute("DELETE FROM strategy_results WHERE run_date=%s AND sport='FTS'",(today,))
psycopg2.extras.execute_values(cur,"INSERT INTO strategy_results VALUES %s",out); print("\ncells written:",len(out))
print("\n=== SURVIVORS (both halves >1 per £100, t>=2 both, n>=100) ===")
S=pd.DataFrame(surv_rows,columns=['strategy','band','n','h1','h2','t1','t2']).sort_values('h2',ascending=False)
print(S.to_string(index=False) if len(S) else "none")
PYFILE
python3 -m py_compile fts_battery.py || exit 1
timeout 3300 python3 fts_battery.py 2>&1 | grep -v -E "UserWarning|pd.read_sql"
