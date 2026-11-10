#!/bin/bash
# 516: crypto into the loop. Alpaca's free crypto feed (same keys) -> 1-min BTC/USD, ETH/USD, SOL/USD from 2021 into
# /root/pe-data/alpaca/<SYM>/ (SYM = BTCUSD etc), nightly refresh, plus 8 crypto-specific mechanism hypotheses (24/7 market:
# weekend gap, Monday open, US-open effect, Asia-session reversal, funding-time drift, BTC->ETH lead, ORB on BTC at US open,
# last-hour-of-UTC-day momentum), each pre-registered with a random-sign control. Promised Sunday 8 Nov, pushed Tue 10 Nov.
cd /root/pe-fin || exit 1
cat > crypto_pull.py <<'PY'
import os, sys, time, datetime, requests, pandas as pd
sys.path.insert(0,'/root/pe-queue/runner'); import creds
E=creds.all_vars(); K,S=E.get('ALPACA_KEY'),E.get('ALPACA_SECRET')
if not K or not S: print("NO ALPACA KEYS"); sys.exit(1)
H={'APCA-API-KEY-ID':K,'APCA-API-SECRET-KEY':S}; BASE='/root/pe-data/alpaca'
SYMS={'BTC/USD':'BTCUSD','ETH/USD':'ETHUSD','SOL/USD':'SOLUSD'}
START=datetime.date(2021,1,1); today=datetime.date.today(); cur=today.replace(day=1)
months=[]; m=cur
while m>=START: months.append(m); m=(m-datetime.timedelta(days=1)).replace(day=1)
budget=time.time()+9000
def fetch_month(sym,m0):
    m1=(m0.replace(day=28)+datetime.timedelta(days=4)).replace(day=1); frames=[]; tok=None
    while True:
        p={'symbols':sym,'timeframe':'1Min','start':f"{m0}T00:00:00Z",'end':f"{min(m1,today+datetime.timedelta(days=1))}T00:00:00Z",'limit':10000,'sort':'asc'}
        if tok: p['page_token']=tok
        for a in range(5):
            r=requests.get('https://data.alpaca.markets/v1beta3/crypto/us/bars',params=p,headers=H,timeout=60)
            if r.status_code==429: time.sleep(5+5*a); continue
            if r.status_code>=500: time.sleep(3); continue
            break
        if r.status_code!=200: print(sym,m0,"HTTP",r.status_code,r.text[:120]); return None
        j=r.json(); bars=(j.get('bars') or {}).get(sym) or []
        if bars: frames.append(pd.DataFrame(bars))
        tok=j.get('next_page_token')
        if not tok: break
        time.sleep(0.3)
    if not frames: return pd.DataFrame()
    b=pd.concat(frames); b['ts']=pd.to_datetime(b['t'],utc=True); b=b.set_index('ts').sort_index()
    b=b.rename(columns={'o':'open','h':'high','l':'low','c':'close','v':'volume','n':'ticks'})[['open','high','low','close','volume','ticks']]
    return b[~b.index.duplicated()]
for sym,d in SYMS.items():
    os.makedirs(f"{BASE}/{d}",exist_ok=True); new=0
    for m0 in months:
        out=f"{BASE}/{d}/1m_{m0:%Y-%m}.parquet"
        if os.path.exists(out) and m0!=cur: continue
        if time.time()>budget: print("budget hit, resume next run"); break
        b=fetch_month(sym,m0)
        if b is None: break
        if len(b): b.to_parquet(out); new+=1
        if new%12==1: print(d,m0.strftime('%Y-%m'),"bars",len(b),flush=True)
    print(d,"months on disk",len([f for f in os.listdir(f"{BASE}/{d}") if f.endswith('.parquet')]))
