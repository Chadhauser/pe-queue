#!/bin/bash
set -o pipefail
# 499_dnb_sep_tape (Finder 2026-11-05, queue item 111): reopen 0f for one month, Draw No Bet on the Sep 2026 tape. Read only. ONE MONTH, prints only, no book: a screen, so a pass is an upper bound and would earn a real-touch record, no more.
# ASIAN HANDICAP BLOCKED: bf_hist_other stores only the team name for ASIAN_HANDICAP runners, no handicap column, so a price cannot be tied to its line and cannot be settled. It would need the handicap kept by the loader.
# GAMES, STATE AT A PRINT, FILL: as jobs/499_ou05_cs00.sh. Feed goals can be phantom (about 2%, item 0g). Runner to side: folded name equal to the event name's home or away; anything else not traded, counted.
# LINES, fixed before any price is read:
#   PRE: first print from T-15 to the scheduled off, not in play, FAV (price under 2.0) and DOG (2.0 and over), back and lay.
#   T in 46, 60, 75: each runner's first settled print with feed minute T to T+9, classed by the feed score from that runner's side: 00 (0-0), LEVEL (level after goals), LEAD1, TRAIL1. Two goals or more apart not traded, counted. Back and lay.
# SETTLE: to the final score. Runner wins: back +10 x (fill - 1) x 0.98, lay -10. Runner loses: back -10, lay +10/(fill - 1) x 0.98. DRAW IS VOID: 0 both ways, kept in n as the stake was tied up. One tick adverse, 2%, back stake 10, lay liability 10. Price over 50 not traded, a back filling at 1.01 is no bet, both counted.
# At level scores both runners enter, one game twice and mirror images, so games is shown beside n. Halves: median market date.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,re,unicodedata,time,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); import creds
pd.set_option('display.width',230); pd.set_option('display.max_rows',100); pd.set_option('display.max_columns',30)
T0=time.time()
LD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    v=lo
    while v<hi-1e-9: LD.append(round(v,2)); v+=st
LD.append(1000.0); LD=np.array(LD)
def ix(p): return int(np.searchsorted(LD,round(float(p),2)-1e-9))
def step(p,k): return float(LD[min(max(ix(p)+k,0),len(LD)-1)])
def pnl(side,p,diff):
    """diff = final goals for the runner minus against. 0 is a draw: void."""
    if side=='B':
        a=step(p,-1)
        if a<=1.01: return np.nan
        return 0.0 if diff==0 else (10*(a-1)*0.98 if diff>0 else -10.0)
    a=step(p,1)
    return 0.0 if diff==0 else (-10.0 if diff>0 else 10/(a-1)*0.98)
def klass(gf,ga):
    if gf==ga: return '00' if gf==0 else 'LEVEL'
    if gf-ga==1: return 'LEAD1'
    if ga-gf==1: return 'TRAIL1'
    return None
def fold(s): return re.sub(r"[^a-z0-9]","",unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower())
def side_of(sel,h,a):
    f=fold(sel)
    if f==fold(h): return 'H'
    if f==fold(a): return 'A'
    return None
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
    i=np.searchsorted(ft,ts,side='right')-1; j=np.searchsorted(ft,ts-120,side='right')-1
    if i<0 or j<0 or ts-ft[i]>300: return None
    if (fh[j:i+1]!=fh[j]).any() or (fa[j:i+1]!=fa[j]).any(): return None
    return fm[i],int(fh[j]),int(fa[j])
def fill(ts,px,i,side):
    p=float(px[i])
    if i+1<len(ts) and ts[i+1]-ts[i]<=120: p=max(p,float(px[i+1])) if side=='L' else min(p,float(px[i+1]))
    return p
def first_in_window(ts,T,ft,fm,fh,fa):
    """First print with a settled state and feed minute T..T+9. Returns (index, home goals, away goals) or None."""
    for i in range(len(ts)):
        st=state_at(ts[i],ft,fm,fh,fa)
        if st is not None and T<=st[0]<T+10: return i,st[1],st[2]
    return None
def tstat(x):
    x=np.asarray(x,dtype=float); x=x[np.isfinite(x)]
    if len(x)<2: return 0.0
    s=x.std(ddof=1); return float(x.mean()/(s/len(x)**0.5)) if s>0 else 0.0
def secs(col): return (pd.to_datetime(col,utc=True)-pd.Timestamp('1970-01-01',tz='UTC'))/pd.Timedelta(seconds=1)
def gate(v,when):
    m=np.isfinite(v); v=v[m]; when=when[m]
    if len(v)==0: return dict(n=0,mean=np.nan,t=0.0,n1=0,h1=np.nan,n2=0,h2=np.nan,PASS=False)
    md=np.median(when); a=v[when<md]; b=v[when>=md]; t=tstat(v)
    return dict(n=len(v),mean=v.mean(),t=t,n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,
                PASS=bool(len(v)>=300 and len(a)>=150 and len(b)>=150 and t>=3.5 and a.mean()>0 and b.mean()>0 and v.mean()>=0.15))
