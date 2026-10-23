#!/bin/bash
# 141: FACTORY v3 — CONFIRMED TRIGGERS. First clean Factory run (23 Oct) shows in-play cells with +50..+200 per £100 ("fav drifts to
# 2-3x SP: back") which is the signature of phantom ticks: a single bad LTP print nobody could be matched at. Rule now: an in-play
# level counts only when TWO consecutive minute prints are at/through it, and the fill is the SECOND print. Applies to E (drift-back),
# F (lay-green target and stop) and G (steam-ride entry). Settle-at-SP cells (A/B/C/D/H/A2/B2) are unaffected. Re-runs the Factory
# now in the background so tonight's report has confirmed numbers next to today's raw ones.
cd /root/pe-factory && python3 - <<'PY'
p='factory.py'; s=open(p).read(); n=0
helper='''
def conf_ge(path,level):
    for i in range(len(path)-1):
        if path[i]>=level and path[i+1]>=level: return path[i+1]
    return None
def conf_le(path,level):
    for i in range(len(path)-1):
        if path[i]<=level and path[i+1]<=level: return path[i+1]
    return None
'''
if 'def conf_ge' not in s:
    s=s.replace("def tstat(x):",helper+"def tstat(x):",1); n+=1
oldE="F[f'e{k}']=[next((p for p in path if p>=k*s),None) for path,s in zip(F.fpath,F.sp)]"
newE="F[f'e{k}']=[conf_ge(path,k*s) for path,s in zip(F.fpath,F.sp)]"
if oldE in s: s=s.replace(oldE,newE); n+=1
oldF='''            for p in row.fpath:
                if p>=tg: return lay_hedge(e,p)
                if p<=st: return lay_hedge(e,p)
            return lay_settle(e,row.won)'''
newF='''            path=row.fpath
            for i in range(len(path)-1):
                if path[i]>=tg and path[i+1]>=tg: return lay_hedge(e,path[i+1])
                if path[i]<=st and path[i+1]<=st: return lay_hedge(e,path[i+1])
            return lay_settle(e,row.won)'''
if oldF in s: s=s.replace(oldF,newF); n+=1
oldG='''        for p,t in zip(row.fpath,row.ftimes):
            if e is None and p<=0.7*row.sp: e=p; t0=t; continue'''
newG='''        prev=None
        for p,t in zip(row.fpath,row.ftimes):
            if e is None and p<=0.7*row.sp and prev is not None and prev<=0.7*row.sp: e=p; t0=t; continue
            prev=p
            if e is None: continue'''
if oldG in s: s=s.replace(oldG,newG); n+=1
s=s.replace("emit(sport,f'E fav drifts to {k}x SP: back, settle'","emit(sport,f'E fav drifts to {k}x SP (confirmed 2 ticks): back, settle'")
s=s.replace("emit(sport,f'F lay fav at SP, green +{int(gpct*100)}% stop -{int(spct*100)}%'","emit(sport,f'F lay fav at SP, green +{int(gpct*100)}% stop -{int(spct*100)}% (confirmed)'")
s=s.replace("emit(sport,'G fav shortens to 0.7x SP in play: back, sell +10m'","emit(sport,'G fav shortens to 0.7x SP (confirmed): back, sell +10m'")
open(p,'w').write(s); print("factory patches applied:",n,"of 4 (helper, E, F, G)")
PY
python3 -m py_compile factory.py || exit 1
python3 - <<'PY'
def conf_ge(path,level):
    for i in range(len(path)-1):
        if path[i]>=level and path[i+1]>=level: return path[i+1]
    return None
print("spike test: single tick 3.9 then back to 1.3 ->",conf_ge([1.2,3.9,1.3,1.25],3.6),"| genuine drift ->",conf_ge([1.2,3.7,3.9,4.0],3.6))
PY
# keep today's raw results for comparison, run confirmed version now
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require'); c.autocommit=True; cur=c.cursor()
cur.execute("UPDATE strategy_results SET run_date=run_date-1 WHERE run_date=current_date AND sport NOT IN ('FTS','Soccer-copy','Soccer-2s','CLV','InPlay') AND strategy NOT LIKE '%confirmed%'"); print("raw run re-dated to yesterday so the confirmed run writes today:",cur.rowcount)
PY
(nohup timeout 7200 python3 factory.py >> factory.log 2>&1 &) ; echo "factory v3 started in background"
