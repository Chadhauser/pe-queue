#!/bin/bash
set -o pipefail
# 499_sep_tape_rest (Finder 2026-11-05, queue item 113): HALF_TIME, DOUBLE_CHANCE and OVER_UNDER_45 on the Sep 2026 tape. Read only. ONE MONTH, prints only, no book: a screen, so a pass is an upper bound and would earn a real-touch record, no more.
# NOT TESTED: TEAM_A_1 and TEAM_B_1. They are three-way team handicaps, not team goals as item 113 first said, and hold about 10 rows a market across all runners and the whole game, too thin for a state test.
# GAMES, STATE AT A PRINT, FILL: as jobs/499_ou05_cs00.sh. Feed goals can be phantom (about 2%, item 0g).
# SCORES CHECKED: the feed's final score and half-time score (last row with status HT) are compared with af_fixtures where the fixture is held, and printed. The final score check also covers items 106 and 111, which use the same feed. Below 90% agreement stops the job. No HT row: HALF_TIME lines not traded, counted.
# LINES, fixed before any price is read. First settled print with feed minute T to T+4, one entry per game per runner per T:
#   OU45: T 46, 60, 75, total goals 0, 1, 2, 3: Over and Under, back and lay. PRE: first print T-15 to off, back and lay both.
#   DC: T 46, 60, 75. Home or Draw and Draw or Away: covered team 00, LEVEL, LEAD1, TRAIL1. Home or Away: 00, LEVEL, ONE (a goal apart). Back and lay. PRE: each of the three, back and lay.
#   HT: T 15, 25, 35, 40: The Draw at 0-0; the leader at one goal apart; back and lay; to the half-time score, so a goal after the entry settles at the result.
# SETTLE: to the result. One tick adverse, 2%, back stake 10, lay liability 10. Over 50 not traded, a back filling at 1.01 no bet, both counted. Halves: median market date.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,re,unicodedata,time,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); import creds
pd.set_option('display.width',230); pd.set_option('display.max_rows',150); pd.set_option('display.max_columns',30)
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
def klass(gf,ga):
    if gf==ga: return '00' if gf==0 else 'LEVEL'
    if gf-ga==1: return 'LEAD1'
    if ga-gf==1: return 'TRAIL1'
    return None
def dc_state(sel,h,a):
    """Feed score h-a at entry, from the side of a double chance runner."""
    if sel=='Home or Draw': return klass(h,a)
    if sel=='Draw or Away': return klass(a,h)
    if h==a: return '00' if h==0 else 'LEVEL'
    return 'ONE' if abs(h-a)==1 else None
def dc_won(sel,hg,ag):
    return hg>=ag if sel=='Home or Draw' else (ag>=hg if sel=='Draw or Away' else hg!=ag)
def ht_side(sel,hn,an):
    f=fold(sel)
    if f==fold(hn): return 'H'
    if f==fold(an): return 'A'
    return 'D' if sel=='The Draw' else None
def ht_line(sd,h,a):
    """HALF_TIME runner at feed score h-a: DRAW00, LEADER, or not traded."""
    if sd=='D': return 'DRAW00' if h==0 and a==0 else None
    if sd=='H': return 'LEADER' if h-a==1 else None
    return 'LEADER' if a-h==1 else None
def ht_won(sd,h,a): return h==a if sd=='D' else (h>a if sd=='H' else a>h)
def ht_score(status,sh,sa):
    """Score on the last row with status HT, or None."""
    idx=[i for i,s in enumerate(status) if s=='HT']
    return None if not idx else (int(sh[idx[-1]]),int(sa[idx[-1]]))
