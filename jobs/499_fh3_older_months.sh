#!/bin/bash
set -o pipefail
# 499_fh3_older_months (Finder 2026-11-05, queue item 138, from item 124, jobs/499_long_goal_lines.sh, jobs/499_cs_scorelines.sh): three or more first-half goals overpriced, on Jun-Aug 2026, months that did not choose the lines (both from Sep 2026). Read only. Rule in the queue before any Jun-Aug price was read, no new cuts.
# LINE A: FIRST_HALF_GOALS_25, Over runner, first in-play print at feed minute 15 to 19 with a score unchanged over the previous 120 s, total 0, lay. LINE B: HALF_TIME_SCORE, 'Any Unquoted', first non-in-play print T-15 min to the off, lay. Worse of that print and the next within 120 s, one tick adverse, 2%, £10 liability, hold to the half-time score from the last HT feed row; no HT row not traded, counted. Over 200 not traded, counted.
# The two lines are the same event on the same games: one lead, not two. REGRESSION: Sep 2026 must return A n 1,558 +0.135 and B n 871 +0.166; that window chose the lines and is not evidence. Prints only: a pass is an upper bound.
# REGRESSION RESULT 2026-11-05: A n 1,823 +0.142, B n 1,001 +0.117, not the figures above, as Sep 2026 grew about 17% after those were read; jobs/499_long_goal_lines.sh and jobs/499_cs_scorelines.sh on the same data return the same n, per10, t, h1 and h2, so the code agrees.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,lay_settle,tstat,passes,norm,loose
import lib_cand; lib_cand._checks()
T0=time.time()
def fill(ts,px,i):
    p=float(px[i])
    if i+1<len(ts) and ts[i+1]-ts[i]<=120: p=max(p,float(px[i+1]))
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
def unq_won(hg,ag): return hg>2 or ag>2
# known answers, worked by hand. Lay 21 -> 22 fill, stake 10/21=0.476, wins 0.4667; loses -10.
assert abs(lay_settle(step(21.0,1),False)-10/21*.98)<1e-9 and lay_settle(step(21.0,1),True)==-10.0
assert unq_won(3,0) and unq_won(0,3) and not unq_won(2,2) and not unq_won(0,0)
assert fill(np.array([0.,60.]),np.array([20.,22.]),0)==22.0 and fill(np.array([0.,200.]),np.array([20.,22.]),0)==20.0
_f=np.array([0.,100.,200.,300.,400.,500.]); _m=np.array([10.,15.,16.,18.,19.,20.]); _h=np.array([0,0,0,0,1,1]); _a=np.zeros(6,int)
assert first_in_window(np.array([150.]),15,_f,_m,_h,_a)==(0,0,0)        # minute 15, 0-0 for 120 s before
assert first_in_window(np.array([450.]),15,_f,_m,_h,_a) is None          # goal inside the previous 120 s: state not settled, no fill
print("known-answer checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
def run(FROM,TO,label):
    SK=Counter(); rows=[]
    lo_=str(pd.Timestamp(FROM)-pd.Timedelta(days=1))[:10]; hi_=str(pd.Timestamp(TO)+pd.Timedelta(days=2))[:10]
    GT=pd.read_sql(f"SELECT DISTINCT ON (fixture_id) fixture_id,home_team,away_team,captured_at,minute,score_home,score_away,status FROM goal_timeline WHERE captured_at>='{lo_}' AND captured_at<'{hi_}' AND score_home IS NOT NULL AND score_away IS NOT NULL ORDER BY fixture_id,captured_at DESC",con)
    GT['t']=pd.to_datetime(GT.captured_at,utc=True); GT['mn']=pd.to_numeric(GT.minute,errors='coerce')
    GT=GT[GT.status.isin(['FT','AET','PEN','Match Finished','FINISHED'])|(GT.mn>=88)].sort_values('t').reset_index(drop=True)
    GT['H']=GT.home_team.map(norm); GT['A']=GT.away_team.map(norm); tt=GT.t.values.astype('datetime64[ns]')
    HTF=pd.read_sql(f"SELECT DISTINCT ON (fixture_id) fixture_id,score_home h,score_away a FROM goal_timeline WHERE captured_at>='{lo_}' AND captured_at<'{hi_}' AND status='HT' AND score_home IS NOT NULL AND score_away IS NOT NULL ORDER BY fixture_id,captured_at DESC",con)
    HTD={int(r.fixture_id):(int(r.h),int(r.a)) for r in HTF.itertuples()}
    print(f"{label}: finished fixtures on goal_timeline {len(GT)}, with an HT row {len(HTD)}",flush=True)
    cur.execute(f"SELECT DISTINCT market_id,market_type,event_name,market_time FROM bf_hist_other WHERE sport='Soccer' AND market_type IN ('FIRST_HALF_GOALS_25','HALF_TIME_SCORE') AND market_time>='{FROM}' AND market_time<'{TO}'")
    MK={}
    for mid,mty,ev,mt in cur.fetchall(): SK[mty+' markets']+=1; MK.setdefault((ev,pd.Timestamp(mt).tz_convert('UTC')),{})[mty]=mid
    Games=[]
    for (ev,mt),v in MK.items():
        h,_x,a=ev.partition(' v '); lo=np.searchsorted(tt,np.datetime64(mt.tz_convert(None))); hi=np.searchsorted(tt,np.datetime64((mt+pd.Timedelta(minutes=240)).tz_convert(None)),side='right')
        m=loose(norm(h),norm(a),[(r.H,r.A,int(r.fixture_id)) for r in GT.iloc[lo:hi].itertuples()])
        if m is None: SK['event: no score']+=1; continue
        Games.append(dict(ev=ev,mt=mt,fx=m,mk=v))
    print(f"  events {len(MK)}, scored {len(Games)}, {time.time()-T0:.0f}s",flush=True)
    for c in range(0,len(Games),300):
        sub=Games[c:c+300]
        F=pd.read_sql("SELECT fixture_id,captured_at,minute,score_home,score_away FROM goal_timeline WHERE fixture_id=ANY(%s) AND score_home IS NOT NULL AND score_away IS NOT NULL ORDER BY fixture_id,captured_at",con,params=([g['fx'] for g in sub],))
        F['tt']=secs(F.captured_at); F['mn']=pd.to_numeric(F.minute,errors='coerce'); FF={k:x for k,x in F.groupby('fixture_id')}
        P=pd.read_sql("SELECT market_id,sel,ts,ltp::float8 ltp,inplay FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s) AND ltp>=1.01 AND ltp<1000",con,params=([v for g in sub for v in g['mk'].values()],))
        P['tt']=secs(P.ts); P=P.drop_duplicates(['market_id','sel','tt']).sort_values('tt',kind='stable'); PX={k:x for k,x in P.groupby('market_id')}
        for g in sub:
            off=g['mt'].timestamp(); hs=HTD.get(g['fx']); fd=FF.get(g['fx']); fd=fd[fd.mn.notna()] if fd is not None else None; ok=fd is not None and len(fd)>=5
            if ok: ft,fm,fh,fa=fd.tt.values,fd.mn.values,fd.score_home.values.astype(int),fd.score_away.values.astype(int)
            for mty,mid in g['mk'].items():
                if mid not in PX: continue
                if hs is None: SK[mty+': no HT row, not traded']+=1; continue
                for s,y in PX[mid].groupby('sel',sort=False):
                    ipm=y.inplay.values.astype(bool); ts,px=y.tt.values,y.ltp.values
                    if mty=='HALF_TIME_SCORE':
                        if s.strip().lower()!='any unquoted': continue
                        pre=np.where((~ipm)&(ts>=off-900)&(ts<=off))[0]
                        if not len(pre): continue
                        p=fill(ts[pre],px[pre],0); w=unq_won(*hs); L='B HTS PRE Any Unquoted lay'
                    else:
                        if not str(s).strip().lower().startswith('over'): continue
                        if not ok: continue
                        ti,pi=ts[ipm],px[ipm]; e=first_in_window(ti,15,ft,fm,fh,fa)
                        if e is None or e[1]+e[2]!=0: continue
                        p=fill(ti,pi,e[0]); w=sum(hs)>2.5; L='A FH25 T15 Over 0-0 lay'
                    if p>200: SK['over 200, not traded']+=1; continue
                    rows.append((L,g['ev'],off,p,w,lay_settle(step(p,1),w)))
    print('  counted:',dict(sorted(SK.items())),flush=True)
    R=pd.DataFrame(rows,columns='L ev when p won v'.split()); res={}
    for L in ('A FH25 T15 Over 0-0 lay','B HTS PRE Any Unquoted lay'):
        x=R[R.L==L] if len(R) else R
        if not len(x): print(f"  {L}: n 0"); res[L]=False; continue
        md=np.median(x.when.values); a=x[x.when<md].v; b=x[x.when>=md].v; n=len(x); t=tstat(x.v.values); ok=passes(n,len(a),len(b),t,a.mean() if len(a) else -1,b.mean() if len(b) else -1,x.v.mean())
        print(f"  {L:28s} n {n:5d} games {x.ev.nunique():5d} per10 {x.v.mean():+.3f} t {t:5.2f} h1 {a.mean() if len(a) else float('nan'):+.3f} (n {len(a)}) h2 {b.mean() if len(b) else float('nan'):+.3f} (n {len(b)}) won {x.won.mean():.3f} implied {(1/x.p.map(lambda q:step(q,1))).mean():.3f} PASS {ok}",flush=True); res[L]=ok
        for k,y in x.assign(mo=pd.to_datetime(x.when,unit='s').dt.strftime('%Y-%m')).groupby('mo'): print(f"      {k} n {len(y)} per10 {y.v.mean():+.3f} t {tstat(y.v.values):.2f}")
    return res
print("\n== REGRESSION, Sep 2026, chose the lines, NOT evidence: A n 1,558 +0.135, B n 871 +0.166",flush=True)
run('2026-09-01','2026-10-02','Sep')
print("\n== UNSEEN, Jun-Aug 2026",flush=True)
Z=run('2026-06-01','2026-09-01','Jun-Aug')
print("\n== SURVIVORS (standard bar)"); S=[k for k,v in Z.items() if v]; print(S if S else "none"); print(f"done {time.time()-T0:.0f}s")
PY
