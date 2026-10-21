#!/bin/bash
# 119: M1 goal counter counted every reopen burst as a goal (Roma v Slovan 20 Oct: "goal 3 of match" at 39' with 1-1 on the pitch;
# Liverpool 45' real 3rd goal fine, but HT/FT suspension bursts pushed real 2nd goals past the ">2 goals" filter). Now a goal =
# a reopen where a team shortened 3%+, and reopens within 4 minutes of the previous counted goal are the same goal.
python3 - <<'PY'
p='/root/pe-push/m1_alert.py'; s=open(p).read()
old='''            cur.execute("SELECT count(DISTINCT goal_ts) n FROM liq_goal_depth WHERE event_name=%s AND mkt='MO' AND offset_s=0 AND goal_ts<=%s AND goal_ts>now()-interval '3 hours'",(ev,gts))
            goals=cur.fetchone()['n'] or 1'''
new='''            cur.execute("""SELECT goal_ts FROM liq_goal_depth WHERE event_name=%s AND mkt='MO' AND offset_s=0 AND goal_ts<=%s AND goal_ts>now()-interval '3 hours'
                           AND upper(coalesce(sel,'')) NOT IN ('DRAW','THE DRAW','X') AND pre_ltp>0 AND ltp>0
                           GROUP BY goal_ts HAVING min(ltp/pre_ltp)<=0.97 ORDER BY goal_ts""",(ev,gts))
            _gl=[r['goal_ts'] for r in cur.fetchall()]; goals=0; _last=None
            for _t in _gl:
                if _last is None or (_t-_last).total_seconds()>=240: goals+=1; _last=_t
            goals=goals or 1'''
assert old in s, "pattern not found"
s=s.replace(old,new); open(p,'w').write(s); print("goal counter patched")
PY
python3 -m py_compile /root/pe-push/m1_alert.py || exit 1
pkill -f m1_alert.py; echo "alerter restarts via keepalive"
sleep 70; pgrep -af m1_alert.py; cat /root/pe-push/m1_mode