def fold(s): return re.sub(r"[^a-z0-9]","",unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower())
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
    for i in range(len(ts)):
        st=state_at(ts[i],ft,fm,fh,fa)
        if st is not None and T<=st[0]<T+5: return i,st[1],st[2]
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
assert abs(pnl('B',2.0,True)-10*0.99*0.98)<1e-9 and pnl('B',2.0,False)==-10.0 and np.isnan(pnl('B',1.02,True))
assert abs(pnl('L',6.0,False)-10/5.2*0.98)<1e-9 and pnl('L',6.0,True)==-10.0
assert dc_won('Home or Draw',1,1) and dc_won('Home or Draw',2,1) and not dc_won('Home or Draw',0,1)
assert dc_won('Draw or Away',0,0) and dc_won('Draw or Away',0,2) and not dc_won('Draw or Away',1,0)
assert dc_won('Home or Away',1,0) and dc_won('Home or Away',0,1) and not dc_won('Home or Away',1,1)
assert dc_state('Home or Draw',1,0)=='LEAD1' and dc_state('Draw or Away',1,0)=='TRAIL1' and dc_state('Home or Away',1,0)=='ONE' and dc_state('Home or Away',2,0) is None and dc_state('Home or Away',1,1)=='LEVEL' and dc_state('Draw or Away',0,0)=='00' and dc_state('Home or Draw',3,0) is None
assert ht_side('Csm Slatina','ACS Dumbravita','CSM Slatina')=='A' and ht_side('The Draw','X','Y')=='D' and ht_side('Other','X','Y') is None
assert ht_line('D',0,0)=='DRAW00' and ht_line('D',1,1) is None and ht_line('H',1,0)=='LEADER' and ht_line('A',1,0) is None and ht_line('A',0,1)=='LEADER' and ht_line('H',2,0) is None
assert ht_won('D',1,1) and not ht_won('D',1,0) and ht_won('H',1,0) and not ht_won('A',1,0) and ht_won('A',0,2)
assert ht_score(['1H','HT','HT','2H'],[0,1,1,2],[0,0,1,1])==(1,1) and ht_score(['1H','2H'],[0,1],[0,0]) is None     # last HT row; no HT row: None
_f=np.array([0.,100.,200.,300.,400.,500.]); _m=np.array([50.,55.,56.,60.,61.,62.]); _h=np.array([0,0,0,0,1,1]); _a=np.zeros(6,int)
assert first_in_window(np.array([150.]),55,_f,_m,_h,_a)==(0,0,0) and first_in_window(np.array([450.,650.]),60,_f,_m,_h,_a)==(1,1,0) and first_in_window(np.array([350.]),46,_f,_m,_h,_a) is None
_ts=np.array([0.,100.,500.]); _px=np.array([2.0,1.9,3.0]); assert fill(_ts,_px,0,'B')==1.9 and fill(_ts,_px,0,'L')==2.0 and fill(_ts,_px,2,'B')==3.0
_g=gate(np.array([1.0,0.5]*200),np.arange(400.0)); assert _g['PASS'] is True
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
HTF=pd.read_sql("""SELECT DISTINCT ON (fixture_id) fixture_id,score_home h,score_away a FROM goal_timeline WHERE captured_at>='2026-08-31' AND captured_at<'2026-10-03' AND status='HT' AND score_home IS NOT NULL AND score_away IS NOT NULL ORDER BY fixture_id,captured_at DESC""",con)
HTD={int(r.fixture_id):(int(r.h),int(r.a)) for r in HTF.itertuples()}
AF=pd.read_sql("SELECT fixture_id,hg,ag,ht_hg,ht_ag FROM af_fixtures WHERE kickoff>='2026-08-31' AND kickoff<'2026-10-03' AND hg IS NOT NULL",con)
CK=AF.merge(GT[['fixture_id','score_home','score_away']],on='fixture_id'); fa=((CK.hg==CK.score_home)&(CK.ag==CK.score_away)).mean()
CK['fh']=CK.fixture_id.map(lambda x:HTD.get(int(x),(None,None))[0]); CK['fa']=CK.fixture_id.map(lambda x:HTD.get(int(x),(None,None))[1]); H=CK[CK.fh.notna()&CK.ht_hg.notna()]; ha=((H.ht_hg==H.fh)&(H.ht_ag==H.fa)).mean()
print(f"== SCORE CHECK v af_fixtures: final agrees {fa:.4f} on {len(CK)} fixtures; half-time agrees {ha:.4f} on {len(H)} fixtures; feed HT rows for {len(HTD)} fixtures",flush=True)
if len(CK)<200 or len(H)<200 or fa<0.90 or ha<0.90: sys.exit("score check failed: feed scores cannot be used")
def match(ev,mt):
    h,_,a=ev.partition(' v '); H_,A_=norm(h),norm(a); e=[x for x in SC.get((H_,A_),[]) if 0<=(x[0]-mt).total_seconds()/60<=240]
    if len(e)==1: return e[0][1:]
    if e: return None
    lo=np.searchsorted(tt,np.datetime64(mt.tz_convert(None))); hi=np.searchsorted(tt,np.datetime64((mt+pd.Timedelta(minutes=240)).tz_convert(None)),side='right')
    return loose(H_,A_,[(r.H,r.A,(int(r.fixture_id),int(r.score_home),int(r.score_away))) for r in GT.iloc[lo:hi].itertuples()])
