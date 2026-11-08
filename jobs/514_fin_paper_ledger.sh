#!/bin/bash
# 514: forward PAPER ledger for ORB-QQQ (the one WORKS AT SMALL SIZE edge). Peter asked "Paper P&L since 2 Nov" and the honest
# answer was "none recorded" — the backtest table stopped at 30 Oct and nothing was walking the rule forward day by day.
# This runs the published rule on each new day's Alpaca QQQ bars at $100 risk/trade, from 2026-11-02, writes
# /root/pe-fin/team/paper_ledger.json, and the scoreboard's money line + a "Paper ledger" section read from it (Verifier file,
# no human edits). Runs nightly 23:45 UTC after alpaca_daily (23:30). Backfills 2-6 Nov now. Labelled UNVERIFIED-PAPER:
# simulated fills on IEX 1-min bars, not a broker. FX fixed at 0.77 GBP/USD for the money line.
cd /root/pe-fin/team || exit 1
cat > paper_orb.py <<'PY'
import sys, json, datetime as dt, numpy as np, pandas as pd
sys.path.insert(0,'/root/pe-fin'); from alpaca_load import load
START=dt.date(2026,11,2); RISK_USD=100.0; FX=0.77
b=load('QQQ'); ny=b.index.tz_convert('America/New_York'); b=b.assign(d=ny.date,t=ny.time); b=b[b.d>=START]
COST=0.01+2*0.01; T0,T1,TC=dt.time(9,30),dt.time(9,35),dt.time(16,0); rows=[]
for d,g in b.groupby('d'):
    sess=g[(g.t>=T0)&(g.t<TC)]
    if len(sess)<300: rows.append(dict(date=str(d),note='incomplete bars, no trade')); continue
    fb=sess[(sess.t>=T0)&(sess.t<T1)]
    if len(fb)<3: rows.append(dict(date=str(d),note='no opening bars')); continue
    o,c,hi,lo=fb.open.iloc[0],fb.close.iloc[-1],fb.high.max(),fb.low.min(); rng=hi-lo
    if rng<=0 or abs(c-o)<0.05*rng: rows.append(dict(date=str(d),note='no signal (doji open)')); continue
    side=1 if c>o else -1; rest=sess[sess.t>=T1]; entry=rest.open.iloc[0]; stop=lo if side>0 else hi; R=abs(entry-stop)
    if R<=0 or (side>0 and stop>=entry) or (side<0 and stop<=entry): rows.append(dict(date=str(d),note='stop on wrong side of entry (gap) — no trade')); continue
    target=entry+side*10*R; ex=rest.close.iloc[-1]; reason='close'
    for r in rest.itertuples():
        if side>0 and r.low<=stop: ex=stop; reason='stop'; break
        if side<0 and r.high>=stop: ex=stop; reason='stop'; break
        if side>0 and r.high>=target: ex=target; reason='target'; break
        if side<0 and r.low<=target: ex=target; reason='target'; break
    rm=(side*(ex-entry)-COST)/R
    rows.append(dict(date=str(d),side='long' if side>0 else 'short',entry=round(float(entry),2),stop=round(float(stop),2),exit=round(float(ex),2),reason=reason,r_mult=round(float(rm),3),usd=round(float(rm*RISK_USD),2)))
tr=[r for r in rows if 'usd' in r]; usd=sum(r['usd'] for r in tr)
led=dict(strategy='ORB-QQQ (Zarattini-Aziz) $100 risk/trade, simulated on Alpaca IEX 1-min bars',label='UNVERIFIED-PAPER',start=str(START),
         updated=dt.datetime.utcnow().isoformat()[:16],days=rows,trades=len(tr),wins=sum(1 for r in tr if r['usd']>0),usd=round(usd,2),gbp=round(usd*FX,2),fx=FX)
json.dump(led,open('paper_ledger.json.tmp','w'),indent=1); import os; os.replace('paper_ledger.json.tmp','paper_ledger.json')
print(f"paper ledger: {len(tr)} trades since {START}, ${usd:+.2f} = £{usd*FX:+.2f}"); [print(r) for r in rows]
PY
python3 - <<'PY'
s=open('fin_team.py').read()
if 'paper_ledger' not in s:
    s=s.replace("    sb['data_health']=data_health();",
"""    try:
        led=json.load(open('/root/pe-fin/team/paper_ledger.json')); sb['money']['paper_month']=led.get('gbp',0); sb['paper']=led
    except Exception: pass
    sb['data_health']=data_health();""")
    s=s.replace("""    L+=["","## Queue"]""",
"""    p=sb.get('paper')
    if p:
        L+=["",f"## Paper ledger — {p['label']} — {p['strategy']} — from {p['start']}",f"trades {p['trades']} | wins {p['wins']} | ${p['usd']:+.2f} = £{p['gbp']:+.2f} (fx {p['fx']})","","| date | side | entry | stop | exit | reason | R | $ |","|---|---|---|---|---|---|---|---|"]
        for r in p['days']:
            L.append(f"| {r['date']} | {r.get('side','-')} | {r.get('entry','')} | {r.get('stop','')} | {r.get('exit','')} | {r.get('reason') or r.get('note')} | {r.get('r_mult','')} | {r.get('usd','')} |")
    L+=["","## Queue"]""")
    open('fin_team.py','w').write(s)
