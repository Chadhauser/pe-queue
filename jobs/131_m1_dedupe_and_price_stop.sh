#!/bin/bash
# 131: M1 fixes from Wednesday's UCL pushes: (1) Bayern 62' was pushed twice (two reopen rows seconds apart) -> any market with a
# non-SKIP alert in the last 4 minutes is a duplicate; (2) Sporting v LASK: LASK scored again and the "next goal" exit never fired
# (-£6.97 instead of ~-£3) -> add a PRICE stop: if the laid team's back price falls 20%+ below our lay price, exit now (STOP).
python3 - <<'PY'
p='/root/pe-push/m1_alert.py'; s=open(p).read()
a='''            cur.execute("SELECT 1 FROM m1_alerts WHERE market_id=%s AND goal_ts=%s",(mid,gts))
            if cur.fetchone(): continue
'''
b=a+'''            cur.execute("SELECT 1 FROM m1_alerts WHERE market_id=%s AND reason NOT LIKE 'SKIP%%' AND goal_ts > %s - interval '4 minutes' AND goal_ts < %s",(mid,gts,gts))
            if cur.fetchone():
                cur.execute("INSERT INTO m1_alerts (market_id,goal_ts,event_name,competition,reason) VALUES (%s,%s,%s,%s,'SKIP: duplicate reopen within 4 min') ON CONFLICT DO NOTHING",(mid,gts,rows[0]['event_name'],rows[0]['competition'])); continue
'''
assert a in s, "dedupe anchor not found"; s=s.replace(a,b)
old='''            cur.execute("SELECT 1 FROM liq_goal_depth WHERE market_id=%s AND offset_s=0 AND goal_ts>%s LIMIT 1",(t['market_id'],t['entry_sent'])); newg=cur.fetchone() is not None
            if not newg and now<t['exit_due']: continue
            cur.execute("SELECT back_px FROM liq_sample WHERE market_id=%s AND sel=%s AND back_px IS NOT NULL ORDER BY ts DESC LIMIT 1",(t['market_id'],t['sel'])); r=cur.fetchone()
            bp=float(r['back_px']) if r else None
'''
new='''            cur.execute("SELECT 1 FROM liq_goal_depth WHERE market_id=%s AND offset_s=0 AND goal_ts>%s LIMIT 1",(t['market_id'],t['entry_sent'])); newg=cur.fetchone() is not None
            cur.execute("SELECT back_px FROM liq_sample WHERE market_id=%s AND sel=%s AND back_px IS NOT NULL ORDER BY ts DESC LIMIT 1",(t['market_id'],t['sel'])); r=cur.fetchone()
            bp=float(r['back_px']) if r else None
            stop=(bp is not None and bp<=float(t['entry_px'])*0.80)
            if not newg and not stop and now<t['exit_due']: continue
            if stop and not newg: newg=True   # treat as the next-goal exit (price says they scored again)
'''
assert old in s, "exit anchor not found"; s=s.replace(old,new)
s=s.replace("(bp,'GOAL' if newg else 'CLOCK',t['id'])","(bp,('STOP' if stop else 'GOAL') if newg else 'CLOCK',t['id'])")
open(p,'w').write(s); print("m1_alert.py patched: 4-min dedupe + 20pct price stop")
PY
python3 -m py_compile /root/pe-push/m1_alert.py || exit 1
pkill -f m1_alert.py; sleep 70; pgrep -af m1_alert.py; cat /root/pe-push/m1_mode
