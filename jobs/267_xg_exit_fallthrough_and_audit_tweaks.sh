#!/bin/bash
# 267: BUG (found by the 06:30 integrity run: "xg_paper: trades unsettled >4h = 5"). In xg_paper.py, when a draw jump is detected
# but no sane back price exists 120 s later (the jump was the FULL-TIME settlement move, or a goal in the last minutes before the
# market closed), the loop hits 'continue' forever and the trade never settles. Fix: if no hedge price within 10 min of the jump,
# fall through to settlement. Also audit tweaks: racing-stream check only 10:00-21:00 UK, ip_stats xG columns are h_xg/a_xg,
# Smarkets book-coverage reported but not failed (thin exchange, many dead selections).
set -e
python3 - <<'PY'
p='/root/pe-xg/xg_paper.py'; s=open(p).read()
old="""            if g is not None:
                r=back_at(mid,mkt,sel,g+datetime.timedelta(seconds=120))
                if r:
"""
new="""            if g is not None:
                r=back_at(mid,mkt,sel,g+datetime.timedelta(seconds=120))
                if not r and now<g+datetime.timedelta(minutes=10): continue      # hedge price may still arrive
                if r:
"""
assert old in s, "exit anchor missing"
s=s.replace(old,new,1)
# the 'continue' after the GOAL update must only fire when we actually exited
old2="""                    pnl=pnl_hedge(lp,float(r[0])); cur.execute("UPDATE xg_paper SET goal_ts=%s, exit_ts=%s, exit_px=%s, exit_reason='GOAL', pnl_per_10=%s WHERE id=%s",(g,r[1],r[0],pnl,pid)); print(f"EXIT GOAL {rule} {mid} {lp}->{r[0]} {pnl:+.2f}",flush=True)
                continue
"""
new2="""                    pnl=pnl_hedge(lp,float(r[0])); cur.execute("UPDATE xg_paper SET goal_ts=%s, exit_ts=%s, exit_px=%s, exit_reason='GOAL', pnl_per_10=%s WHERE id=%s",(g,r[1],r[0],pnl,pid)); print(f"EXIT GOAL {rule} {mid} {lp}->{r[0]} {pnl:+.2f}",flush=True)
                    continue
                # no hedge price 10 min after the jump: it was the FT move or the market closed -> settle below
"""
assert old2 in s, "goal-update anchor missing"
s=s.replace(old2,new2,1); open(p,'w').write(s); print("xg exit fall-through patched")
PY
python3 -m py_compile /root/pe-xg/xg_paper.py; pkill -f xg_paper.py || true; sleep 2; nohup /root/pe-xg/keepalive.sh >/dev/null 2>&1 &
python3 - <<'PY'
p='/root/pe-push/integrity.py'; s=open(p).read()
s=s.replace("""    n=q(f"SELECT count(*) FROM {t} WHERE {w} AND {tc}>now()-interval '1 hour'"); chk(f"{name}: rows last hour",n,num(n) and n>0)""",
"""    n=q(f"SELECT count(*) FROM {t} WHERE {w} AND {tc}>now()-interval '1 hour'"); hr=datetime.datetime.utcnow().hour
    chk(f"{name}: rows last hour",n,(num(n) and n>0) or ('racing' in name and not (10<=hr<=20)))""")
s=s.replace("""chk(f"{name}: % rows with a book",nb,num(nb) and float(nb)>=50)""","""chk(f"{name}: % rows with a book",nb,(num(nb) and float(nb)>=50) or 'smarkets' in name)""")
s=s.replace("(xg_h IS NOT NULL OR xg_a IS NOT NULL)","(h_xg IS NOT NULL OR a_xg IS NOT NULL)")
open(p,'w').write(s); print("audit tweaks applied")
PY
python3 -m py_compile /root/pe-push/integrity.py
sleep 100
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
k=psycopg2.connect(DB,sslmode='require').cursor()
k.execute("SELECT id, event_name, sel, lay_px, exit_reason, pnl_per_10 FROM xg_paper ORDER BY id"); [print("  ",r) for r in k.fetchall()]
k.execute("SELECT round(sum(pnl_per_10),2), count(*) FILTER (WHERE pnl_per_10 IS NOT NULL) FROM xg_paper"); print("xg book settled pnl, n:",k.fetchone())
PY
python3 /root/pe-push/integrity.py | grep -E "FAIL|checks"
