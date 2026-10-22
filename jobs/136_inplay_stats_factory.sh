#!/bin/bash
# 136: IN-PLAY STATS FACTORY (Peter 22 Oct: "any other clever ways... I shouldn't have to look at them all myself"). Nightly 03:40.
# For every match with stats (ip_stats, from 135) matched to a Betfair MO market, build the minute timeline: score, xG, shots, SoT,
# possession, dangerous attacks, corners + the MO / OU15 / OU25 prices at each stats timestamp (liq_sample). Then book each rule as a
# paper trade (£10, 2pct comm, hedged exits at the touch, stop with every entry) and write cells to strategy_results sport='InPlay'.
# Rules (one entry per match per rule):
#  R1 dominant side unmoved: one side xG lead >=0.8 by 30-60', its MO back price not shortened >5pct since the first stats row -> BACK it, exit on goal (+60s lay) or 75'
#  R2 scoreboard-xG lag: leading 1-0 but xG behind by >=0.8 (30-75') -> LAY leader, green on equaliser (+60s back), stop 80' / 2-0
#  R3 dead game: 0-0 at 58-62', combined xG <1.0 and total shots <6 -> BACK Under 2.5, settle (stop = first goal: lay U2.5 at +60s)
#  R4 shot burst: +3 SoT for one side within 10 min (20-80') -> BACK Over (next line: O1.5 if 0 goals, O2.5 if 1, O3.5 if 2), exit goal(+60s) or +15 min
#  R5 HT 0-0 pressure: 0-0 at 45' both xG >=0.6 -> BACK Over 1.5 at the HT price, settle at FT (stop none: liability = stake)
#  R6 lucky scorer fade: goal by the side BEHIND on xG by >=0.5 (10-75', <=2nd goal) -> LAY scorer at +60s, exit +10 min or next goal
#  R7 possession trap: 65%+ possession but lower xG than opponent at 30-60', score level -> LAY possession side, exit 75' or goal
#  R8 late surge: trailing side dangerous attacks +15 and corners +2 in last 10 min after 75' -> BACK Over next line, exit goal or 88'
#  R9 trailing favourite: pre-match fav (first MO price <=2.0) trailing at 60-70' with xG lead >=0.5 -> BACK it, exit goal(+60s) or 85'
mkdir -p /root/pe-factory && cat > /root/pe-factory/inplay_factory.py <<'PYFILE'
import sys, math, datetime, psycopg2, psycopg2.extras, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
COMM=0.02; STAKE=10.0; today=datetime.date.today()
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("""CREATE TABLE IF NOT EXISTS inplay_paper (id SERIAL PRIMARY KEY, play_date DATE, market_id TEXT, event_name TEXT, league TEXT, rule TEXT, side TEXT, mkt TEXT, sel TEXT,
  entry_min INT, entry_px NUMERIC, exit_min INT, exit_px NUMERIC, exit_reason TEXT, pnl NUMERIC, note TEXT, UNIQUE (market_id, rule))""")
pd.set_option('display.width',250)
def prof(p): return p*(1-COMM) if p>0 else p
def back_hedge(e,x): return prof((e/x-1)*STAKE)
def lay_hedge(e,x): return prof((1-e/x)*STAKE)
def back_settle(e,won): return prof((e-1)*STAKE) if won else -STAKE
def tstat(x): x=pd.Series(x,dtype=float).dropna(); return float(x.mean()/(x.std(ddof=1)/math.sqrt(len(x)))) if len(x)>2 and x.std(ddof=1)>0 else 0.0
cur.execute("SELECT DISTINCT market_id, event_name, league FROM ip_stats WHERE market_id IS NOT NULL AND ts>now()-interval '2 days'")
games=cur.fetchall(); print("matched games last 2 days:",len(games),flush=True)
def px_at(P,mkt,sel_like,ts,col,after=False):
    d=P[(P.mkt==mkt)&P.sel.str.contains(sel_like,case=False,regex=True)&P[col].notna()]
    d=d[d.ts>=ts] if after else d[d.ts<=ts]
    if d.empty: return None
    return float(d[col].iloc[0] if after else d[col].iloc[-1])
