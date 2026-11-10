#!/bin/bash
# 518: FX into the loop. Oanda v20 (token in /root/pe-logger/.env, OANDA_ENV=live -> api-fxtrade; data only, no orders) ->
# 1-min bid/ask/mid candles from 2020 for EUR_USD GBP_USD USD_JPY AUD_USD USD_CAD XAU_USD into /root/pe-data/oanda/<INST>/,
# nightly refresh 00:30 UTC, plus 10 FX session hypotheses (mech_fx.py) each pre-registered with a random-sign control,
# costed at the REAL spread in the data (half-spread each side). Nothing here places an order.
cd /root/pe-fin || exit 1
cat > oanda_pull.py <<'PY'
import os, sys, time, datetime, requests, pandas as pd
sys.path.insert(0,'/root/pe-queue/runner'); import creds
E=creds.all_vars(); T=E.get('OANDA_TOKEN'); ENV=E.get('OANDA_ENV','practice')
if not T: print("NO OANDA_TOKEN"); sys.exit(1)
HOST='https://api-fxtrade.oanda.com' if ENV=='live' else 'https://api-fxpractice.oanda.com'
H={'Authorization':f'Bearer {T}','Accept-Datetime-Format':'RFC3339'}; BASE='/root/pe-data/oanda'
INST=['EUR_USD','GBP_USD','USD_JPY','AUD_USD','USD_CAD','XAU_USD']
START=datetime.date(2020,1,1); today=datetime.date.today(); cur=today.replace(day=1)
months=[]; m=cur
while m>=START: months.append(m); m=(m-datetime.timedelta(days=1)).replace(day=1)
budget=time.time()+9000
def fetch_month(inst,m0):
    m1=min((m0.replace(day=28)+datetime.timedelta(days=4)).replace(day=1), today+datetime.timedelta(days=1)); frames=[]; t0=f"{m0}T00:00:00Z"
    while True:
        p={'granularity':'M1','price':'MBA','count':5000,'from':t0,'includeFirst':'false' if frames else 'true'}
        for a in range(5):
            r=requests.get(f"{HOST}/v3/instruments/{inst}/candles",params=p,headers=H,timeout=60)
            if r.status_code in (429,502,503,504): time.sleep(2+3*a); continue
            break
        if r.status_code!=200: print(inst,m0,"HTTP",r.status_code,r.text[:150]); return None
        c=r.json().get('candles',[])
        if not c: break
        rows=[dict(ts=x['time'],open=float(x['mid']['o']),high=float(x['mid']['h']),low=float(x['mid']['l']),close=float(x['mid']['c']),
                   spread=float(x['ask']['c'])-float(x['bid']['c']),volume=x['volume'],ticks=x['volume']) for x in c if x.get('complete')]
        frames.append(pd.DataFrame(rows)); t0=c[-1]['time']
        if pd.Timestamp(t0)>=pd.Timestamp(f"{m1}T00:00:00Z") or len(c)<5000: break
        time.sleep(0.15)
    if not frames: return pd.DataFrame()
    b=pd.concat(frames); b['ts']=pd.to_datetime(b.ts,utc=True); b=b.set_index('ts').sort_index(); b=b[~b.index.duplicated()]
    return b[(b.index>=pd.Timestamp(f"{m0}T00:00:00Z"))&(b.index<pd.Timestamp(f"{m1}T00:00:00Z"))]
for inst in INST:
    os.makedirs(f"{BASE}/{inst}",exist_ok=True); new=0
    for m0 in months:
        out=f"{BASE}/{inst}/1m_{m0:%Y-%m}.parquet"
        if os.path.exists(out) and m0!=cur: continue
        if time.time()>budget: print("budget hit, resume next run"); break
        b=fetch_month(inst,m0)
        if b is None: break
        if len(b): b.to_parquet(out); new+=1
        if new%12==1: print(inst,m0.strftime('%Y-%m'),"bars",len(b),"spread",round(b.spread.mean(),5),flush=True)
    print(inst,"months on disk",len([f for f in os.listdir(f"{BASE}/{inst}") if f.endswith('.parquet')]))
PY
cat > oanda_load.py <<'PY'
import os, pandas as pd
BASE='/root/pe-data/oanda'
def load(inst):
    d=f"{BASE}/{inst}"; fs=sorted(f for f in os.listdir(d) if f.endswith('.parquet')) if os.path.isdir(d) else []
    if not fs: return pd.DataFrame(columns=['open','high','low','close','spread','ticks','volume'])
    b=pd.concat(pd.read_parquet(f"{d}/{f}") for f in fs).sort_index(); return b[~b.index.duplicated()]
