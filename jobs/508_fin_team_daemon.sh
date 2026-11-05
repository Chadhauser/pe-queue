#!/bin/bash
# 508: FINANCIAL — the TEAM: continuous background loop on this server (Proposer = pre-registered hypotheses.json; Critics = mechanical
# checks; Builder runs the script; Verifier applies the gates and is the ONLY writer of /root/pe-fin/team/scoreboard.{json,md}).
# Data health block in the scoreboard every cycle; nightly Alpaca current-month refresh 23:30 UTC. Daemon under nohup + @reboot + keepalive.
# Seeded with the verdicts to date and two queued hypotheses (H1-5 mechanisms, H6 fade-spike). Peter 5 Nov 08:16. Tested offline.
mkdir -p /root/pe-fin/team && cd /root/pe-fin/team
cat > fin_team.py <<'PYFILE'
# FIN TEAM — continuous background loop on the trading server (Peter, 5 Nov 2026: Proposer / Critics / Builder / Verifier, one
# scoreboard only the Verifier writes, data health every morning). No LLM on the box: the Proposer is a registry of pre-registered
# hypotheses (hypotheses.json), each a script that prints `RESULT {...}` lines; Critics are mechanical pre-run checks; the Builder runs
# the script; the Verifier applies the gates and is the ONLY writer of scoreboard.json / scoreboard.md.
import os, sys, json, time, subprocess, datetime, glob, re, traceback
ROOT='/root/pe-fin/team'; REG=f'{ROOT}/hypotheses.json'; SB=f'{ROOT}/scoreboard.json'; SBMD=f'{ROOT}/scoreboard.md'; LOG=f'{ROOT}/team.log'
GATE=dict(t_single=2.5, t_sweep=3.5, n_min=200, control_abs_max=2.0)
def log(m):
    with open(LOG,'a') as f: f.write(f"{datetime.datetime.utcnow():%Y-%m-%d %H:%M:%S} {m}\n")
def jload(p,d): 
    try: return json.load(open(p))
    except Exception: return d
def data_health():
    """rows in last 24h (weekday-aware), last timestamp, per feed. Zero on a trading day = BROKEN."""
    import pandas as pd
    out={}; now=pd.Timestamp.utcnow(); wk=now.weekday()<5
    for name,pattern in (('alpaca_etf','/root/pe-data/alpaca/QQQ/1m_*.parquet'),('alpaca_stocks','/root/pe-data/alpaca/AAPL/1m_*.parquet'),('yf1m','/root/pe-data/yf1m/*.parquet')):
        files=sorted(glob.glob(pattern))
        if not files: out[name]=dict(status='BROKEN',last=None,rows_24h=0,note='no files'); continue
        try:
            df=pd.read_parquet(files[-1]); last=df.index.max(); last=last.tz_convert('UTC') if last.tzinfo else last.tz_localize('UTC')
            rows=int((df.index>=now-pd.Timedelta(hours=24)).sum()) if last.tzinfo else 0
            stale=(now-last)>pd.Timedelta(hours=30 if wk else 72)
            out[name]=dict(status='BROKEN' if stale else 'ok',last=str(last)[:16],rows_24h=rows)
        except Exception as e: out[name]=dict(status='BROKEN',note=repr(e)[:80])
    try:
        sys.path.insert(0,'/root/pe-fin'); from findb import DB; import psycopg2
        con=psycopg2.connect(DB,sslmode='prefer'); cur=con.cursor(); cur.execute("select last_run,status from fin_heartbeat limit 1"); r=cur.fetchone(); con.close()
        out['local_pg']=dict(status='ok',note=f"fin_heartbeat {r[0]} {r[1]}" if r else 'no heartbeat row')
    except Exception as e: out['local_pg']=dict(status='BROKEN',note=repr(e)[:80])
    return out
def critics(h):
    probs=[]
    if not os.path.exists(h['script']): probs.append('script missing')
    else:
        src=open(h['script']).read()
        if 'RESULT' not in src: probs.append('script prints no RESULT line')
        if 'control' not in src.lower(): probs.append('no control in script')
        if 'shift(-' in src or 'iloc[i+1]' in src: probs.append('possible look-ahead (negative shift)')
    if not h.get('pre_registered_sign'): probs.append('no pre-registered direction')
    return probs