rows=[]
for mid,ev,lg in games:
    S=pd.read_sql('SELECT ts, minute, hs, "as" AS a_s, h_xg::float h_xg, a_xg::float a_xg, h_shots, a_shots, h_sot, a_sot, h_poss::float h_poss, h_dang, a_dang, h_corn, a_corn FROM ip_stats WHERE market_id=%s ORDER BY ts',con,params=(mid,))
    P=pd.read_sql("SELECT ts, mkt, sel, minute, back_px::float back_px, lay_px::float lay_px FROM liq_sample WHERE market_id=%s AND mkt IN ('MO','OU15','OU25','OU35') ORDER BY ts",con,params=(mid,))
    if len(S)<8 or P.empty: continue
    S=S[S.h_xg.notna()].reset_index(drop=True)
    if S.empty: continue
    home,away=[x.strip() for x in ev.split(' v ',1)]
    H=f"^{home}$|HOME"; A=f"^{away}$|AWAY"
    goals=[]; prev=(0,0)
    for _,r in S.iterrows():
        if (r.hs,r.a_s)!=prev: goals.append((r.ts,int(r.minute),int(r.hs),int(r.a_s),'H' if r.hs>prev[0] else 'A')); prev=(r.hs,r.a_s)
    final=(int(S.hs.iloc[-1]),int(S.a_s.iloc[-1])); tg=final[0]+final[1]
    first_mo_h=px_at(P,'MO',H,S.ts.iloc[0],'back_px'); first_mo_a=px_at(P,'MO',A,S.ts.iloc[0],'back_px')
    def next_goal_after(ts):
        g=[x for x in goals if x[0]>ts]; return g[0] if g else None
    def book(rule,side,mkt,sel_like,sel_name,ts,emin,action,exit_rule,stop_min,note=''):
        col='back_px' if action=='BACK' else 'lay_px'; e=px_at(P,mkt,sel_like,ts,col)
        if not e or e<1.01: return
        ng=next_goal_after(ts); xr='CLOCK'; xmin=stop_min; xts=None
        if ng and ng[1]<stop_min and exit_rule in ('goal','goal_or_clock'): xmin=ng[1]; xr='GOAL'; xts=ng[0]+pd.Timedelta(seconds=60)
        if exit_rule=='settle':
            won=(final[0]+final[1]>float(sel_name.split()[1])) if sel_name.startswith('Over') else (final[0]+final[1]<float(sel_name.split()[1]))
            pnl=back_settle(e,won); rows.append((today,mid,ev,lg,rule,side,mkt,sel_name,emin,e,None,None,'SETTLE',round(pnl,2),note)); return
        if xts is None:
            st=S[S.minute>=stop_min]; xts=st.ts.iloc[0] if not st.empty else S.ts.iloc[-1]
        xcol='lay_px' if action=='BACK' else 'back_px'; x=px_at(P,mkt,sel_like,xts,xcol,after=True) or px_at(P,mkt,sel_like,xts,xcol)
        if not x: return
        pnl=back_hedge(e,x) if action=='BACK' else lay_hedge(e,x)
        rows.append((today,mid,ev,lg,rule,side,mkt,sel_name,emin,e,xmin,x,xr,round(pnl,2),note))
    done=set()
    for i,r in S.iterrows():
        m=int(r.minute); lvl=(r.hs==r.a_s); xd=r.h_xg-r.a_xg
        # R1
        if 'R1' not in done and 30<=m<=60 and lvl and abs(xd)>=0.8:
            side='H' if xd>0 else 'A'; sel=H if side=='H' else A; first=first_mo_h if side=='H' else first_mo_a; now_px=px_at(P,'MO',sel,r.ts,'back_px')
            if first and now_px and now_px>=first*0.95: book('R1 dominant side unmoved: back',side,'MO',sel,home if side=='H' else away,r.ts,m,'BACK','goal_or_clock',75,f"xd {xd:+.2f}"); done.add('R1')
        # R2
        if 'R2' not in done and 30<=m<=75 and abs(r.hs-r.a_s)==1 and r.hs+r.a_s==1:
            lead='H' if r.hs>r.a_s else 'A'; lag=(xd if lead=='A' else -xd)
            if lag>=0.8: book('R2 scoreboard-xG lag: lay leader',lead,'MO',H if lead=='H' else A,home if lead=='H' else away,r.ts,m,'LAY','goal_or_clock',80,f"lead behind xG by {lag:.2f}"); done.add('R2')
        # R3
        if 'R3' not in done and 58<=m<=62 and r.hs+r.a_s==0 and (r.h_xg+r.a_xg)<1.0 and (r.h_shots+r.a_shots)<6:
            book('R3 dead game: back under 2.5','U','OU25','Under','Under 2.5',r.ts,m,'BACK','settle',90); done.add('R3')
        # R4
        if 'R4' not in done and 20<=m<=80 and i>=3:
            past=S[(S.ts<=r.ts-pd.Timedelta(minutes=10))]
            if not past.empty:
                p=past.iloc[-1]
                if (r.h_sot-p.h_sot)>=3 or (r.a_sot-p.a_sot)>=3:
                    line={0:('OU15','Over 1.5'),1:('OU25','Over 2.5'),2:('OU35','Over 3.5')}.get(int(r.hs+r.a_s))
                    if line: book('R4 shot burst: back over next line','H' if (r.h_sot-p.h_sot)>=3 else 'A',line[0],'Over',line[1],r.ts,m,'BACK','goal_or_clock',min(90,m+15)); done.add('R4')
        # R5
        if 'R5' not in done and 44<=m<=47 and r.hs+r.a_s==0 and r.h_xg>=0.6 and r.a_xg>=0.6:
            book('R5 HT 0-0 pressure: back over 1.5','O','OU15','Over','Over 1.5',r.ts,m,'BACK','settle',90); done.add('R5')
        # R6
        if 'R6' not in done:
            g=[x for x in goals if x[0]==r.ts]
            if g and 10<=m<=75 and (r.hs+r.a_s)<=2:
                sc=g[0][4]; behind=(xd<=-0.5) if sc=='H' else (xd>=0.5)
                if behind: book('R6 lucky scorer fade: lay scorer',sc,'MO',H if sc=='H' else A,home if sc=='H' else away,r.ts+pd.Timedelta(seconds=60),m,'LAY','goal_or_clock',min(90,m+10),f"scorer xd {xd:+.2f}"); done.add('R6')
        # R7
        if 'R7' not in done and 30<=m<=60 and lvl and r.h_poss is not None:
            if r.h_poss>=65 and xd<0: book('R7 possession trap: lay possession side','H','MO',H,home,r.ts,m,'LAY','goal_or_clock',75); done.add('R7')
            elif r.h_poss<=35 and xd>0: book('R7 possession trap: lay possession side','A','MO',A,away,r.ts,m,'LAY','goal_or_clock',75); done.add('R7')
        # R8
        if 'R8' not in done and m>=75 and r.hs!=r.a_s and i>=3:
            past=S[(S.ts<=r.ts-pd.Timedelta(minutes=10))]
            if not past.empty:
                p=past.iloc[-1]; tr='H' if r.hs<r.a_s else 'A'
                dd=(r.h_dang-p.h_dang) if tr=='H' else (r.a_dang-p.a_dang); dc=(r.h_corn-p.h_corn) if tr=='H' else (r.a_corn-p.a_corn)
                if dd>=15 and dc>=2:
                    line={1:('OU15','Over 1.5'),2:('OU25','Over 2.5'),3:('OU35','Over 3.5')}.get(int(r.hs+r.a_s))
                    if line: book('R8 late surge: back over next line',tr,line[0],'Over',line[1],r.ts,m,'BACK','goal_or_clock',88); done.add('R8')
        # R9
        if 'R9' not in done and 60<=m<=70 and r.hs!=r.a_s:
            tr='H' if r.hs<r.a_s else 'A'; fav=(first_mo_h and first_mo_h<=2.0 and tr=='H') or (first_mo_a and first_mo_a<=2.0 and tr=='A')
            lead=(xd if tr=='H' else -xd)
            if fav and lead>=0.5: book('R9 trailing favourite with xG lead: back',tr,'MO',H if tr=='H' else A,home if tr=='H' else away,r.ts,m,'BACK','goal_or_clock',85); done.add('R9')
