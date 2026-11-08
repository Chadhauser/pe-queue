#!/bin/bash
# 515: speed. (1) 18 new mechanism hypotheses of our own (mech2.py: gap fade / gap-and-go / lunch reversal / last-hour momentum /
# TLT->QQQ same sign / IWM-QQQ and SPY-QQQ convergence pairs / turnaround Tuesday / open drive / VWAP reversion / 30 & 60-min ORB /
# 5-min ORB on SPY, IWM, TQQQ), each pre-registered, each with a random-sign control, graded one by one by the Verifier.
# (2) the Builder runs 2 hypotheses per cycle in parallel instead of 1 (box has spare cores; ETF tests are seconds-to-minutes).
cd /root/pe-fin/team || exit 1
cat > mech2.py <<'PY'
# MECH2 — second batch of OUR OWN mechanism hypotheses on Alpaca 1-min ETF bars (QQQ SPY IWM TLT GLD USO TQQQ SQQQ, Jul 2020 ->).
# Each hypothesis is a named function returning one return per trade (bps of price, after 1c spread + 1c slip per side on the
# traded ETF) indexed by date. Direction is PRE-REGISTERED in the docstring. Control = same trades with random sign.
# Usage: python3 -I mech2.py <id>      prints one RESULT line.    python3 -I mech2.py list   prints ids.
import sys, math, json, datetime as dt, numpy as np, pandas as pd
sys.path.insert(0,'/root/pe-fin'); from alpaca_load import load
_cache={}
def bars(sym):
    if sym not in _cache:
        b=load(sym); ny=b.index.tz_convert('America/New_York'); b=b.assign(d=ny.date, mi=ny.hour*60+ny.minute-570)
        _cache[sym]=b[(b.mi>=0)&(b.mi<390)]
    return _cache[sym]
def px_at(b, mi):
    """price at minute-of-session mi (open of that bar), per day"""
    s=b[b.mi==mi]; return pd.Series(s.open.values,index=s.d)
def daily(sym):
    b=bars(sym); g=b.groupby('d')
    return pd.DataFrame(dict(o=g.open.first(),h=g.high.max(),l=g.low.min(),c=g.close.last(),n=g.size()))
COST_BPS=lambda price: 1e4*(0.01+2*0.01)/price   # round trip in bps of price
def ret(sym, t_in, t_out, cond, sign):
    """trade sym from minute t_in to t_out on days where cond(day)->True, direction sign(day) in {+1,-1}; returns bps series"""
    b=bars(sym); pi=px_at(b,t_in); po=px_at(b,t_out) if t_out<390 else daily(sym).c
    out={}
    for d in pi.index:
        if d not in po.index: continue
        try: ok=cond(d)
        except Exception: ok=False
        if not ok: continue
        s=sign(d)
        if s==0: continue
        out[d]=s*1e4*(po[d]-pi[d])/pi[d]-COST_BPS(pi[d])
    return pd.Series(out).sort_index()
# ----- shared features -----
def gap(sym):
    D=daily(sym); return (D.o/D.c.shift(1)-1)
def move(sym, a, b_):
    pa=px_at(bars(sym),a); pb=px_at(bars(sym),b_); return (pb/pa-1).dropna()
H={}
def reg(id_, doc):
    def w(f): f.__doc__=doc; H[id_]=f; return f
    return w
@reg('M1','QQQ gap DOWN >=0.7%: FADE (long) open->10:30. Mechanism: overnight gap partially fills.')
def M1():
    g=gap('QQQ'); return ret('QQQ',0,60,lambda d: g.get(d,0)<=-0.007, lambda d: 1)
@reg('M2','QQQ gap UP >=0.7%: FADE (short) open->10:30.')
def M2():
    g=gap('QQQ'); return ret('QQQ',0,60,lambda d: g.get(d,0)>=0.007, lambda d: -1)
@reg('M3','Lev-ETF rebalance, WIDER: |QQQ move 09:30->15:30|>=1.5% -> trade QQQ WITH it 15:30->close (H1 next door).')
def M3():
    m=move('QQQ',0,360); return ret('QQQ',360,390,lambda d: abs(m.get(d,0))>=0.015, lambda d: int(np.sign(m[d])))
