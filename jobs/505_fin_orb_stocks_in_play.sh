#!/bin/bash
# 505: FINANCIAL — ORB on STOCKS IN PLAY (Zarattini-Barbon-Aziz 2024): 100 liquid US stocks, 1-minute Alpaca history (resumable, exit 75
# until all months are down, ~1-2 h), then: each day top-20 names by first-5-min relative volume, 5-min ORB, stop = first-bar extreme
# (floor 0.1 ATR14), 10R target, flat at close, 1% risk split across names. IS/OOS halves, random-side control, Topstep MC. Tested offline.
cd /root/pe-fin
cat > alpaca_stocks.py <<'PYFILE'
# 505a: 1-minute Alpaca history (free IEX) for ~100 liquid US stocks, monthly parquet, resumable (exit 75). Same puller as 501 with a stock list.
import os, sys, time, datetime, requests, pandas as pd
sys.path.insert(0,'/root/pe-queue/runner'); import creds
E=creds.all_vars(); K,S=E.get('ALPACA_KEY'),E.get('ALPACA_SECRET')
if not K or not S: print("NO ALPACA KEYS"); sys.exit(1)
H={'APCA-API-KEY-ID':K,'APCA-API-SECRET-KEY':S}; BASE='/root/pe-data/alpaca'
SYMS="AAPL MSFT NVDA AMZN META GOOGL TSLA AMD AVGO NFLX CRM ADBE INTC MU QCOM ORCL CSCO PYPL SHOP UBER COIN PLTR SNOW ROKU SQ JPM BAC WFC C GS MS XOM CVX OXY SLB COP BA CAT DE GE HD LOW NKE SBUX MCD DIS WMT COST TGT PG KO PEP PFE MRK JNJ LLY UNH ABBV AMGN GILD MRNA V MA AXP T VZ TMUS F GM RIVN LCID NIO BABA PDD JD MARA RIOT AAL DAL UAL CCL RCL LUV MGM WYNN DKNG ARKK SMCI ARM MSTR SOFI HOOD AFRM UPST CVNA GME AMC".split()
START=datetime.date(2020,7,1); today=datetime.date.today(); first=(today.replace(day=1)-datetime.timedelta(days=1)).replace(day=1)
months=[]; m=first
while m>=START: months.append(m); m=(m-datetime.timedelta(days=1)).replace(day=1)
budget=time.time()+9000; unfinished=False
def fetch_month(sym,m0):
    m1=(m0.replace(day=28)+datetime.timedelta(days=4)).replace(day=1); frames=[]; tok=None
    while True:
        p={'symbols':sym,'timeframe':'1Min','start':f"{m0}T00:00:00Z",'end':f"{m1}T00:00:00Z",'limit':10000,'feed':'iex','adjustment':'all','sort':'asc'}
        if tok: p['page_token']=tok
        r=None
        for a in range(6):
            r=requests.get('https://data.alpaca.markets/v2/stocks/bars',params=p,headers=H,timeout=60)
            if r.status_code==429: time.sleep(5+5*a); continue
            if r.status_code>=500: time.sleep(3); continue
            break
        if r is None or r.status_code!=200: print(sym,m0,"HTTP",getattr(r,'status_code',None)); return None
        j=r.json(); bars=(j.get('bars') or {}).get(sym) or []
        if bars: frames.append(pd.DataFrame(bars))
        tok=j.get('next_page_token')
        if not tok: break
        time.sleep(0.3)
    if not frames: return pd.DataFrame()
    b=pd.concat(frames); b['ts']=pd.to_datetime(b['t'],utc=True); b=b.set_index('ts').sort_index()
    b=b.rename(columns={'o':'open','h':'high','l':'low','c':'close','v':'volume','n':'ticks'})[['open','high','low','close','volume','ticks']]
    return b[~b.index.duplicated()]