cur.execute("""SELECT DISTINCT market_id,market_type,event_name,market_time FROM bf_hist_other WHERE sport='Soccer' AND market_type IN ('HALF_TIME','DOUBLE_CHANCE','OVER_UNDER_45') AND market_time>='2026-09-01' AND market_time<'2026-10-02'""")
MK={}; SK=Counter()
for mid,mty,ev,mt in cur.fetchall():
    SK[f'{mty} markets']+=1; MK.setdefault((ev,pd.Timestamp(mt).tz_convert('UTC')),{})[mty]=mid
Games=[]
for (ev,mt),v in MK.items():
    m=match(ev,mt)
    if m is None: SK['event: no unique score']+=1; continue
    Games.append(dict(ev=ev,mt=mt,fx=m[0],hg=m[1],ag=m[2],**v))
print(f"events {len(MK)}, scored {len(Games)}, {dict(SK)}, {time.time()-T0:.0f}s",flush=True)
if len(Games)<500: sys.exit(f"only {len(Games)} games scored: a code fault, not a result")
rows=[]
def add(mk,tag,line,side,p,g,w):
    if p>50: SK['over 50, not traded']+=1; return
    v=pnl(side,p,w)
    if np.isnan(v): SK['back fills at 1.01, no bet']+=1; return
    rows.append((mk,tag,line,side,g['ev'],g['mt'].timestamp(),p,w,v))
