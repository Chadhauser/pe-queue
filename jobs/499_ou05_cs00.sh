#!/bin/bash
set -o pipefail
# 499_ou05_cs00 (Finder 2026-11-05, queue item 106): Over 0.5, correct score 0-0 and odd/even, on the tape for the first time (loader 347, Sep 2026). Item 25(d), Hargraves' lay of 0-0 at 60', could not be tested when no Over 0.5 was on the box. Read only. ONE MONTH, prints only, no book, so a pass is an upper bound and would earn a real-touch record, no more.
# GAMES: bf_hist_other Soccer, OVER_UNDER_05, CORRECT_SCORE, ODD_OR_EVEN, market_time 1 Sep to 1 Oct 2026. Final score and score path from goal_timeline, exact names first, then the loose match, as jobs/499_grid_cells_third_season.sh. Feed goals can be phantom (about 2%, item 0g).
# STATE AT A PRINT, no look-ahead, as that job: score on the last feed row at least 120 s before the print, no feed row up to the print differs from it, last feed row within 300 s of the print; minute from the last feed row at or before the print.
# LINES, fixed before any price is read:
#   T in 46, 55, 60, 65, 70, 75, 80: first print with the feed at 0-0 and minute T to T+4. Over 0.5, Under 0.5, CS 0-0, back and lay, to the result.
#   PRE: first print from T-15 to the scheduled off, not in play. The same three, back and lay, to the result.
#   PARITY T in 60, 70, 80: first print at any score, minute T to T+4, the runner matching the current total goals odd or even, back and lay, to the result.
# FILL as 470: worse of that print and the same runner's next print within 2 min; one tick adverse; 2%; back stake 10, lay liability 10. Price over 50 not traded, counted. A back that fills at 1.01 is no bet, counted. One entry per game per line. Nothing is dropped for settling: every entry is held to the result.
# Halves: median market date. Lines overlap heavily, as one game can be in all 7 minutes.
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
def pnl(side,p,won):
    if side=='B':
        a=step(p,-1)
        if a<=1.01: return np.nan
        return 10*(a-1)*0.98 if won else -10.0
    a=step(p,1)
    return -10.0 if won else 10/(a-1)*0.98
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
def won(line,hg,ag):
    t=hg+ag
    if line=='OVER': return t>0
    if line=='UNDER': return t==0
    if line=='CS00': return hg==0 and ag==0
    if line=='ODD': return t%2==1
    if line=='EVEN': return t%2==0
    raise ValueError(line)
def fill(ts,px,i,side):
    p=float(px[i])
    if i+1<len(ts) and ts[i+1]-ts[i]<=120: p=max(p,float(px[i+1])) if side=='L' else min(p,float(px[i+1]))
    return p
