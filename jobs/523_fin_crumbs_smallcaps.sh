#!/bin/bash
# 523: CRUMBS — capacity-limited edges in US small/illiquid caps, where the big money can't deploy. Universe from Nasdaq Trader
# symbol files, consolidated daily bars + historic earnings dates from Yahoo (yfinance), S&P 500 add/delete table from Wikipedia.
# Six pre-registered hypotheses (PEAD, non-earnings gap fade, earnings gap continuation, 5-day reversal, S&P addition flow,
# quarter-end unwind), 30 bps round-trip cost for thin names, random-sign control, clustered tests also graded by date.
# Weekly refresh Sunday 02:10 UTC. Pushed Sat 14 Nov on Peter's "do now".
mkdir -p /root/pe-data/crumbs && cd /root/pe-fin/team || exit 1
cat > crumbs_pull.py <<'PY'
# CRUMBS data: US small/illiquid-cap universe + daily bars + earnings dates + S&P 500 add/delete list.
# Sources (all free, all reachable from the box already): Nasdaq Trader symbol files (universe), Yahoo via yfinance (daily
# consolidated OHLCV and historic earnings dates), Wikipedia (S&P 500 changes table). Alpaca's free IEX feed is NOT used here:
# it carries only IEX-executed trades, which for thin names is a fraction of the tape and would understate volume and ranges.
import os, sys, io, time, json, datetime as dt, requests, pandas as pd, numpy as np
OUT='/root/pe-data/crumbs'; os.makedirs(OUT,exist_ok=True)
def universe():
    syms=[]
    for url,col in (('https://www.nasdaqtrader.com/dynamic/SymDir/nasdaqlisted.txt','Symbol'),('https://www.nasdaqtrader.com/dynamic/SymDir/otherlisted.txt','ACT Symbol')):
        t=requests.get(url,timeout=60).text; df=pd.read_csv(io.StringIO(t),sep='|'); df=df[~df[col].astype(str).str.contains(r'[\.\$\^]',regex=True)]
        if 'ETF' in df: df=df[df['ETF']!='Y']
        if 'Test Issue' in df: df=df[df['Test Issue']!='Y']
        syms+=df[col].astype(str).tolist()
    syms=sorted({s for s in syms if s.isalpha() and 1<=len(s)<=5}); print("universe raw",len(syms)); return syms
def daily(syms, start='2021-01-01'):
    import yfinance as yf
    frames=[]
    for i in range(0,len(syms),200):
        chunk=syms[i:i+200]
        try: d=yf.download(chunk,start=start,group_by='ticker',auto_adjust=False,threads=True,progress=False)
        except Exception as e: print("chunk fail",i,repr(e)[:80]); continue
        for s in chunk:
            try:
                x=d[s].dropna(how='all')
                if len(x)<200: continue
                x=x.rename(columns=str.lower)[['open','high','low','close','volume']]; x['sym']=s; frames.append(x)
            except Exception: pass
        print("daily chunk",i,"frames",len(frames),flush=True); time.sleep(1)
    D=pd.concat(frames); D.index.name='date'; return D
if __name__=='__main__':
    syms=universe()
    D=daily(syms); D.to_parquet(f"{OUT}/daily_all.parquet"); print("daily rows",len(D),"symbols",D.sym.nunique())
    # pick the thin end: average daily dollar volume $1m-$30m over the last year, price $3-$60
    last=D[D.index>=str(dt.date.today()-dt.timedelta(days=365))]; g=last.groupby('sym')
    stats=pd.DataFrame(dict(adv=(g.apply(lambda x:(x.close*x.volume).mean())),px=g.close.last(),days=g.size()))
    small=stats[(stats.adv.between(1e6,3e7))&(stats.px.between(3,60))&(stats.days>200)].sort_values('adv')
    small.to_csv(f"{OUT}/universe_small.csv"); print("small/illiquid universe",len(small))
    # earnings dates for the small universe (yfinance, per ticker; slow but once)
    import yfinance as yf
    ed={};
    for n,s in enumerate(small.index):
        try:
            e=yf.Ticker(s).get_earnings_dates(limit=40)
            if e is not None and len(e): ed[s]=sorted({str(i.date()) for i in e.index if i.date()<=dt.date.today()})
        except Exception: pass
        if n%50==0: print("earnings",n,len(ed),flush=True); time.sleep(1)
    json.dump(ed,open(f"{OUT}/earnings_dates.json",'w')); print("earnings dates for",len(ed),"symbols")
    # S&P 500 changes (adds/deletes) from Wikipedia
    try:
        html=requests.get('https://en.wikipedia.org/wiki/List_of_S%26P_500_companies',headers={'User-Agent':'Mozilla/5.0'},timeout=60).text
        tabs=pd.read_html(io.StringIO(html)); ch=[t for t in tabs if t.shape[1]>=5 and 'Date' in str(t.columns)][0]
        ch.columns=['date','add_sym','add_name','del_sym','del_name','reason'][:ch.shape[1]]; ch.to_csv(f"{OUT}/sp500_changes.csv",index=False); print("sp500 changes rows",len(ch))
    except Exception as e: print("sp500 changes failed",repr(e)[:120])