def build(h):
    try:
        p=subprocess.run(['python3','-I',h['script']]+h.get('args',[]),cwd='/root/pe-fin',capture_output=True,text=True,timeout=h.get('timeout',3600))
        res=[json.loads(l[7:]) for l in p.stdout.splitlines() if l.startswith('RESULT ')]
        return res,(p.stdout[-3000:]+p.stderr[-1500:])
    except Exception as e: return [],repr(e)
def verify(h,res):
    """gates: t>=2.5 single / 3.5 sweep; both halves >0; n>=200; |control t|<=2. Returns verdict rows."""
    out=[]
    for r in res:
        thr=GATE['t_sweep'] if h.get('kind')=='sweep' else GATE['t_single']
        ok=(r.get('t',0)>=thr and r.get('is_mean',0)>0 and r.get('oos_mean',0)>0 and r.get('n',0)>=GATE['n_min'] and abs(r.get('control_t',0))<=GATE['control_abs_max'])
        supports=None
        if not ok and r.get('n',0)>=60 and r.get('t',0)>=1.5 and r.get('oos_mean',0)>0: supports='positive OOS at small size — capacity to be measured'
        out.append(dict(name=r.get('name',h['id']),n=r.get('n'),mean_bps=r.get('mean_bps'),t=r.get('t'),is_t=r.get('is_t'),oos_t=r.get('oos_t'),control_t=r.get('control_t'),verdict='WORKS' if ok else ('WORKS AT SMALL SIZE' if supports else 'NOT YET'),next_door=h.get('next_door'),checked=datetime.datetime.utcnow().isoformat()[:16]))
    return out
def write_scoreboard(sb):
    json.dump(sb,open(SB+'.tmp','w'),indent=1); os.replace(SB+'.tmp',SB)
    L=[f"# FIN SCOREBOARD (Verifier-only) — {sb['updated']} UTC","",f"Money: live £{sb['money']['live_month']} | paper £{sb['money']['paper_month']} | live edges {sb['money']['live_edges']}","","## Data health"]
    for k,v in sb['data_health'].items(): L.append(f"- {k}: {v.get('status')} | last {v.get('last')} | rows24h {v.get('rows_24h')} {v.get('note','')}")
    L+=["","## Verdicts (gates: t>=2.5 single / 3.5 sweep, both halves >0, n>=200, |control t|<=2)","","| hypothesis | n | mean bps | t | IS t | OOS t | control t | verdict | next door |","|---|---|---|---|---|---|---|---|---|"]
    for v in sb['verdicts']: L.append(f"| {v['name']} | {v.get('n')} | {v.get('mean_bps')} | {v.get('t')} | {v.get('is_t')} | {v.get('oos_t')} | {v.get('control_t')} | **{v['verdict']}** | {v.get('next_door') or ''} |")
    L+=["","## Queue"]+[f"- {h['id']}: {h['status']}" for h in sb['queue']]
    open(SBMD+'.tmp','w').write("\n".join(L)); os.replace(SBMD+'.tmp',SBMD)
def cycle():
    reg=jload(REG,{'hypotheses':[]}); sb=jload(SB,{'money':{'live_month':0,'paper_month':0,'live_edges':0},'verdicts':[],'queue':[]})
    sb['data_health']=data_health(); broken=[k for k,v in sb['data_health'].items() if v.get('status')=='BROKEN']
    if broken: log(f"DATA BROKEN: {broken}")
    ran=0
    for h in reg['hypotheses']:
        if h.get('status')!='proposed' or ran>=1: continue
        probs=critics(h)
        if probs: h['status']='rejected_by_critics'; h['note']='; '.join(probs); log(f"{h['id']} rejected: {probs}"); continue
        h['status']='running'; json.dump(reg,open(REG,'w'),indent=1); log(f"building {h['id']}")
        res,tail=build(h); h['last_output']=tail[-1500:]
        if not res: h['status']='failed'; log(f"{h['id']} no RESULT"); continue
        verd=verify(h,res); sb['verdicts']=[v for v in sb['verdicts'] if not v['name'].startswith(h['id'])]+verd
        h['status']='verified'; h['verdicts']=[v['verdict'] for v in verd]; ran+=1; log(f"{h['id']} -> {h['verdicts']}")
    json.dump(reg,open(REG,'w'),indent=1)
    sb['queue']=[{'id':h['id'],'status':h['status']} for h in reg['hypotheses']]; sb['updated']=datetime.datetime.utcnow().isoformat()[:16]
    write_scoreboard(sb)