# known answers, worked by hand
assert abs(pnl('B',2.0,1)-10*0.99*0.98)<1e-9 and pnl('B',2.0,-2)==-10.0 and pnl('B',2.0,0)==0.0 and np.isnan(pnl('B',1.02,1))   # 2.0 fills 1.99; a draw is void; 1.02 fills 1.01: no bet
assert abs(pnl('L',6.0,-1)-10/5.2*0.98)<1e-9 and pnl('L',6.0,1)==-10.0 and pnl('L',6.0,0)==0.0                                  # 6.0 fills 6.2
assert [klass(*x) for x in ((0,0),(1,1),(2,2),(1,0),(2,1),(0,1),(1,2),(2,0),(0,2))]==['00','LEVEL','LEVEL','LEAD1','LEAD1','TRAIL1','TRAIL1',None,None]
assert side_of('Csm Slatina','ACS Dumbravita','CSM Slatina')=='A' and side_of('Acs Dumbravita','ACS Dumbravita','CSM Slatina')=='H' and side_of('Other','ACS Dumbravita','CSM Slatina') is None
_f=np.array([0.,100.,200.,300.,400.,500.]); _m=np.array([50.,55.,56.,60.,61.,62.]); _h=np.array([0,0,0,0,1,1]); _a=np.zeros(6,int)
_t=np.array([150.,350.,450.,650.])
assert first_in_window(_t,46,_f,_m,_h,_a)==(0,0,0) and first_in_window(_t,60,_f,_m,_h,_a)==(1,0,0)                               # 150 s minute 55; 350 s minute 60
assert first_in_window(np.array([450.,650.]),60,_f,_m,_h,_a)==(1,1,0)                                                           # 450 s is unsettled, a goal at 400 s; 650 s is 1-0
assert first_in_window(np.array([900.]),60,_f,_m,_h,_a) is None                                                                 # feed stale
_ts=np.array([0.,100.,500.]); _px=np.array([2.0,1.9,3.0]); assert fill(_ts,_px,0,'B')==1.9 and fill(_ts,_px,0,'L')==2.0 and fill(_ts,_px,2,'B')==3.0
_g=gate(np.array([1.0,0.5]*200),np.arange(400.0)); assert _g['PASS'] is True and abs(_g['mean']-0.75)<1e-9
_g=gate(np.array([1.0]*300+[0.0]*300),np.arange(600.0)); assert _g['PASS'] is False
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)

con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
GT=pd.read_sql("""SELECT DISTINCT ON (fixture_id) fixture_id,home_team,away_team,captured_at,minute,score_home,score_away,status FROM goal_timeline WHERE captured_at>='2026-08-31' AND captured_at<'2026-10-03' AND score_home IS NOT NULL AND score_away IS NOT NULL ORDER BY fixture_id,captured_at DESC""",con)
GT['t']=pd.to_datetime(GT.captured_at,utc=True); GT['mn']=pd.to_numeric(GT.minute,errors='coerce')
GT=GT[GT.status.isin(['FT','AET','PEN','Match Finished','FINISHED'])|(GT.mn>=88)].sort_values('t').reset_index(drop=True)
GT['H']=GT.home_team.map(norm); GT['A']=GT.away_team.map(norm); tt=GT.t.values.astype('datetime64[ns]'); SC=defaultdict(list)
for r in GT.itertuples(): SC[(r.H,r.A)].append((r.t,int(r.fixture_id),int(r.score_home),int(r.score_away)))
print(f"finished fixtures {len(GT)}, {time.time()-T0:.0f}s",flush=True)
def match(ev,mt):
    h,_,a=ev.partition(' v '); H,A=norm(h),norm(a); e=[x for x in SC.get((H,A),[]) if 0<=(x[0]-mt).total_seconds()/60<=240]
    if len(e)==1: return e[0][1:]
    if e: return None
    lo=np.searchsorted(tt,np.datetime64(mt.tz_convert(None))); hi=np.searchsorted(tt,np.datetime64((mt+pd.Timedelta(minutes=240)).tz_convert(None)),side='right')
    return loose(H,A,[(r.H,r.A,(int(r.fixture_id),int(r.score_home),int(r.score_away))) for r in GT.iloc[lo:hi].itertuples()])
cur.execute("""SELECT DISTINCT market_id,event_name,market_time FROM bf_hist_other WHERE sport='Soccer' AND market_type='DRAW_NO_BET' AND market_time>='2026-09-01' AND market_time<'2026-10-02'""")
SK=Counter(); Games=[]
for mid,ev,mt in cur.fetchall():
    SK['markets']+=1; mt=pd.Timestamp(mt).tz_convert('UTC'); m=match(ev,mt)
    if m is None: SK['market: no unique score']+=1; continue
    Games.append(dict(mid=mid,ev=ev,mt=mt,fx=m[0],hg=m[1],ag=m[2]))