def first_entry(ts,px,T,ft,fm,fh,fa,zero_only):
    """First print with the feed in minute T..T+4, at 0-0 if zero_only. Returns (index, h, a) or None."""
    for i in range(len(ts)):
        st=state_at(ts[i],ft,fm,fh,fa)
        if st is None or not (T<=st[0]<T+5): continue
        if zero_only and (st[1]!=0 or st[2]!=0): continue
        return i,st[1],st[2]
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
assert abs(pnl('B',2.0,True)-10*0.99*0.98)<1e-9 and pnl('B',2.0,False)==-10.0 and np.isnan(pnl('B',1.02,True))   # 2.0 fills 1.99; 1.02 fills 1.01: no bet
assert abs(pnl('L',6.0,False)-10/5.2*0.98)<1e-9 and pnl('L',6.0,True)==-10.0                                      # 6.0 fills 6.2, stake 10/5.2 for a 10 liability
assert won('OVER',1,0) and not won('OVER',0,0) and won('UNDER',0,0) and not won('UNDER',0,1) and won('CS00',0,0) and not won('CS00',1,1)
assert won('ODD',2,1) and not won('ODD',1,1) and won('EVEN',0,0) and won('EVEN',2,2) and not won('EVEN',1,0)      # 0 goals is even
_ts=np.array([0.,100.,500.]); _px=np.array([2.0,1.9,3.0])
assert fill(_ts,_px,0,'B')==1.9 and fill(_ts,_px,0,'L')==2.0 and fill(_ts,_px,1,'L')==1.9 and fill(_ts,_px,2,'B')==3.0   # worse of two prints, only if the next is within 120 s
_f=np.array([0.,100.,200.,300.,400.,500.]); _m=np.array([50.,55.,56.,60.,61.,62.]); _h=np.array([0,0,0,0,1,1]); _a=np.zeros(6,int)
assert state_at(250,_f,_m,_h,_a)==(56.0,0,0) and state_at(450,_f,_m,_h,_a) is None and state_at(650,_f,_m,_h,_a)==(62.0,1,0) and state_at(50,_f,_m,_h,_a) is None and state_at(900,_f,_m,_h,_a) is None
_t2=np.array([150.,250.,350.,450.,650.])
assert first_entry(_t2,_t2,55,_f,_m,_h,_a,True)==(0,0,0)                                                          # 150 s: minute 55
assert first_entry(_t2,_t2,60,_f,_m,_h,_a,True)==(2,0,0)                                                          # 350 s: minute 60, still 0-0
assert first_entry(np.array([650.]),np.array([650.]),60,_f,_m,_h,_a,True) is None                                 # 1-0 at minute 62: not a 0-0 entry
assert first_entry(np.array([650.]),np.array([650.]),60,_f,_m,_h,_a,False)==(0,1,0)                               # any score: entered, odd
assert secs(pd.Series(['1970-01-01 00:01:00+00']))[0]==60.0
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
cur.execute("""SELECT DISTINCT market_id,market_type,event_name,market_time FROM bf_hist_other WHERE sport='Soccer' AND market_type IN ('OVER_UNDER_05','CORRECT_SCORE','ODD_OR_EVEN') AND market_time>='2026-09-01' AND market_time<'2026-10-02'""")
MK={}; SK=Counter()
for mid,mty,ev,mt in cur.fetchall():
    SK[f'{mty} markets']+=1; k=(ev,pd.Timestamp(mt).tz_convert('UTC')); MK.setdefault(k,{})[mty]=mid
print(f"events {len(MK)}, {dict(SK)}, {time.time()-T0:.0f}s",flush=True)
Games=[]
for (ev,mt),v in MK.items():
    m=match(ev,mt)
    if m is None: SK['event: no unique score']+=1; continue
    SK['event: scored']+=1; Games.append(dict(ev=ev,mt=mt,fx=m[0],hg=m[1],ag=m[2],**v))
print(f"scored games {len(Games)}, of events {len(MK)}, {time.time()-T0:.0f}s",flush=True)
if len(Games)<500: sys.exit(f"only {len(Games)} games scored: a code fault, not a result")
SEL={'OVER_UNDER_05':{'Over 0.5 Goals':'OVER','Under 0.5 Goals':'UNDER'},'CORRECT_SCORE':{'0 - 0':'CS00'},'ODD_OR_EVEN':{'Odd':'ODD','Even':'EVEN'}}
ALLSEL=[s for d in SEL.values() for s in d]; TS=(46,55,60,65,70,75,80); PT=(60,70,80); rows=[]
def add(tag,line,side,p,g,held=None):
    # held: the runner actually held, when the line's name is not a runner (PARITY is ODD or EVEN by the score at entry)
    if p>50: SK['over 50, not traded']+=1; return
    w=won(held or line,g['hg'],g['ag']); v=pnl(side,p,w)
    if np.isnan(v): SK['back fills at 1.01, no bet']+=1; return
    rows.append((tag,line,side,g['ev'],g['mt'].timestamp(),p,w,v))