if __name__=='__main__':
    once='--once' in sys.argv
    while True:
        try: cycle()
        except Exception: log(traceback.format_exc()[-800:])
        if once: break
        time.sleep(600)
PYFILE
cat > fade_spike.py <<'PYFILE'
# H6 (pre-registered 5 Nov 2026, from the 505 control anomaly): on each stock, after the first 5-minute bar, enter AGAINST the first-bar
# direction with stop = 0.1*ATR14 beyond entry, target 10R, flat at close; top-20 by relative volume. Direction fixed in advance: FADE.
import sys, os, math, json, numpy as np, pandas as pd
sys.path.insert(0,'/root/pe-fin'); from alpaca_load import load
BASE='/root/pe-data/alpaca'; N=20; CTRL='--control' in sys.argv
syms=[s for s in os.listdir(BASE) if os.path.isdir(f"{BASE}/{s}") and s not in ('QQQ','SPY','IWM','TLT','GLD','USO','TQQQ','SQQQ')]
def run(control):
    recs=[]; rng=np.random.default_rng(5)
    for sym in syms:
        b=load(sym)
        if len(b)<50000: continue
        ny=b.index.tz_convert('America/New_York'); b=b.assign(d=ny.date, mi=ny.hour*60+ny.minute-570); b=b[(b.mi>=0)&(b.mi<390)]
        day=b.groupby('d').agg(o=('open','first'),h=('high','max'),l=('low','min'),c=('close','last'),v=('volume','sum'))
        f5=b[b.mi<5].groupby('d').agg(o5=('open','first'),c5=('close','last'),v5=('volume','sum')); day=day.join(f5); day['prev']=day.c.shift(1)
        tr=np.maximum(day.h-day.l,np.maximum((day.h-day.prev).abs(),(day.l-day.prev).abs())); day['atr14']=tr.rolling(14).mean().shift(1)
        day['relvol']=day.v5/day.v5.rolling(14).mean().shift(1); day['dollar']=(day.c*day.v).rolling(14).mean().shift(1); g=b.groupby('d')
        for d,r in day.iterrows():
            if not (r.relvol>0 and r.dollar>5e7 and r.o>5 and r.atr14>0): continue
            if abs(r.c5-r.o5)<0.002*r.o5: continue
            side=-1 if r.c5>r.o5 else 1
            if control: side=rng.choice([-1,1])
            rest=g.get_group(d); rest=rest[rest.mi>=5]
            if len(rest)<100: continue
            entry=rest.open.iloc[0]; R=0.1*r.atr14; stop=entry-side*R; target=entry+side*10*R; ex=rest.close.iloc[-1]
            hit=np.where(((rest.low<=stop) if side>0 else (rest.high>=stop)))[0]; tg=np.where(((rest.high>=target) if side>0 else (rest.low<=target)))[0]
            i_s=hit[0] if len(hit) else 10**9; i_t=tg[0] if len(tg) else 10**9
            if i_s<=i_t and i_s<10**9: ex=stop
            elif i_t<i_s: ex=target
            pts=side*(ex-entry)-(0.02+0.00005*entry); recs.append(dict(date=pd.Timestamp(d),sym=sym,relvol=r.relvol,r_mult=pts/R))
    A=pd.DataFrame(recs).sort_values(['date','relvol'],ascending=[True,False]); A['rank']=A.groupby('date').cumcount()+1; P=A[A['rank']<=N]
    return P.groupby('date').r_mult.mean()
def stats(s):
    n=len(s); h=n//2; t=lambda a:a.mean()/(a.std(ddof=1)/math.sqrt(len(a))) if len(a)>5 else 0
    return dict(n=n,mean=float(s.mean()),t=float(t(s)),is_mean=float(s[:h].mean()),is_t=float(t(s[:h])),oos_mean=float(s[h:].mean()),oos_t=float(t(s[h:])))
