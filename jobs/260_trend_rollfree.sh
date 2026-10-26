#!/bin/bash
# 260: TREND PORTFOLIO ON ROLL-FREE INSTRUMENTS (241 showed roll gaps cost 0.17 Sharpe and the result was still 0.10 vs 0.4 published).
# Universe = what a UK spread-bet book actually trades: cash indices, spot FX, spot metals/commodity ETFs, bond ETFs. No futures rolls, total-return ETFs.
# 241 (fixes 232): store bug (np.float64 -> float) and a ROLL-GAP DIAGNOSTIC — yfinance '=F' is stitched front-month with roll
# jumps left in, which a trend rule reads as price moves. Flag |daily return| > 6 sigma (rolling 60d) per instrument, count them, and
# rerun the whole portfolio with those days' returns set to 0 (both for signal and P&L). If Sharpe moves materially, the data is the
# problem and we need back-adjusted series before the trend verdict means anything.
# 232: FINANCIAL — TREND FOLLOWING AT PORTFOLIO LEVEL (the research verdict: a single instrument at Sharpe ~0.4 needs ~24y of data
# to show up, so 66x55 single cells over 16y found nothing even if the edge is real; the published evidence is for a diversified
# portfolio). Rules copied from Carver (Systematic Trading / pysystemtrade defaults) + Moskowitz-Ooi-Pedersen 12m TSMOM:
#   forecasts: EWMAC 16/64, 32/128, 64/256 = (EWMA_fast - EWMA_slow) / daily price vol; TSMOM12 = sign(12m excess return) * 10
#   each forecast scaled so its long-run mean |f| = 10, capped +-20; combined with equal weights; position = f/10 * (target vol /
#   instrument vol), instrument weight 1/N; portfolio vol target 20% annualised; 10%-of-position buffer before trading;
#   cost 0.03% per unit of |position change| (brief's conservative table), FX via =F futures proxies.
# Data: yfinance daily continuous futures (front-month, yfinance's own roll) from 2000 for ~35 instruments across 6 sectors.
# Split: IS 2000-2014 / OOS 2015-today, NO parameter fitting (Carver's published defaults) so the IS/OOS split is a stability check.
# Synthetic: random walks with each instrument's vol on the same dates must give portfolio Sharpe ~0.
# Report: portfolio Sharpe/t/maxDD/CAGR, by year, by sector, each forecast alone, the published benchmark (0.4 net planning /
# 0.76 net 1880-2016 AQR), and what £250k at this Sharpe pays per month. Stores v4_trend_rollfree.
mkdir -p /root/pe-factory/v4 && cd /root/pe-factory/v4
cat > trend_rollfree.py <<'PYFILE'
CLEAN='--clean' in __import__('sys').argv
import sys, math, datetime, warnings, numpy as np, pandas as pd
warnings.filterwarnings('ignore'); pd.set_option('display.width',250)
SYNTH='--synthetic' in sys.argv
UNI={'equity':['^GSPC','^NDX','^DJI','^RUT','^GDAXI','^FTSE','^N225','^HSI','^STOXX50E','^AXJO'],
     'bond':['TLT','IEF','SHY','LQD','HYG'],
     'fx':['EURUSD=X','GBPUSD=X','USDJPY=X','AUDUSD=X','USDCAD=X','USDCHF=X','NZDUSD=X','EURGBP=X'],
     'metal':['GLD','SLV','PPLT','CPER'],
     'energy':['USO','UNG','BNO'],
     'ag':['DBA','CORN','WEAT','SOYB','CANE']}
COST=0.0003; VOL_TARGET=0.20; START='2000-01-01'; OOS='2015-01-01'
def declip(c):
    r=np.log(c).diff(); sd=r.rolling(60,min_periods=30).std(); bad=(r.abs()>6*sd.shift(1)).fillna(False)
    if CLEAN: r2=r.where(~bad,0.0); return pd.Series(c.iloc[0]*np.exp(r2.fillna(0).cumsum()),index=c.index), int(bad.sum())
    return c, int(bad.sum())
def load():
    import yfinance as yf; data={}; GAPS={}
    for sec,ts in UNI.items():
        for t in ts:
            try:
                df=yf.download(t,start=START,progress=False,auto_adjust=True,threads=False)
                if isinstance(df.columns,pd.MultiIndex): df.columns=df.columns.get_level_values(0)
                c=df['Close'].dropna(); c=c[c>0]
                if len(c)<1000: print('skip',t,len(c)); continue
                c,ng=declip(c); GAPS[t]=ng; data[(sec,t)]=c
            except Exception as e: print('skip',t,repr(e)[:60])
    if SYNTH:
        rng=np.random.default_rng(11)
        for k,c in data.items():
            r=np.log(c).diff().dropna(); s=rng.normal(0,r.std(),len(c)); data[k]=pd.Series(100*np.exp(np.cumsum(s)),index=c.index)
    if not SYNTH: print('roll-gap days (>6 sigma) per instrument:',GAPS,'| total',sum(GAPS.values()),'| CLEAN mode' if CLEAN else '| RAW mode')
    return data
def ewmac(c,f,s):
    vol=c.diff().ewm(span=36).std(); return ((c.ewm(span=f).mean()-c.ewm(span=s).mean())/vol)
def tsmom(c): return np.sign(c/c.shift(252)-1)*10
def scale(f):
    sc=10/f.abs().expanding(min_periods=250).mean(); return (f*sc).clip(-20,20)
