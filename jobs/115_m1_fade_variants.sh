#!/bin/bash
# 115: M1 FADE VARIANTS in the shadow book. Udinese v Lecce showed the fade paid on the CONCEDING team (+6.86) and the DRAW (+4.59)
# and lost on the scorer (-6.19). For every qualifying goal the alerter now also records, silently, the lay-conceder and lay-draw
# legs: entry = that selection's best lay at +60s, exit = its best back at +10 min or the next goal. Table m1_variants.
python3 - <<'PY'
p='/root/pe-push/m1_alert.py'; s=open(p).read()
if 'm1_variants' not in s:
    s=s.replace("def push(title,body,tag):",
"""cur.execute(\"\"\"CREATE TABLE IF NOT EXISTS m1_variants (id SERIAL PRIMARY KEY, market_id TEXT, goal_ts TIMESTAMPTZ, event_name TEXT, competition TEXT, minute INT, leg TEXT, sel TEXT,
  entry_px NUMERIC, entry_at TIMESTAMPTZ, exit_due TIMESTAMPTZ, exit_px NUMERIC, exit_at TIMESTAMPTZ, exit_reason TEXT, UNIQUE (market_id, goal_ts, leg))\"\"\")
def record_variants(mid,gts,ev,comp,minute,scorer_sel):
    other={'HOME':'AWAY','AWAY':'HOME'}.get((scorer_sel or '').upper())
    for leg,sel in (('conceder',other),('draw','DRAW')):
        if not sel: continue
        cur.execute("SELECT lay_px FROM liq_goal_depth WHERE market_id=%s AND goal_ts=%s AND sel=%s AND offset_s>0 AND lay_px IS NOT NULL ORDER BY ts DESC LIMIT 1",(mid,gts,sel)); r=cur.fetchone()
        if not r:
            cur.execute("SELECT lay_px FROM liq_sample WHERE market_id=%s AND sel=%s AND lay_px IS NOT NULL AND ts>%s ORDER BY ts DESC LIMIT 1",(mid,sel,gts)); r=cur.fetchone()
        if not r: continue
        cur.execute("INSERT INTO m1_variants (market_id,goal_ts,event_name,competition,minute,leg,sel,entry_px,entry_at,exit_due) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,now(),%s) ON CONFLICT DO NOTHING",
                    (mid,gts,ev,comp,minute,leg,sel,float(r['lay_px']),gts+datetime.timedelta(seconds=60+HOLD)))
def close_variants():
    cur.execute("SELECT * FROM m1_variants WHERE exit_at IS NULL")
    for v in cur.fetchall():
        cur.execute("SELECT 1 FROM liq_goal_depth WHERE market_id=%s AND offset_s=0 AND goal_ts>%s LIMIT 1",(v['market_id'],v['entry_at'])); newg=cur.fetchone() is not None
        if not newg and datetime.datetime.now(datetime.timezone.utc)<v['exit_due']: continue
        cur.execute("SELECT back_px FROM liq_sample WHERE market_id=%s AND sel=%s AND back_px IS NOT NULL ORDER BY ts DESC LIMIT 1",(v['market_id'],v['sel'])); r=cur.fetchone()
        cur.execute("UPDATE m1_variants SET exit_at=now(), exit_px=%s, exit_reason=%s WHERE id=%s",(float(r['back_px']) if r else None,'GOAL' if newg else 'CLOCK',v['id']))
def push(title,body,tag):""")
    # record variants wherever an entry (shadow or pushed) is written
    s=s.replace("                print('shadow entry',p['ev'],px,flush=True); continue",
                "                record_variants(mid,gts,p['ev'],p['comp'],p['minute'],p['sel']); print('shadow entry',p['ev'],px,flush=True); continue")
    s=s.replace("            n=push(f\"M1 ENTRY — {p['ev']}\"","            record_variants(mid,gts,p['ev'],p['comp'],p['minute'],p['sel'])\n            n=push(f\"M1 ENTRY — {p['ev']}\"")
    # close variants each loop (before exits block)
    s=s.replace("        # 3. exits: +10 min, or a new goal/suspension on the market first","        close_variants()\n        # 3. exits: +10 min, or a new goal/suspension on the market first")
    open(p,'w').write(s); print("variants patched:", s.count('record_variants('), "call sites")
else: print("already patched")
PY
python3 -m py_compile /root/pe-push/m1_alert.py && pkill -f m1_alert.py; sleep 75; pgrep -af m1_alert.py; tail -3 /root/pe-push/m1.log
echo "--- factory v2 progress:"; tail -5 /root/pe-factory/factory_run.log