real=run(False); ctrl=run(True); sr=stats(real); sc=stats(ctrl)
print("real",sr); print("control",sc)
print("RESULT "+json.dumps(dict(name="H6 fade opening spike, tight stop, top-20 relvol stocks",n=sr['n'],mean_bps=f"{sr['mean']:+.3f} R/day",t=round(sr['t'],2),is_mean=sr['is_mean'],is_t=round(sr['is_t'],2),oos_mean=sr['oos_mean'],oos_t=round(sr['oos_t'],2),control_t=round(sc['t'],2))))
PYFILE
cat > mechanisms.py <<'PYFILE'
# 507: FIVE PRE-REGISTERED MECHANISM TESTS (our own, stated in advance 4 Nov 2026, direction fixed before running). One test each,
# 2 bps round-trip cost, IS/OOS halves, sign-shuffled control. Data: Alpaca 1-min (QQQ, TQQQ, TLT), Alpaca daily BTC/USD.
#  H1 leveraged-ETF rebalance: on days where QQQ is up/down >=1% by 15:30, the 15:30->close move continues in the same direction.
#  H2 crypto overnight lead: BTC's move from 16:00 ET prev close to 09:30 ET predicts QQQ open->close direction (same sign).
#  H3 bond first-hour lead: TLT's 09:30->10:30 move predicts QQQ's 10:30->12:30 move with the OPPOSITE sign (risk-on/off).
#  H4 month-end flow: last trading day of month, 15:00->close QQQ move is positive (pension/rebalance buying).
#  H5 expiry pin: on Fridays, in the last hour QQQ moves toward the nearest $5 strike (|dist| shrinks from 15:00 to close).
import sys, os, math, json, datetime, numpy as np, pandas as pd, requests
sys.path.insert(0,'/root/pe-fin'); from alpaca_load import load
sys.path.insert(0,'/root/pe-queue/runner'); import creds
NMIN=390; COST=0.0002; rng=np.random.default_rng(21)
def mat(sym):
    b=load(sym); ny=b.index.tz_convert('America/New_York'); mi=(ny.hour*60+ny.minute)-570; ok=(mi>=0)&(mi<NMIN)
    df=pd.DataFrame({'d':ny[ok].date,'m':mi[ok],'c':b.close.values[ok]})
    P=df.pivot_table(index='d',columns='m',values='c',aggfunc='last').reindex(columns=range(NMIN)); P=P[P.notna().sum(axis=1)>=200].ffill(axis=1).bfill(axis=1)
    return P
def report(name,x,hyp_dir):
    x=np.asarray(x,float); x=x[np.isfinite(x)]; n=len(x); h=n//2
    if n<30: print(f"{name}: n {n} too few"); return
    t=lambda a:a.mean()/(a.std(ddof=1)/math.sqrt(len(a))) if len(a)>5 and a.std()>0 else 0
    ctrl=x*rng.choice([-1,1],n)
    print(f"{name}: n {n} | mean {1e4*x.mean():+.1f} bps | t {t(x):.2f} | IS {1e4*x[:h].mean():+.1f} bps t {t(x[:h]):.2f} | OOS {1e4*x[h:].mean():+.1f} bps t {t(x[h:]):.2f} | control t {t(ctrl):.2f} | pre-registered sign {hyp_dir} -> {'SUPPORTED' if (t(x)>=2.5 and x[:h].mean()>0 and x[h:].mean()>0) else 'NOT YET'}")
    print("RESULT "+json.dumps(dict(name=name,n=int(n),mean_bps=round(1e4*x.mean(),1),t=round(t(x),2),is_mean=float(x[:h].mean()),is_t=round(t(x[:h]),2),oos_mean=float(x[h:].mean()),oos_t=round(t(x[h:]),2),control_t=round(t(ctrl),2))))
