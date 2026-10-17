#!/bin/bash
# 097: TENNIS SYSTEMS ON THE NEW HISTORY (Peter 17 Oct: "I can't believe only one strategy in tennis works"). bf_hist_other is
# filling with Basic tennis MATCH_ODDS history (LTP per runner per minute, pre-match and in-play, Sep 2024 -> Sep 2026 once the
# loader finishes). Winner = runner whose last in-play LTP < 1.10. Tests, each by price band, by month halves (train/test), 2pct
# spread, 2pct comm, P&L per £100 risk, t-stat:
#  A. Trend Report slam-style LAYS: lay the player priced 2.0-10.0 at the last pre-match LTP, settle at result (bands 2-3,3-4.5,4.5-6,6-10).
#  B. BACK short favourites (Hammer pre-match proxy): back fav <=1.30 / 1.30-1.50 at start, settle at result.
#  C. HAMMER in-play: fav <=1.30 pre-match drifts in-play to >=1.60 (a break conceded) -> back at the drift, settle at result;
#     and the trade version: back at drift, lay when back to within 10pct of start price, else settle.
#  D. MONEY METHOD proxy: lay fav <1.50 at start; close (back) when fav first trades >= 1.25x start in-play (green) or settle if never.
#  E. T2 (the live bot's logic) re-measured on this history: fav 1.30-2.00 drifts to >=2x start -> back, settle. Gives the bot
#     a 2-year sample instead of 100 trades.
# WAITS (exit 75) until >=6 tennis months are DONE. Verdict rule as always: positive in both halves with t>=2 both.
cd /root/pe-scan && cat > tennis_hist_test.py <<'PYFILE'
import sys, math, psycopg2, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
SPREAD=0.02; COMM=0.02
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor()
cur.execute("SELECT count(*) FROM bf_hist_months WHERE sport='Tennis' AND status='DONE'"); n=cur.fetchone()[0]
print("tennis months loaded:",n)
if n<6: print("WAITING: need 6 tennis months"); sys.exit(75)
D=pd.read_sql("SELECT market_id, event_name, market_time, sel, ts, ltp::float ltp, inplay FROM bf_hist_other WHERE sport='Tennis' AND market_type='MATCH_ODDS' ORDER BY market_id, ts",con)
print("rows",len(D),"markets",D.market_id.nunique(),D.market_time.min(),"->",D.market_time.max(),flush=True)
rows=[]
for mid,g in D.groupby('market_id'):
    sels=g.sel.unique()
    if len(sels)!=2: continue
    pre=g[~g.inplay]; ip=g[g.inplay]
    if pre.empty or ip.empty: continue
    sp={s:pre[pre.sel==s].ltp.iloc[-1] for s in sels if not pre[pre.sel==s].empty}
    if len(sp)!=2: continue
    last={s:ip[ip.sel==s].ltp.iloc[-1] for s in sels if not ip[ip.sel==s].empty}
    if len(last)!=2: continue
    win=[s for s in sels if last[s]<1.10]
    if len(win)!=1: continue
    fav=min(sp,key=sp.get); dog=max(sp,key=sp.get)
    fi=ip[ip.sel==fav]
    rows.append(dict(mid=mid,ev=g.event_name.iloc[0],mt=g.market_time.iloc[0],fav_sp=sp[fav],dog_sp=sp[dog],fav_won=(win[0]==fav),
                     fav_max=fi.ltp.max(),fav_ip=list(fi.ltp.values)))
M=pd.DataFrame(rows); print("settled 2-runner markets with pre-match and in-play prices:",len(M),flush=True)
M['month']=pd.to_datetime(M.mt).dt.to_period('M').astype(str); med=pd.to_datetime(M.mt).median(); M['half']=np.where(pd.to_datetime(M.mt)<med,'h1','h2')
def tstat(x): x=pd.Series(x).dropna(); return round(float(x.mean()/(x.std(ddof=1)/math.sqrt(len(x)))),1) if len(x)>2 and x.std(ddof=1)>0 else 0.0
def rep(df,col,title,by='band'):
    if df.empty: print(f"\n=== {title}: no qualifiers ==="); return
    print(f"\n=== {title}: n {len(df)} | P&L per £100 risk {df[col].mean()*100:+.1f} | t {tstat(df[col])} ===")
    g=df.groupby([by,'half'])[col].agg(['size','mean']).unstack('half'); print((g*[1,1,100,100] if g.shape[1]==4 else g).round(1).to_string())
    print("by month:",df.groupby('month')[col].mean().mul(100).round(1).to_dict())
