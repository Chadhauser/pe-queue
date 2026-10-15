#!/bin/bash
# 083: THE GOALS LADDER "ROLL" (what STL's Goal Mastery is selling, tested on our tape before they reveal it). After each goal the
# next Over line up (goals+1.5) should reprice DOWN (more likely now) but 061 showed O/U 1.5/3.5 lag 3-5 min. So: back the next
# line at its LTP at +1/+2/+3 min after the goal (stale = better price if the lag is real), and compare with backing at +10 min
# (fully repriced). Settle (a) to FT and (b) exit at +10 min by laying the same line. 2% spread each way + 2% comm. By season,
# goal number, minute band, tier of line. If the stale entry beats the repriced entry in BOTH seasons, the roll is real.
cd /root/pe-scan && cat > ladder_roll.py <<'PYFILE'
import re, sys, math, datetime, collections, psycopg2, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
SPREAD=0.02; COMM=0.02
def norm(s): return re.sub(r'[^a-z]','',(s or '').lower().split(' ')[0])
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor()
cur.execute("SELECT match_date, home_team, away_team, goal_times, ft_home, ft_away FROM fts_advanced_results WHERE match_date>='2024-08-01'")
G={}
for d,h,a,gt,fh,fa in cur.fetchall():
    d=datetime.date.fromisoformat(str(d)[:10]); goals=[]
    for t in (gt or '').split('|'):
        mm=re.match(r"\s*(\d+)(?:\+(\d+))?\((H|A)\)",t)
        if mm: goals.append(int(mm.group(1))+int(mm.group(2) or 0))
    G[(d,norm(h),norm(a))]=(sorted(goals),int(fh)+int(fa))
LINE={1:'OU15',2:'OU25',3:'OU35'}   # after goal number k, next line up = over (k+0.5) -> k=1 -> OU15? no: after 1 goal next line is Over 1.5 (needs 2) -> OU15; after 2 -> OU25; after 3 -> OU35
def back(e,won): return ((e*(1-SPREAD)-1)*(1-COMM)) if won else -1.0
def tp_back(e,x): p=(e*(1-SPREAD))/(x*(1+SPREAD))-1; return p*(1-COMM) if p>0 else p
rows=[]
scur=con.cursor(name='tape'); scur.itersize=50000
scur.execute("SELECT event_id,hw,aw,m,minute,mkt,sel,ltp FROM bf_hist_price WHERE ht_offset IS NOT NULL AND mkt IN ('OU15','OU25','OU35') AND sel='OVER' ORDER BY event_id,m")
n_seen=0; n_j=0
def px_at(d,t,tol=2):
    for k in list(range(t,t+tol+1))+list(range(t-1,t-tol-1,-1)):
        if k in d: return d[k]
    return None
def process(rs):
    global n_seen,n_j
    n_seen+=1; d=rs[0][3].date(); hw,aw=norm(rs[0][1]),norm(rs[0][2])
    key=next((k for k in ((d,hw,aw),(d-datetime.timedelta(days=1),hw,aw),(d+datetime.timedelta(days=1),hw,aw)) if k in G),None)
    if not key: return
    n_j+=1; goals,tot=G[key]; season='2024/25' if d<datetime.date(2025,7,1) else '2025/26'
    px=collections.defaultdict(dict)
    for _,_,_,m,minute,mkt,sel,ltp in rs:
        if ltp and ltp>1.0: px[mkt][int(minute)]=float(ltp)
    for k,g in enumerate(goals,1):
        if k>3 or g>80: break
        line=LINE[k]; d_=px.get(line,{})
        won=tot>(k+0.5)
        p10=px_at(d_,g+10,2)
        if not p10: continue
        for off in (1,2,3):
            e=px_at(d_,g+off,0)
            if not e or e<1.05: continue
            rows.append((season,k,g,off,line,e,p10,back(e,won),back(p10,won),tp_back(e,p10)))
buf=[]; last=None
for r in scur:
    if last is not None and r[0]!=last: process(buf); buf=[]
    buf.append(r); last=r[0]
if buf: process(buf)
D=pd.DataFrame(rows,columns=['season','goal_no','minute','off','line','entry','repriced','ft_stale','ft_repriced','exit10'])
print(f"events {n_seen} joined {n_j} roll entries {len(D)}")
D['edge_vs_repriced']=D.ft_stale-D.ft_repriced
D['mb']=pd.cut(D.minute,[0,30,45,60,80],labels=['1-30','31-45','46-60','61-80'])
pd.set_option('display.width',240); pd.set_option('display.max_rows',300)
def tstat(x): x=x.dropna(); return round(float(x.mean()/(x.std(ddof=1)/math.sqrt(len(x)))),1) if len(x)>2 and x.std(ddof=1)>0 else 0.0
def show(by,title):
    print(f"\n=== {title} ===")
    t=D.groupby(by+['season'],observed=True).agg(n=('ft_stale','size'),stale_to_FT=('ft_stale',lambda x:round(100*x.mean(),1)),repriced_to_FT=('ft_repriced',lambda x:round(100*x.mean(),1)),exit_at_10=('exit10',lambda x:round(100*x.mean(),1)),t_exit10=('exit10',tstat),t_edge=('edge_vs_repriced',tstat))
    print(t.unstack('season').to_string())
show(['line','off'],'1. ROLL into the next Over line at +off min after the goal: P&L per £100 (stale entry vs fully-repriced entry vs exit at +10)')
show(['goal_no','mb'],'2. +1 min entry by goal number x minute band')
print("\n=== 3. How stale is the entry? median (entry / repriced - 1) by line x off — positive = we got a bigger price than the settled one ===")
print(D.groupby(['line','off'],observed=True).apply(lambda g:(g.entry/g.repriced-1).median()).unstack('off').round(3).to_string())
print("\nVERDICT RULE: the roll is real if exit_at_10 (or stale_to_FT minus repriced_to_FT) is >+1 per £100 with t>=2 in BOTH seasons. LTP only: a live version must be confirmed against the ladder recorder before any stake.")
PYFILE
python3 ladder_roll.py