PY
python3 -m py_compile crypto_pull.py || exit 1
cat > /root/pe-fin/team/mech_crypto.py <<'PY'
# MECH-CRYPTO — our own mechanism hypotheses on 24/7 crypto 1-min bars (Alpaca, 2021->). Returns bps per trade after
# 10 bps round trip (Alpaca crypto taker 25bps/side is worse: WORKS here must survive 50 bps too, printed as 'at_50bps').
# Direction pre-registered in each docstring. Control = random sign. Usage: python3 -I mech_crypto.py <id> | list
import sys, math, json, datetime as dt, numpy as np, pandas as pd
sys.path.insert(0,'/root/pe-fin'); from alpaca_load import load
COST=10.0; _c={}
def bars(sym):
    if sym not in _c:
        b=load(sym); b=b.assign(d=b.index.date, hr=b.index.hour, mi=b.index.hour*60+b.index.minute, wd=b.index.weekday); _c[sym]=b
    return _c[sym]
def px_at(b,mi):
    s=b[b.mi==mi]; return pd.Series(s.open.values,index=s.d)
def ret(sym,t_in,t_out,cond,sign):
    b=bars(sym); pi=px_at(b,t_in); po=px_at(b,t_out) if t_out<1440 else b.groupby('d').close.last(); out={}
    for d in pi.index:
        if d not in po.index: continue
        try: ok=cond(d)
        except Exception: ok=False
        if not ok: continue
        s=sign(d)
        if s==0: continue
        out[d]=s*1e4*(po[d]-pi[d])/pi[d]-COST
    return pd.Series(out).sort_index()
def move(sym,a,b_):
    pa=px_at(bars(sym),a); pb=px_at(bars(sym),b_); return (pb/pa-1).dropna()
def daily(sym):
    g=bars(sym).groupby('d'); return pd.DataFrame(dict(o=g.open.first(),c=g.close.last(),h=g.high.max(),l=g.low.min()))
H={}
def reg(i,doc):
    def w(f): f.__doc__=doc; H[i]=f; return f
    return w
@reg('C1','Weekend gap: BTC Fri 21:00 UTC -> Mon 00:00 move >=2% -> FADE Mon 00:00->13:30 UTC (thin weekend tape over-extends).')
def C1():
    b=bars('BTCUSD'); fri=px_at(b,1260); fri=fri[[d.weekday()==4 for d in fri.index]]; mon=px_at(b,0)
    g={}
    for d in mon.index:
        if d.weekday()!=0: continue
        f=d-dt.timedelta(days=3)
        if f in fri.index: g[d]=mon[d]/fri[f]-1
    return ret('BTCUSD',0,810,lambda d: abs(g.get(d,0))>=0.02, lambda d: -int(np.sign(g[d])))
@reg('C2','US equity open effect: BTC 13:00->13:30 UTC move >=0.5% -> WITH it 13:30->16:00 UTC (US flows continue).')
def C2():
    m=move('BTCUSD',780,810); return ret('BTCUSD',810,960,lambda d: abs(m.get(d,0))>=0.005, lambda d: int(np.sign(m[d])))
@reg('C3','Asia-session reversal: BTC 00:00->08:00 UTC move >=1.5% -> FADE 08:00->13:00 UTC (London unwinds Asia).')
def C3():
    m=move('BTCUSD',0,480); return ret('BTCUSD',480,780,lambda d: abs(m.get(d,0))>=0.015, lambda d: -int(np.sign(m[d])))
@reg('C4','Funding-time drift: BTC 07:00->08:00 UTC move >=0.5% (pre-funding) -> FADE 08:00->09:00 UTC.')
def C4():
    m=move('BTCUSD',420,480); return ret('BTCUSD',480,540,lambda d: abs(m.get(d,0))>=0.005, lambda d: -int(np.sign(m[d])))
@reg('C5','BTC leads ETH: BTC 13:30->14:30 UTC move >=1% -> ETH WITH it 14:30->16:00 UTC.')
def C5():
    m=move('BTCUSD',810,870); return ret('ETHUSD',870,960,lambda d: abs(m.get(d,0))>=0.01, lambda d: int(np.sign(m[d])))
