#!/bin/bash
# 273: USER-SUBMITTED TRADE GRADER (Peter 27 Oct: "any way of testing user submitted trades and you coming up with a rule?").
# Peter posts trades in chat in one line: Match | MO or OU25 | HOME/AWAY/DRAW/OVER/UNDER | back or lay | price | minute | score | note
# Each becomes a row in user_trades. grade.py maps the trade to its cell in the TRUE-goal history (3,440 top-league games,
# v4_stats_minute: state = score/lead, minute, price band, direction) and reports the historical mean per £10 for every exit,
# plus the live outcome once the game is on the tape (goal after entry, price 10/20 min later). The RULE is then the cells his
# profitable trades share — reported once 20 trades are in. This job builds the table and script and grades a worked example.
set -e
mkdir -p /root/pe-user
cat > /root/pe-user/grade.py <<'PYFILE'
import sys, re, psycopg2, datetime
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("""CREATE TABLE IF NOT EXISTS user_trades (id SERIAL PRIMARY KEY, submitted TIMESTAMPTZ DEFAULT now(), match TEXT, mkt TEXT, sel TEXT, side TEXT,
  price NUMERIC, minute INT, score TEXT, note TEXT, market_id TEXT, hist_fam TEXT, hist_cells TEXT, live_goal_ts TIMESTAMPTZ, live_px10 NUMERIC, live_px20 NUMERIC, live_pnl_hedge10 NUMERIC, graded TIMESTAMPTZ)""")
def band(p): return '<1.5' if p<1.5 else '1.5-2.5' if p<2.5 else '2.5-5' if p<5 else '5+'
def add(line):
    parts=[x.strip() for x in line.split('|')]
    if len(parts)<7: raise SystemExit("need: Match | MO/OU25 | HOME/AWAY/DRAW/OVER/UNDER | back/lay | price | minute | score | note")
    match,mkt,sel,side,price,minute,score=parts[:7]; note=parts[7] if len(parts)>7 else ''
    cur.execute("INSERT INTO user_trades (match,mkt,sel,side,price,minute,score,note) VALUES (%s,%s,%s,%s,%s,%s,%s,%s) RETURNING id",(match,mkt.upper(),sel.upper(),side.lower(),float(price),int(minute),score,note)); return cur.fetchone()[0]
def grade(tid):
    cur.execute("SELECT match,mkt,sel,side,price,minute,score FROM user_trades WHERE id=%s",(tid,)); match,mkt,sel,side,price,minute,score=cur.fetchone(); price=float(price)
    try: hs,as_=[int(x) for x in re.split(r'[-:]',score)]
    except Exception: hs,as_=None,None
    fams=[]
    if mkt=='MO':
        if hs==0 and as_==0: fams.append('LEVEL00')
        if hs is not None and abs(hs-as_)==1: fams.append('LEAD1')
        fams+=['DOMxg0.5','DOMxg0.8','DOMxg1.2','DOMsot3']
    else:
        fams+=['OPENxg1.0','OPENxg1.5','OPENxg2.0','G2LATE']
    m5=int(round(minute/5.0)*5); b=band(price); selkey=f"{mkt} {sel}"
    cur.execute("""SELECT fam, exit, n, round(mean,2), round(t,2) FROM v4_stats_minute WHERE run_date=(SELECT max(run_date) FROM v4_stats_minute)
                   AND fam = ANY(%s) AND sel=%s AND dir=%s AND band=%s AND minute BETWEEN %s AND %s AND n>=50 ORDER BY fam, exit""",(fams,selkey,side,b,m5-5,m5+5))
    rows=cur.fetchall()
    cells="; ".join(f"{f}@{e}: n{n} {mean:+}/£10 t{t}" for f,e,n,mean,t in rows) or "no history cell for this state (price band %s, minute %s, %s %s)"%(b,m5,side,selkey)
    # live match on the tape
    cur.execute("SELECT market_id FROM liq_sample WHERE mkt=%s AND lower(event_name)=lower(%s) ORDER BY ts DESC LIMIT 1",(mkt if mkt in('MO','OU25') else 'MO',match.replace(' vs ',' v ')))
    r=cur.fetchone(); mid=r[0] if r else None
    px10=px20=pnl=None; gts=None
    if mid:
        tsel={'OVER':'OVER','UNDER':'UNDER','HOME':'HOME','AWAY':'AWAY','DRAW':'DRAW'}[sel]
        cur.execute("SELECT ts FROM liq_sample WHERE market_id=%s AND sel=%s AND minute>=%s ORDER BY ts LIMIT 1",(mid,tsel,minute)); r=cur.fetchone(); t0=r[0] if r else None
        if t0:
            for k,off in (('px10',10),('px20',20)):
                cur.execute("SELECT back_px, lay_px FROM liq_sample WHERE market_id=%s AND sel=%s AND back_px IS NOT NULL AND lay_px IS NOT NULL AND lay_px<=back_px*1.2 AND ts>=%s ORDER BY ts LIMIT 1",(mid,tsel,t0+datetime.timedelta(minutes=off))); r=cur.fetchone()
                if r: (px10 if k=='px10' else px20)
                if k=='px10' and r: px10=float(r[1] if side=='back' else r[0])
                if k=='px20' and r: px20=float(r[1] if side=='back' else r[0])
            if px20: pnl=round(10*(1-px20/price),2) if side=='back' else round(10*(px20/price-1),2)
    cur.execute("UPDATE user_trades SET market_id=%s, hist_fam=%s, hist_cells=%s, live_px10=%s, live_px20=%s, live_pnl_hedge10=%s, graded=now() WHERE id=%s",(mid,",".join(fams),cells,px10,px20,pnl,tid))
    print(f"#{tid} {match} | {side} {selkey} @ {price} {minute}' {score}\n   history: {cells}\n   live: market {mid or 'not on tape'} | price +10m {px10} | +20m {px20} | hedge-at-20m P&L per £10 {pnl}")
def rule():
    cur.execute("SELECT count(*) FROM user_trades"); n=cur.fetchone()[0]
    if n<20: print(f"rule: {n}/20 trades submitted — rule mining starts at 20"); return
    cur.execute("SELECT hist_fam, side, mkt||' '||sel, count(*), round(avg(live_pnl_hedge10),2) FROM user_trades WHERE live_pnl_hedge10 IS NOT NULL GROUP BY 1,2,3 ORDER BY 5 DESC"); print("rule candidates (state, side, runner, n, live mean/£10):",cur.fetchall())
if __name__=='__main__':
    a=sys.argv[1:]
    if a and a[0]=='add':
        for line in a[1:]: grade(add(line))
    elif a and a[0]=='regrade':
        cur.execute("SELECT id FROM user_trades"); [grade(i) for (i,) in cur.fetchall()]
    rule()
PYFILE
python3 -m py_compile /root/pe-user/grade.py
echo "== worked example (one of Peter's own ideas-in-form: lay the draw at 0-0, 60', 3.4)"
python3 /root/pe-user/grade.py add "Walsall v Salford City | MO | DRAW | lay | 3.4 | 60 | 0-0 | worked example"
