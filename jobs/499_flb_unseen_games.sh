#!/bin/bash
set -o pipefail
# 499_flb_unseen_games (Finder 2026-11-04, queue item 68): two lines picked after seeing jobs/499_third_season_goal_flb.sh, on games that job could not see. Lines fixed in advance, no new cuts: MO favourite at <=1.5 at T15 BACK (there n 883 +0.413 t 2.37 h1 +0.377 h2 +0.444); MO draw at 5-10 at T15 LAY (there n 773 +0.338 t 2.39 h1 +0.425 h2 +0.265).
# GAMES: MATCH_ODDS markets with NO exact team-name score match, which that job left out. Scores by loose match: both team names share a word, summed Jaccard >= 1.0, lead over the next candidate >= 0.3, feed's last row 0-240 min after the scheduled off. A market where any runner's name differs from the event name is dropped whichever way the game went.
# GATE, checked before reading any P&L: where a final in-play print <= 1.05 exists it must agree with the matched score on >= 95% (a wrong match would break this; that rule is only used here as a check on the match, never to settle), and won must sit near implied over all runners.
# COST: first print in the 15 min before the off, one tick adverse, 3 ticks reported, 2% commission, held to the score, back stake 10, lay liability 10; one entry per market. Halves by median date. Prints only, no book, so a pass is an upper bound. Read only.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,re,unicodedata,time,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',240); pd.set_option('display.max_rows',100); pd.set_option('display.max_columns',30)
T0=time.time()
LD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    v=lo
    while v<hi-1e-9: LD.append(round(v,2)); v+=st
LD.append(1000.0); LD=np.array(LD)
def ix(p): return int(np.searchsorted(LD,round(float(p),2)-1e-9))
def step(p,k): return float(LD[min(max(ix(p)+k,0),len(LD)-1)])
def back_res(p,won,k):
    a=step(p,-k)
    if a<=1.01: return np.nan
    return 10*(a-1)*0.98 if won else -10.0
def lay_res(p,won,k):
    a=step(p,k)
    return -10.0 if won else 10/(a-1)*0.98