Q=mat('QQQ'); print("QQQ days",len(Q))
# H1
up=Q[360]/Q[0]-1; last=Q[389]/Q[360]-1; sel=up.abs()>=0.01; H1=np.sign(up[sel])*last[sel]-COST; report("H1 lev-ETF rebalance (|move by 15:30|>=1%, trade with it to close)",H1,"+")
# H2 BTC overnight -> QQQ open-close
E=creds.all_vars(); H={'APCA-API-KEY-ID':E.get('ALPACA_KEY'),'APCA-API-SECRET-KEY':E.get('ALPACA_SECRET')}
r=requests.get('https://data.alpaca.markets/v1beta3/crypto/us/bars',params={'symbols':'BTC/USD','timeframe':'1Hour','start':'2020-07-01T00:00:00Z','end':f'{datetime.date.today()}T00:00:00Z','limit':10000},headers=H,timeout=60)
frames=[]; tok=None
while True:
    p={'symbols':'BTC/USD','timeframe':'1Hour','start':'2020-07-01T00:00:00Z','end':f'{datetime.date.today()}T00:00:00Z','limit':10000}
    if tok: p['page_token']=tok
    j=requests.get('https://data.alpaca.markets/v1beta3/crypto/us/bars',params=p,headers=H,timeout=60).json(); bars=(j.get('bars') or {}).get('BTC/USD') or []
    if bars: frames.append(pd.DataFrame(bars))
    tok=j.get('next_page_token')
    if not tok: break
B=pd.concat(frames); B['ts']=pd.to_datetime(B['t'],utc=True).dt.tz_convert('America/New_York'); B=B.set_index('ts').sort_index()
print("BTC hourly bars",len(B))
bt=B['c']; qd=pd.to_datetime(Q.index)
prev16=[]; at930=[]
for d in qd:
    a=bt[:pd.Timestamp(d-pd.Timedelta(days=1)).tz_localize('America/New_York').replace(hour=16)]; b_=bt[:pd.Timestamp(d).tz_localize('America/New_York').replace(hour=9,minute=30)]
    prev16.append(a.iloc[-1] if len(a) else np.nan); at930.append(b_.iloc[-1] if len(b_) else np.nan)
btmove=pd.Series(np.array(at930)/np.array(prev16)-1,index=Q.index); qoc=Q[389]/Q[0]-1
sel=btmove.abs()>=0.01; H2=np.sign(btmove[sel])*qoc[sel]-COST; report("H2 BTC overnight >=1% -> QQQ open->close same sign",H2,"+")
# H3 TLT first hour -> QQQ 10:30-12:30 opposite sign
T=mat('TLT'); idx=Q.index.intersection(T.index); tl=T.loc[idx,60]/T.loc[idx,0]-1; q2=Q.loc[idx,180]/Q.loc[idx,60]-1
sel=tl.abs()>=0.003; H3=-np.sign(tl[sel])*q2[sel]-COST; report("H3 TLT first-hour >=0.3% -> QQQ 10:30-12:30 OPPOSITE sign",H3,"+")
# H4 month-end last hour long
qd=pd.Series(pd.to_datetime(Q.index),index=Q.index); me=qd.dt.month!=qd.shift(-1).dt.month; H4=(Q[389]/Q[330]-1)[me]-COST; report("H4 last trading day of month, long 15:00->close",H4,"+")
# H5 expiry pin on Fridays: distance to nearest $5 strike shrinks 15:00 -> close (trade toward strike)
fri=qd.dt.dayofweek==4; p15=Q.loc[fri,330]; strike=(p15/5).round()*5; direction=np.sign(strike-p15); move=Q.loc[fri,389]/p15-1
sel=(strike-p15).abs()/p15>0.001; H5=direction[sel]*move[sel]-COST; report("H5 Friday last hour, trade toward nearest $5 strike (dist>0.1%)",H5,"+")
print("\nOWNER RULE: each NOT YET gets its next door in the header; SUPPORTED goes to the portfolio MC with ORB.")
PYFILE
cat > alpaca_daily.py <<'PYFILE'
# nightly: re-pull the CURRENT month for every symbol on disk so the 1-minute history stays live (past months are immutable).
import os, sys, datetime, importlib.util
sys.path.insert(0,'/root/pe-fin'); spec=importlib.util.spec_from_file_location('ap','/root/pe-fin/alpaca_pull.py')
# reuse fetch_month/H from alpaca_pull without running its main loop: exec only the definitions
src=open('/root/pe-fin/alpaca_pull.py').read().split('tot_new=0')[0].split('budget=time.time()')[0]
ns={}; exec(src,ns); fetch_month=ns['fetch_month']; BASE=ns['BASE']
m0=datetime.date.today().replace(day=1); n=0
for sym in sorted(os.listdir(BASE)):
    if not os.path.isdir(f"{BASE}/{sym}"): continue
    b=fetch_month(sym,m0)
    if b is None or b.empty: continue
    b.to_parquet(f"{BASE}/{sym}/1m_{m0:%Y-%m}.parquet"); n+=1