def run(data):
    rets=pd.DataFrame({tk:c.pct_change() for (sec,tk),c in data.items()}).fillna(0); N=len(rets.columns)
    inst_vol=rets.ewm(span=36).std()*math.sqrt(252); fcs={}
    for name,fn in (('ewmac16',lambda c:ewmac(c,16,64)),('ewmac32',lambda c:ewmac(c,32,128)),('ewmac64',lambda c:ewmac(c,64,256)),('tsmom12',tsmom)):
        fcs[name]=pd.DataFrame({tk:scale(fn(c)) for (sec,tk),c in data.items()}).reindex(rets.index)
    comb=sum(fcs.values())/len(fcs); comb=comb.clip(-20,20)
    def positions(f):
        pos=(f/10)*(VOL_TARGET/inst_vol.replace(0,np.nan))/N; pos=pos.fillna(0)
        # buffer: only move when change > 10% of |position|
        out=pos.copy(); prev=pos.iloc[0]*0
        vals=pos.values; o=np.zeros_like(vals)
        for i in range(len(vals)):
            cur=vals[i]; move=np.abs(cur-prev)>0.1*np.abs(cur); prev=np.where(move,cur,prev); o[i]=prev
        return pd.DataFrame(o,index=pos.index,columns=pos.columns)
    results={}
    for name,f in list(fcs.items())+[('COMBINED',comb)]:
        pos=positions(f).shift(1).fillna(0); turn=pos.diff().abs().fillna(0)
        pnl=(pos*rets).sum(axis=1)-COST*turn.sum(axis=1); results[name]=(pnl,pos)
    return results,rets
def stats(p):
    p=p[p.index>='2001-01-01']
    if len(p)<250 or p.std()==0: return None
    sh=p.mean()/p.std()*math.sqrt(252); t=p.mean()/(p.std()/math.sqrt(len(p))); eq=(1+p).cumprod(); dd=((eq/eq.cummax())-1).min()
    return dict(sharpe=round(sh,2),t=round(t,2),cagr=round(eq.iloc[-1]**(252/len(p))-1,4),vol=round(p.std()*math.sqrt(252),3),maxdd=round(dd,3),n_days=len(p))
def main():
    data=load(); print('instruments',len(data),'| synthetic' if SYNTH else '| real',flush=True)
    results,rets=run(data)
    print(f"\n=== PORTFOLIO (N={len(rets.columns)}, vol target {VOL_TARGET}, cost {COST}/unit change, Carver defaults, no fitting) ===")
    for name,(pnl,pos) in results.items():
        a=stats(pnl); i=stats(pnl[pnl.index<OOS]); o=stats(pnl[pnl.index>=OOS])
        print(f"  {name:9s} ALL {a} | IS<2015 Sharpe {i['sharpe'] if i else None} t {i['t'] if i else None} | OOS>=2015 Sharpe {o['sharpe'] if o else None} t {o['t'] if o else None}")
    pnl,pos=results['COMBINED']
    print('\nCOMBINED by year:'); yr=pnl.groupby(pnl.index.year).agg(['sum',lambda s:s.mean()/s.std()*math.sqrt(252) if s.std()>0 else 0]); yr.columns=['ret','sharpe']; print(yr.round(3).T.to_string())
    print('\nCOMBINED by sector (Sharpe of sector sleeve):')
    for sec in UNI:
        cols=[tk for (s,tk) in data if s==sec]
        if cols:
            sp=(pos[cols]*rets[cols]).sum(axis=1); s=stats(sp); print(f"  {sec:7s} n={len(cols)} {s}")
    a=stats(pnl); print(f"\nBENCHMARK: AQR 1880-2016 net Sharpe 0.76 (VERIFIED), planning number 0.4 net. This run: {a['sharpe']} over {a['n_days']} days ({a['n_days']/252:.1f}y).")
    print(f"At this Sharpe and 20% vol: expected return {a['sharpe']*VOL_TARGET*100:.1f}%/yr -> £250k pays ~£{250000*a['sharpe']*VOL_TARGET/12:,.0f}/month; £50k ~£{50000*a['sharpe']*VOL_TARGET/12:,.0f}/month. Max DD seen {a['maxdd']*100:.0f}%.")
    print("CAVEATS: yfinance front-month continuous (roll gaps not adjusted), no carry sleeve yet, no financing on FX, survivorship-free (all live contracts).")
    if not SYNTH:
        import psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
        con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
        cur.execute("CREATE TABLE IF NOT EXISTS v4_trend_rollfree (run_date DATE, forecast TEXT, period TEXT, sharpe NUMERIC, t NUMERIC, cagr NUMERIC, vol NUMERIC, maxdd NUMERIC, n_days INT, n_inst INT)")
        cur.execute("DELETE FROM v4_trend_rollfree WHERE run_date=current_date")
        for name,(p,_) in results.items():
            for per,sl in (('ALL',p),('IS',p[p.index<OOS]),('OOS',p[p.index>=OOS])):
                s=stats(sl)
                if s: cur.execute("INSERT INTO v4_trend_rollfree VALUES (current_date,%s,%s,%s,%s,%s,%s,%s,%s,%s)",(name+('_clean' if CLEAN else ''),per,*(float(s[k]) for k in ('sharpe','t','cagr','vol','maxdd')),int(s['n_days']),int(len(rets.columns))))
        print('stored v4_trend_rollfree')
main()
PYFILE
python3 -m py_compile trend_rollfree.py || exit 1
echo "== synthetic control (must be ~0)"; timeout 1200 python3 trend_rollfree.py --synthetic 2>&1 | grep -E "instruments|COMBINED "
echo; echo "== REAL, roll-free universe"; timeout 1500 python3 trend_rollfree.py 2>&1 | grep -v Warning
