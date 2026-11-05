#!/bin/bash
set -o pipefail
# 499_ou15_00_t75_unseen (Finder 2026-11-05, queue item 119, Finder's own, source a): lay Over 1.5 at 0-0 at 75' on Sep 2026, the tape that did not suggest it. Rule fixed in the queue before these prices were read. Read only. The number 499 is reused with a new slug: 450-499 are all taken.
# GAMES, STATE AT A PRINT, FILL: as jobs/499_sep_tape_rest.sh, whose first_in_window, state_at and fill are copied unchanged. To the result, so nothing is dropped. One tick adverse, 2%, £10 risk.
# T75 lay Over is the line under test. T70, T80 and back Under are printed as neighbours and cannot pass.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,warnings,psycopg2,pandas as pd,numpy as np
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,back_settle,lay_settle,tstat,passes,norm,loose
import lib_cand; lib_cand._checks()
pd.set_option('display.width',220); pd.set_option('display.max_rows',100); pd.set_option('display.max_columns',30)
T0=time.time()
def pnl(side,p,won):
    if side=='B':
        a=step(p,-1)
        return np.nan if a<=1.01 else back_settle(a,won)
    return lay_settle(step(p,1),won)
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
# known answers, worked by hand
assert abs(pnl('L',11.0,False)-10/10.5*0.98)<1e-9 and pnl('L',11.0,True)==-10.0     # 11.0 one tick adverse is 11.5, stake 10/10.5
assert abs(pnl('B',1.10,True)-10*0.09*0.98)<1e-9 and pnl('B',1.10,False)==-10.0 and np.isnan(pnl('B',1.02,True))
_f=np.array([0.,100.,200.,300.,400.,500.]); _m=np.array([50.,55.,56.,60.,61.,62.]); _h=np.array([0,0,0,0,1,1]); _a=np.zeros(6,int)
assert first_in_window(np.array([150.]),55,_f,_m,_h,_a)==(0,0,0) and first_in_window(np.array([350.]),46,_f,_m,_h,_a) is None
print("known-answer checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
GT=pd.read_sql("""SELECT DISTINCT ON (fixture_id) fixture_id,home_team,away_team,captured_at,minute,score_home,score_away,status FROM goal_timeline WHERE captured_at>='2026-08-31' AND captured_at<'2026-10-03' AND score_home IS NOT NULL AND score_away IS NOT NULL ORDER BY fixture_id,captured_at DESC""",con)
GT['t']=pd.to_datetime(GT.captured_at,utc=True); GT['mn']=pd.to_numeric(GT.minute,errors='coerce')
GT=GT[GT.status.isin(['FT','AET','PEN','Match Finished','FINISHED'])|(GT.mn>=88)].sort_values('t').reset_index(drop=True)
GT['H']=GT.home_team.map(norm); GT['A']=GT.away_team.map(norm); tt=GT.t.values.astype('datetime64[ns]')
def match(ev,mt):
    h,_,a=ev.partition(' v '); lo=np.searchsorted(tt,np.datetime64(mt.tz_convert(None))); hi=np.searchsorted(tt,np.datetime64((mt+pd.Timedelta(minutes=240)).tz_convert(None)),side='right')
    return loose(norm(h),norm(a),[(r.H,r.A,(int(r.fixture_id),int(r.score_home),int(r.score_away))) for r in GT.iloc[lo:hi].itertuples()])
cur.execute("""SELECT DISTINCT market_id,event_name,market_time FROM bf_hist_other WHERE sport='Soccer' AND market_type='OVER_UNDER_15' AND market_time>='2026-09-01' AND market_time<'2026-10-02'""")
Games=[]; nomatch=0; allm=cur.fetchall()
for mid,ev,mt in allm:
    mt=pd.Timestamp(mt).tz_convert('UTC'); m=match(ev,mt)
    if m is None: nomatch+=1; continue
    Games.append(dict(ev=ev,mt=mt,mid=mid,fx=m[0],tot=m[1]+m[2]))
print(f"markets {len(allm)}, scored {len(Games)}, no unique score {nomatch}, {time.time()-T0:.0f}s",flush=True)
if len(Games)<500: sys.exit("too few games: a code fault")
rows=[]
for c in range(0,len(Games),300):
    sub=Games[c:c+300]
    F=pd.read_sql("SELECT fixture_id,captured_at,minute,score_home,score_away FROM goal_timeline WHERE fixture_id=ANY(%s) AND score_home IS NOT NULL AND score_away IS NOT NULL ORDER BY fixture_id,captured_at",con,params=([g['fx'] for g in sub],))
    F['tt']=secs(F.captured_at); F['mn']=pd.to_numeric(F.minute,errors='coerce'); FF={k:x for k,x in F.groupby('fixture_id')}
    P=pd.read_sql("SELECT market_id,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s) AND inplay AND ltp>=1.01 AND ltp<1000",con,params=([g['mid'] for g in sub],))
    P['tt']=secs(P.ts); P=P.drop_duplicates(['market_id','sel','tt']).sort_values('tt',kind='stable'); PX={k:x for k,x in P.groupby('market_id')}
    for g in sub:
        fd=FF.get(g['fx']); fd=fd[fd.mn.notna()] if fd is not None else None
        if fd is None or len(fd)<5 or g['mid'] not in PX: continue
        ft,fm,fh,fa=fd.tt.values,fd.mn.values,fd.score_home.values.astype(int),fd.score_away.values.astype(int)
        for s,y in PX[g['mid']].groupby('sel',sort=False):
            if s not in ('Over 1.5 Goals','Under 1.5 Goals'): continue
            ts,px=y.tt.values,y.ltp.values; over=g['tot']>1.5; won=over if s.startswith('Over') else not over
            for T in (70,75,80):
                e=first_in_window(ts,T,ft,fm,fh,fa)
                if e is None or e[1]+e[2]!=0: continue
                for side in 'BL':
                    p=fill(ts,px,e[0],side); v=pnl(side,p,won)
                    if not np.isnan(v): rows.append((T,s.split()[0],side,g['ev'],g['mt'].timestamp(),p,won,v))
    print(f"  {min(c+300,len(Games))}/{len(Games)} rows {len(rows)} {time.time()-T0:.0f}s",flush=True)
con.close()
R=pd.DataFrame(rows,columns=['T','sel','side','ev','when','p','won','v'])
out=[]
for k,d in R.groupby(['T','sel','side']):
    v=d.v.values; md=np.median(d.when.values); a=v[d.when.values<md]; b=v[d.when.values>=md]; fp=d.p.map(lambda q:step(q,-1)) if k[2]=='B' else d.p.map(lambda q:step(q,1))
    out.append(dict(T=k[0],sel=k[1],side=k[2],n=len(v),games=d.ev.nunique(),per10=v.mean(),t=tstat(v),h1=a.mean(),h2=b.mean(),won=d.won.mean(),imp=(1/fp).mean(),med_p=d.p.median(),PASS=passes(len(v),len(a),len(b),tstat(v),a.mean(),b.mean(),v.mean())))
S=pd.DataFrame(out); print("\n== every line\n",S.round(3).to_string(index=False))
Y=S[(S['T']==75)&(S.sel=='Over')&(S.side=='L')]; print("\n== LINE UNDER TEST\n",Y.round(3).to_string(index=False))
Z=Y[Y.PASS]; print(f"\n== SURVIVORS: {len(Z)} of 1\n",Z.round(3).to_string(index=False) if len(Z) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
