#!/bin/bash
set -o pipefail
# 499_grid_cells_third_season (Finder 2026-11-04, queue item 69): the top 20 in-play cells of the two-season grid, on a season none of them has seen. Chosen from grid_cells_v4 BEFORE any 2026 price is read, and printed first: MO and OU25, exit SETTLE, dirty = 0, n >= 300, both halves positive, ranked by t. All 20 are reported, whatever they are. Read only.
# EXIT is settle only: the item names goal +8 too, but the table's goal exits are g+2, g+10 and g+20, and items 19 and 22 showed g+2 rests on a clock look-ahead, so settle is the one exit that needs no goal clock.
# GAMES: bf_hist_other Soccer, MO and OU25, Jul-Sep 2026; final score and score path from goal_timeline, exact names first, then the loose match of jobs/499_flb_unseen_games.sh. Home and away stay oriented, as names are matched side to side.
# STATE AT A PRINT, no look-ahead: the score on the last feed row at least 120 s before the print, and no feed row up to the print may differ from it (the same 2-minute guard as 470); the feed's last row must be within 300 s of the print. MINUTE: from the last feed row at or before the print. Feed goals can be phantom (about 2%, item 0g), which only makes entries worse.
# ENTRY as 470: first print in the band in that state, one per game per cell; fill = worse of that print and the next print within 2 min; one tick adverse; 2% commission; back stake 10, lay liability 10. Price over 50 not traded. A selection already decided is not traded.
# DIFFERENCE FROM THE GRID: favourite and draw bands use the T-15 print, as this tape has one; the grid used its first print after kick-off. Clock is the feed's, not af's. Prints only, no book, so a pass is an upper bound. About 3 months, so n >= 300 is unlikely per cell: the useful reading is how many of 20 stay positive and their pooled mean.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,re,unicodedata,time,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
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
def pnl(side,p,won,k=1):
    if side=='B':
        a=step(p,-k)
        if a<=1.01: return np.nan
        return 10*(a-1)*0.98 if won else -10.0
    a=step(p,k)
    return -10.0 if won else 10/(a-1)*0.98
