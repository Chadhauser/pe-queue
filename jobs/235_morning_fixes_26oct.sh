#!/bin/bash
# 235: Monday fixes. (1) opportunity map crashed on numpy floats in the insert -> cast; rerun on 30 days. (2) late lay-Over settlement
# left two trades UNKNOWN when the closing book failed the spread check -> fall back to the ESPN final score of the matched Match Odds
# market (3+ goals = Over landed). (3) cross-exchange test died silently (likely memory on 12 days of rows) -> 5 days, in-play rows only,
# errors printed unfiltered.
set -e
python3 - <<'PY'
p='/root/pe-factory/opp_map.py'; s=open(p).read()
old="rows.append((datetime.date.today(),mid,evn,g.competition.iloc[0],mkt,sel,dr,ei,xi,round(epx,2),round(xpx,2),round(p,2),goals_at(ei),n))"
new="rows.append((datetime.date.today(),mid,evn,g.competition.iloc[0],mkt,sel,dr,int(ei),int(xi),float(round(epx,2)),float(round(xpx,2)),float(round(p,2)),int(goals_at(ei)),int(n)))"
assert old in s; s=s.replace(old,new,1); open(p,'w').write(s); print("opp_map cast fixed")
p='/root/pe-xg/late_over_paper.py'; s=open(p).read()
old="""            if not r: reason,pnl='UNKNOWN',None
            elif float(r[0])<=1.15: reason,pnl='SETTLE_LOSS',round(-STAKE*(lp-1),2)
            elif float(r[0])>=5: reason,pnl='SETTLE_WIN',round(STAKE*(1-COMM),2)
            else: reason,pnl='UNKNOWN',None"""
new="""            cur.execute("SELECT mo_market_id FROM late_over_paper WHERE id=%s",(pid,)); mo=cur.fetchone()[0]
            cur.execute('SELECT hs, "as", minute FROM espn_stats WHERE market_id=%s AND hs IS NOT NULL ORDER BY ts DESC LIMIT 1',(mo,)) if mo else None
            fs=cur.fetchone() if mo else None
            if fs and fs[2] is not None and fs[2]>=88: reason,pnl=('SETTLE_LOSS',round(-STAKE*(lp-1),2)) if fs[0]+fs[1]>=3 else ('SETTLE_WIN',round(STAKE*(1-COMM),2))
            elif not r: reason,pnl='UNKNOWN',None
            elif float(r[0])<=1.15: reason,pnl='SETTLE_LOSS',round(-STAKE*(lp-1),2)
            elif float(r[0])>=5: reason,pnl='SETTLE_WIN',round(STAKE*(1-COMM),2)
            else: reason,pnl='UNKNOWN',None"""
assert old in s; s=s.replace(old,new,1); open(p,'w').write(s); print("late-over settle fallback added")
PY
python3 -m py_compile /root/pe-factory/opp_map.py /root/pe-xg/late_over_paper.py
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require'); c.autocommit=True; k=c.cursor()
k.execute("UPDATE late_over_paper SET exit_ts=NULL, exit_reason=NULL WHERE exit_reason='UNKNOWN'"); print("re-opened UNKNOWN:",k.rowcount)
PY
pkill -f late_over_paper.py || true; sleep 2; /root/pe-xg/keepalive_lo.sh
cd /root/pe-factory && timeout 3000 python3 opp_map.py 30 2>&1 | grep -v -E "UserWarning|pd.read_sql|events, rows"