@reg('M6','Lunch reversal: QQQ 11:30->13:30 move >=0.5% -> FADE 13:30->15:00.')
def M6():
    m=move('QQQ',120,240); return ret('QQQ',240,330,lambda d: abs(m.get(d,0))>=0.005, lambda d: -int(np.sign(m[d])))
@reg('M7','Last-hour momentum: QQQ 09:30->15:00 move >=1% -> WITH it 15:00->close.')
def M7():
    m=move('QQQ',0,330); return ret('QQQ',330,390,lambda d: abs(m.get(d,0))>=0.01, lambda d: int(np.sign(m[d])))
@reg('M8','TLT first hour >=0.3% -> QQQ 10:30-12:30 SAME sign (H3 tested opposite; rates-equity co-move).')
def M8():
    m=move('TLT',0,60); return ret('QQQ',60,180,lambda d: abs(m.get(d,0))>=0.003, lambda d: int(np.sign(m[d])))
@reg('M9','IWM vs QQQ first-hour divergence >=0.5% -> long the LAGGARD, short the leader, 10:30->close (pairs convergence). Reported on the laggard leg.')
def M9():
    a=move('IWM',0,60); q=move('QQQ',0,60); dv=(a-q).dropna()
    lag=ret('IWM',60,390,lambda d: abs(dv.get(d,0))>=0.005, lambda d: -int(np.sign(dv[d])))
    lead=ret('QQQ',60,390,lambda d: abs(dv.get(d,0))>=0.005, lambda d: int(np.sign(dv[d])))
    return (lag.add(lead,fill_value=0))/2
@reg('M10','SPY vs QQQ first-hour divergence >=0.4% -> convergence pair 10:30->close.')
def M10():
    a=move('SPY',0,60); q=move('QQQ',0,60); dv=(a-q).dropna()
    lag=ret('SPY',60,390,lambda d: abs(dv.get(d,0))>=0.004, lambda d: -int(np.sign(dv[d])))
    lead=ret('QQQ',60,390,lambda d: abs(dv.get(d,0))>=0.004, lambda d: int(np.sign(dv[d])))
    return (lag.add(lead,fill_value=0))/2
@reg('M11','Turnaround Tuesday: Monday QQQ close-to-close <=-1% -> LONG Tuesday open->close.')
def M11():
    D=daily('QQQ'); r=D.c.pct_change(); prev={}
    idx=list(D.index)
    for i in range(1,len(idx)): prev[idx[i]]=(idx[i-1],r.iloc[i-1])
    def cond(d):
        p=prev.get(d); return d.weekday()==1 and p and p[0].weekday()==0 and p[1]<=-0.01
    return ret('QQQ',0,390,cond,lambda d: 1)
@reg('M12','Open drive: QQQ first 15-min range >=0.6% and close in top/bottom 20% of it -> continuation 09:45->12:00.')
def M12():
    b=bars('QQQ'); f=b[b.mi<15].groupby('d').agg(h=('high','max'),l=('low','min'),c=('close','last'),o=('open','first'))
    f['rng']=(f.h-f.l)/f.o; f['pos']=(f.c-f.l)/(f.h-f.l)
    def sign(d):
        r=f.loc[d]; return 1 if r.pos>=0.8 else (-1 if r.pos<=0.2 else 0)
    return ret('QQQ',15,150,lambda d: f.loc[d].rng>=0.006, sign)
@reg('M13','Gap-and-go: QQQ opens OUTSIDE yesterday\'s high-low range -> continuation open->close.')
def M13():
    D=daily('QQQ'); ph=D.h.shift(1); pl=D.l.shift(1)
    def sign(d): return 1 if D.o[d]>ph[d] else (-1 if D.o[d]<pl[d] else 0)
    return ret('QQQ',0,390,lambda d: d in ph.index and not np.isnan(ph[d]), sign)
@reg('M14','Gap INSIDE range: QQQ gaps >=0.3% but opens inside yesterday\'s range -> FADE to prior close, open->11:00.')
def M14():
    D=daily('QQQ'); ph=D.h.shift(1); pl=D.l.shift(1); g=gap('QQQ')
    def cond(d): return abs(g.get(d,0))>=0.003 and pl[d]<D.o[d]<ph[d]
    return ret('QQQ',0,90,cond,lambda d: -int(np.sign(g[d])))