print("refreshed current-month files:",n)
PYFILE
cat > hypotheses.json <<'JSONF'
{"hypotheses":[
 {"id":"H1-5 mechanisms","script":"/root/pe-fin/team/mechanisms.py","status":"proposed","pre_registered_sign":"+ as stated per test","next_door":"per test: widen threshold / other instrument","timeout":1800},
 {"id":"H6 fade-spike","script":"/root/pe-fin/team/fade_spike.py","status":"proposed","pre_registered_sign":"fade (against first bar)","next_door":"stop 0.2 ATR / exit at 11:00","timeout":7000}
]}
JSONF
[ -f scoreboard.json ] || cat > scoreboard.json <<'JSONF'
{"money":{"live_month":0,"paper_month":0,"live_edges":0},
 "verdicts":[
  {"name":"ORB-QQQ (Zarattini-Aziz, 501)","n":1397,"mean_bps":"+0.166 R/trade","t":2.43,"is_t":1.59,"oos_t":1.84,"control_t":-0.26,"verdict":"WORKS AT SMALL SIZE","next_door":"prop-firm MC: 52-63% pass at $100 risk (502/504); combine with any new WORKS before evaluation","checked":"2026-11-04"},
  {"name":"ORB stocks-in-play top-20 (505)","n":1558,"mean_bps":"+0.037 R/day","t":2.16,"is_t":1.08,"oos_t":2.11,"control_t":3.42,"verdict":"NOT YET","next_door":"H6 fade-spike test (control anomaly) in queue","checked":"2026-11-04"},
  {"name":"Intraday grammar sweep 7,070 cells (503)","n":7070,"mean_bps":"best t 3.27 GLD gap","t":3.27,"is_t":null,"oos_t":null,"control_t":0,"verdict":"NOT YET","next_door":"mechanism tests H1-H5 in queue","checked":"2026-11-03"},
  {"name":"Mallik TQQQ/SQQQ rules (500)","n":4206,"mean_bps":"sma150 L/C 35.9% CAGR","t":2.63,"is_t":null,"oos_t":2.63,"control_t":0,"verdict":"WORKS AT SMALL SIZE","next_door":"200-day filter halves TQQQ drawdown; own-capital only, not prop-firm","checked":"2026-11-01"}],
 "queue":[]}
JSONF
python3 -m py_compile fin_team.py fade_spike.py mechanisms.py alpaca_daily.py || exit 1
cat > run_team.sh <<'SH'
#!/bin/bash
cd /root/pe-fin/team && exec python3 fin_team.py >> team.out 2>&1
SH
chmod +x run_team.sh
( crontab -l 2>/dev/null | grep -v 'run_team.sh\|alpaca_daily.py' ; echo "@reboot nohup /root/pe-fin/team/run_team.sh &"; echo "*/10 * * * * pgrep -f 'fin_team.py' >/dev/null || nohup /root/pe-fin/team/run_team.sh &"; echo "30 23 * * 1-5 cd /root/pe-fin/team && python3 alpaca_daily.py >> alpaca_daily.log 2>&1" ) | crontab -
pkill -f 'fin_team.py' 2>/dev/null; sleep 1; nohup /root/pe-fin/team/run_team.sh & disown
sleep 2; pgrep -f fin_team.py >/dev/null && echo "team daemon running pid $(pgrep -f fin_team.py | head -1)" || { echo "DAEMON NOT RUNNING"; exit 1; }
echo "== first scoreboard (data health only until the first hypothesis finishes; H1-5 ~minutes, H6 ~1h)"; sleep 90; cat scoreboard.md 2>/dev/null || echo "scoreboard not yet written"; echo; tail -5 team.log
