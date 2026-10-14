#!/bin/bash
# 065: (1) 053 goal-signal-vs-market: crash on the money table (groupby astype) fixed, rerun.
#      (2) 048 racing pre-off v2: v1's 'survivors' were artefacts — scalps measured from the MID of a wide back/lay spread at 20+
#          prices (you cannot back at the mid), and section 3 measured a move using the same prices that defined the move band.
#          v2 enters at the REAL side (back at best back, lay at best lay), closes at BSP, drops the self-referential section, and
#          caps prices at 30.
#      (3) Credential diagnostic: 059 reported betfair username/password NOT visible to the runner although the recorders are alive.
#          Print WHERE the live recorder got them (names only from /proc/<pid>/environ), crontab env lines (names), /etc/environment names.
set +e
cd /root/pe-scan
python3 - <<'PY'
s=open('goal_signal_vs_market_v2.py').read()
s=s.replace("goal10=D.groupby('direction').goal_in_10.astype(float).mean().round(3)","goal10=D.assign(g=D.goal_in_10.astype(float)).groupby('direction').g.mean().round(3)")
open('goal_signal_vs_market_v2.py','w').write(s)
s=open('racing_preoff_scan.py').read()
s=s.replace("D['scalp_b5_bsp']=[back_then_lay(e,x) for e,x in zip(D.p5,D.bsp)]","D=D[(D.p5_b.astype(float)<=30)&(D.p10.astype(float)<=30)].copy()\nD['scalp_b5_bsp']=[back_then_lay(float(e),x) for e,x in zip(D.p5_b,D.bsp)]")
s=s.replace("D['scalp_l5_bsp']=[lay_then_back(e,x) for e,x in zip(D.p5,D.bsp)]","D['scalp_l5_bsp']=[lay_then_back(float(e),x) for e,x in zip(D.p5_l,D.bsp)]")
s=s.replace("D['scalp_b10_5']=[back_then_lay(e,x) for e,x in zip(D.p10,D.p5)]","D['scalp_b10_5']=[back_then_lay(float(e),float(x)) for e,x in zip(D.p10_b,D.p5_l)]")
s=s.replace("D['win5']=np.where(D.won,(D.p5*(1-SPREAD)-1)*(1-COMM),-1.0)","D['win5']=np.where(D.won,(D.p5_b.astype(float)*(1-SPREAD)-1)*(1-COMM),-1.0)")
s=s.replace("D['lay5']=np.where(D.won,-(D.p5*(1+SPREAD)-1),(1-COMM))","D['lay5']=np.where(D.won,-(D.p5_l.astype(float)*(1+SPREAD)-1),(1-COMM))")
s=s.replace("D['lay5_liab']=D.lay5/np.where(D.won,1,1)/(D.p5*(1+SPREAD)-1).clip(lower=0.01)","D['lay5_liab']=D.lay5/(D.p5_l.astype(float)*(1+SPREAD)-1).clip(lower=0.01)")
s=s.replace("survivors(['band10','mv'],['scalp_b10_5'],'3. SCALP 10m -> 5m (does a move continue?)')","print('\\n(section 3 removed: it measured the move with the prices that defined it)')")
s=s.replace("print(\"\\nVERDICT RULE","print('\\n=== 7. Spread at 5m by band (lay/back-1, median) — why the mid is not tradeable at long prices ===')\nprint((D.p5_l.astype(float)/D.p5_b.astype(float)-1).groupby(D.band10,observed=True).median().round(3).to_string())\nprint(\"\\nVERDICT RULE")
open('racing_preoff_scan.py','w').write(s)
PY
python3 -m py_compile goal_signal_vs_market_v2.py racing_preoff_scan.py || exit 1
echo "=================== CREDENTIAL SOURCES ==================="
for p in $(pgrep -f "ip_recorder.py|liq_recorder.py|pg_bot.py"); do echo "pid $p $(tr '\0' '\n' < /proc/$p/environ | grep -oE '^(BETFAIR|BF|APP|API)[A-Z_]*' | sort -u | tr '\n' ' ')"; done
echo "runner env names: $(env | grep -oE '^(BETFAIR|BF|APP|API)[A-Z_]*' | sort -u | tr '\n' ' ')"
echo "crontab env lines (names): $(crontab -l | grep -E '^[A-Z_]+=' | cut -d= -f1 | tr '\n' ' ')"
echo "/etc/environment names: $(grep -oE '^[A-Z_]+' /etc/environment 2>/dev/null | tr '\n' ' ')"
echo ".env files: $(ls /root/pe-*/.env* /root/*/.env 2>/dev/null | tr '\n' ' ')"
echo ".env var names: $(cat /root/pe-logger/.env | grep -oE '^[A-Za-z_]+' | sort -u | tr '\n' ' ')"
python3 -c "import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds; print('creds.report:',creds.report())"
echo "=================== 053 GOAL SIGNAL VS MARKET (rerun) ==================="; python3 goal_signal_vs_market_v2.py
echo "=================== 048 RACING PRE-OFF v2 ==================="; python3 racing_preoff_scan.py