@reg('M15','VWAP reversion: QQQ at 10:00 >=0.4% from session VWAP -> FADE 10:00->11:00.')
def M15():
    b=bars('QQQ'); s=b[b.mi<30].copy(); s['pv']=s.close*s.volume; v=s.groupby('d').agg(pv=('pv','sum'),vol=('volume','sum')); vwap=v.pv/v.vol
    p=px_at(b,30); dev=(p/vwap-1).dropna()
    return ret('QQQ',30,90,lambda d: abs(dev.get(d,0))>=0.004, lambda d: -int(np.sign(dev[d])))
@reg('M20','60-min ORB on QQQ: break of 09:30-10:30 range by 10:35 close -> continuation to close.')
def M20():
    b=bars('QQQ'); f=b[b.mi<60].groupby('d').agg(h=('high','max'),l=('low','min')); c=px_at(b,65)
    def sign(d): return 1 if c[d]>f.h[d] else (-1 if c[d]<f.l[d] else 0)
    return ret('QQQ',65,390,lambda d: d in f.index and d in c.index, sign)
@reg('M21','30-min ORB on QQQ: break of 09:30-10:00 range by 10:05 -> continuation to close.')
def M21():
    b=bars('QQQ'); f=b[b.mi<30].groupby('d').agg(h=('high','max'),l=('low','min')); c=px_at(b,35)
    def sign(d): return 1 if c[d]>f.h[d] else (-1 if c[d]<f.l[d] else 0)
    return ret('QQQ',35,390,lambda d: d in f.index and d in c.index, sign)
def orb5(sym):
    """5-min ORB direction (Zarattini-Aziz) with stop-side guard, held to close with stop at range edge: returns R-multiples"""
    b=bars(sym); COST=0.03; out={}; g=b.groupby('d')
    for d,sess in g:
        if len(sess)<300: continue
        fb=sess[sess.mi<5]; rest=sess[sess.mi>=5]
        if len(fb)<3 or not len(rest): continue
        o,c,hi,lo=fb.open.iloc[0],fb.close.iloc[-1],fb.high.max(),fb.low.min(); rng=hi-lo
        if rng<=0 or abs(c-o)<0.05*rng: continue
        side=1 if c>o else -1; entry=rest.open.iloc[0]; stop=lo if side>0 else hi; R=abs(entry-stop)
        if R<=0 or (side>0 and stop>=entry) or (side<0 and stop<=entry): continue
        target=entry+side*10*R; ex=rest.close.iloc[-1]
        for r in rest.itertuples():
            if side>0 and (r.low<=stop or r.high>=target): ex=stop if r.low<=stop else target; break
            if side<0 and (r.high>=stop or r.low<=target): ex=stop if r.high>=stop else target; break
        out[d]=(side*(ex-entry)-COST)/R
    return pd.Series(out).sort_index()
@reg('M23','5-min ORB on SPY (ORB-QQQ next door), R-multiples.')
def M23(): return orb5('SPY')
@reg('M24','5-min ORB on IWM, R-multiples.')
def M24(): return orb5('IWM')
@reg('M25','5-min ORB on TQQQ (3x: same signal, levered instrument; checks the edge is in QQQ direction not in the ETF), R-multiples.')
def M25(): return orb5('TQQQ')
def st(s):
    s=s.dropna(); n=len(s); h=n//2; t=lambda a:a.mean()/(a.std(ddof=1)/math.sqrt(len(a))) if len(a)>5 and a.std(ddof=1)>0 else 0
    return dict(n=n,mean=float(s.mean()) if n else 0,t=float(t(s)),is_mean=float(s[:h].mean()) if h else 0,is_t=float(t(s[:h])),oos_mean=float(s[h:].mean()) if n else 0,oos_t=float(t(s[h:])))
if __name__=='__main__':
    a=sys.argv[1] if len(sys.argv)>1 else 'list'
    if a=='list': [print(k,'—',f.__doc__) for k,f in H.items()]; sys.exit(0)
    s=H[a](); R=st(s); rng=np.random.default_rng(11); C=st(s*rng.choice([-1,1],len(s)))
    unit='R/trade' if a in ('M23','M24','M25') else 'bps/trade'
    print(a,H[a].__doc__); print('real',R); print('control',C)
    print("RESULT "+json.dumps(dict(name=f"{a} {H[a].__doc__[:70]}",n=R['n'],mean_bps=f"{R['mean']:+.2f} {unit}",t=round(R['t'],2),is_mean=R['is_mean'],is_t=round(R['is_t'],2),oos_mean=R['oos_mean'],oos_t=round(R['oos_t'],2),control_t=round(C['t'],2))))