# A. lay the 2.0-10 priced player at SP (per £1 liability)
A=M[(M.dog_sp>=2.0)&(M.dog_sp<=10)].copy(); A['band']=pd.cut(A.dog_sp,[2,3,4.5,6,10]); A['lay_px']=A.dog_sp*(1+SPREAD)
A['pnl']=np.where(~A.fav_won,-1.0,(1/(A.lay_px-1))*(1-COMM)); rep(A,'pnl','A. LAY the 2.0-10 priced player at SP, per £1 liability')
# B. back short favs
B=M[M.fav_sp<=1.5].copy(); B['band']=pd.cut(B.fav_sp,[1,1.15,1.3,1.5]); B['pnl']=np.where(B.fav_won,(B.fav_sp*(1-SPREAD)-1)*(1-COMM),-1.0); rep(B,'pnl','B. BACK favourite <=1.50 at SP, per £1 stake')
# C. Hammer: fav<=1.30 drifts to >=1.60 in play -> back there
C=M[(M.fav_sp<=1.30)&(M.fav_max>=1.60)].copy(); C['band']=pd.cut(C.fav_sp,[1,1.15,1.30])
C['entry']=[next(p for p in ip if p>=1.60) for ip in C.fav_ip]; C['pnl']=np.where(C.fav_won,(C.entry*(1-SPREAD)-1)*(1-COMM),-1.0)
rep(C,'pnl','C1. HAMMER hold: back fav<=1.30 when it drifts to 1.60+, settle')
def trade(r):
    e=r.entry*(1-SPREAD); seen=False
    for p in r.fav_ip:
        if not seen: seen=(p>=1.60); continue
        if p<=r.fav_sp*1.10: x=p*(1+SPREAD); return (e/x-1)*(1-COMM)
    return (e-1)*(1-COMM) if r.fav_won else -1.0
C['pnl2']=C.apply(trade,axis=1); rep(C,'pnl2','C2. HAMMER trade: back at 1.60+, lay out when back within 10pct of SP, else settle')
# D. Money method proxy: lay fav<1.50 at SP, back out when fav >= 1.25x SP, else settle (per £1 lay stake)
Dm=M[M.fav_sp<1.5].copy(); Dm['band']=pd.cut(Dm.fav_sp,[1,1.15,1.3,1.5])
def money(r):
    e=r.fav_sp*(1+SPREAD); tgt=r.fav_sp*1.25
    for p in r.fav_ip:
        if p>=tgt: x=p*(1-SPREAD); return (1-e/x)*(1-COMM)   # lay at e, back at x, per £1 stake
    return (1-COMM) if not r.fav_won else -(e-1)
Dm['pnl']=Dm.apply(money,axis=1); rep(Dm,'pnl','D. MONEY METHOD proxy: lay fav<1.50 at SP, green at +25pct drift, else settle')
# E. T2 on history: fav 1.30-2.00 drifts to >=2x SP -> back, settle
E=M[(M.fav_sp>=1.30)&(M.fav_sp<=2.0)&(M.fav_max>=2*M.fav_sp)].copy(); E['band']=pd.cut(E.fav_sp,[1.3,1.5,1.7,2.0])
E['entry']=[next(p for p,s in zip(ip,[sp]*len(ip)) if p>=2*s) for ip,sp in zip(E.fav_ip,E.fav_sp)]
E['pnl']=np.where(E.fav_won,(E.entry*(1-SPREAD)-1)*(1-COMM),-1.0); rep(E,'pnl','E. T2 on 2 years: back fav 1.30-2.00 at 2x SP drift, settle')
print("\nVERDICT RULE: a system is a candidate only if positive in BOTH halves with t>=2 in both; candidates go to the tennis bot at £3 alongside T2.")
PYFILE
python3 tennis_hist_test.py