PY
cat > orb_qqq_v2.py <<'PY'
# Critic finding (8 Nov): orb_qqq.py took the trade even when the 09:35 open gapped past the 5-min range, putting the stop on the
# wrong side of entry -> instant phantom 'stop' at a profit. v2 skips those days. Random-side control included.
import sys, json, math, datetime as dt, numpy as np, pandas as pd
sys.path.insert(0,'/root/pe-fin'); from alpaca_load import load
b=load('QQQ'); ny=b.index.tz_convert('America/New_York'); b=b.assign(d=ny.date,t=ny.time)
COST=0.03; T0,T1,TC=dt.time(9,30),dt.time(9,35),dt.time(16,0)
def run(control):
    rng=np.random.default_rng(5); out=[]; skipped=0
    for d,g in b.groupby('d'):
        sess=g[(g.t>=T0)&(g.t<TC)]
        if len(sess)<300: continue
        fb=sess[(sess.t>=T0)&(sess.t<T1)]
        if len(fb)<3: continue
        o,c,hi,lo=fb.open.iloc[0],fb.close.iloc[-1],fb.high.max(),fb.low.min(); rngv=hi-lo
        if rngv<=0 or abs(c-o)<0.05*rngv: continue
        side=1 if c>o else -1
        if control: side=int(rng.choice([-1,1]))
        rest=sess[sess.t>=T1]; entry=rest.open.iloc[0]; stop=lo if side>0 else hi; R=abs(entry-stop)
        if R<=0 or (side>0 and stop>=entry) or (side<0 and stop<=entry): skipped+=1; continue
        target=entry+side*10*R; ex=rest.close.iloc[-1]
        for r in rest.itertuples():
            if side>0 and r.low<=stop: ex=stop; break
            if side<0 and r.high>=stop: ex=stop; break
            if side>0 and r.high>=target: ex=target; break
            if side<0 and r.low<=target: ex=target; break
        out.append((pd.Timestamp(d),(side*(ex-entry)-COST)/R))
    s=pd.Series(dict(out)).sort_index(); return s,skipped
def st(s):
    n=len(s); h=n//2; t=lambda a:a.mean()/(a.std(ddof=1)/math.sqrt(len(a))) if len(a)>5 else 0
    return dict(n=n,mean=float(s.mean()),t=float(t(s)),is_mean=float(s[:h].mean()),is_t=float(t(s[:h])),oos_mean=float(s[h:].mean()),oos_t=float(t(s[h:])))
real,sk=run(False); ctrl,_=run(True); R=st(real); C=st(ctrl); print("skipped gap days",sk,"real",R,"control",C)
print("RESULT "+json.dumps(dict(name=f"ORB-QQQ v2 (stop-side guard, {sk} gap days skipped)",n=R['n'],mean_bps=f"{R['mean']:+.3f} R/trade",t=round(R['t'],2),is_mean=R['is_mean'],is_t=round(R['is_t'],2),oos_mean=R['oos_mean'],oos_t=round(R['oos_t'],2),control_t=round(C['t'],2))))
PY
python3 - <<'PY'
import json; reg=json.load(open('hypotheses.json'))
reg['hypotheses']=[h for h in reg['hypotheses'] if not h['id'].startswith('ORB-QQQ v2')]
reg['hypotheses'].append({"id":"ORB-QQQ v2","script":"/root/pe-fin/team/orb_qqq_v2.py","status":"proposed","pre_registered_sign":"+ (must stay WORKS AT SMALL SIZE or better after removing gap-day phantom wins; if it drops below, the 501 verdict is withdrawn)","next_door":"if withdrawn: ORB on SPY/IWM with the guard","timeout":3600})
json.dump(reg,open('hypotheses.json','w'),indent=1)
PY
python3 -m py_compile fin_team.py paper_orb.py orb_qqq_v2.py || exit 1
python3 paper_orb.py || exit 1
( crontab -l 2>/dev/null | grep -v paper_orb.py; echo "45 23 * * 1-5 cd /root/pe-fin/team && /usr/bin/python3 paper_orb.py >> paper.log 2>&1" ) | crontab -
restart(){ pkill -f 'fin_team.py'; sleep 1; nohup /root/pe-fin/team/run_team.sh & disown; sleep 3; pgrep -f fin_team.py >/dev/null && echo "daemon restarted" || echo "DAEMON NOT RUNNING"; }
if python3 -c "import json,sys; sys.exit(0 if any(h['status']=='running' for h in json.load(open('hypotheses.json'))['hypotheses']) else 1)"; then
  echo "a hypothesis is running (H7?) — restart deferred until it finishes, so its 3h run is not wasted"
  nohup bash -c 'while python3 -c "import json,sys; sys.exit(0 if any(h[\"status\"]==\"running\" for h in json.load(open(\"/root/pe-fin/team/hypotheses.json\"))[\"hypotheses\"]) else 1)"; do sleep 120; done; pkill -f fin_team.py; sleep 1; nohup /root/pe-fin/team/run_team.sh & disown' >/dev/null 2>&1 & disown
else restart; sleep 60; fi
head -5 scoreboard.md; grep -A12 "## Paper ledger" scoreboard.md
bash publish.sh 2>&1 | tail -2