def state(h,a): return f"{h}-{a}" if (h+a<3 or (h==2 and a==2) or (h==2 and a==1) or (h==1 and a==2)) and h<=2 and a<=2 else '3+'
def band(m): return '00-15' if m<15 else '15-30' if m<30 else '30-45' if m<=45 else 'HT' if m<=48 else '45-60' if m<=60 else '60-75' if m<75 else '75-90' if m<=90 else None
def favband(f): return '<1.5' if f<1.5 else '1.5-2' if f<2 else '2-3' if f<3 else '3+'
def drawband(d): return '<3' if d<3 else '3-3.6' if d<3.6 else '3.6-4.5' if d<4.5 else '4.5-5.5' if d<5.5 else '5.5+'
def norm(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
    s=re.sub(r"\b(fc|cf|afc|sc|ac|as|ss|us|sv|vfb|vfl|tsg|fk|club|de|the|cd|ud|sd|rcd|calcio|ii|b|if|bk|ff|aif|sk|fsv)\b"," ",s)
    return frozenset(w for w in re.sub(r"[^a-z0-9 ]"," ",s).split() if len(w)>2)
def jac(X,Y): return len(X&Y)/max(1,len(X|Y))
def loose(H,A,cands):
    sc=[]
    for c in cands:
        a,b=jac(H,c[0]),jac(A,c[1])
        if a>0 and b>0: sc.append((a+b,c[2]))
    sc.sort(key=lambda z:-z[0])
    if not sc or sc[0][0]<1.0 or (len(sc)>1 and sc[0][0]-sc[1][0]<0.3): return None
    return sc[0][1]
def state_at(ts,ft,fm,fh,fa):
    # ts and ft in seconds, ft ascending. Returns (state, minute, h, a) or None
    i=np.searchsorted(ft,ts,side='right')-1; j=np.searchsorted(ft,ts-120,side='right')-1
    if i<0 or j<0 or ts-ft[i]>300: return None
    if (fh[j:i+1]!=fh[j]).any() or (fa[j:i+1]!=fa[j]).any(): return None
    return state(int(fh[j]),int(fa[j])),fm[i],int(fh[j]),int(fa[j])
def won(mk,sel,hg,ag):
    if mk=='MO': return hg>ag if sel=='HOME' else (hg<ag if sel=='AWAY' else hg==ag)
    return (hg+ag>2.5)==(sel=='OVER')
def secs(col):
    # seconds since 1970 whatever resolution pandas holds; astype int64 / 1e9 is wrong when the column is in microseconds
    return (pd.to_datetime(col,utc=True)-pd.Timestamp('1970-01-01',tz='UTC'))/pd.Timedelta(seconds=1)
def tstat(x):
    x=np.asarray(x,dtype=float); x=x[~np.isnan(x)]; s=x.std(ddof=1) if len(x)>1 else 0
    return x.mean()/(s/len(x)**0.5) if s>0 else 0.0
# known answers, worked by hand
assert abs(pnl('B',2.0,True)-9.702)<1e-9 and pnl('B',2.0,False)==-10.0 and np.isnan(pnl('B',1.02,True))
assert abs(pnl('L',6.0,False)-10/5.2*0.98)<1e-9 and pnl('L',6.0,True)==-10.0
assert [state(*x) for x in ((0,0),(2,1),(1,2),(2,2),(3,0),(0,3),(3,1),(2,0))]==['0-0','2-1','1-2','2-2','3+','3+','3+','2-0']
assert [band(m) for m in (0,14,15,45,46,48,49,60,74,75,90,91)]==['00-15','00-15','15-30','30-45','HT','HT','45-60','45-60','60-75','75-90','75-90',None]
assert favband(1.49)=='<1.5' and favband(2.0)=='2-3' and drawband(3.0)=='3-3.6' and drawband(5.5)=='5.5+'
_f=np.array([0.,100.,200.,300.]); _m=np.array([10,12,13,15]); _h=np.array([0,0,1,1]); _a=np.array([0,0,0,0])
assert state_at(150,_f,_m,_h,_a)==('0-0',12,0,0)      # 30 s row is the 2-min-old one, no change since
assert state_at(250,_f,_m,_h,_a) is None              # a goal shows at 200, the row 120 s back still says 0-0: not settled
assert state_at(330,_f,_m,_h,_a)==('1-0',15,1,0)      # 210 s row says 1-0, nothing newer differs
assert state_at(50,_f,_m,_h,_a) is None               # no row 120 s back
assert state_at(700,_f,_m,_h,_a) is None              # feed stale
assert won('OU25','OVER',2,1) and won('OU25','UNDER',1,1) and not won('OU25','OVER',1,1) and won('MO','DRAW',0,0) and won('MO','AWAY',0,1)
assert secs(pd.Series(['1970-01-01 00:01:00+00']))[0]==60.0 and abs(secs(pd.Series(['2026-08-01 00:00:00.5+00']))[0]-1785542400.5)<1e-6
print("checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'"); cur.execute("SET statement_timeout='2400s'")
C=pd.read_sql("SELECT state,band,mkt,sel,side,exit,fav,draw,dirty,n,s,ss,n1,s1,n2,s2 FROM grid_cells_v4 WHERE mkt IN ('MO','OU25') AND exit='SETTLE' AND dirty=0 AND n>=300 AND s1>0 AND s2>0",con)
C['per10']=C.s/C.n; C['t']=C.per10/np.sqrt((C.ss/C.n-C.per10**2)/C.n); C['h1']=C.s1/C.n1; C['h2']=C.s2/C.n2
C=C.sort_values('t',ascending=False).head(20).reset_index(drop=True); C['cell']=C.index+1
print(f"== THE 20 CELLS, written before any 2026 price is read; {time.time()-T0:.0f}s"); print(C[['cell','state','band','mkt','sel','side','fav','draw','n','per10','t','h1','h2']].round(3).to_string(index=False),flush=True)
if len(C)<20: print(f"only {len(C)} cells qualify")
GT=pd.read_sql("""SELECT DISTINCT ON (fixture_id) fixture_id,home_team,away_team,captured_at,minute,score_home,score_away,status FROM goal_timeline WHERE captured_at>='2026-06-30' AND captured_at<'2026-10-02' AND score_home IS NOT NULL ORDER BY fixture_id,captured_at DESC""",con)
GT['t']=pd.to_datetime(GT.captured_at,utc=True); GT['mn']=pd.to_numeric(GT.minute,errors='coerce')
GT=GT[GT.status.isin(['FT','AET','PEN','Match Finished','FINISHED'])|(GT.mn>=88)].sort_values('t').reset_index(drop=True)
GT['H']=GT.home_team.map(norm); GT['A']=GT.away_team.map(norm); tt=GT.t.values.astype('datetime64[ns]'); SC=defaultdict(list)
for r in GT.itertuples(): SC[(r.H,r.A)].append((r.t,int(r.fixture_id),int(r.score_home),int(r.score_away)))
print(f"finished fixtures {len(GT)}, {time.time()-T0:.0f}s",flush=True)
def scan(lo,hi):
    cur.execute("""WITH RECURSIVE t AS ((SELECT market_id FROM bf_hist_other WHERE sport='Soccer' AND market_id>=%s AND market_id<%s ORDER BY market_id LIMIT 1)
     UNION ALL SELECT (SELECT market_id FROM bf_hist_other WHERE sport='Soccer' AND market_id>t.market_id AND market_id<%s ORDER BY market_id LIMIT 1) FROM t WHERE t.market_id IS NOT NULL) SELECT market_id FROM t WHERE market_id IS NOT NULL""",(lo,hi,hi))
    return [r[0] for r in cur.fetchall() if '|' in r[0]]
def match(ev,mt):
    h,_,a=ev.partition(' v '); H,A=norm(h),norm(a); e=[x for x in SC.get((H,A),[]) if 0<=(x[0]-mt).total_seconds()/60<=240]
    if len(e)==1: return e[0][1:]
    if e: return None
    lo=np.searchsorted(tt,np.datetime64(mt.tz_convert(None))); hi=np.searchsorted(tt,np.datetime64((mt+pd.Timedelta(minutes=240)).tz_convert(None)),side='right')
    return loose(H,A,[(r.H,r.A,(int(r.fixture_id),int(r.score_home),int(r.score_away))) for r in GT.iloc[lo:hi].itertuples()])
MK={}
for key,lo,hi in (('MO','MATCH_ODDS','MATCH_ODDT'),('OU25','OVER_UNDER_25','OVER_UNDER_26')):
    for i in scan(lo,hi):
        _,ev,mt=i.split('|',2); mt=pd.Timestamp(mt); m=match(ev,mt)
        if m is not None: MK.setdefault((ev,mt),dict(score=m))[key]=i
Games=[v for v in MK.values() if 'MO' in v]; print(f"games with MO and a score {len(Games)}, of those with OU25 {sum('OU25' in v for v in Games)}; {time.time()-T0:.0f}s",flush=True)
need=defaultdict(list)
for r in C.itertuples(): need[(r.mkt,r.sel,r.state,r.band)].append(r)
bands_needed=set((r.state,r.band) for r in C.itertuples()); rows=[]; stats=defaultdict(int)
def price_rows(ids):
    P=pd.read_sql("SELECT market_id,event_name,market_time,sel,ts,ltp::float ltp,inplay FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s) AND ltp>=1.01 AND ltp<1000",con,params=(ids,))
    P['tt']=secs(P.ts) if len(P) else []; P['mt']=pd.to_datetime(P.market_time,utc=True) if len(P) else []
    return {k:g.sort_values('tt') for k,g in P.groupby('market_id')} if len(P) else {}
for c in range(0,len(Games),300):
    sub=Games[c:c+300]; fid=[g['score'][0] for g in sub]
    F=pd.read_sql("SELECT fixture_id,captured_at,minute,score_home,score_away FROM goal_timeline WHERE fixture_id=ANY(%s) AND score_home IS NOT NULL AND score_away IS NOT NULL ORDER BY fixture_id,captured_at",con,params=(fid,))
    F['tt']=secs(F.captured_at); F['mn']=pd.to_numeric(F.minute,errors='coerce'); FF={k:g for k,g in F.groupby('fixture_id')}
    PX=price_rows([g[k] for g in sub for k in ('MO','OU25') if k in g])
    for g in sub:
        fx,hg,ag=g['score']; fd=FF.get(fx); mo=PX.get(g['MO'])
        if fd is None or mo is None: stats['no_feed_or_prices']+=1; continue
        fd=fd[fd.mn.notna()]
        if len(fd)<5: stats['thin_feed']+=1; continue
        ft,fm,fh,fa=fd.tt.values,fd.mn.values,fd.score_home.values.astype(int),fd.score_away.values.astype(int)
        ev=mo.event_name.iloc[0]; h,_,a=ev.partition(' v '); h,a=h.strip(),a.strip(); sels=set(mo.sel)
        if not sels<={h,a,'The Draw'} or len(sels)<3: stats['runner_name']+=1; continue
        d=mo.mt.iloc[0]; off=d.timestamp(); nm={h:'HOME',a:'AWAY','The Draw':'DRAW'}; tp={}
        for s,x in mo.groupby('sel'):
            ip=x.inplay.values.astype(bool); w=x[(~ip)&(x.tt.values>=off-900)&(x.tt.values<=off)]
            if len(w): tp[nm[s]]=w.ltp.iloc[0]
        if not all(k in tp for k in ('HOME','AWAY','DRAW')): stats['no_t15_book']+=1; continue
        fb,db=favband(min(tp['HOME'],tp['AWAY'])),drawband(tp['DRAW']); stats['games_used']+=1
        for key,sm in (('MO',nm),('OU25',{'Over 2.5 Goals':'OVER','Under 2.5 Goals':'UNDER'})):
            df=PX.get(g.get(key))
            if df is None: continue
            for s,x in df[df.inplay].groupby('sel'):
                sl=sm.get(s)
                if sl is None: continue
                ts,px=x.tt.values,x.ltp.values; seen=set()
                for i in range(len(ts)):
                    st=state_at(ts[i],ft,fm,fh,fa)
                    if st is None: continue
                    b=band(st[1])
                    if b is None or (st[0],b)not in bands_needed or (st[0],b) in seen: continue
                    seen.add((st[0],b))
                    if key=='OU25' and st[2]+st[3]>=3: continue
                    for cell in need.get((key,sl,st[0],b),[]):
                        if cell.fav!=fb or cell.draw!=db: continue
                        p=px[i]
                        if i+1<len(ts) and ts[i+1]-ts[i]<=120: p=max(p,px[i+1]) if cell.side=='L' else min(p,px[i+1])
                        if p>50: stats['over_50']+=1; continue
                        w=won(key,sl,hg,ag); rows.append(dict(cell=cell.cell,mid=g[key],d=d,side=cell.side,p=p,won=w,pnl=pnl(cell.side,p,w),x3=pnl(cell.side,p,w,3),min=st[1]))
    print(f"  {min(c+300,len(Games))}/{len(Games)} entries {len(rows)} {time.time()-T0:.0f}s",flush=True)
con.close(); print(f"stats {dict(stats)}",flush=True)
if stats['games_used']<1000: sys.exit(f"only {stats['games_used']} games used of {len(Games)}: a code fault, not a result")
print("\n== GATE: entries, won v implied at the fill price")
R=pd.DataFrame(rows)
if not len(R): print("no entries"); print("\n== SURVIVORS\nnone"); sys.exit(0)
R['imp']=1/R.p; print(f"entries {len(R)}, games {R.mid.nunique()}, won {R.won.mean():.3f} v implied {R.imp.mean():.3f}")
med=R.d.median(); R['h']=np.where(R.d<=med,1,2); print(f"dates {R.d.min():%Y-%m-%d} to {R.d.max():%Y-%m-%d}, median {med:%Y-%m-%d}")
O=[]
for r in C.itertuples():
    x=R[R.cell==r.cell]; v=x.pnl.dropna(); a=x[x.h==1].pnl.dropna(); b=x[x.h==2].pnl.dropna()
    O.append(dict(cell=r.cell,line=f"{r.mkt} {r.sel} {r.side} {r.state} {r.band} fav {r.fav} draw {r.draw}",grid_n=r.n,grid_per10=r.per10,grid_t=r.t,n=len(v),per10=v.mean() if len(v) else np.nan,t=tstat(v),h1=a.mean() if len(a) else np.nan,h2=b.mean() if len(b) else np.nan,n1=len(a),n2=len(b),x3=x.x3.mean() if len(x) else np.nan))
O=pd.DataFrame(O); O['PASS']=(O.n>=300)&(O.n1>=150)&(O.n2>=150)&(O.t>=3.5)&(O.h1>0)&(O.h2>0)&(O.per10>=0.15)
print("\n== ALL 20 CELLS on Jul-Sep 2026"); print(O.drop(columns=['n1','n2']).round(3).to_string(index=False))
sc=O[O.n>0]; print(f"\ncells with entries {len(sc)}; positive {int((sc.per10>0).sum())} of {len(sc)}; at n >= 30 positive {int((sc[sc.n>=30].per10>0).sum())} of {int((sc.n>=30).sum())}")
one=R.dropna(subset=['pnl']).sort_values('d'); print(f"pooled, all entries: n {len(one)}, per 10 {one.pnl.mean():+.3f}, t {tstat(one.pnl):.2f}, h1 {one[one.h==1].pnl.mean():+.3f}, h2 {one[one.h==2].pnl.mean():+.3f}, x3 {one.x3.mean():+.3f}")
f=one.drop_duplicates('mid'); print(f"pooled, first entry per market: n {len(f)}, per 10 {f.pnl.mean():+.3f}, t {tstat(f.pnl):.2f}, h1 {f[f.h==1].pnl.mean():+.3f}, h2 {f[f.h==2].pnl.mean():+.3f}, x3 {f.x3.mean():+.3f}")
print("\n== SURVIVORS"); s=O[O.PASS]; print(s.round(3).to_string(index=False) if len(s) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
