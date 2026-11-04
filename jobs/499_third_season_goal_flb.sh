#!/bin/bash
set -o pipefail
# 499_third_season_goal_flb (Finder 2026-11-04, queue items 65 and 66): two tests on the Jul-Sep 2026 football tape, sharing one fetch. bf_hist_other Soccer x real scores from goal_timeline by exact team name (a final print is NOT a result: jobs/499_line_move_result_check.sh). Only markets with a score are fetched. Read only.
# ENTRY T15: the first print in the 15 minutes before the scheduled off, not in play, so no signal or later print is used. ENTRY IP (item 66 only, as item 52): the first in-play print from 5 min before to 20 min after the scheduled off. A goal may already have been scored at IP, and this job does not check; T15 is the clean entry and the one to believe.
# COST: one tick adverse, 3 ticks reported; 2% commission; back stake 10, lay liability 10; held to the score. Halves by median date. Pass as the house rule.
# ITEM 65: by market, runner and price band, back and lay, one entry per market per line. ITEM 66: leagues fixed in advance from 2024 by jobs/499_league_goal_error.sh cut 2, no new cuts: lay Under 2.5 in Segunda 141, Serie B 136, La Liga 140, Scottish Premiership 179; back it in Allsvenskan 113, Eredivisie 88, Premier League 39. Item 45's line = Segunda alone.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,re,unicodedata,time,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',240); pd.set_option('display.max_rows',150); pd.set_option('display.max_columns',30)
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
def true_winner(mk,ev,hs,as_):
    h,_,a=ev.partition(' v ')
    if mk=='OU25': return 'Over 2.5 Goals' if hs+as_>=3 else 'Under 2.5 Goals'
    return 'The Draw' if hs==as_ else (h.strip() if hs>as_ else a.strip())
def t15(mins,px,ip):
    # first print in the 15 minutes before the off, not in play; mins falls through time
    for m,p,i in zip(mins,px,ip):
        if i: return None
        if 0<=m<15: return p
    return None
def first_ip(mins,px,ip):
    for m,p,i in zip(mins,px,ip):
        if i: return p if -20<=m<=5 else None
    return None
def tstat(x):
    x=np.asarray(x,dtype=float); x=x[~np.isnan(x)]; s=x.std(ddof=1) if len(x)>1 else 0
    return x.mean()/(s/len(x)**0.5) if s>0 else 0.0
# known answers, worked by hand
assert abs(back_res(3.0,True,1)-19.404)<1e-9 and back_res(3.0,False,1)==-10.0 and np.isnan(back_res(1.02,True,1))
assert abs(lay_res(3.0,False,1)-10/2.05*0.98)<1e-9 and lay_res(3.0,True,1)==-10.0
assert abs(lay_res(2.0,False,1)-10/1.02*0.98)<1e-9                      # lay 2.02: wins 9.804, less 2%
assert t15([200,20,10,3],[2,2.1,2.2,2.3],[0,0,0,0])==2.2 and t15([200,20],[2,2.1],[0,0]) is None and t15([20,10],[2,2.1],[0,1]) is None and t15([-1,10],[2,2.1],[0,0])==2.1
assert first_ip([10,-2,-5],[2,2.1,2.2],[0,1,1])==2.1 and first_ip([10,-40],[2,2.1],[0,1]) is None and first_ip([10,7],[2,2.1],[0,1]) is None and first_ip([10],[2],[0]) is None
assert true_winner('OU25','A v B',2,1)=='Over 2.5 Goals' and true_winner('MO','Leeds v Hull',1,1)=='The Draw' and true_winner('MO','Leeds v Hull',0,1)=='Hull'
print("checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'"); cur.execute("SET statement_timeout='2400s'")
GT=pd.read_sql("""SELECT DISTINCT ON (fixture_id) fixture_id,league_id,league_name,home_team,away_team,captured_at,minute,score_home,score_away,status FROM goal_timeline WHERE captured_at>='2026-06-30' AND captured_at<'2026-10-02' AND score_home IS NOT NULL ORDER BY fixture_id,captured_at DESC""",con)
GT['t']=pd.to_datetime(GT.captured_at,utc=True); GT['mn']=pd.to_numeric(GT.minute,errors='coerce')
GT=GT[GT.status.isin(['FT','AET','PEN','Match Finished','FINISHED'])|(GT.mn>=88)].copy()
SC={}
for r in GT.itertuples(): SC.setdefault((norm(r.home_team),norm(r.away_team)),[]).append((r.t,int(r.score_home),int(r.score_away),int(r.league_id),r.league_name))
print(f"goal_timeline finished fixtures {len(GT)}, {time.time()-T0:.0f}s",flush=True)
FIX={141:('LAY','Segunda'),136:('LAY','Serie B'),140:('LAY','La Liga'),179:('LAY','Scottish Premiership'),113:('BACK','Allsvenskan'),88:('BACK','Eredivisie'),39:('BACK','Premier League')}
print("league id check, names on the feed:")
for k,(sd,nm) in FIX.items(): print(f"  {k} want {nm}: {GT[GT.league_id==k].league_name.value_counts().head(2).to_dict()}")
def score_of(ev,mt):
    h,_,a=ev.partition(' v '); hits=[x for x in SC.get((norm(h),norm(a)),[]) if 0<=(x[0]-mt).total_seconds()/60<=240]
    return hits[0][1:] if len(hits)==1 else None
