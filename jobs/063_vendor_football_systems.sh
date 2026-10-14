#!/bin/bash
# 063: THE THREE VENDOR FOOTBALL SYSTEMS worth testing (from the Trend Report PDFs, 13 Oct) on OUR tape, two seasons, 2% spread
# each way + 2% comm, train 2024/25 / test 2025/26. Same join as the state scan (fts_advanced_results goal times + bf_hist_price).
#  A. LAY THE DRAW 5.6-7.6: draw LTP at KO (minute 0-2) in band -> lay to 1pt liability; exits: (1) hold to FT; (2) if favourite leads
#     at any point cash out at the draw price 3 min after that goal; if underdog scores first lay underdog at its price 3 min after
#     (liability = the green). Leagues: all, then vendor's 7.
#  B. EARLY GOAL GLITCH: home KO price >=1.80, away scores first, 2nd goal before HT; at 1-1 back U3.5 (only if O3.5 after goal <=1.80);
#     at 0-2 back O3.5. Price = OU35 LTP 2 min after the 2nd goal. Hold to FT.
#  C. GOLDEN GOALS price/score tiers at 80 min (no stats needed): band1 home<=1.8 at KO & away leads by 1; band2 away<=1.8 & 1-1;
#     band3 both>1.8 & away leads by 1-2 -> back next-goal line (OU at current goals+0.5) at the 80-min LTP, hold to FT.
#     PLUS the stats version on the subset with in-play SOT (goal_backfill_predictions): 10+ total SOT at 78-80 min, any score.
cd /root/pe-scan && cat > vendor_football.py <<'PYFILE'
import re, sys, math, datetime, collections, psycopg2, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
SPREAD=0.02; COMM=0.02
def norm(s): return re.sub(r'[^a-z]','',(s or '').lower().split(' ')[0])
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor()
cur.execute("SELECT match_date, competition, home_team, away_team, goal_times, mo_home_back, mo_draw_back, mo_away_back, ft_home, ft_away FROM fts_advanced_results WHERE match_date>='2024-08-01'")
G={}
for d,lg,h,a,gt,ph,pdw,pa,fh,fa in cur.fetchall():
    d=datetime.date.fromisoformat(str(d)[:10]); goals=[]
    for t in (gt or '').split('|'):
        mm=re.match(r"\s*(\d+)(?:\+(\d+))?\((H|A)\)",t)
        if mm: goals.append((int(mm.group(1))+int(mm.group(2) or 0),mm.group(3),int(mm.group(1))))
    G[(d,norm(h),norm(a))]=(sorted(goals),int(fh),int(fa),lg)
print("goal records",len(G),flush=True)
# SOT subset for Golden Goals stats version
cur.execute("""SELECT h.kickoff::date, h.home_team, h.away_team, g.minute, coalesce(g.home_sot,0)+coalesce(g.away_sot,0) FROM goal_backfill_predictions g JOIN hist_fixtures h ON h.fixture_id=g.fixture_id WHERE g.minute BETWEEN 74 AND 82""")
SOT={}
for d,h,a,mn,s in cur.fetchall():
    k=(datetime.date.fromisoformat(str(d)[:10]),norm(h),norm(a)); SOT[k]=max(SOT.get(k,0),int(s or 0))
print("fixtures with SOT near 80 min",len(SOT),flush=True)
def back(e,won): return ((e*(1-SPREAD)-1)*(1-COMM)) if won else -1.0
def lay_liab(e,won):  # lay to 1pt liability at e
    return -1.0 if won else (1/(e*(1+SPREAD)-1))*(1-COMM)
def tp(side,e,x):
    p=(e*(1-SPREAD))/(x*(1+SPREAD))-1 if side=='back' else 1-(e*(1+SPREAD))/(x*(1-SPREAD)); return p*(1-COMM) if p>0 else p
