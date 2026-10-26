#!/bin/bash
# 255: BUG — 3 of 4 XG_DOM paper trades from 25 Oct never settled: settlement needs a sane draw sample at minute>=85 in the
# recorder, and when there is none (recorder minute is estimated from scheduled KO; market often closes before it reads 85) the
# bot 'continue's forever. Fix: fall back to the ESPN final score (laid side won = loss, otherwise win), UNKNOWN only after 4 h.
set -e
python3 - <<'PY'
p='/root/pe-xg/xg_paper.py'; s=open(p).read()
old="""                fin=final_book(mid)
                if not fin: continue
                w=min(fin,key=fin.get)
                if fin[w]>1.15: reason,pnl='UNKNOWN',None
                elif w==sel: reason,pnl='SETTLE_LOSS',round(-STAKE*(lp-1),2)
                else: reason,pnl='SETTLE_WIN',round(STAKE*(1-COMM),2)
"""
new="""                fin=final_book(mid)
                if fin and min(fin.values())<=1.15:
                    w=min(fin,key=fin.get)
                    if w==sel: reason,pnl='SETTLE_LOSS',round(-STAKE*(lp-1),2)
                    else: reason,pnl='SETTLE_WIN',round(STAKE*(1-COMM),2)
                else:
                    fs=final_score(mid)
                    if fs and fs[2] is not None and fs[2]>=85:
                        won=(fs[0]>fs[1]) if sel=='HOME' else (fs[1]>fs[0])
                        reason,pnl=('SETTLE_LOSS',round(-STAKE*(lp-1),2)) if won else ('SETTLE_WIN',round(STAKE*(1-COMM),2))
                    elif now<ets+datetime.timedelta(hours=4): continue
                    else: reason,pnl='UNKNOWN',None
"""
if new in s: print("already patched")
else:
    assert old in s, "settle anchor missing"; s=s.replace(old,new,1); open(p,'w').write(s); print("xg settle patched")
PY
python3 -m py_compile /root/pe-xg/xg_paper.py; pkill -f xg_paper.py || true; sleep 2; nohup /root/pe-xg/keepalive.sh >/dev/null 2>&1 &
sleep 90; pgrep -af xg_paper.py | head -1
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
k=psycopg2.connect(DB,sslmode='require').cursor()
k.execute("SELECT id, event_name, sel, lay_px, exit_reason, pnl_per_10 FROM xg_paper ORDER BY id"); [print("  ",r) for r in k.fetchall()]
k.execute("SELECT * FROM xg_heartbeat"); print("xg hb:",k.fetchall())
PY
