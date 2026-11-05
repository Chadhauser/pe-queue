#!/bin/bash
set -o pipefail
# 499_cs_scorelines (Finder 2026-11-05, queue items 114, 115, Finder's own, source d): correct score before the off per scoreline, Sep 2024 to Apr 2025 with Sep 2026 unseen; current scoreline in-play and HALF_TIME_SCORE on Sep 2026. Rules written in the queue before any price was read. The number 499 is reused with a new slug: 450-499 are all taken.
# 114 ENTRY first print T-15 to the off, filled at the worse of it and the next print within 120 s (back the lower, lay the higher), as jobs/499_sep_tape_rest.sh. Over 200 not traded, a back filling at 1.01 no bet, both counted. One entry per game per line.
# 114 RESULT from af_fixtures (exact team names first, loose match otherwise, kick-off within 3 h of the market time) or fd_matches (same date, loose match). If both are held and disagree, the game is dropped and counted. A final print is never used. Games outside those two sources are not scored, so the sample is the leagues they cover, not all 49,700 markets.
# 114 GOAL LEVEL share of the book on scorelines with 2 or fewer goals, at the entry prints; tercile cuts from the first half by date. Sep 2026: same lines, scored from goal_timeline, read only as unseen.
# 115 FILL AND STATE as jobs/499_sep_tape_rest.sh: first settled print at feed minute T to T+4, a score unchanged for the 120 s before it. To the result; HALF_TIME_SCORE to the last HT feed row, no HT row not traded, counted.
# ALL LTP, one tick adverse, 2%, back stake £10, lay liability £10, so a pass is an upper bound. Halves by median market date.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,re,time,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,back_settle,lay_settle,tstat,passes,norm,loose
import lib_cand; lib_cand._checks()
pd.set_option('display.width',240); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',30)
T0=time.time()
def pnl(side,p,won):
    if side=='B':
        a=step(p,-1)
        return np.nan if a<=1.01 else back_settle(a,won)
    return lay_settle(step(p,1),won)
def cs_won(s,hg,ag):
    """Correct score runner v the final score. Listed runners are 0-3 each way; the three Any Others take the rest."""
    s=s.strip()
    if s=='Any Other Home Win': return hg>ag and hg>3
    if s=='Any Other Away Win': return ag>hg and ag>3
    if s=='Any Other Draw': return hg==ag and hg>3
    m=re.fullmatch(r'(\d+) - (\d+)',s)
    return None if m is None else (int(m[1])==hg and int(m[2])==ag)
def ht_won(s,hg,ag):
    """HALF_TIME_SCORE runner v the half-time score. Listed 0-2 each way, 'Any Unquoted' the rest."""
    s=s.strip()
    if s.lower()=='any unquoted': return hg>2 or ag>2
    m=re.fullmatch(r'(\d+) - (\d+)',s)
    return None if m is None else (int(m[1])==hg and int(m[2])==ag)
def goals_in(s):
    m=re.fullmatch(r'(\d+) - (\d+)',s.strip()); return None if m is None else int(m[1])+int(m[2])
def fill(ts,px,i,side):
    p=float(px[i])
    if i+1<len(ts) and ts[i+1]-ts[i]<=120: p=max(p,float(px[i+1])) if side=='L' else min(p,float(px[i+1]))
    return p
def state_at(ts,ft,fm,fh,fa):
    i=np.searchsorted(ft,ts,side='right')-1; j=np.searchsorted(ft,ts-120,side='right')-1
    if i<0 or j<0 or ts-ft[i]>300: return None
    if (fh[j:i+1]!=fh[j]).any() or (fa[j:i+1]!=fa[j]).any(): return None
    return fm[i],int(fh[j]),int(fa[j])
def first_in_window(ts,T,ft,fm,fh,fa):
    for i in range(len(ts)):
        st=state_at(ts[i],ft,fm,fh,fa)
        if st is not None and T<=st[0]<T+5: return i,st[1],st[2]
    return None
