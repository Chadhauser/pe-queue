#!/bin/bash
# 526: Saturday-build items 1-3, started Mon 16 Nov (Peter: "carry on with the build"). portfolio_lab.py = rating simulator
# (Darwinex-style PROXY: return per unit of drawdown, positive months, CAGR when rescaled to 6.5% monthly VaR), sizing-for-rating
# (fixed, vol-target, DD throttle, risk cap, quarter-Kelly fitted on the first half) and the ORB+M7b signal portfolio with its
# correlation. Judged on the second half only. Noise leak test passed offline (no sizer turns a zero-mean stream into profit).
# Output: scoreboard/portfolio.md in the repo + a Verifier row. Also fixes a false alarm: data health flagged every feed BROKEN on
# Monday mornings (last bar Friday night > 30h ago); Sat/Sun/Mon now allow 80h.
cd /root/pe-fin/team || exit 1
cat > portfolio_lab.py <<'PY'
# PORTFOLIO LAB — Saturday-build items 1-3 (rating simulator, sizing-for-rating, signal portfolio).
# Inputs: the two verified QQQ edges as daily return streams (0 on no-trade days):
#   ORB  = 5-min ORB on QQQ with gap guard (R-multiples per trade; equity return = risk_fraction * R)
#   M7b  = last-hour momentum, QQQ >=1.5% by 15:00 -> with it to close (bps on notional; equity return = leverage * bps/1e4)
# Every sizing rule uses only information available BEFORE the day it sizes (rolling stats shifted 1 day); anything fitted
# (Kelly fraction, vol target) is fitted on the FIRST half and judged on the SECOND half only.
# Rating proxy: Darwinex rescales every strategy to a fixed monthly risk budget, so what a rating rewards is return per unit of
# drawdown, not raw return. We report Calmar (CAGR / max drawdown), share of positive months, worst month, and the CAGR the curve
# would show if rescaled to a 6.5% monthly 95% VaR (the classic DARWIN risk target; Zero's exact formula is not public, so this is
# a PROXY and labelled as such). Output: /root/pe-fin/team/public/portfolio.md (published to the repo with the scoreboard).
import sys, math, json, datetime as dt, numpy as np, pandas as pd
sys.path.insert(0,'/root/pe-fin'); sys.path.insert(0,'/root/pe-fin/team')
OUT='/root/pe-fin/team/public/portfolio.md'
def load_streams():
    from mech2 import orb5, bars
    import mech_next
    orb=orb5('QQQ')                                            # R per trade, cost included
    m7=mech_next.H['M7b']()/1e4                                # fraction of notional per trade, cost included
    days=pd.Index(sorted(set(bars('QQQ').d)))
    days=pd.to_datetime(days)
    orb.index=pd.to_datetime(orb.index); m7.index=pd.to_datetime(m7.index)
    return pd.DataFrame({'ORB':orb.reindex(days).fillna(0.0),'M7b':m7.reindex(days).fillna(0.0)})
def metrics(r):
    r=r.dropna(); eq=(1+r).cumprod(); yrs=len(r)/252
    cagr=eq.iloc[-1]**(1/yrs)-1 if yrs>0 and eq.iloc[-1]>0 else -1
    dd=(eq/eq.cummax()-1).min(); vol=r.std()*math.sqrt(252)
    m=(1+r).groupby([r.index.year,r.index.month]).prod()-1
    var95=-np.percentile(m,5) if len(m)>5 else np.nan
    scale=0.065/var95 if var95 and var95>0 else np.nan
    rm=(1+r*scale).cumprod() if scale==scale else None
    cagr_d=(rm.iloc[-1]**(1/yrs)-1) if rm is not None and rm.iloc[-1]>0 else np.nan
    dd_d=(rm/rm.cummax()-1).min() if rm is not None else np.nan
    return dict(cagr=cagr,vol=vol,sharpe=(r.mean()/r.std()*math.sqrt(252)) if r.std()>0 else 0,maxdd=dd,calmar=cagr/abs(dd) if dd<0 else np.nan,
                pos_months=float((m>0).mean()),worst_month=float(m.min()),var95_m=var95,cagr_at_dvar=cagr_d,dd_at_dvar=dd_d)
def roll_vol(x,n=60): return x.rolling(n,min_periods=20).std().shift(1)*math.sqrt(252)
def sizers(U,half):
    """U = unit streams (ORB per 1R risk, M7b per 1x notional). Returns dict name -> daily equity returns."""
    out={}
    out['fixed 0.5% risk ORB only']=0.005*U.ORB
    out['fixed 1% risk ORB only']=0.010*U.ORB
    out['fixed 1% ORB + 1x M7b']=0.010*U.ORB+1.0*U.M7b
    def vt(orb_cap):
        leg={}
        for c in U:
            v=roll_vol(U[c]); w=(0.10/v).clip(upper=(orb_cap if c=='ORB' else 3.0)).fillna(0)   # caps: ORB max risk/trade, M7b 3x notional
            leg[c]=w*U[c]
        combo=pd.DataFrame(leg).mean(axis=1); k=(0.10/roll_vol(combo)).clip(upper=3).fillna(0)
        # final ORB risk after the combo scaling must still respect the cap
        return (pd.DataFrame(leg).mul(k,axis=0)/2).pipe(lambda d: d.assign(ORB=d.ORB.where(d.ORB.abs()<=orb_cap*U.ORB.abs()+1e-12, np.sign(d.ORB)*orb_cap*U.ORB.abs()))).sum(axis=1)
    def throttle(r):
        eq=1.0; hwm=1.0; adj=[]
        for x in r.values:
            f=0.5 if eq/hwm<0.95 else 1.0; y=f*x; adj.append(y); eq*=1+y; hwm=max(hwm,eq)
        return pd.Series(adj,index=r.index)
    out['vol-target 10%, ORB+M7b']=vt(0.03)
    out['vol-target + DD throttle']=throttle(out['vol-target 10%, ORB+M7b'])
    out['vol-target, max 1.5% risk/trade + DD throttle']=throttle(vt(0.015))
    # quarter-Kelly per leg, fitted on the first half only, applied everywhere (judge on second half)
    kel={}
    for c in U:
        a=U[c].iloc[:half]; a=a[a!=0]; f=(a.mean()/a.var()) if a.var()>0 else 0
        kel[c]=max(0.0,0.25*f)
    kel['ORB']=min(kel['ORB'],0.03); kel['M7b']=min(kel['M7b'],3.0)
    out[f"quarter-Kelly (ORB {kel['ORB']:.3f}, M7b {kel['M7b']:.2f}x) fit on 1st half"]=kel['ORB']*U.ORB+kel['M7b']*U.M7b
    return out