PY
python3 -m py_compile mech2.py || exit 1
python3 -I mech2.py list | head -3
python3 - <<'PY'
import json, subprocess; reg=json.load(open('hypotheses.json'))
lines=[l for l in subprocess.run(['python3','-I','mech2.py','list'],capture_output=True,text=True).stdout.splitlines() if ' — ' in l]
have={h['id'] for h in reg['hypotheses']}; n=0
for l in lines:
    i,doc=l.split(' — ',1)
    if i in have: continue
    reg['hypotheses'].append({"id":i,"script":"/root/pe-fin/team/mech2.py","args":[i],"status":"proposed","pre_registered_sign":doc,"next_door":"widen/narrow threshold once, then sibling instrument, then dead","timeout":1800}); n+=1
json.dump(reg,open('hypotheses.json','w'),indent=1); print('registered',n,'queue now',len(reg['hypotheses']))
PY
python3 - <<'PY'
s=open('fin_team.py').read()
old="""    ran=0
    for h in reg['hypotheses']:
        if h.get('status')!='proposed' or ran>=1: continue
        probs=critics(h)
        if probs: h['status']='rejected_by_critics'; h['note']='; '.join(probs); log(f"{h['id']} rejected: {probs}"); continue
        h['status']='running'; json.dump(reg,open(REG,'w'),indent=1); log(f"building {h['id']}")
        res,tail=build(h); h['last_output']=tail[-1500:]
        if not res: h['status']='failed'; log(f"{h['id']} no RESULT"); continue
        verd=verify(h,res); sb['verdicts']=[v for v in sb['verdicts'] if not v['name'].startswith(h['id'])]+verd
        h['status']='verified'; h['verdicts']=[v['verdict'] for v in verd]; ran+=1; log(f"{h['id']} -> {h['verdicts']}")
"""
new="""    todo=[]
    for h in reg['hypotheses']:
        if h.get('status')!='proposed' or len(todo)>=WORKERS: continue
        probs=critics(h)
        if probs: h['status']='rejected_by_critics'; h['note']='; '.join(probs); log(f"{h['id']} rejected: {probs}"); continue
        h['status']='running'; todo.append(h); log(f"building {h['id']}")
    json.dump(reg,open(REG,'w'),indent=1)
    if todo:
        from concurrent.futures import ThreadPoolExecutor
        with ThreadPoolExecutor(max_workers=WORKERS) as ex: outs=list(ex.map(build,todo))
        for h,(res,tail) in zip(todo,outs):
            h['last_output']=tail[-1500:]
            if not res: h['status']='failed'; log(f"{h['id']} no RESULT"); continue
            verd=verify(h,res); sb['verdicts']=[v for v in sb['verdicts'] if not v['name'].startswith(h['id'])]+verd
            h['status']='verified'; h['verdicts']=[v['verdict'] for v in verd]; log(f"{h['id']} -> {h['verdicts']}")
"""
if 'WORKERS=' in s: print("already patched")
else:
    assert old in s, "cycle block not found — fin_team.py differs, NOT patched"
    s=s.replace(old,new).replace("GATE=dict(","WORKERS=2\nGATE=dict(",1); open('fin_team.py','w').write(s); print("PATCHED: 2 parallel workers")
PY
python3 -m py_compile fin_team.py || exit 1
restart(){ pkill -f 'fin_team.py'; sleep 1; nohup /root/pe-fin/team/run_team.sh & disown; sleep 3; pgrep -f fin_team.py >/dev/null && echo "daemon restarted" || echo "DAEMON NOT RUNNING"; }
if python3 -c "import json,sys; sys.exit(0 if any(h['status']=='running' for h in json.load(open('hypotheses.json'))['hypotheses']) else 1)"; then
  echo "a hypothesis is running — restart deferred until it finishes"
  nohup bash -c 'while python3 -c "import json,sys; sys.exit(0 if any(h[\"status\"]==\"running\" for h in json.load(open(\"/root/pe-fin/team/hypotheses.json\"))[\"hypotheses\"]) else 1)"; do sleep 120; done; pkill -f fin_team.py; sleep 1; nohup /root/pe-fin/team/run_team.sh & disown' >/dev/null 2>&1 & disown
else restart; fi
nproc; uptime