def norm(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
    s=re.sub(r"\b(fc|cf|afc|sc|ac|as|ss|us|sv|vfb|vfl|tsg|fk|club|de|the|cd|ud|sd|rcd|calcio|ii|b|if|bk|ff|aif|sk|fsv)\b"," ",s)
    return frozenset(w for w in re.sub(r"[^a-z0-9 ]"," ",s).split() if len(w)>2)
def jac(X,Y): return len(X&Y)/max(1,len(X|Y))
def loose(H,A,cands):
    # cands: list of (H,A,payload). Both sides must share a word
    sc=[]
    for c in cands:
        a,b=jac(H,c[0]),jac(A,c[1])
        if a>0 and b>0: sc.append((a+b,c[2]))
    sc.sort(key=lambda z:-z[0])
    if not sc or sc[0][0]<1.0 or (len(sc)>1 and sc[0][0]-sc[1][0]<0.3): return None
    return sc[0][1]
def t15(mins,px,ip):
    for m,p,i in zip(mins,px,ip):
        if i: return None
        if 0<=m<15: return p
    return None
def tstat(x):
    x=np.asarray(x,dtype=float); x=x[~np.isnan(x)]; s=x.std(ddof=1) if len(x)>1 else 0
    return x.mean()/(s/len(x)**0.5) if s>0 else 0.0
# known answers
assert abs(back_res(1.4,True,1)-10*0.39*0.98)<1e-9 and back_res(1.4,False,1)==-10.0     # back 1.39: 3.90, less 2% = 3.822
assert abs(lay_res(6.0,False,1)-10/5.2*0.98)<1e-9 and lay_res(6.0,True,1)==-10.0         # lay 6.2: 10/5.2 = 1.923, less 2% = 1.885
_n=lambda s:norm(s)
assert loose(_n('Man Utd'),_n('Roma'),[(_n('Man Utd'),_n('AS Roma'),'x')])=='x'
assert loose(_n('Leeds'),_n('Hull'),[(_n('Leeds'),_n('Stoke'),'x')]) is None             # one side only
assert loose(_n('Real Oviedo'),_n('Real Madrid'),[(_n('Real Oviedo'),_n('Real Madrid'),'a'),(_n('Real Oviedo'),_n('Real Madrid'),'b')]) is None   # no clear winner
assert t15([20,10,3],[2,2.1,2.2],[0,0,0])==2.1 and t15([20],[2],[0]) is None
print("checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'"); cur.execute("SET statement_timeout='2400s'")
GT=pd.read_sql("""SELECT DISTINCT ON (fixture_id) fixture_id,home_team,away_team,captured_at,minute,score_home,score_away,status FROM goal_timeline WHERE captured_at>='2026-06-30' AND captured_at<'2026-10-02' AND score_home IS NOT NULL ORDER BY fixture_id,captured_at DESC""",con)
GT['t']=pd.to_datetime(GT.captured_at,utc=True); GT['mn']=pd.to_numeric(GT.minute,errors='coerce')
GT=GT[GT.status.isin(['FT','AET','PEN','Match Finished','FINISHED'])|(GT.mn>=88)].sort_values('t').reset_index(drop=True)
GT['H']=GT.home_team.map(norm); GT['A']=GT.away_team.map(norm); tt=GT.t.values.astype('datetime64[ns]'); SC={}
for r in GT.itertuples(): SC.setdefault((r.H,r.A),[]).append((r.t,int(r.score_home),int(r.score_away)))
print(f"finished fixtures {len(GT)}, {time.time()-T0:.0f}s",flush=True)
cur.execute("""WITH RECURSIVE t AS ((SELECT market_id FROM bf_hist_other WHERE sport='Soccer' AND market_id>='MATCH_ODDS' AND market_id<'MATCH_ODDT' ORDER BY market_id LIMIT 1)
 UNION ALL SELECT (SELECT market_id FROM bf_hist_other WHERE sport='Soccer' AND market_id>t.market_id AND market_id<'MATCH_ODDT' ORDER BY market_id LIMIT 1) FROM t WHERE t.market_id IS NOT NULL) SELECT market_id FROM t WHERE market_id IS NOT NULL""")
ids=[r[0] for r in cur.fetchall() if '|' in r[0]]; keep={}; exact=0; nomatch=0
for i in ids:
    _,ev,mt=i.split('|',2); mt=pd.Timestamp(mt); h,_,a=ev.partition(' v '); H,A=norm(h),norm(a)
    if [x for x in SC.get((H,A),[]) if 0<=(x[0]-mt).total_seconds()/60<=240]: exact+=1; continue   # seen by the job that chose the lines
    lo=np.searchsorted(tt,np.datetime64(mt.tz_convert(None))); hi=np.searchsorted(tt,np.datetime64((mt+pd.Timedelta(minutes=240)).tz_convert(None)),side='right')
    g=GT.iloc[lo:hi]; m=loose(H,A,[(r.H,r.A,(int(r.score_home),int(r.score_away))) for r in g.itertuples()])
    if m is None: nomatch+=1
    else: keep[i]=m
print(f"markets {len(ids)}: exact, already seen {exact}; unseen with a loose score {len(keep)}; unseen with no score {nomatch}; {time.time()-T0:.0f}s",flush=True)
L=list(keep); rows=[]; agree=[]; dropped=0
for c in range(0,len(L),400):
    P=pd.read_sql("SELECT market_id,event_name,market_time,sel,ts,ltp::float ltp,inplay FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s) AND ltp>=1.01 AND ltp<1000",con,params=(L[c:c+400],))
    if not len(P): continue
    P['mt']=pd.to_datetime(P.market_time,utc=True); P['t']=pd.to_datetime(P.ts,utc=True); P['mins']=(P.mt-P.t).dt.total_seconds()/60; P=P.sort_values(['market_id','sel','t'])
    for mid,G in P.groupby('market_id',sort=False):
        ev=G.event_name.iloc[0]; h,_,a=ev.partition(' v '); h,a=h.strip(),a.strip(); sels=set(G.sel)
        if not sels<={h,a,'The Draw'} or len(sels)<3: dropped+=1; continue
        hs,as_=keep[mid]; tw='The Draw' if hs==as_ else (h if hs>as_ else a); f={}; d=G.mt.iloc[0]; last={}
        for sel,g in G.groupby('sel',sort=False):
            ip=g.inplay.values.astype(bool); f[sel]=t15(g.mins.values,g.ltp.values,ip)
            if ip.any(): last[sel]=g.ltp.values[ip][-1]
        w=[s for s,v in last.items() if v<=1.05]
        if len(w)==1: agree.append(w[0]==tw)
        pr={s:v for s,v in f.items() if v is not None}
        for s,v in pr.items(): rows.append(dict(mid=mid,d=d,sel=s,p=v,won=s==tw,draw=s=='The Draw',fav=(v==min(pr.values()) and sum(1 for x in pr.values() if x==v)==1)))
    print(f"  {min(c+400,len(L))}/{len(L)} {time.time()-T0:.0f}s",flush=True)
con.close(); R=pd.DataFrame(rows); R['imp']=1/R.p
print(f"markets scored {R.mid.nunique()}, dropped for a runner name {dropped}, runners {len(R)}, dates {R.d.min():%Y-%m-%d} to {R.d.max():%Y-%m-%d}")
print("\n== GATE"); ga=np.mean(agree) if agree else float('nan'); print(f"final print <= 1.05 agrees with the loose score on {ga:.3f} of {len(agree)} (bar 0.95); won {R.won.mean():.3f} v implied {R.imp.mean():.3f}")
R['band']=pd.cut(R.p,[1,1.5,2,3,5,10,20,1000],labels=['<=1.5','1.5-2','2-3','3-5','5-10','10-20','20+']).astype(str); print(R.groupby('band').agg(n=('p','size'),implied=('imp','mean'),won=('won','mean')).round(3).to_string())
if not ga>=0.95: print("GATE FAILED: results not used"); print("\n== SURVIVORS\nnone"); sys.exit(0)
med=R.d.median(); R['h']=np.where(R.d<=med,1,2); print(f"median date {med:%Y-%m-%d}")
for k in (1,3): R[f'b{k}']=[back_res(p,w,k) for p,w in zip(R.p,R.won)]; R[f'l{k}']=[lay_res(p,w,k) for p,w in zip(R.p,R.won)]
out=[]
def line(nm,x,c,c3):
    x=x[x[c].notna()]; a=x[x.h==1][c]; b=x[x.h==2][c]
    out.append(dict(line=nm,n=len(x),per10=x[c].mean(),t=tstat(x[c]),h1=a.mean(),n1=len(a),h2=b.mean(),n2=len(b),x3=x[c3].mean(),maxwin=x[c].max(),won=x.won.mean(),implied=x.imp.mean()))
line("PRESET fav <=1.5 BACK",R[R.fav&(R.band=='<=1.5')],'b1','b3'); line("PRESET draw 5-10 LAY",R[R.draw&(R.band=='5-10')],'l1','l3')
line("reference: fav all BACK",R[R.fav],'b1','b3'); line("reference: draw all LAY",R[R.draw],'l1','l3')
O=pd.DataFrame(out); O['PASS']=(O.n>=300)&(O.n1>=150)&(O.n2>=150)&(O.t>=3.5)&(O.h1>0)&(O.h2>0)&(O.per10>=0.15)
print("\n== LINES"); print(O.round(3).to_string(index=False))
print("\n== SURVIVORS"); s=O[O.PASS&O.line.str.startswith('PRESET')]; print(s.round(3).to_string(index=False) if len(s) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