def scan(lo,hi):
    cur.execute("""WITH RECURSIVE t AS ((SELECT market_id FROM bf_hist_other WHERE sport='Soccer' AND market_id>=%s AND market_id<%s ORDER BY market_id LIMIT 1)
     UNION ALL SELECT (SELECT market_id FROM bf_hist_other WHERE sport='Soccer' AND market_id>t.market_id AND market_id<%s ORDER BY market_id LIMIT 1) FROM t WHERE t.market_id IS NOT NULL) SELECT market_id FROM t WHERE market_id IS NOT NULL""",(lo,hi,hi))
    return [r[0] for r in cur.fetchall() if '|' in r[0]]
out=[]; miss=0
for MK,lo,hi in (('MO','MATCH_ODDS','MATCH_ODDT'),('OU25','OVER_UNDER_25','OVER_UNDER_26')):
    ids=scan(lo,hi); keep=[]
    if len(ids)<1000: sys.exit(f"{MK}: only {len(ids)} markets; stopping")
    for i in ids:
        _,ev,mt=i.split('|',2)
        if score_of(ev,pd.Timestamp(mt))is not None: keep.append(i)
    print(f"{MK}: {len(ids)} markets, {len(keep)} with a score, {time.time()-T0:.0f}s",flush=True)
    for c in range(0,len(keep),400):
        P=pd.read_sql("SELECT market_id,event_name,market_time,sel,ts,ltp::float ltp,inplay FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s) AND ltp>=1.01 AND ltp<1000",con,params=(keep[c:c+400],))
        if not len(P): continue
        P['mt']=pd.to_datetime(P.market_time,utc=True); P['t']=pd.to_datetime(P.ts,utc=True); P['mins']=(P.mt-P.t).dt.total_seconds()/60; P=P.sort_values(['market_id','sel','t'])
        for mid,G in P.groupby('market_id',sort=False):
            ev=G.event_name.iloc[0]; d=G.mt.iloc[0]; sc=score_of(ev,d)
            if sc is None: continue
            tw=true_winner(MK,ev,sc[0],sc[1]); sels=set(G.sel)
            if tw not in sels: miss+=1; continue
            h,_,a=ev.partition(' v ')
            for sel,g in G.groupby('sel',sort=False):
                m,p,ip=g.mins.values,g.ltp.values,g.inplay.values.astype(bool); pt=t15(m,p,ip); pi=first_ip(m,p,ip)
                who=sel if MK=='OU25' else ('DRAW' if sel=='The Draw' else ('HOME' if sel==h.strip() else ('AWAY' if sel==a.strip() else 'OTHER')))
                out.append(dict(mk=MK,mid=mid,who=who,d=d,lg=sc[2],won=sel==tw,pt=pt if pt is not None else np.nan,pi=pi if pi is not None else np.nan))
        if c%4000==0: print(f"  {MK} {min(c+400,len(keep))}/{len(keep)} {time.time()-T0:.0f}s",flush=True)
con.close()
R=pd.DataFrame(out)
# a runner whose name differs from the event name can only reach here when it lost: when it won, the score's winner is not found and the market is skipped above. Drop those markets whole, or they read as a sure loser
bad=set(R[R.who=='OTHER'].mid); print(f"MO markets dropped for a runner name that differs from the event name: {len(bad)}, plus {miss} skipped above where that runner won",flush=True); R=R[~R.mid.isin(bad)].copy()
assert (R.who!='OTHER').all()
print(f"runners {len(R)}, markets {R.mid.nunique()}, runner name missing {miss}, T15 print on {R.pt.notna().mean():.3f}, in-play print on {R.pi.notna().mean():.3f}; who {R.who.value_counts().to_dict()}; {time.time()-T0:.0f}s",flush=True)
med=R.d.median(); R['h']=np.where(R.d<=med,1,2); print(f"dates {R.d.min():%Y-%m-%d} to {R.d.max():%Y-%m-%d}, median {med:%Y-%m-%d}")
for k in (1,3):
    R[f'b{k}']=[back_res(p,w,k) if p==p else np.nan for p,w in zip(R.pt,R.won)]; R[f'l{k}']=[lay_res(p,w,k) if p==p else np.nan for p,w in zip(R.pt,R.won)]
    R[f'bi{k}']=[back_res(p,w,k) if p==p else np.nan for p,w in zip(R.pi,R.won)]; R[f'li{k}']=[lay_res(p,w,k) if p==p else np.nan for p,w in zip(R.pi,R.won)]
