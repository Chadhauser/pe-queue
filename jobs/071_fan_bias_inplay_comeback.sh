#!/bin/bash
# 071: FAN BIAS, STEP 2 (Peter's own next step): the emotional money arrives IN-PLAY when the big club goes behind — fans back the
# comeback. Test on the tape: every match where a big club (24 names) concedes to go behind; LAY the big club at its Match Odds LTP
# 3 min after the goal; (a) hold to FT per £1 liability; (b) exit at +15 min; (c) exit at +30 min. Split: big club home/away,
# minute band of the goal, big-club price after the goal. CONTROL: every non-big-club FAVOURITE (KO price <=1.60) that goes behind,
# same rules — if the big clubs' comeback is overbet relative to equally short favourites, the lay beats the control.
cd /root/pe-scan && cat > fan_inplay.py <<'PYFILE'
import re, sys, math, datetime, collections, psycopg2, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
SPREAD=0.02; COMM=0.02
BIG=['man city','manchester city','man utd','man united','manchester united','liverpool','arsenal','chelsea','tottenham','spurs','celtic','rangers','real madrid','barcelona','atletico madrid','ath madrid','bayern','dortmund','juventus','inter','ac milan','milan','psg','paris','benfica','porto','sporting','ajax','psv','galatasaray','fenerbahce']
def isbig(n): n=(n or '').lower(); return any(b==n or n.startswith(b+' ') or n.endswith(' '+b) or b in n.split() or n.startswith(b) for b in BIG)
def norm(s): return re.sub(r'[^a-z]','',(s or '').lower().split(' ')[0])
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor()
cur.execute("SELECT match_date, competition, home_team, away_team, goal_times, ft_home, ft_away FROM fts_advanced_results WHERE match_date>='2024-08-01'")
G={}
for d,lg,h,a,gt,fh,fa in cur.fetchall():
    d=datetime.date.fromisoformat(str(d)[:10]); goals=[]
    for t in (gt or '').split('|'):
        mm=re.match(r"\s*(\d+)(?:\+(\d+))?\((H|A)\)",t)
        if mm: goals.append((int(mm.group(1))+int(mm.group(2) or 0),mm.group(3)))
    G[(d,norm(h),norm(a))]=(sorted(goals),int(fh),int(fa),lg)
def px_at(px,sel,t,tol=2):
    d=px.get(sel,{})
    for k in list(range(t,t+tol+1))+list(range(t-1,t-tol-1,-1)):
        if k in d: return d[k]
    return None
def lay_liab(e,won): return -1.0 if won else (1/(e*(1+SPREAD)-1))*(1-COMM)
def lay_exit(e,x):   # lay at e, back at x, per £1 liability
    p=1-(e*(1+SPREAD))/(x*(1-SPREAD)); p=p*(1-COMM) if p>0 else p; return p/(e*(1+SPREAD)-1)
rows=[]
scur=con.cursor(name='tape'); scur.itersize=50000
scur.execute("SELECT event_id,hw,aw,m,minute,mkt,sel,ltp FROM bf_hist_price WHERE ht_offset IS NOT NULL AND mkt='MO' ORDER BY event_id,m")
n_seen=0; n_j=0
def process(rs):
    global n_seen,n_j
    n_seen+=1; hw,aw=rs[0][1],rs[0][2]; d=rs[0][3].date(); k=(d,norm(hw),norm(aw))
    key=next((kk for kk in (k,(d-datetime.timedelta(days=1),k[1],k[2]),(d+datetime.timedelta(days=1),k[1],k[2])) if kk in G),None)
    if not key: return
    n_j+=1; goals,fh,fa,lg=G[key]; season='2024/25' if d<datetime.date(2025,7,1) else '2025/26'
    px=collections.defaultdict(dict)
    for _,_,_,m,minute,mkt,sel,ltp in rs:
        if ltp and ltp>1.0: px[sel][int(minute)]=float(ltp)
    koh,koa=px_at(px,'HOME',0,3),px_at(px,'AWAY',0,3)
    if not (koh and koa): return
    for side,name,ko in (('H',hw,koh),('A',aw,koa)):
        big=isbig(name); fav_short=(ko<=1.60)
        if not (big or fav_short): continue
        sh=sa=0
        for g,s in goals:
            if s=='H': sh+=1
            else: sa+=1
            behind=(sh<sa) if side=='H' else (sa<sh)
            onegoal=abs(sh-sa)==1
            if behind and onegoal and g<=80:
                sel='HOME' if side=='H' else 'AWAY'
                e=px_at(px,sel,g+3,3)
                if not e or e<1.2 or e>12: break
                won=(fh>fa) if side=='H' else (fa>fh)
                x15=px_at(px,sel,g+18,3); x30=px_at(px,sel,g+33,3)
                rows.append((season,'big club' if big else 'control fav<=1.60',side,ko,g,e,lay_liab(e,won),lay_exit(e,x15) if x15 else np.nan,lay_exit(e,x30) if x30 else np.nan,lg,name))
                break
buf=[]; last=None
for r in scur:
    if last is not None and r[0]!=last: process(buf); buf=[]
    buf.append(r); last=r[0]
if buf: process(buf)
D=pd.DataFrame(rows,columns=['season','group','side','ko','goal_min','price_after','hold','exit15','exit30','lg','team'])
print(f"events {n_seen} joined {n_j} behind-events {len(D)} (big {int((D.group=='big club').sum())})")
pd.set_option('display.width',240); pd.set_option('display.max_rows',200)
def tstat(x): x=x.dropna(); return round(float(x.mean()/(x.std(ddof=1)/math.sqrt(len(x)))),1) if len(x)>2 and x.std(ddof=1)>0 else 0.0
def show(by,title):
    print(f"\n=== {title} (per £100 liability) ===")
    for col in ('hold','exit15','exit30'):
        t=D.groupby(by+['season'],observed=True)[col].agg(n='size',per100=lambda x:round(100*x.mean(),1),t=tstat); print(f"-- {col}"); print(t.unstack('season').to_string())
show(['group'],'1. LAY the side that just went behind: big clubs vs equally short favourites')
show(['group','side'],'2. by home/away')
D['mb']=pd.cut(D.goal_min,[0,30,45,60,80],labels=['1-30','31-45','46-60','61-80']); show(['group','mb'],'3. by minute of the goal')
D['pb']=pd.cut(D.price_after,[1,1.6,2,3,5,12],labels=['<1.6','1.6-2','2-3','3-5','5+']); show(['group','pb'],'4. by big-club price after going behind')
B=D[D.group=='big club']; print("\n=== 5. by team (hold, both seasons pooled, n>=15) ==="); t=B.groupby('team').hold.agg(n='size',per100=lambda x:round(100*x.mean(),1),t=tstat); print(t[t.n>=15].sort_values('per100',ascending=False).to_string())
print("\nVERDICT RULE: fan-bias in-play exists if big-club lay beats the control group in BOTH seasons with t>=2; per-team cells need both seasons separately before anyone trades them.")
PYFILE
python3 fan_inplay.py