PY
cat > mech_crumbs.py <<'PY'
# MECH-CRUMBS — capacity-limited edges in US small/illiquid caps on consolidated DAILY bars (Yahoo), 2021->. Returns bps per
# trade after a 30 bps round trip (thin-name spread proxy; S&P names 10 bps). Direction pre-registered per docstring; control =
# random sign. K4/K6 use stock-day units that cluster by date, so their t is optimistic: both must also clear the gate on the
# per-date average (printed as 'by_date_t') before anything is called WORKS.  Usage: python3 -I mech_crumbs.py <id> | list
import sys, json, math, datetime as dt, numpy as np, pandas as pd
OUT='/root/pe-data/crumbs'; COST=30.0
D=pd.read_parquet(f"{OUT}/daily_all.parquet"); D=D.reset_index().sort_values(['sym','date'])
small=set(pd.read_csv(f"{OUT}/universe_small.csv",index_col=0).index)
S=D[D.sym.isin(small)].copy(); S['prev']=S.groupby('sym').close.shift(1); S['gap']=S.open/S.prev-1; S['cc']=S.close/S.prev-1; S['oc']=S.close/S.open-1
S['c5f']=S.groupby('sym').close.shift(periods=-5); S['o1f']=S.groupby('sym').open.shift(periods=-1)   # forward prices: used ONLY as the exit of a trade entered today
S['r5b']=S.close/S.groupby('sym').close.shift(5)-1
try: ED=json.load(open(f"{OUT}/earnings_dates.json"))
except Exception: ED={}
edays={(s,d) for s,ds in ED.items() for d in ds}
def near_earn(sym,date,k=1):
    d=pd.Timestamp(date).date(); return any((sym,str(d+dt.timedelta(days=i))) in edays for i in range(-k,k+1))
H={}
def reg(i,doc):
    def w(f): f.__doc__=doc; H[i]=f; return f
    return w
def finish(df,sign_col,ret_col,cost=COST):
    r=(df[sign_col]*df[ret_col]*1e4-cost); return pd.Series(r.values,index=pd.to_datetime(df.date).values).sort_index()
@reg('K1','PEAD small caps: earnings reaction day |close-to-close| >=5% -> SAME sign from next open to close 5 days later.')
def K1():
    rows=[]
    for s,ds in ED.items():
        g=S[S.sym==s].set_index('date')
        for d in ds:
            d=pd.Timestamp(d); cands=g[(g.index>=d)&(g.index<=d+pd.Timedelta(days=3))].head(2)
            if len(cands)<1: continue
            r=cands.iloc[cands.gap.abs().values.argmax()]
            if abs(r.cc)>=0.05 and pd.notna(r.o1f) and pd.notna(r.c5f): rows.append(dict(date=r.name,sign=np.sign(r.cc),ret=r.c5f/r.o1f-1))
    df=pd.DataFrame(rows); return finish(df,'sign','ret')
@reg('K2','Overnight gap fade, small caps, NO earnings within a day: |gap| >=5% -> FADE open->close.')
def K2():
    x=S[(S.gap.abs()>=0.05)&S.oc.notna()].copy(); x=x[[not near_earn(s,d) for s,d in zip(x.sym,x.date)]]; x['sign']=-np.sign(x.gap); return finish(x,'sign','oc')
@reg('K3','Earnings gap continuation, small caps: |gap| >=5% on the reaction day -> WITH it open->close.')
def K3():
    x=S[(S.gap.abs()>=0.05)&S.oc.notna()].copy(); x=x[[near_earn(s,d) for s,d in zip(x.sym,x.date)]]; x['sign']=np.sign(x.gap); return finish(x,'sign','oc')
@reg('K4','Short-term reversal, small caps (clustered): 5-day return <= -15% -> LONG next 5 days close->close.')
def K4():
    x=S[(S.r5b<=-0.15)&S.c5f.notna()].copy(); x['sign']=1; x['ret']=x.c5f/x.close-1; return finish(x,'sign','ret')