@reg('C6','ORB at US open on BTC: 13:30-13:45 UTC range, break by 13:50 close -> continuation to 20:00 UTC.')
def C6():
    b=bars('BTCUSD'); f=b[(b.mi>=810)&(b.mi<825)].groupby('d').agg(h=('high','max'),l=('low','min')); c=px_at(b,830)
    def sign(d): return 1 if c[d]>f.h[d] else (-1 if c[d]<f.l[d] else 0)
    return ret('BTCUSD',830,1200,lambda d: d in f.index and d in c.index, sign)
@reg('C7','Daily-close momentum: BTC 00:00->23:00 UTC move >=3% -> WITH it 23:00->24:00 UTC (daily-candle chasing).')
def C7():
    m=move('BTCUSD',0,1380); return ret('BTCUSD',1380,1440,lambda d: abs(m.get(d,0))>=0.03, lambda d: int(np.sign(m[d])))
@reg('C8','Monday open: BTC Sun 00:00->24:00 UTC move >=2% -> FADE Mon 00:00->12:00 UTC.')
def C8():
    D=daily('BTCUSD'); idx=list(D.index); pos={d:i for i,d in enumerate(idx)}
    def sun(d): i=pos[d]; return (D.c[idx[i-1]]/D.o[idx[i-1]]-1) if i>0 and idx[i-1].weekday()==6 else 0
    return ret('BTCUSD',0,720,lambda d: d.weekday()==0 and abs(sun(d))>=0.02, lambda d: -int(np.sign(sun(d))))
def st(s):
    s=s.dropna(); n=len(s); h=n//2; t=lambda a:a.mean()/(a.std(ddof=1)/math.sqrt(len(a))) if len(a)>5 and a.std(ddof=1)>0 else 0
    return dict(n=n,mean=float(s.mean()) if n else 0,t=float(t(s)),is_mean=float(s[:h].mean()) if h else 0,is_t=float(t(s[:h])),oos_mean=float(s[h:].mean()) if n else 0,oos_t=float(t(s[h:])))
if __name__=='__main__':
    a=sys.argv[1] if len(sys.argv)>1 else 'list'
    if a=='list': [print(k,'—',f.__doc__) for k,f in H.items()]; sys.exit(0)
    s=H[a](); R=st(s); rng=np.random.default_rng(13); C=st(s*rng.choice([-1,1],len(s))); R50=st(s-40)
    print(a,H[a].__doc__); print('real',R); print('control',C); print('at_50bps',R50)
    print("RESULT "+json.dumps(dict(name=f"{a} {H[a].__doc__[:70]} | at 50bps t {R50['t']:.2f}",n=R['n'],mean_bps=f"{R['mean']:+.2f} bps/trade",t=round(R['t'],2),is_mean=R['is_mean'],is_t=round(R['is_t'],2),oos_mean=R['oos_mean'],oos_t=round(R['oos_t'],2),control_t=round(C['t'],2))))
PY
python3 -m py_compile /root/pe-fin/team/mech_crypto.py || exit 1
echo "pulling crypto bars (up to 2.5h budget)..."; python3 crypto_pull.py 2>&1 | tail -8
( crontab -l 2>/dev/null | grep -v crypto_pull.py; echo "15 0 * * * cd /root/pe-fin && /usr/bin/python3 crypto_pull.py >> crypto_pull.log 2>&1" ) | crontab -
cd /root/pe-fin/team && python3 - <<'PY'
import json, subprocess; reg=json.load(open('hypotheses.json'))
lines=[l for l in subprocess.run(['python3','-I','mech_crypto.py','list'],capture_output=True,text=True).stdout.splitlines() if ' — ' in l]
have={h['id'] for h in reg['hypotheses']}; n=0
for l in lines:
    i,doc=l.split(' — ',1)
    if i in have: continue
    reg['hypotheses'].append({"id":i,"script":"/root/pe-fin/team/mech_crypto.py","args":[i],"status":"proposed","pre_registered_sign":doc,"next_door":"widen/narrow threshold once, then ETH/SOL, then dead","timeout":1800}); n+=1
json.dump(reg,open('hypotheses.json','w'),indent=1); print('registered',n,'crypto hypotheses')
PY
ls /root/pe-data/alpaca/BTCUSD | wc -l