if rows:
    psycopg2.extras.execute_values(cur,"INSERT INTO inplay_paper (play_date,market_id,event_name,league,rule,side,mkt,sel,entry_min,entry_px,exit_min,exit_px,exit_reason,pnl,note) VALUES %s ON CONFLICT (market_id,rule) DO NOTHING",rows)
    print("booked",len(rows),"paper trades tonight")
R=pd.read_sql("SELECT rule, play_date, pnl FROM inplay_paper WHERE pnl IS NOT NULL",con)
out=[]
print("\n=== IN-PLAY STATS FACTORY — all paper trades to date (per £10) ===")
for rule,g in R.groupby('rule'):
    n=len(g); tot=g.pnl.sum(); t=tstat(g.pnl)
    med=pd.to_datetime(g.play_date).median(); a=g[pd.to_datetime(g.play_date)<med].pnl; b=g[pd.to_datetime(g.play_date)>=med].pnl
    p1=a.mean()*10 if len(a) else float('nan'); p2=b.mean()*10 if len(b) else float('nan')
    surv=bool(n>=100 and len(a)>=40 and len(b)>=40 and p1>1 and p2>1 and tstat(a)>=2 and tstat(b)>=2)
    print(f"  {rule:48s} n {n:4d} | total {tot:+7.2f} | per £100 {g.pnl.mean()*10:+6.1f} | t {t:4.1f} | h1 {p1:+.1f} h2 {p2:+.1f} {'SURVIVOR' if surv else ''}")
    out.append((today,'InPlay',rule,'all',int(n),int(len(a)),float(round(p1,2)) if len(a) else 0.0,float(round(tstat(a),2)),int(len(b)),float(round(p2,2)) if len(b) else 0.0,float(round(tstat(b),2)),float(round(g.pnl.mean()*10,2)),surv,f"{g.play_date.min()}->{g.play_date.max()}"))
if out:
    cur.execute("DELETE FROM strategy_results WHERE run_date=%s AND sport='InPlay'",(today,)); psycopg2.extras.execute_values(cur,"INSERT INTO strategy_results VALUES %s",out)
PYFILE
python3 -m py_compile /root/pe-factory/inplay_factory.py || exit 1
( crontab -l 2>/dev/null | grep -v inplay_factory ; echo "40 3 * * * cd /root/pe-factory && python3 inplay_factory.py >> inplay_factory.log 2>&1" ) | crontab -
cd /root/pe-factory && python3 inplay_factory.py 2>&1 | grep -v -E "UserWarning|pd.read_sql"
