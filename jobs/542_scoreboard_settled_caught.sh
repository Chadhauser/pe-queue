#!/bin/bash
# 542 (Mon 9 Nov 2026). Scoreboard: (1) SETTLED table — £ per £100 after commission, by live line (bookie v2, desk FADE, desk HT11),
# the only money number Peter is told; (2) CAUGHT (24h) — what the controls stopped: Railway reads killed, catalogue overflows handled,
# desk calls voided for no tape, v1.1 relaunch attempts; (3) the daemon's start_bookie_if_ready() relaunched the stopped two-sided v1.1
# bot whenever fair_price_calib had rows — it now points at v2 (caught while reading the source for this job).
set -o pipefail
export PYTHONDONTWRITEBYTECODE=1
cd /root/pe-sports/team && cp sports_team.py sports_team.py.bak_542
python3 - <<'PY'
p='/root/pe-sports/team/sports_team.py'; s=open(p).read()
# (3) relaunch target -> v2, no .ready file
old="""        if n and subprocess.run(['pgrep','-f','bookie_paper.py'],capture_output=True).returncode!=0:
            open('/root/pe-sports/bookie/.ready','w').write('1'); subprocess.Popen(['nohup','/root/pe-sports/bookie/run_bookie.sh'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL); log("bookie paper bot started")"""
new="""        if n and subprocess.run(['pgrep','-f','bookie_v2.py'],capture_output=True).returncode!=0:   # 542: v2 only; v1.1 (two-sided) is stopped for good
            subprocess.Popen(['nohup','/root/pe-sports/bookie/run_bookie_v2.sh'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL); log("bookie v2 started by daemon")"""
assert s.count(old)==1, "relaunch anchor"; s=s.replace(old,new)
# (1)+(2) helpers before write_scoreboard
helpers='''
def settled_lines():
    """£ per £100 after commission by live line — the only money number reported."""
    rows=[]
    def add(label,sql):
        try:
            r=q('local',sql)[0]; n,stk,pnl,n7,pnl7=r
            rows.append((label,int(n or 0),float(pnl or 0),(float(pnl or 0)/float(stk))*100 if stk else None,int(n7 or 0),float(pnl7 or 0)))
        except Exception as e: rows.append((label,0,0.0,None,0,0.0))
    add('bookie v2 (Betfair, pre-off, passed cells)',"select count(*), coalesce(sum(stake),0), coalesce(sum(pnl),0), count(*) filter (where settled_ts>now()-interval '7 days'), coalesce(sum(pnl) filter (where settled_ts>now()-interval '7 days'),0) from bookie_paper where version='v2' and status='settled'")
    add('desk FADE (lay scorer +2m, out +10m)',"select count(*), coalesce(sum(stake),0), coalesce(sum(pnl),0), count(*) filter (where exit_ts>now()-interval '7 days'), coalesce(sum(pnl) filter (where exit_ts>now()-interval '7 days'),0) from desk_calls where line='FADE' and status='closed'")
    add('desk HT11 (1-1 HT, back O2.5)',"select count(*), coalesce(sum(stake),0), coalesce(sum(pnl),0), count(*) filter (where exit_ts>now()-interval '7 days'), coalesce(sum(pnl) filter (where exit_ts>now()-interval '7 days'),0) from desk_calls where line='HT11' and status='settled'")
    return rows
def caught_24h():
    """What the controls stopped in the last 24 h (empty for a week = the controls are not working; say so)."""
    out=[]; cut=(datetime.datetime.utcnow()-datetime.timedelta(hours=24)).strftime('%Y-%m-%d %H:%M:%S')
    def count(path,needle=None):
        try: return sum(1 for l in open(path) if l[:19]>=cut and (needle is None or needle in l))
        except Exception: return 0
    k=count('/root/pe-guard/railway_guard.log','killed');            out.append(f"Railway reads over 4 min killed: {k}")
    k=count('/root/pe-liq/bf_chunk.log','TOO_MUCH_DATA');            out.append(f"Betfair catalogue overflows absorbed (recorder stayed up): {k}")
    try: v=q('local',"select count(*) from desk_calls where status='void' and ts>now()-interval '24 hours'")[0][0]
    except Exception: v=0
    out.append(f"desk calls voided for no tape at exit: {v}")
    k=count('/root/pe-sports/team/sports_team.log','bookie v2 started by daemon'); out.append(f"bookie v2 relaunched by daemon: {k}")
    try: nq=q('local',"select count(*) from bookie_paper where version='v2' and ts>now()-interval '24 hours'")[0][0]; nc=q('local',"select count(*) from fair_price_passed")[0][0]
    except Exception: nq=nc=None
    out.append(f"bookie v2: passed cells {nc}, quotes 24h {nq} (no cell -> no quote)")
    return out
def write_scoreboard(sb):'''
assert s.count("\ndef write_scoreboard(sb):")==1; s=s.replace("\ndef write_scoreboard(sb):",helpers,1)
old2='''    broken=[k for k,v in sb['data_health'].items() if v['status']=='BROKEN']'''
new2='''    try:
        L.insert(3,""); L.insert(4,"## Settled — £ per £100 after commission (the number that matters)"); L.insert(5,"| line | settled n | £ | £ per £100 | n 7d | £ 7d |"); L.insert(6,"|---|---|---|---|---|---|")
        for i,(lab,n,pnl,per100,n7,p7) in enumerate(settled_lines()): L.insert(7+i,f"| {lab} | {n} | {pnl:+.2f} | {'n/a' if per100 is None else f'{per100:+.2f}'} | {n7} | {p7:+.2f} |")
    except Exception as e: L+=[f"(settled lines failed: {e!r})"]
    broken=[k for k,v in sb['data_health'].items() if v['status']=='BROKEN']'''
assert s.count(old2)==1, "render anchor"; s=s.replace(old2,new2)
old3="    open(SBMD+'.tmp','w').write(\"\\n\".join(L)); os.replace(SBMD+'.tmp',SBMD)"
new3='''    try: L+=["","## Caught (24h) — what the controls stopped"]+[f"- {c}" for c in caught_24h()]
    except Exception as e: L+=[f"(caught line failed: {e!r})"]
'''+old3
assert s.count(old3)==1, "write anchor"; s=s.replace(old3,new3)
open(p,'w').write(s); print("sports_team patched: settled table, caught line, v2 relaunch")
PY
python3 -m py_compile sports_team.py && echo compiles || { cp sports_team.py.bak_542 sports_team.py; echo RESTORED; exit 1; }
pkill -f 'sports_team.py'; sleep 2; nohup /root/pe-sports/team/run_team.sh >/dev/null 2>&1 & disown
sleep 90; sed -n 1,16p /root/pe-sports/team/scoreboard.md; grep -A6 "## Caught" /root/pe-sports/team/scoreboard.md
echo "542 done"