def run(U):
    half=len(U)//2; S=sizers(U,half)
    corr=U.replace(0,np.nan).corr().iloc[0,1]; corr_all=U.corr().iloc[0,1]
    L=[f"# Portfolio lab — rating simulator (PROXY) — {dt.datetime.utcnow():%Y-%m-%d %H:%M} UTC","",
       f"Streams: ORB-QQQ {int((U.ORB!=0).sum())} trades, M7b {int((U.M7b!=0).sum())} trades, {len(U)} days {U.index[0].date()} -> {U.index[-1].date()}.",
       f"Correlation ORB vs M7b daily: {corr_all:+.2f} (all days), {corr:+.2f} (days both traded). Low = they diversify.","",
       "Judged on the SECOND half only (anything fitted used the first half). D-VaR CAGR = CAGR if rescaled to 6.5% monthly 95% VaR (Darwinex-style).","",
       "| sizing | CAGR | vol | Sharpe | max DD | Calmar | +months | worst month | D-VaR CAGR | D-VaR max DD |","|---|---|---|---|---|---|---|---|---|---|"]
    best=None
    for name,r in S.items():
        m=metrics(r.iloc[half:])
        L.append(f"| {name} | {m['cagr']:+.1%} | {m['vol']:.1%} | {m['sharpe']:.2f} | {m['maxdd']:.1%} | {m['calmar']:.2f} | {m['pos_months']:.0%} | {m['worst_month']:+.1%} | {m['cagr_at_dvar']:+.1%} | {m['dd_at_dvar']:.1%} |")
        if best is None or (m['calmar']==m['calmar'] and m['calmar']>best[1]['calmar']): best=(name,m)
    full=metrics(S[best[0]])
    L+=["",f"**Best by Calmar (2nd half): {best[0]}** — whole-history check: CAGR {full['cagr']:+.1%}, max DD {full['maxdd']:.1%}, Calmar {full['calmar']:.2f}, positive months {full['pos_months']:.0%}.",
        "Reading: a rating that rewards return per unit of drawdown wants the row with the highest Calmar and positive months, not the highest CAGR.",
        "Caveats: rating formula is a proxy; costs are the backtest's (1c spread + 1c slip/side on QQQ) — a CFD at Darwinex charges its own spread, measured once the MT5 demo runs."]
    return "\n".join(L), best
if __name__=='__main__':
    U=load_streams(); md,best=run(U)
    import os; os.makedirs(os.path.dirname(OUT),exist_ok=True); open(OUT,'w').write(md); print(md)
    print("RESULT "+json.dumps(dict(name=f"PORTFOLIO best sizing: {best[0]} | 2nd-half Calmar {best[1]['calmar']:.2f} maxDD {best[1]['maxdd']:.1%} (control: n/a, diagnostic)",n=len(U),mean_bps=f"CAGR {best[1]['cagr']:+.1%}",t=0,is_mean=0,is_t=0,oos_mean=0,oos_t=0,control_t=0)))
PY
python3 -m py_compile portfolio_lab.py || exit 1
python3 - <<'PY'
s=open('fin_team.py').read()
old="stale=(now-last)>pd.Timedelta(hours=30 if wk else 72)"
if old in s: s=s.replace(old,"stale=(now-last)>pd.Timedelta(hours=30 if now.weekday() in (1,2,3,4) else 80)"); open('fin_team.py','w').write(s); print("data-health weekend fix applied")
else: print("data-health line not found — left as is")
import json; reg=json.load(open('hypotheses.json')); have={h['id'] for h in reg['hypotheses']}
if 'PORTFOLIO lab' not in have:
    reg['hypotheses'].append({"id":"PORTFOLIO lab","script":"/root/pe-fin/team/portfolio_lab.py","status":"proposed","pre_registered_sign":"diagnostic: best sizing by 2nd-half Calmar","next_door":"MT5 bridge (Saturday item 4) sized with the winning rule","timeout":3600})
json.dump(reg,open('hypotheses.json','w'),indent=1); print("PORTFOLIO lab registered")
PY
python3 -m py_compile fin_team.py || exit 1
python3 -I portfolio_lab.py 2>&1 | tail -16
pkill -f 'fin_team.py'; sleep 1; nohup /root/pe-fin/team/run_team.sh >/dev/null 2>&1 & disown; sleep 3; pgrep -f fin_team.py >/dev/null && echo "daemon restarted" || echo "DAEMON NOT RUNNING"
/root/pe-fin/team/publish.sh; echo published