print(f"scored {len(Games)} of {SK['markets']}, {time.time()-T0:.0f}s",flush=True)
if len(Games)<500: sys.exit(f"only {len(Games)} games scored: a code fault, not a result")
TS=(46,60,75); rows=[]
def add(tag,cl,side,p,g,diff):
    if p>50: SK['over 50, not traded']+=1; return
    v=pnl(side,p,diff)
    if np.isnan(v): SK['back fills at 1.01, no bet']+=1; return
    rows.append((tag,cl,side,g['mid'],g['mt'].timestamp(),p,diff,v))
for c in range(0,len(Games),300):
    sub=Games[c:c+300]
    F=pd.read_sql("SELECT fixture_id,captured_at,minute,score_home,score_away FROM goal_timeline WHERE fixture_id=ANY(%s) AND score_home IS NOT NULL AND score_away IS NOT NULL ORDER BY fixture_id,captured_at",con,params=([g['fx'] for g in sub],))
    F['tt']=secs(F.captured_at); F['mn']=pd.to_numeric(F.minute,errors='coerce'); FF={k:x for k,x in F.groupby('fixture_id')}
    P=pd.read_sql("SELECT market_id,sel,ts,ltp::float8 ltp,inplay FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s) AND ltp>=1.01 AND ltp<1000",con,params=([g['mid'] for g in sub],))
    P['tt']=secs(P.ts); P=P.drop_duplicates(['market_id','sel','tt']).sort_values('tt',kind='stable'); PX={k:x for k,x in P.groupby('market_id')}
    for g in sub:
        x=PX.get(g['mid']); off=g['mt'].timestamp(); h,_,a=g['ev'].partition(' v ')
        if x is None: SK['no prints']+=1; continue
        fd=FF.get(g['fx']); fd=fd[fd.mn.notna()] if fd is not None else None; feed_ok=fd is not None and len(fd)>=5
        if feed_ok: ft,fm,fh,fa=fd.tt.values,fd.mn.values,fd.score_home.values.astype(int),fd.score_away.values.astype(int)
        else: SK['feed thin, PRE only']+=1
        for s,y in x.groupby('sel',sort=False):
            sd=side_of(s,h.strip(),a.strip())
            if sd is None: SK['runner name not home or away']+=1; continue
            diff=(g['hg']-g['ag'])*(1 if sd=='H' else -1); ipm=y.inplay.values.astype(bool); ts,px=y.tt.values,y.ltp.values
            pre=np.where((~ipm)&(ts>=off-900)&(ts<=off))[0]
            if len(pre):
                i=int(pre[0]); cl='FAV' if px[i]<2.0 else 'DOG'
                for side in 'BL': add('PRE',cl,side,fill(ts,px,i,side),g,diff)
            if not feed_ok or not ipm.any(): continue
            ti,pi=ts[ipm],px[ipm]
            for T in TS:
                e=first_in_window(ti,T,ft,fm,fh,fa)
                if e is None: SK[f'T{T} no print in window']+=1; continue
                gf,ga=(e[1],e[2]) if sd=='H' else (e[2],e[1]); cl=klass(gf,ga)
                if cl is None: SK['two or more apart, not traded']+=1; continue
                for side in 'BL': add(f'T{T}',cl,side,fill(ti,pi,e[0],side),g,diff)
    print(f"  {min(c+300,len(Games))}/{len(Games)} rows {len(rows)} {time.time()-T0:.0f}s",flush=True)
con.close(); print("counts:",dict(sorted(SK.items())),flush=True)
R=pd.DataFrame(rows,columns=['tag','cl','side','mid','when','p','diff','v'])
if R.empty: print("ERROR: no entries, so no verdict"); sys.exit(1)
print(f"\ndates {pd.Timestamp(R.when.min(),unit='s'):%Y-%m-%d} to {pd.Timestamp(R.when.max(),unit='s'):%Y-%m-%d}; markets with an entry {R.mid.nunique()}")
out=[]
for (tag,cl,side),d in R.groupby(['tag','cl','side']):
    r=gate(d.v.values.astype(float),d.when.values)
    out.append(dict(tag=tag,cl=cl,side=side,**r,games=d.mid.nunique(),win=(d['diff']>0).mean(),void=(d['diff']==0).mean(),med_p=d.p.median()))
S=pd.DataFrame(out); print(f"\nlines {len(S)}, at n>=300: {(S.n>=300).sum()}")
print("\n== ALL LINES, per £10\n",S.sort_values(['tag','cl','side']).drop(columns=['n1','n2']).round(3).to_string(index=False))
Y=S[S.PASS]; print(f"\n== SURVIVORS: {len(Y)} of {len(S)}\n",Y.round(3).to_string(index=False) if len(Y) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