@reg('K5','S&P 500 additions: LONG from close 5 trading days before the effective date to the effective-date close (index-fund forced buying).')
def K5():
    ch=pd.read_csv(f"{OUT}/sp500_changes.csv"); rows=[]
    for _,r in ch.iterrows():
        s=str(r.get('add_sym','')).strip();
        if not s or s=='nan': continue
        try: eff=pd.Timestamp(r['date'])
        except Exception: continue
        g=D[D.sym==s].set_index('date')
        if eff not in g.index: continue
        i=g.index.get_loc(eff)
        if i<5: continue
        rows.append(dict(date=eff,sign=1,ret=g.close.iloc[i]/g.close.iloc[i-5]-1))
    return finish(pd.DataFrame(rows),'sign','ret',cost=10.0)
@reg('K6','Quarter-end unwind, small caps (clustered): last trading day of quarter -> SHORT close->next close (window-dressing reversal).')
def K6():
    x=S.copy(); dts=pd.to_datetime(x.date); q=dts.dt.to_period('Q'); last=dts.groupby(q).transform('max'); x=x[dts==last].copy()
    x['nxt']=S.groupby('sym').close.shift(periods=-1).loc[x.index]; x=x[x.nxt.notna()]; x['sign']=-1; x['ret']=x.nxt/x.close-1; return finish(x,'sign','ret')
def st(s):
    s=s.dropna(); n=len(s); h=n//2; t=lambda a:a.mean()/(a.std(ddof=1)/math.sqrt(len(a))) if len(a)>5 and a.std(ddof=1)>0 else 0
    return dict(n=n,mean=float(s.mean()) if n else 0,t=float(t(s)),is_mean=float(s[:h].mean()) if h else 0,is_t=float(t(s[:h])),oos_mean=float(s[h:].mean()) if n else 0,oos_t=float(t(s[h:])))
if __name__=='__main__':
    a=sys.argv[1] if len(sys.argv)>1 else 'list'
    if a=='list': [print(k,'—',f.__doc__) for k,f in H.items()]; sys.exit(0)
    s=H[a](); R=st(s); g=np.random.default_rng(23); C=st(s*g.choice([-1,1],len(s))); bd=st(s.groupby(s.index).mean())
    print(a,H[a].__doc__); print('real',R); print('control',C); print('by_date',bd)
    print("RESULT "+json.dumps(dict(name=f"{a} {H[a].__doc__[:70]} | by-date t {bd['t']:.2f} n {bd['n']}",n=R['n'],mean_bps=f"{R['mean']:+.1f} bps/trade",t=round(min(R['t'],bd['t']) if a in ('K4','K6') else R['t'],2),is_mean=R['is_mean'],is_t=round(R['is_t'],2),oos_mean=R['oos_mean'],oos_t=round(R['oos_t'],2),control_t=round(C['t'],2))))
PY
python3 -m py_compile crumbs_pull.py mech_crumbs.py || exit 1
python3 -c "import yfinance" 2>/dev/null || pip install -q yfinance --break-system-packages
echo "pulling universe + daily bars + earnings dates (30-60 min)..."; python3 crumbs_pull.py 2>&1 | tail -12
[ -f /root/pe-data/crumbs/universe_small.csv ] || { echo "PULL FAILED"; exit 1; }
( crontab -l 2>/dev/null | grep -v crumbs_pull.py; echo "10 2 * * 0 cd /root/pe-fin/team && /usr/bin/python3 crumbs_pull.py >> crumbs_pull.log 2>&1" ) | crontab -
python3 - <<'PY'
import json, subprocess; reg=json.load(open('hypotheses.json')); have={h['id'] for h in reg['hypotheses']}; n=0
for l in subprocess.run(['python3','-I','mech_crumbs.py','list'],capture_output=True,text=True).stdout.splitlines():
    if ' — ' not in l: continue
    i,doc=l.split(' — ',1)
    if i in have: continue
    reg['hypotheses'].append({"id":i,"script":"/root/pe-fin/team/mech_crumbs.py","args":[i],"status":"proposed","pre_registered_sign":doc,"next_door":"threshold once, then liquidity band (ADV $30-100m), then dead; any WORKS must survive a next-day-open fill check before trading","timeout":3600}); n+=1
json.dump(reg,open('hypotheses.json','w'),indent=1); print('registered',n,'crumb hypotheses')
PY
wc -l /root/pe-data/crumbs/universe_small.csv
