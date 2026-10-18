#!/bin/bash
# 106: M1 SHADOW MODE. Goals that meet the M1 rules (10'-75', <=2nd goal, scorer lay 1.30-2.50) in any tier-1/2 competition but
# are NOT card/£500k games are recorded as paper trades (reason 'SHADOW', no push): entry at +60s best lay, exit at +10 min or
# next goal, same as the pushed ones. Fills the M1 paper book 20x faster. Tier list = the PG bot's TIER12 set.
python3 - <<'PY'
p='/root/pe-push/m1_alert.py'; s=open(p).read()
if 'SHADOW' not in s:
    s=s.replace("MAXDAY=6\n","MAXDAY=6\nimport re as _re\nTIER12=_re.compile(r'premier league|la liga|serie a|bundesliga|ligue 1|champions league|europa league|championship|eredivisie|primeira|pro league|super lig|premiership|segunda|serie b|2\\. bundesliga|ligue 2',_re.I)\n")
    s=s.replace("            why='card' if ev[:40].strip() in CARD else ('big' if tm>=BIG else None)\n",
                "            why='card' if ev[:40].strip() in CARD else ('big' if tm>=BIG else ('SHADOW' if TIER12.search(comp or '') else None))\n")
    # shadow entries: record but do not push
    s=s.replace("            exit_min=(p['minute'] or 0)+10\n            n=push(",
                "            exit_min=(p['minute'] or 0)+10\n            if p['why']=='SHADOW':\n                cur.execute(\"INSERT INTO m1_alerts (market_id,goal_ts,event_name,competition,team,sel,minute,goals,reason,entry_px,entry_sent,exit_due,recipients) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,'SHADOW',%s,now(),%s,0) ON CONFLICT DO NOTHING\",(mid,gts,p['ev'],p['comp'],p['team'],p['sel'],p['minute'],p['goals'],px,gts+datetime.timedelta(seconds=60+HOLD)))\n                print('shadow entry',p['ev'],px,flush=True); continue\n            n=push(")
    # shadow exits: compute, no push
    s=s.replace("            push(f\"M1 EXIT — {t['event_name']}\"","            if t['reason']=='SHADOW':\n                cur.execute(\"UPDATE m1_alerts SET exit_sent=now(), exit_px=%s, exit_reason=%s WHERE id=%s\",(bp,'GOAL' if newg else 'CLOCK',t['id'])); continue\n            push(f\"M1 EXIT — {t['event_name']}\"")
    # daily cap applies to pushed only
    s=s.replace("cur.execute(\"SELECT count(*) n FROM m1_alerts WHERE entry_sent::date=current_date\"); today=cur.fetchone()['n']","cur.execute(\"SELECT count(*) n FROM m1_alerts WHERE entry_sent::date=current_date AND reason<>'SHADOW'\"); today=cur.fetchone()['n']")
    open(p,'w').write(s); print("shadow mode patched")
else: print("already patched")
PY
python3 -m py_compile /root/pe-push/m1_alert.py && pkill -f m1_alert.py; sleep 70; pgrep -af m1_alert.py; tail -3 /root/pe-push/m1.log