def row(name,x,col,col3):
    x=x[x[col].notna()]; v=x[col]; a=x[x.h==1][col]; b=x[x.h==2][col]
    return dict(line=name,n=len(v),games=x.mid.nunique(),per10=v.mean() if len(v) else np.nan,t=tstat(v),h1=a.mean() if len(a) else np.nan,n1=len(a),h2=b.mean() if len(b) else np.nan,n2=len(b),x3=x[col3].mean() if len(x) else np.nan)
def passed(D): return (D.n>=300)&(D.n1>=150)&(D.n2>=150)&(D.t>=3.5)&(D.h1>0)&(D.h2>0)&(D.per10>=0.15)
print("\n== ITEM 65: T15 calibration, overround not removed")
T=R[R.pt.notna()].copy(); T['imp']=1/T.pt; T['band']=pd.cut(T.pt,[1,1.5,2,3,5,10,20,1000],labels=['<=1.5','1.5-2','2-3','3-5','5-10','10-20','20+']).astype(str)
print(T.groupby(['mk','band']).agg(n=('pt','size'),implied=('imp','mean'),won=('won','mean')).round(3).to_string()); print(T.groupby('mk').agg(n=('pt','size'),implied=('imp','mean'),won=('won','mean')).round(3).to_string())
fav=T[T.mk=='MO'].sort_values('pt').drop_duplicates('mid').assign(who='FAV'); lines=[]
for (mk,src) in (('MO',pd.concat([T[T.mk=='MO'],fav])),('OU25',T[T.mk=='OU25'])):
    for who,g in src.groupby('who'):
        for bd in ['all','<=1.5','1.5-2','2-3','3-5','5-10','10-20','20+']:
            x=g if bd=='all' else g[g.band==bd]
            if len(x)<30: continue
            lines.append(row(f"{mk} {who} {bd} BACK",x,'b1','b3')); lines.append(row(f"{mk} {who} {bd} LAY",x,'l1','l3'))
L=pd.DataFrame(lines); L['PASS']=passed(L); print(f"\n{len(L)} lines, {int((L.n>=300).sum())} at n>=300, {int(L.PASS.sum())} pass")
print("\n== ITEM 65: top 15 by t at n>=300"); print(L[L.n>=300].sort_values('t',ascending=False).head(15).round(3).to_string(index=False))
print("\n== ITEM 65: every all-price line"); print(L[L.line.str.contains(' all ')].round(3).to_string(index=False))
print("\n== ITEM 66: league goal error, third season, fixed leagues")
U=R[(R.mk=='OU25')&(R.who=='Under 2.5 Goals')].copy(); U=U.drop_duplicates('mid')
U['sd']=U.lg.map(lambda k:FIX[k][0] if k in FIX else None); U['nm']=U.lg.map(lambda k:FIX[k][1] if k in FIX else None)
O=R[(R.mk=='OU25')&(R.who=='Over 2.5 Goals')].drop_duplicates('mid').set_index('mid').pt; U['ot']=U.mid.map(O); W=U[U.pt.notna()&U.ot.notna()].copy(); W['pu']=(1/W.pt)/(1/W.pt+1/W.ot)
print("Under 2.5, error at T15, overround removed; was the 2024 sign right?"); e=W[W.nm.notna()].groupby(['sd','nm']).agg(n=('pu','size'),priced=('pu','mean'),won=('won','mean')).round(3); e['error_pts']=(100*(e.won-e.priced)).round(1); print(e.to_string())
print(f"all matched games: n {len(W)}, priced {W.pu.mean():.3f}, won {W.won.mean():.3f}")
A=[]
for tag,bc,lc,b3,l3 in (('T15','b1','l1','b3','l3'),('IP','bi1','li1','bi3','li3')):
    Lz=U[U.sd=='LAY']; Bz=U[U.sd=='BACK']
    al=pd.concat([Lz.assign(p=Lz[lc],p3=Lz[l3]),Bz.assign(p=Bz[bc],p3=Bz[b3])])
    A.append(row(f"{tag} item 52 cut 2, all",al,'p','p3')); A.append(row(f"{tag} lay only",Lz,lc,l3)); A.append(row(f"{tag} back only",Bz,bc,b3)); A.append(row(f"{tag} Segunda alone, item 45",U[U.lg==141],lc,l3))
    A.append(row(f"{tag} control: lay Under, all games",U,lc,l3)); A.append(row(f"{tag} control: back Under, all games",U,bc,b3))
    for k,(sd,nm) in FIX.items():
        A.append(row(f"{tag}   {nm} {sd}",U[U.lg==k],lc if sd=='LAY' else bc,l3 if sd=='LAY' else b3))
A=pd.DataFrame(A); A['PASS']=passed(A); print(A.round(3).to_string(index=False))
print("\n== SURVIVORS")
s=pd.concat([L[L.PASS],A[A.PASS]]); print(s.round(3).to_string(index=False) if len(s) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