def px_at(px,mkt,sel,t,tol=2):
    d=px.get((mkt,sel),{})
    for k in range(t,t+tol+1):
        if k in d: return d[k]
    for k in range(t-1,t-tol-1,-1):
        if k in d: return d[k]
    return None
A=[];B=[];C=[];CS=[]
scur=con.cursor(name='tape'); scur.itersize=50000
scur.execute("SELECT event_id,hw,aw,m,minute,mkt,sel,ltp FROM bf_hist_price WHERE ht_offset IS NOT NULL AND mkt IN ('MO','OU25','OU35','OU15') ORDER BY event_id,m")
n_seen=0; n_j=0
V7={'Belgian Jupiler League','German Bundesliga','English Premier League','Italian Serie A','Portuguese Primeira Liga','Spanish Primera Division','Turkish Super Lig','Belgian Pro League','Spanish La Liga','Turkish Super League'}
def process(rows):
    global n_seen,n_j
    n_seen+=1
    hw,aw=norm(rows[0][1]),norm(rows[0][2]); d=rows[0][3].date()
    key=next((k for k in ((d,hw,aw),(d-datetime.timedelta(days=1),hw,aw),(d+datetime.timedelta(days=1),hw,aw)) if k in G),None)
    if n_seen==300: print(f"SELF-CHECK after 300 events: {n_j} joined",flush=True)
    if not key: return
    n_j+=1; goals,fh,fa,lg=G[key]; season='2024/25' if d<datetime.date(2025,7,1) else '2025/26'
    px=collections.defaultdict(dict)
    for _,_,_,m,minute,mkt,sel,ltp in rows:
        if ltp and ltp>1.0: px[(mkt,sel)][int(minute)]=float(ltp)
    ko_h=px_at(px,'MO','HOME',0,3); ko_d=px_at(px,'MO','DRAW',0,3); ko_a=px_at(px,'MO','AWAY',0,3)
    if not (ko_h and ko_d and ko_a): return
    fav='H' if ko_h<ko_a else 'A'; dog='A' if fav=='H' else 'H'
    # ---- A. LTD 5.6-7.6
    if 5.6<=ko_d<=7.6:
        hold=lay_liab(ko_d, fh==fa)
        # traded: walk goals
        pnl=None; sh=sa=0
        for g,s,_ in goals:
            if s=='H': sh+=1
            else: sa+=1
            lead=('H' if sh>sa else 'A' if sa>sh else None)
            if lead==fav:
                x=px_at(px,'MO','DRAW',g+3,3)
                if x: pnl=tp('lay',ko_d,x)   # cash out: back the draw at x (we laid at ko_d)
                else: pnl=hold
                break
            if lead==dog and sh+sa==1:
                # lay underdog for the available green: green per £1 liab on draw lay = stake*(1-comm) if no draw; approx: lay dog with liability = that green
                xd=px_at(px,'MO','DRAW',g+3,3); xu=px_at(px,'MO',('HOME' if dog=='H' else 'AWAY'),g+3,3)
                if xd and xu:
                    green=(1/(ko_d*(1+SPREAD)-1))*(1-COMM)
                    dog_won=(fh>fa) if dog=='H' else (fa>fh)
                    # draw lay settles: draw -> -1 ; else +green. dog lay with liability=green: dog wins -> -green ; else +green/(xu-1)
                    pnl=(-1.0 if fh==fa else green)+(-green if dog_won else (green/(xu*(1+SPREAD)-1))*(1-COMM))
                    break
        if pnl is None: pnl=hold
        A.append((season,lg,ko_d,'hold',hold)); A.append((season,lg,ko_d,'traded',pnl))
    # ---- B. Early goal glitch
    if ko_h>=1.80 and len(goals)>=2 and goals[0][1]=='A' and goals[1][2]<=45:
        g2=goals[1][0]; st='1-1' if goals[1][1]=='H' else '0-2'
        o35=px_at(px,'OU35','OVER',g2+2,3); u35=px_at(px,'OU35','UNDER',g2+2,3)
        tot=fh+fa
        if st=='1-1' and u35 and o35 and o35<=1.80: B.append((season,lg,st,'back U3.5',u35,back(u35,tot<3.5)))
        if st=='0-2' and o35: B.append((season,lg,st,'back O3.5',o35,back(o35,tot>3.5)))
    # ---- C. Golden goals at 80
    sh=sum(1 for g,s,_ in goals if g<=80 and s=='H'); sa=sum(1 for g,s,_ in goals if g<=80 and s=='A'); gl=sh+sa
    if not any(0<=80-g<3 for g,_,_ in goals) and gl<=5:
        line={0:'OU15',1:'OU15',2:'OU25',3:'OU35'}.get(gl)  # next-goal line: goals so far -> over (gl+0.5); OU15 covers 0/1 approx
        if gl==1: line='OU15'
        if gl==0: line='OU15'
        if line:
            o=px_at(px,line,'OVER',80,2); thr={'OU15':1.5,'OU25':2.5,'OU35':3.5}[line]
            won=(fh+fa)>thr
            if o and gl==(int(thr)):   # only exact next-goal lines
                tier=None
                if ko_h<=1.8 and sa-sh==1: tier='band1 homefav, away+1'
                elif ko_a<=1.8 and sh==sa and gl>0: tier='band2 awayfav, level'
                elif ko_h>1.8 and ko_a>1.8 and 1<=sa-sh<=2: tier='band3 even, away leads'
                if tier: C.append((season,lg,tier,o,back(o,won)))
                s=SOT.get(key)
                if s is not None: CS.append((season,'sot10+' if s>=10 else 'sot<10',o,back(o,won)))