PY
python3 -m py_compile oanda_pull.py oanda_load.py || exit 1
cat > /root/pe-fin/team/mech_fx.py <<'PY'
# MECH-FX — our own FX session hypotheses on Oanda 1-min mid candles with REAL spreads (2020->). Return per trade in bps of
# price after paying half the quoted spread at entry and at exit. Direction pre-registered in each docstring. Control = random sign.
# Usage: python3 -I mech_fx.py <id> | list.   Times are UTC minutes-of-day.
import sys, math, json, datetime as dt, numpy as np, pandas as pd
sys.path.insert(0,'/root/pe-fin'); from oanda_load import load
_c={}
def bars(i):
    if i not in _c:
        b=load(i); b=b.assign(d=b.index.date, mi=b.index.hour*60+b.index.minute, wd=b.index.weekday); _c[i]=b
    return _c[i]
def at(b,mi):
    s=b[b.mi==mi]; return pd.Series(s.open.values,index=s.d), pd.Series(s.spread.values,index=s.d)
def ret(inst,t_in,t_out,cond,sign):
    b=bars(inst); pi,si=at(b,t_in); po,so=at(b,t_out); out={}
    for d in pi.index:
        if d not in po.index or d.weekday()>4: continue
        try: ok=cond(d)
        except Exception: ok=False
        if not ok: continue
        s=sign(d)
        if s==0: continue
        out[d]=s*1e4*(po[d]-pi[d])/pi[d]-1e4*(si[d]/2+so[d]/2)/pi[d]
    return pd.Series(out).sort_index()
def move(inst,a,b_):
    pa,_=at(bars(inst),a); pb,_=at(bars(inst),b_); return (pb/pa-1).dropna()
def rng(inst,a,b_):
    b=bars(inst); f=b[(b.mi>=a)&(b.mi<b_)].groupby('d').agg(h=('high','max'),l=('low','min'),o=('open','first')); return f
H={}
def reg(i,doc):
    def w(f): f.__doc__=doc; H[i]=f; return f
    return w
def orb(inst,a,b_,chk,end):
    f=rng(inst,a,b_); c,_=at(bars(inst),chk)
    def sign(d): return 1 if c[d]>f.h[d] else (-1 if c[d]<f.l[d] else 0)
    return ret(inst,chk,end,lambda d: d in f.index and d in c.index, sign)
@reg('F1','London open range: EUR_USD 07:00-08:00 UTC range, break by 08:05 -> continuation to 12:00.')
def F1(): return orb('EUR_USD',420,480,485,720)
@reg('F2','London open range on GBP_USD, same shape.')
def F2(): return orb('GBP_USD',420,480,485,720)
@reg('F3','Asia range breakout: EUR_USD 00:00-07:00 range, break by 07:05 -> continuation to 10:00.')
def F3(): return orb('EUR_USD',0,420,425,600)
@reg('F4','Asia-session reversal: GBP_USD 00:00->07:00 move >=0.3% -> FADE 07:00->10:00 (London unwinds Asia).')
def F4():
    m=move('GBP_USD',0,420); return ret('GBP_USD',420,600,lambda d: abs(m.get(d,0))>=0.003, lambda d: -int(np.sign(m[d])))
@reg('F5','NY overlap momentum: EUR_USD 12:30->13:30 UTC move >=0.2% -> WITH it 13:30->16:00.')
def F5():
    m=move('EUR_USD',750,810); return ret('EUR_USD',810,960,lambda d: abs(m.get(d,0))>=0.002, lambda d: int(np.sign(m[d])))
@reg('F6','London fix: EUR_USD 15:00->15:55 UTC move >=0.15% -> FADE 16:00->17:00 (fix flow reverses).')
def F6():
    m=move('EUR_USD',900,955); return ret('EUR_USD',960,1020,lambda d: abs(m.get(d,0))>=0.0015, lambda d: -int(np.sign(m[d])))
@reg('F7','Friday afternoon fade: GBP_USD Fri 07:00->15:00 move >=0.4% -> FADE 15:00->20:00 (position squaring).')
def F7():
    m=move('GBP_USD',420,900); return ret('GBP_USD',900,1200,lambda d: d.weekday()==4 and abs(m.get(d,0))>=0.004, lambda d: -int(np.sign(m[d])))