def secs(col): return (pd.to_datetime(col,utc=True)-pd.Timestamp('1970-01-01',tz='UTC'))/pd.Timedelta(seconds=1)
def gate(v,when):
    m=np.isfinite(v); v=v[m]; when=when[m]
    if len(v)==0: return dict(n=0,mean=np.nan,t=0.0,n1=0,h1=np.nan,n2=0,h2=np.nan,PASS=False)
    md=np.median(when); a=v[when<md]; b=v[when>=md]; t=tstat(v)
    return dict(n=len(v),mean=v.mean(),t=t,n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,PASS=passes(len(v),len(a),len(b),t,a.mean() if len(a) else -1,b.mean() if len(b) else -1,v.mean()))
# known answers, worked by hand
assert abs(pnl('B',2.0,True)-10*0.99*0.98)<1e-9 and pnl('B',2.0,False)==-10.0 and np.isnan(pnl('B',1.02,True))
assert abs(pnl('L',6.0,False)-10/5.2*0.98)<1e-9 and pnl('L',6.0,True)==-10.0
assert cs_won('2 - 1',2,1) and not cs_won('2 - 1',1,2) and cs_won('0 - 0',0,0) and cs_won('Any Other Home Win',4,1) and not cs_won('Any Other Home Win',3,1) and cs_won('Any Other Away Win',0,4) and not cs_won('Any Other Away Win',4,0) and cs_won('Any Other Draw',4,4) and not cs_won('Any Other Draw',3,3) and cs_won('Foo',1,1) is None
assert sum(cs_won(s,5,2) for s in ['Any Other Home Win','Any Other Away Win','Any Other Draw','3 - 2'])==1    # a final score wins exactly one runner
assert ht_won('Any Unquoted ',3,0) and not ht_won('any unquoted',2,2) and ht_won('1 - 0',1,0) and not ht_won('1 - 0',0,1) and ht_won('x',0,0) is None
assert goals_in('2 - 1')==3 and goals_in('Any Other Draw') is None
_ts=np.array([0.,100.,500.]); _px=np.array([2.0,1.9,3.0]); assert fill(_ts,_px,0,'B')==1.9 and fill(_ts,_px,0,'L')==2.0 and fill(_ts,_px,2,'B')==3.0
_f=np.array([0.,100.,200.,300.,400.,500.]); _m=np.array([50.,55.,56.,60.,61.,62.]); _h=np.array([0,0,0,0,1,1]); _a=np.zeros(6,int)
assert first_in_window(np.array([150.]),55,_f,_m,_h,_a)==(0,0,0) and first_in_window(np.array([450.,650.]),60,_f,_m,_h,_a)==(1,1,0) and first_in_window(np.array([350.]),46,_f,_m,_h,_a) is None
_g=gate(np.array([1.0,0.5]*200),np.arange(400.0)); assert _g['PASS'] is True
print("known-answer checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
# ---------- results for 2024-25
AF=pd.read_sql("SELECT fixture_id,kickoff,home,away,hg,ag FROM af_fixtures WHERE status='FT' AND hg IS NOT NULL AND kickoff>='2024-08-25' AND kickoff<'2025-05-10'",con)
AF['t']=pd.to_datetime(AF.kickoff,utc=True); AF['H']=AF.home.map(norm); AF['A']=AF.away.map(norm); AF=AF.sort_values('t').reset_index(drop=True); at=AF.t.values.astype('datetime64[ns]')
FD=pd.read_sql("SELECT date,home,away,fthg,ftag FROM fd_matches WHERE fthg IS NOT NULL AND date>='2024-08-25' AND date<'2025-05-10'",con)
FD['H']=FD.home.map(norm); FD['A']=FD.away.map(norm); FDD=defaultdict(list)
for r in FD.itertuples(): FDD[r.date].append((r.H,r.A,(int(r.fthg),int(r.ftag))))
print(f"results held: af {len(AF)}, fd {len(FD)}; {time.time()-T0:.0f}s",flush=True)
def res_af(H,A,mt):
    lo=np.searchsorted(at,np.datetime64((mt-pd.Timedelta(hours=3)).tz_convert(None))); hi=np.searchsorted(at,np.datetime64((mt+pd.Timedelta(hours=3)).tz_convert(None)),side='right')
    return loose(H,A,[(r.H,r.A,(int(r.hg),int(r.ag))) for r in AF.iloc[lo:hi].itertuples()])
def res_fd(H,A,mt):
    return loose(H,A,FDD.get(mt.date(),[])) or None
SK=Counter(); rows=[]
def add(mk,tag,line,side,p,ev,when,w,cap=200):
    if p>cap: SK['over cap, not traded']+=1; return
    v=pnl(side,p,w)
    if np.isnan(v): SK['back fills at 1.01, no bet']+=1; return
    rows.append((mk,tag,line,side,ev,when,p,w,v))
def month_pre(lo,hi):
    """First two prints T-15 to the off, per runner, for CS markets in a month: never reads past the off."""
    return pd.read_sql("""SELECT market_id,event_name,market_time,sel,ts,ltp::float8 ltp FROM (
      SELECT market_id,event_name,market_time,sel,ts,ltp,row_number() OVER (PARTITION BY market_id,sel ORDER BY ts) rn FROM bf_hist_other
      WHERE sport='Soccer' AND market_type='CORRECT_SCORE' AND market_time>=%s AND market_time<%s AND NOT inplay AND ts>=market_time-interval '15 min' AND ts<=market_time AND ltp>=1.01 AND ltp<1000) z WHERE rn<=2""",con,params=(lo,hi))
def score_month(P,resolver,tag):
    P['tt']=secs(P.ts); P=P.sort_values(['market_id','sel','tt']); out=[]; n=0
    for (mid,ev,mt),g in P.groupby(['market_id','event_name','market_time']):
        mt=pd.Timestamp(mt).tz_convert('UTC'); r=resolver(ev,mt)
        if r is None: SK[f'{tag} market: no result']+=1; continue
        SK[f'{tag} market: scored']+=1; hg,ag=r; n+=1; bk={}; x=[]
        for s,y in g.groupby('sel',sort=False):
            won=cs_won(s,hg,ag)
            if won is None: SK['unknown runner']+=1; continue
            ts,px=y.tt.values,y.ltp.values; x.append((s,won,fill(ts,px,0,'B'),fill(ts,px,0,'L'))); bk[s]=float(px[0])
        tot=sum(1/v for v in bk.values()); low=sum(1/v for s,v in bk.items() if goals_in(s) is not None and goals_in(s)<=2)
        lvl=low/tot if tot>0 and len(bk)>=12 else None
        out.append((ev,mt.timestamp(),lvl,x))
    return out
def res1(ev,mt):
    h,_,a=ev.partition(' v '); H,A=norm(h),norm(a); x=res_af(H,A,mt); y=res_fd(H,A,mt)
    if x is not None and y is not None and x!=y: SK['af and fd disagree, dropped']+=1; return None
    if x is not None and y is not None: SK['af and fd agree']+=1
    return x if x is not None else y
Sc=[]
for lo,hi in zip(pd.date_range('2024-08-01','2025-05-01',freq='MS').strftime('%Y-%m-%d'),pd.date_range('2024-09-01','2025-06-01',freq='MS').strftime('%Y-%m-%d')):
    P=month_pre(lo,hi)
    if len(P): Sc+=score_month(P,res1,'24-25')
    print(f"  {lo}: rows {len(P)}, scored so far {len(Sc)}, {time.time()-T0:.0f}s",flush=True)
if len(Sc)<3000: print(dict(SK)); sys.exit(f"only {len(Sc)} scored: a code fault, not a result")
# a scored game must win exactly one runner, or the settlement is wrong
one=Counter(sum(1 for s,w,_,_ in x if w) for _,_,_,x in Sc); print("runners won per scored game (books can lack a runner, so 0 is possible, more than 1 never):",dict(one),flush=True); assert max(one)<=1
when=np.array([z[1] for z in Sc]); med=np.median(when); L1=[z[2] for z in Sc if z[1]<med and z[2] is not None]; c1,c2=np.quantile(L1,[1/3,2/3])
print(f"goal-level cuts from first half: {c1:.3f} {c2:.3f}; median date {pd.Timestamp(med,unit='s'):%Y-%m-%d}",flush=True)
def lv(l): return None if l is None else ('LOWG' if l>=c2 else 'HIGHG' if l<=c1 else 'MIDG')
def emit(Sc,mk):
    for ev,when,l,x in Sc:
        for s,w,pb,pl in x:
            for line in [s]+([f"{s} {lv(l)}"] if lv(l) else []):
                add(mk,'PRE',line,'B',pb,ev,when,w); add(mk,'PRE',line,'L',pl,ev,when,w)
emit(Sc,'CS')
# ---------- Sep 2026, unseen for 114, whole of 115
GT=pd.read_sql("""SELECT DISTINCT ON (fixture_id) fixture_id,home_team,away_team,captured_at,minute,score_home,score_away,status FROM goal_timeline WHERE captured_at>='2026-08-31' AND captured_at<'2026-10-03' AND score_home IS NOT NULL AND score_away IS NOT NULL ORDER BY fixture_id,captured_at DESC""",con)
GT['t']=pd.to_datetime(GT.captured_at,utc=True); GT['mn']=pd.to_numeric(GT.minute,errors='coerce')
GT=GT[GT.status.isin(['FT','AET','PEN','Match Finished','FINISHED'])|(GT.mn>=88)].sort_values('t').reset_index(drop=True)
GT['H']=GT.home_team.map(norm); GT['A']=GT.away_team.map(norm); tt=GT.t.values.astype('datetime64[ns]')
HTF=pd.read_sql("""SELECT DISTINCT ON (fixture_id) fixture_id,score_home h,score_away a FROM goal_timeline WHERE captured_at>='2026-08-31' AND captured_at<'2026-10-03' AND status='HT' AND score_home IS NOT NULL AND score_away IS NOT NULL ORDER BY fixture_id,captured_at DESC""",con)
HTD={int(r.fixture_id):(int(r.h),int(r.a)) for r in HTF.itertuples()}
def match26(ev,mt):
    h,_,a=ev.partition(' v '); lo=np.searchsorted(tt,np.datetime64(mt.tz_convert(None))); hi=np.searchsorted(tt,np.datetime64((mt+pd.Timedelta(minutes=240)).tz_convert(None)),side='right')
    return loose(norm(h),norm(a),[(r.H,r.A,(int(r.fixture_id),int(r.score_home),int(r.score_away))) for r in GT.iloc[lo:hi].itertuples()])
cur.execute("""SELECT DISTINCT market_id,market_type,event_name,market_time FROM bf_hist_other WHERE sport='Soccer' AND market_type IN ('CORRECT_SCORE','HALF_TIME_SCORE') AND market_time>='2026-09-01' AND market_time<'2026-10-02'""")
MK={}
for mid,mty,ev,mt in cur.fetchall(): MK.setdefault((ev,pd.Timestamp(mt).tz_convert('UTC')),{})[mty]=mid
Games=[]
for (ev,mt),v in MK.items():
    m=match26(ev,mt)
    if m is None: SK['26 event: no score']+=1; continue
    Games.append(dict(ev=ev,mt=mt,fx=m[0],hg=m[1],ag=m[2],**v))
print(f"Sep 2026 events {len(MK)}, scored {len(Games)}, {time.time()-T0:.0f}s",flush=True)
if len(Games)<500: sys.exit("too few Sep 2026 games: a code fault")
CURR={'1 - 0','0 - 1','1 - 1','2 - 0','0 - 2','2 - 1','1 - 2'}; HTCUR={'0 - 0','1 - 0','0 - 1'}
Sc26=[]
for c in range(0,len(Games),300):
    sub=Games[c:c+300]
    F=pd.read_sql("SELECT fixture_id,captured_at,minute,score_home,score_away FROM goal_timeline WHERE fixture_id=ANY(%s) AND score_home IS NOT NULL AND score_away IS NOT NULL ORDER BY fixture_id,captured_at",con,params=([g['fx'] for g in sub],))
    F['tt']=secs(F.captured_at); F['mn']=pd.to_numeric(F.minute,errors='coerce'); FF={k:x for k,x in F.groupby('fixture_id')}
    ids=[g[k] for g in sub for k in ('CORRECT_SCORE','HALF_TIME_SCORE') if k in g]
    P=pd.read_sql("SELECT market_id,sel,ts,ltp::float8 ltp,inplay FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s) AND ltp>=1.01 AND ltp<1000",con,params=(ids,))
    P['tt']=secs(P.ts); P=P.drop_duplicates(['market_id','sel','tt']).sort_values('tt',kind='stable'); PX={k:x for k,x in P.groupby('market_id')}
    for g in sub:
        off=g['mt'].timestamp(); hg,ag=g['hg'],g['ag']; fd=FF.get(g['fx']); fd=fd[fd.mn.notna()] if fd is not None else None; ok=fd is not None and len(fd)>=5
        if ok: ft,fm,fh,fa=fd.tt.values,fd.mn.values,fd.score_home.values.astype(int),fd.score_away.values.astype(int)
        hs=HTD.get(g['fx'])
        if 'CORRECT_SCORE' in g and g['CORRECT_SCORE'] in PX:
            bk={}; xs=[]
            for s,y in PX[g['CORRECT_SCORE']].groupby('sel',sort=False):
                won=cs_won(s,hg,ag)
                if won is None: continue
                ipm=y.inplay.values.astype(bool); ts,px=y.tt.values,y.ltp.values; pre=np.where((~ipm)&(ts>=off-900)&(ts<=off))[0]
                if len(pre):
                    # the fill may only use a pre-off print, as in 2024-25
                    tp,pp=ts[pre],px[pre]; xs.append((s,won,fill(tp,pp,0,'B'),fill(tp,pp,0,'L'))); bk[s]=float(pp[0])
                if ok and s.strip() in CURR:
                    ti,pi=ts[ipm],px[ipm]
                    for T in (60,70,80):
                        e=first_in_window(ti,T,ft,fm,fh,fa)
                        if e is None or f"{e[1]} - {e[2]}"!=s.strip(): continue
                        for side in 'BL': add('CSIP',f'T{T}',s.strip(),side,fill(ti,pi,e[0],side),g['ev'],off,won)
            if bk:
                tot=sum(1/v for v in bk.values()); low=sum(1/v for s,v in bk.items() if goals_in(s) is not None and goals_in(s)<=2)
                Sc26.append((g['ev'],off,low/tot if len(bk)>=12 else None,xs))
        if 'HALF_TIME_SCORE' in g and g['HALF_TIME_SCORE'] in PX:
            if hs is None: SK['HT market, no HT row, not traded']+=1; continue
            for s,y in PX[g['HALF_TIME_SCORE']].groupby('sel',sort=False):
                won=ht_won(s,hs[0],hs[1])
                if won is None: SK['unknown HT runner']+=1; continue
                lab='Any Unquoted' if s.strip().lower()=='any unquoted' else s.strip()
                ipm=y.inplay.values.astype(bool); ts,px=y.tt.values,y.ltp.values; pre=np.where((~ipm)&(ts>=off-900)&(ts<=off))[0]
                if len(pre):
                    tp,pp=ts[pre],px[pre]
                    add('HTS','PRE',lab,'B',fill(tp,pp,0,'B'),g['ev'],off,won); add('HTS','PRE',lab,'L',fill(tp,pp,0,'L'),g['ev'],off,won)
                if ok and lab in HTCUR:
                    ti,pi=ts[ipm],px[ipm]
                    for T in (25,35):
                        e=first_in_window(ti,T,ft,fm,fh,fa)
                        if e is None or f"{e[1]} - {e[2]}"!=lab: continue
                        for side in 'BL': add('HTS',f'T{T}',lab,side,fill(ti,pi,e[0],side),g['ev'],off,won)
    print(f"  {min(c+300,len(Games))}/{len(Games)} rows {len(rows)} {time.time()-T0:.0f}s",flush=True)
con.close()
emit(Sc26,'CS26')
print("counts:",dict(sorted(SK.items())),flush=True)
R=pd.DataFrame(rows,columns=['mk','tag','line','side','ev','when','p','won','v'])
out=[]
for (mk,tag,line,side),d in R.groupby(['mk','tag','line','side']):
    r=gate(d.v.values.astype(float),d.when.values); fp=d.p.map(lambda q:step(q,-1)) if side=='B' else d.p.map(lambda q:step(q,1))
    out.append(dict(mk=mk,tag=tag,line=line,side=side,**r,games=d.ev.nunique(),won=d.won.mean(),imp=(1/fp).mean(),med_p=d.p.median()))
S=pd.DataFrame(out)
cs=S[S.mk=='CS']; print(f"\ndates CS {pd.Timestamp(R[R.mk=='CS'].when.min(),unit='s'):%Y-%m-%d} to {pd.Timestamp(R[R.mk=='CS'].when.max(),unit='s'):%Y-%m-%d}; games {R[R.mk=='CS'].ev.nunique()}; lines {len(cs)}, n>=300 {(cs.n>=300).sum()}")
print("\n== 114 TOP 15 by t, n>=150\n",cs[cs.n>=150].sort_values('t',ascending=False).head(15).drop(columns=['n1','n2']).round(3).to_string(index=False))
print("\n== 114 every scoreline, all games\n",cs[~cs.line.str.contains('G$')].sort_values(['side','line']).drop(columns=['n1','n2','PASS']).round(3).to_string(index=False))
print("\n== 114 BOTTOM 6\n",cs[cs.n>=150].sort_values('t').head(6).drop(columns=['n1','n2']).round(3).to_string(index=False))
c26=S[S.mk=='CS26'].set_index(['line','side']); sel=cs[(cs.t>=2)&(cs.n>=150)]
print("\n== 114 UNSEEN, every line with t>=2 on 2024-25, unchanged, on Sep 2026")
print(pd.DataFrame([dict(line=r.line,side=r.side,n24=r.n,per24=r.mean,t24=r.t,n26=c26.n.get((r.line,r.side),0),per26=c26['mean'].get((r.line,r.side),np.nan),t26=c26.t.get((r.line,r.side),np.nan)) for r in sel.itertuples()]).round(3).to_string(index=False) if len(sel) else "none")
o=S[S.mk.isin(['CSIP','HTS'])]; print(f"\n== 115 lines {len(o)}, n>=300 {(o.n>=300).sum()}; TOP 15 by t, n>=100\n",o[o.n>=100].sort_values('t',ascending=False).head(15).drop(columns=['n1','n2']).round(3).to_string(index=False))
print("\n== 115 BOTTOM 6\n",o[o.n>=100].sort_values('t').head(6).drop(columns=['n1','n2']).round(3).to_string(index=False))
Y=S[S.PASS&S.mk.isin(['CS','CSIP','HTS'])]; print(f"\n== SURVIVORS (Sep 2026 CS26 is the check, not a gate): {len(Y)} of {len(cs)+len(o)}\n",Y.round(3).to_string(index=False) if len(Y) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