tot_new=0
for sym in SYMS:
    os.makedirs(f"{BASE}/{sym}",exist_ok=True); new=0
    for m0 in months:
        out=f"{BASE}/{sym}/1m_{m0:%Y-%m}.parquet"
        if os.path.exists(out): continue
        if time.time()>budget: unfinished=True; break
        b=fetch_month(sym,m0)
        if b is None: unfinished=True; break
        b.to_parquet(out); new+=1; tot_new+=1
    done=len([f for f in os.listdir(f"{BASE}/{sym}") if f.endswith('.parquet')])
    print(f"{sym}: months {done}/{len(months)} (+{new})",flush=True)
    if unfinished: break
print("new month-files this run:",tot_new); sys.exit(75 if unfinished else 0)
PYFILE
cat > orb_stocks.py <<'PYFILE'
# 505b: ORB on "stocks in play" — Zarattini, Barbon & Aziz (2024) 'A Profitable Day Trading Strategy for the U.S. Equity Market':
# each day pick the top-N stocks by RELATIVE VOLUME in the first 5 minutes (today's 5-min volume / 14-day average 5-min volume),
# price > $5, avg $ volume high; trade the 5-min ORB (direction of first bar, stop = 10% of 14-day ATR... paper uses ATR*0.1? we use
# first-bar extreme as in 231 plus the paper's 'stop = max(first-bar extreme, 0.1*ATR14)'), target 10R, flat at close, 1% risk per
# trade split equally, N=20 names/day, costs 1c spread + 1c slip + 0.5bp. IS/OOS halves, random-side control, Topstep MC.
import sys, os, math, numpy as np, pandas as pd, datetime
sys.path.insert(0,'/root/pe-fin'); from alpaca_load import load
BASE='/root/pe-data/alpaca'; N=20; RANDOM='--random' in sys.argv
syms=[s for s in os.listdir(BASE) if os.path.isdir(f"{BASE}/{s}") and s not in ('QQQ','SPY','IWM','TLT','GLD','USO','TQQQ','SQQQ')]
print("stocks on disk",len(syms))
recs=[]
for sym in syms:
    b=load(sym)
    if len(b)<50000: continue
    ny=b.index.tz_convert('America/New_York'); b=b.assign(d=ny.date, mi=ny.hour*60+ny.minute-570); b=b[(b.mi>=0)&(b.mi<390)]
    day=b.groupby('d').agg(o=('open','first'),h=('high','max'),l=('low','min'),c=('close','last'),v=('volume','sum'))
    f5=b[b.mi<5].groupby('d').agg(o5=('open','first'),c5=('close','last'),h5=('high','max'),l5=('low','min'),v5=('volume','sum'))
    day=day.join(f5); day['prev']=day.c.shift(1)
    tr=np.maximum(day.h-day.l,np.maximum((day.h-day.prev).abs(),(day.l-day.prev).abs())); day['atr14']=tr.rolling(14).mean().shift(1)
    day['v5avg']=day.v5.rolling(14).mean().shift(1); day['relvol']=day.v5/day.v5avg; day['dollar']=(day.c*day.v).rolling(14).mean().shift(1)
    day['sym']=sym
    # simulate per day: entry at open of minute 5, stop first-bar extreme (min 0.1*ATR), target 10R, exit close
    g=b.groupby('d')
    for d,r in day.iterrows():
        if not (r.relvol>0 and r.dollar>5e7 and r.o>5 and r.atr14>0 and r.h5>r.l5): continue
        if abs(r.c5-r.o5)<0.05*(r.h5-r.l5): continue
        side=1 if r.c5>r.o5 else -1
        if RANDOM: side=np.random.choice([-1,1])
        rest=g.get_group(d); rest=rest[rest.mi>=5]
        if len(rest)<100: continue
        entry=rest.open.iloc[0]; stop=r.l5 if side>0 else r.h5; R=max(abs(entry-stop),0.1*r.atr14)
        if side>0: stop=entry-R
        else: stop=entry+R
        target=entry+side*10*R; ex=rest.close.iloc[-1]; reason='close'
        hit=np.where(((rest.low<=stop) if side>0 else (rest.high>=stop)))[0]; tg=np.where(((rest.high>=target) if side>0 else (rest.low<=target)))[0]
        i_s=hit[0] if len(hit) else 10**9; i_t=tg[0] if len(tg) else 10**9
        if i_s<i_t: ex=stop; reason='stop'
        elif i_t<i_s: ex=target; reason='target'
        cost=0.02+0.00005*entry
        pts=side*(ex-entry)-cost; recs.append(dict(date=pd.Timestamp(d),sym=sym,relvol=r.relvol,R=R,r_mult=pts/R,reason=reason))
