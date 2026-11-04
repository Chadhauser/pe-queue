#!/bin/bash
set -o pipefail
# 499_rescore_own_goals (Finder 2026-11-04, queue item 38): re-run 452 (vendor systems), 453 (HT states), 455 (red cards) without the own-goal flip and with exits at goal +8 not +2. The number 499 is reused with a new slug: 450-499 are all taken.
# METHOD: read each old job, apply exact string patches (each count asserted, so a missed patch stops the run), run the patched python. The old job files are not changed. Everything else about the old job stands, including its fill (worse of two prints) and its entries at goal +2 in 452 (c), which are not exits.
# PATCHES: all three: af is_home already credits the benefiting team, so side = is_home with no flip. 452: LTD exit goal+2 -> goal+8, 'c' equaliser exit +2 -> +8. 453: NEXTGOAL +2 -> +8. 455: no goal exit, flip only. Connection: work_mem 64MB, statement_timeout 2400s (house rule since 4 Nov).
# CHECK: FT mismatches with and without the flip, on all mapped games (job 471 found 962 with, 41 without).
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,re,subprocess,time,psycopg2,pandas as pd
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
T0=time.time()
FLIP="side=('h' if r.is_home else 'a') if r.detail!='Own Goal' else ('a' if r.is_home else 'h')"
FIX="side=('h' if r.is_home else 'a')"
def apply(src,patches):
    """Exact replacements; each must match exactly the stated number of times."""
    for old,new,cnt in patches:
        n=src.count(old)
        if n!=cnt: raise ValueError(f"patch expected {cnt}, found {n}: {old}")
        src=src.replace(old,new)
    return src
def timeout_fix(s):
    new,n=re.subn(r"""cur\.execute\("SET statement_timeout='\d+s'"\)""","""cur.execute("SET work_mem='64MB'"); cur.execute("SET statement_timeout='2400s'")""",s)
    if n!=1: raise ValueError(f"timeout patch found {n}")
    return new
def body(src):
    a=src.index("<<'PY'"); a=src.index("\n",a)+1; b=src.rindex("\nPY")
    return src[a:b]
# known answers
assert apply("x=1; y=1",[("x=1","x=8",1)])=="x=8; y=1"
try: apply("x=1",[("z","y",1)]); raise SystemExit("patch check failed")
except ValueError: pass
assert body("a <<'PY' 2>&1 | grep\nprint(1)\nPY\n")=="print(1)"
assert timeout_fix("""cur.execute("SET statement_timeout='3000s'")""").count("work_mem")==1
Row=lambda is_home,detail:(('h' if is_home else 'a') if detail!='Own Goal' else ('a' if is_home else 'h'),('h' if is_home else 'a'))
assert Row(True,'Own Goal')==('a','h') and Row(True,'Normal Goal')==('h','h')
print("known-answer checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'"); cur.execute("SET statement_timeout='2400s'")
G=pd.read_sql("SELECT f.fixture_id,f.hg,f.ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL",con)
E=pd.read_sql("SELECT fixture_id,is_home,detail FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal')",con,params=(list(map(int,G.fixture_id)),))
E['raw_h']=E.is_home.astype(bool); E['flip_h']=[(not h) if d=='Own Goal' else h for h,d in zip(E.raw_h,E.detail)]
for nm,c in (('no flip','raw_h'),('flip','flip_h')):
    x=E.groupby('fixture_id')[c].agg(h='sum',n='size'); x['a']=x.n-x.h; y=G.set_index('fixture_id').join(x).fillna(0)
    print(f"FT mismatches, {nm}: {int(((y.h!=y.hg)|(y.a!=y.ag)).sum())} of {len(y)}",flush=True)
print(f"games with an own goal: {E[E.detail=='Own Goal'].fixture_id.nunique()}",flush=True); con.close()
JOBS=[('452_vendor_systems',[(FLIP,FIX,1),("first+2>95","first+8>95",1),("rp(Dr,first+2,95)","rp(Dr,first+8,95)",1),("rp(F,eq+2,95)","rp(F,eq+8,95)",1),("a LTD exit goal+2","a LTD exit goal+8",3)]),
      ('453_ht_states_all_markets',[(FLIP,FIX,1),("nxt+2>95","nxt+8>95",1),("rp(arr,nxt+2,95)","rp(arr,nxt+8,95)",1)]),
      ('455_red_cards',[(FLIP,FIX,1)])]
for nm,pt in JOBS:
    src=apply(open(f'/root/pe-queue/jobs/{nm}.sh').read(),pt); py=timeout_fix(body(src)); compile(py,nm,'exec')
    print(f"\n\n######## {nm}: patched, {len(pt)} patches, start {time.time()-T0:.0f}s",flush=True)
    r=subprocess.run([sys.executable,'-'],input=py,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    keep=[l for l in r.stdout.splitlines() if not re.match(r"\s+\d+/\d+ games",l)]
    print("\n".join(keep),flush=True); print(f"exit code {r.returncode}",flush=True)
print(f"\n== SURVIVORS: see each job's SURVIVORS section above. total {time.time()-T0:.0f}s")
PY