OU={'Over 4.5 Goals':'OVER','Under 4.5 Goals':'UNDER'}; DC=('Home or Draw','Draw or Away','Home or Away')
for c in range(0,len(Games),300):
    sub=Games[c:c+300]
    F=pd.read_sql("SELECT fixture_id,captured_at,minute,score_home,score_away FROM goal_timeline WHERE fixture_id=ANY(%s) AND score_home IS NOT NULL AND score_away IS NOT NULL ORDER BY fixture_id,captured_at",con,params=([g['fx'] for g in sub],))
    F['tt']=secs(F.captured_at); F['mn']=pd.to_numeric(F.minute,errors='coerce'); FF={k:x for k,x in F.groupby('fixture_id')}
    ids=[g[k] for g in sub for k in ('HALF_TIME','DOUBLE_CHANCE','OVER_UNDER_45') if k in g]
    P=pd.read_sql("SELECT market_id,sel,ts,ltp::float8 ltp,inplay FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s) AND ltp>=1.01 AND ltp<1000",con,params=(ids,))
    P['tt']=secs(P.ts); P=P.drop_duplicates(['market_id','sel','tt']).sort_values('tt',kind='stable'); PX={k:x for k,x in P.groupby('market_id')}
    for g in sub:
        off=g['mt'].timestamp(); hn,_,an=g['ev'].partition(' v '); hn,an=hn.strip(),an.strip(); hg,ag=g['hg'],g['ag']
        fd=FF.get(g['fx']); fd=fd[fd.mn.notna()] if fd is not None else None; ok=fd is not None and len(fd)>=5
        if ok: ft,fm,fh,fa_=fd.tt.values,fd.mn.values,fd.score_home.values.astype(int),fd.score_away.values.astype(int)
        else: SK['feed thin, PRE only']+=1
        for mty in ('OVER_UNDER_45','DOUBLE_CHANCE','HALF_TIME'):
            if mty not in g or g[mty] not in PX: continue
            for s,y in PX[g[mty]].groupby('sel',sort=False):
                ipm=y.inplay.values.astype(bool); ts,px=y.tt.values,y.ltp.values; ti,pi=ts[ipm],px[ipm]
                pre=np.where((~ipm)&(ts>=off-900)&(ts<=off))[0]
                if mty=='OVER_UNDER_45':
                    if s not in OU: continue
                    w=(hg+ag>4.5)==(OU[s]=='OVER')
                    if len(pre):
                        for side in 'BL': add('OU45','PRE',OU[s],side,fill(ts,px,int(pre[0]),side),g,w)
                    if not ok: continue
                    for T in (46,60,75):
                        e=first_in_window(ti,T,ft,fm,fh,fa_)
                        if e is None or e[1]+e[2]>3: continue
                        for side in 'BL': add('OU45',f'T{T}',f'{OU[s]} G{e[1]+e[2]}',side,fill(ti,pi,e[0],side),g,w)
                elif mty=='DOUBLE_CHANCE':
                    if s not in DC: continue
                    w=dc_won(s,hg,ag); nm={'Home or Draw':'HD','Draw or Away':'DA','Home or Away':'HA'}[s]
                    if len(pre):
                        for side in 'BL': add('DC','PRE',nm,side,fill(ts,px,int(pre[0]),side),g,w)
                    if not ok: continue
                    for T in (46,60,75):
                        e=first_in_window(ti,T,ft,fm,fh,fa_)
                        if e is None: continue
                        cl=dc_state(s,e[1],e[2])
                        if cl is None: continue
                        for side in 'BL': add('DC',f'T{T}',f'{nm} {cl}',side,fill(ti,pi,e[0],side),g,w)
                else:
                    sd=ht_side(s,hn,an)
                    if sd is None or not ok: continue
                    hs=HTD.get(g['fx'])
                    if hs is None: SK['HT runner, no HT row, not traded']+=1; continue
                    for T in (15,25,35,40):
                        e=first_in_window(ti,T,ft,fm,fh,fa_)
                        if e is None: continue
                        ln=ht_line(sd,e[1],e[2])
                        if ln is None: continue
                        for side in 'BL': add('HT',f'T{T}',ln,side,fill(ti,pi,e[0],side),g,ht_won(sd,hs[0],hs[1]))
    print(f"  {min(c+300,len(Games))}/{len(Games)} rows {len(rows)} {time.time()-T0:.0f}s",flush=True)
con.close(); print("counts:",dict(sorted(SK.items())),flush=True)
R=pd.DataFrame(rows,columns=['mk','tag','line','side','ev','when','p','won','v'])
if R.empty: print("ERROR: no entries, so no verdict"); sys.exit(1)
print(f"\ndates {pd.Timestamp(R.when.min(),unit='s'):%Y-%m-%d} to {pd.Timestamp(R.when.max(),unit='s'):%Y-%m-%d}; distinct games {R.ev.nunique()}")
out=[]
for (mk,tag,line,side),d in R.groupby(['mk','tag','line','side']):
    r=gate(d.v.values.astype(float),d.when.values); fp=d.p.map(lambda q:step(q,-1)) if side=='B' else d.p.map(lambda q:step(q,1))
    out.append(dict(mk=mk,tag=tag,line=line,side=side,**r,games=d.ev.nunique(),won=d.won.mean(),imp=(1/fp).mean(),med_p=d.p.median()))
S=pd.DataFrame(out); print(f"\nlines {len(S)}, at n>=300: {(S.n>=300).sum()}")
print("\n== TOP 20 by t, n>=100\n",S[S.n>=100].sort_values('t',ascending=False).head(20).drop(columns=['n1','n2']).round(3).to_string(index=False))
print("\n== BOTTOM 8 by t, n>=100\n",S[S.n>=100].sort_values('t').head(8).drop(columns=['n1','n2']).round(3).to_string(index=False))
Y=S[S.PASS]; print(f"\n== SURVIVORS: {len(Y)} of {len(S)}\n",Y.round(3).to_string(index=False) if len(Y) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