A=pd.DataFrame(recs); print("candidate trades",len(A))
# daily top-N by relvol
A=A.sort_values(['date','relvol'],ascending=[True,False]); A['rank']=A.groupby('date').cumcount()+1; P=A[A['rank']<=N].copy()
daily=P.groupby('date').r_mult.mean()   # 1% risk split equally across the day's names => day return in R units
n=len(daily); mid=daily.index[n//2]
def rep(s,lbl):
    t=s.mean()/(s.std(ddof=1)/math.sqrt(len(s))); eq=(1+0.01*s).cumprod(); dd=((eq/eq.cummax())-1).min()
    print(f"{lbl}: days {len(s)} | mean day R {s.mean():+.3f} | t {t:.2f} | Sharpe {s.mean()/s.std()*math.sqrt(252):.2f} | maxDD@1% {100*dd:.1f}% | win {100*(s>0).mean():.0f}%")
print(f"\n=== ORB stocks-in-play, top {N} by rel-volume, {'RANDOM SIDE' if RANDOM else 'real'} ===")
rep(daily,'ALL'); rep(daily[daily.index<mid],'IS'); rep(daily[daily.index>=mid],'OOS')
print("by year:"); print(daily.groupby(daily.index.year).agg(['count','mean']).round(3).T.to_string())
print("per-trade:",f"n {len(P)} | mean R {P.r_mult.mean():+.3f} | win {100*(P.r_mult>0).mean():.1f}% | exits {P.reason.value_counts().to_dict()}")
if not RANDOM:
    rng=np.random.default_rng(3); oos=daily[daily.index>=mid].values
    for risk in (100,200,300):
        c={'pass':0,'bust':0,'neither':0}
        for _ in range(3000):
            bal=0;hi=0;o='neither'
            for x in rng.choice(oos,250,replace=True):
                bal+=risk*x
                if bal>=3000: o='pass';break
                hi=max(hi,bal)
                if bal<=min(hi,2000)-2000: o='bust';break
            c[o]+=1
        print(f"Topstep50K MC daily-risk ${risk}: pass {100*c['pass']/3000:.0f}% bust {100*c['bust']/3000:.0f}%")
    import psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
    con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
    cur.execute("CREATE TABLE IF NOT EXISTS orb_stocks_daily (date DATE PRIMARY KEY, n_names INT, day_r NUMERIC)")
    for d,s in daily.items(): cur.execute("INSERT INTO orb_stocks_daily VALUES (%s,%s,%s) ON CONFLICT (date) DO UPDATE SET n_names=EXCLUDED.n_names, day_r=EXCLUDED.day_r",(d.date(),int((P.date==d).sum()),float(round(s,4))))
    print("stored orb_stocks_daily",n)
PYFILE
python3 -m py_compile alpaca_stocks.py orb_stocks.py || exit 1
timeout 9500 python3 alpaca_stocks.py; rc=$?; echo "pull exit $rc"; [ $rc -eq 75 ] && exit 75; [ $rc -ne 0 ] && exit $rc
echo "== RANDOM-SIDE CONTROL"; timeout 2400 python3 orb_stocks.py --random 2>&1 | grep -v Warning | grep -E "===|ALL|IS|OOS|per-trade"
echo; echo "== REAL"; timeout 3000 python3 orb_stocks.py 2>&1 | grep -v Warning