buf=[]; last=None
for r in scur:
    if last is not None and r[0]!=last: process(buf); buf=[]
    buf.append(r); last=r[0]
if buf: process(buf)
print(f"events {n_seen} joined {n_j}",flush=True)
pd.set_option('display.width',240); pd.set_option('display.max_rows',300)
def tstat(x): x=x.dropna(); return round(float(x.mean()/(x.std(ddof=1)/math.sqrt(len(x)))),1) if len(x)>2 and x.std(ddof=1)>0 else 0.0
def show(df,by,col,title):
    print(f"\n=== {title} ===")
    t=df.groupby(by,observed=True)[col].agg(n='size',per100=lambda x:round(100*x.mean(),1),t=tstat); print(t.unstack('season').to_string() if 'season' in by else t.to_string())
A=pd.DataFrame(A,columns=['season','lg','draw_ko','mode','pnl']); print("\nA. LTD 5.6-7.6 qualifying games:",len(A)//2)
show(A,['mode','season'],'pnl','A1. LTD 5.6-7.6, all leagues, hold vs traded (per £100 liability)')
show(A[A.lg.isin(V7)],['mode','season'],'pnl','A2. vendor 7 leagues only')
show(A,['lg','mode','season'],'pnl','A3. by league (traded)')
B=pd.DataFrame(B,columns=['season','lg','ht_state','bet','price','pnl']); print("\nB. Early goal glitch qualifiers:",len(B))
show(B,['bet','season'],'pnl','B1. Early goal glitch per £100 stake'); show(B,['lg','bet','season'],'pnl','B2. by league')
C=pd.DataFrame(C,columns=['season','lg','tier','price','pnl']); print("\nC. Golden goals tier qualifiers:",len(C))
show(C,['tier','season'],'pnl','C1. Golden goals price/score tiers at 80 min, back next-goal line to FT')
CS=pd.DataFrame(CS,columns=['season','sot','price','pnl']); show(CS,['sot','season'],'pnl','C2. Golden goals STATS version (10+ SOT at ~80 min) on the SOT subset')
print("\nVERDICT RULE: survivor = per100 > +1 and t>=2 in BOTH seasons. Vendor claims: A 3.95% hold / 88% traded ROC; B 9% ROI; C 12% tiers / 30%+ stats.")
PYFILE
python3 vendor_football.py