@reg('F8','USD/JPY Tokyo open momentum: 00:00->00:30 UTC move >=0.15% -> WITH it 00:30->03:00.')
def F8():
    m=move('USD_JPY',0,30); return ret('USD_JPY',30,180,lambda d: abs(m.get(d,0))>=0.0015, lambda d: int(np.sign(m[d])))
@reg('F9','Gold London open range: XAU_USD 07:00-08:00 range, break by 08:05 -> continuation to 13:30.')
def F9(): return orb('XAU_USD',420,480,485,810)
@reg('F10','Gold NY-open momentum: XAU_USD 13:30->14:00 UTC move >=0.3% -> WITH it 14:00->17:00.')
def F10():
    m=move('XAU_USD',810,840); return ret('XAU_USD',840,1020,lambda d: abs(m.get(d,0))>=0.003, lambda d: int(np.sign(m[d])))
def st(s):
    s=s.dropna(); n=len(s); h=n//2; t=lambda a:a.mean()/(a.std(ddof=1)/math.sqrt(len(a))) if len(a)>5 and a.std(ddof=1)>0 else 0
    return dict(n=n,mean=float(s.mean()) if n else 0,t=float(t(s)),is_mean=float(s[:h].mean()) if h else 0,is_t=float(t(s[:h])),oos_mean=float(s[h:].mean()) if n else 0,oos_t=float(t(s[h:])))
if __name__=='__main__':
    a=sys.argv[1] if len(sys.argv)>1 else 'list'
    if a=='list': [print(k,'—',f.__doc__) for k,f in H.items()]; sys.exit(0)
    s=H[a](); R=st(s); g=np.random.default_rng(19); C=st(s*g.choice([-1,1],len(s)))
    print(a,H[a].__doc__); print('real',R); print('control',C)
    print("RESULT "+json.dumps(dict(name=f"{a} {H[a].__doc__[:70]}",n=R['n'],mean_bps=f"{R['mean']:+.2f} bps/trade",t=round(R['t'],2),is_mean=R['is_mean'],is_t=round(R['is_t'],2),oos_mean=R['oos_mean'],oos_t=round(R['oos_t'],2),control_t=round(C['t'],2))))
PY
python3 -m py_compile /root/pe-fin/team/mech_fx.py || exit 1
echo "pulling Oanda candles (budget 2.5h)..."; python3 oanda_pull.py 2>&1 | tail -10
( crontab -l 2>/dev/null | grep -v oanda_pull.py; echo "30 0 * * 2-6 cd /root/pe-fin && /usr/bin/python3 oanda_pull.py >> oanda_pull.log 2>&1" ) | crontab -
cd /root/pe-fin/team && python3 - <<'PY'
import json, subprocess; reg=json.load(open('hypotheses.json'))
lines=[l for l in subprocess.run(['python3','-I','mech_fx.py','list'],capture_output=True,text=True).stdout.splitlines() if ' — ' in l]
have={h['id'] for h in reg['hypotheses']}; n=0
for l in lines:
    i,doc=l.split(' — ',1)
    if i in have: continue
    reg['hypotheses'].append({"id":i,"script":"/root/pe-fin/team/mech_fx.py","args":[i],"status":"proposed","pre_registered_sign":doc,"next_door":"widen/narrow threshold once, then sibling pair, then dead","timeout":1800}); n+=1
json.dump(reg,open('hypotheses.json','w'),indent=1); print('registered',n,'FX hypotheses')
PY
python3 - <<'PY'
# data health: add the Oanda feed to the morning line
s=open('/root/pe-fin/team/fin_team.py').read()
if 'oanda' not in s:
    s=s.replace("('yf1m','/root/pe-data/yf1m/*.parquet')","('yf1m','/root/pe-data/yf1m/*.parquet'),('oanda_fx','/root/pe-data/oanda/EUR_USD/1m_*.parquet'),('alpaca_crypto','/root/pe-data/alpaca/BTCUSD/1m_*.parquet')")
    open('/root/pe-fin/team/fin_team.py','w').write(s); print("data health: oanda_fx + alpaca_crypto added (live after next daemon restart)")
PY
python3 -m py_compile /root/pe-fin/team/fin_team.py || exit 1
ls /root/pe-data/oanda/EUR_USD 2>/dev/null | wc -l