for c in range(0,len(Games),300):
    sub=Games[c:c+300]
    F=pd.read_sql("SELECT fixture_id,captured_at,minute,score_home,score_away FROM goal_timeline WHERE fixture_id=ANY(%s) AND score_home IS NOT NULL AND score_away IS NOT NULL ORDER BY fixture_id,captured_at",con,params=([g['fx'] for g in sub],))
    F['tt']=secs(F.captured_at); F['mn']=pd.to_numeric(F.minute,errors='coerce'); FF={k:g for k,g in F.groupby('fixture_id')}
    ids=[g[k] for g in sub for k in SEL if k in g]
    P=pd.read_sql("SELECT market_id,sel,ts,ltp::float8 ltp,inplay FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s) AND sel=ANY(%s) AND ltp>=1.01 AND ltp<1000",con,params=(ids,ALLSEL))
    P['tt']=secs(P.ts); P=P.drop_duplicates(['market_id','sel','tt']).sort_values('tt',kind='stable'); PX={k:g for k,g in P.groupby(['market_id','sel'])}
    for g in sub:
        off=g['mt'].timestamp(); fd=FF.get(g['fx'])
        fd=fd[fd.mn.notna()] if fd is not None else None
        feed_ok=fd is not None and len(fd)>=5
        SK['game feed ok' if feed_ok else 'game feed thin, PRE lines only']+=1
        if feed_ok: ft,fm,fh,fa=fd.tt.values,fd.mn.values,fd.score_home.values.astype(int),fd.score_away.values.astype(int)
        for mty,d in SEL.items():
            if mty not in g: continue
            for sname,line in d.items():
                x=PX.get((g[mty],sname))
                if x is None: continue
                ipm=x.inplay.values.astype(bool); ts,px=x.tt.values,x.ltp.values
                if line in ('OVER','UNDER','CS00'):
                    pre=np.where((~ipm)&(ts>=off-900)&(ts<=off))[0]
                    if len(pre):
                        i=int(pre[0])
                        for side in 'BL': add('PRE',line,side,fill(ts,px,i,side),g)
                if not feed_ok or not ipm.any(): continue
                ti,pi=ts[ipm],px[ipm]
                if line in ('OVER','UNDER','CS00'):
                    for T in TS:
                        e=first_entry(ti,pi,T,ft,fm,fh,fa,True)
                        if e is None: continue
                        for side in 'BL': add(f'T{T}',line,side,fill(ti,pi,e[0],side),g)
                else:
                    for T in PT:
                        e=first_entry(ti,pi,T,ft,fm,fh,fa,False)
                        if e is None: continue
                        if ('ODD' if (e[1]+e[2])%2==1 else 'EVEN')!=line: continue
                        for side in 'BL': add(f'PAR{T}','PARITY',side,fill(ti,pi,e[0],side),g,held=line)
    print(f"  {min(c+300,len(Games))}/{len(Games)} rows {len(rows)} {time.time()-T0:.0f}s",flush=True)
    if time.time()-T0>2700: print("BUDGET HIT, sample cut"); break
con.close(); print("counts:",{k:v for k,v in sorted(SK.items()) if not k.startswith('try')},flush=True)
R=pd.DataFrame(rows,columns=['tag','line','side','ev','when','p','won','v'])
if R.empty: print("ERROR: no entries, so no verdict"); sys.exit(1)
print(f"\ndates {pd.Timestamp(R.when.min(),unit='s'):%Y-%m-%d} to {pd.Timestamp(R.when.max(),unit='s'):%Y-%m-%d}; distinct games {R.ev.nunique()}")
out=[]
for (tag,line,side),d in R.groupby(['tag','line','side']):
    r=gate(d.v.values.astype(float),d.when.values); fp=d.p.map(lambda q:step(q,-1)) if side=='B' else d.p.map(lambda q:step(q,1))
    out.append(dict(tag=tag,line=line,side=side,**r,games=d.ev.nunique(),won=d.won.mean(),imp=(1/fp).mean(),med_p=d.p.median()))
S=pd.DataFrame(out); print(f"\nlines {len(S)}, at n>=300: {(S.n>=300).sum()}")
order={'PRE':0,**{f'T{t}':t for t in TS},**{f'PAR{t}':100+t for t in PT}}
A=S.assign(o=S.tag.map(order)).sort_values(['o','line','side']).drop(columns=['o','n1','n2'])
print("\n== ALL LINES, per £10\n",A.round(3).to_string(index=False))
print("\n== TOP 15 by t, n>=100\n",S[S.n>=100].sort_values('t',ascending=False).head(15).drop(columns=['n1','n2']).round(3).to_string(index=False))
Y=S[S.PASS]; print(f"\n== SURVIVORS: {len(Y)} of {len(S)}\n",Y.round(3).to_string(index=False) if len(Y) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
