#!/bin/bash
set -o pipefail
# 499_long_goal_lines (Finder 2026-11-05, queue item 122, Finder's own, source d): OVER_UNDER_55, 65, 75 and FIRST_HALF_GOALS_25 on the Sep 2026 tape. Rule written in the queue before any price was read. ONE MONTH, prints only, no book: a screen, so a pass is an upper bound and would earn a real-touch record, no more. The number 499 is reused with a new slug: 450-499 are all taken.
# GAMES, STATE AT A PRINT, FILL: as jobs/499_sep_tape_rest.sh. Feed goals can be phantom (about 2%, item 0g).
# LINES: OU55, OU65, OU75: PRE first print T-15 to the off, and T46, T60, T75 when one or two goals short of landing the Over. FH25: PRE, and T15, T25, T35 at total 0, 1, 2. Over and Under, back and lay; FH settles at the half-time score from the feed, no HT row not traded, counted.
# SETTLE to the result. One tick adverse, 2%, £10 risk. Over 50 is NOT dropped here, as long Overs are the test; over 200 is not traded, counted. A back filling at 1.01 no bet, counted. Halves: median market date.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,math,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,back_settle,lay_settle,tstat,passes,norm,loose
import lib_cand; lib_cand._checks()
pd.set_option('display.width',230); pd.set_option('display.max_rows',150); pd.set_option('display.max_columns',30)
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
def short_by(ln,tot):
    """Goals needed to land Over ln at total tot."""
    return math.ceil(ln)-tot
def side_of(s):
    """Runner name to OVER or UNDER, else None."""
    t=str(s).strip().lower()
    return 'OVER' if t.startswith('over') else 'UNDER' if t.startswith('under') else None
assert abs(pnl('B',2.0,True)-10*0.99*0.98)<1e-9 and pnl('L',6.0,True)==-10.0 and abs(pnl('L',6.0,False)-10/5.2*0.98)<1e-9
assert short_by(5.5,4)==2 and short_by(5.5,5)==1 and short_by(5.5,0)==6 and short_by(7.5,6)==2 and short_by(2.5,2)==1
assert side_of('Over 5.5 Goals')=='OVER' and side_of('Under 7.5 Goals')=='UNDER' and side_of('x') is None
_f=np.array([0.,100.,200.,300.,400.,500.]); _m=np.array([50.,55.,56.,60.,61.,62.]); _h=np.array([0,0,0,0,1,1]); _a=np.zeros(6,int)
assert first_in_window(np.array([150.]),55,_f,_m,_h,_a)==(0,0,0) and first_in_window(np.array([350.]),46,_f,_m,_h,_a) is None
print("known-answer checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
GT=pd.read_sql("""SELECT DISTINCT ON (fixture_id) fixture_id,home_team,away_team,captured_at,minute,score_home,score_away,status FROM goal_timeline WHERE captured_at>='2026-08-31' AND captured_at<'2026-10-03' AND score_home IS NOT NULL AND score_away IS NOT NULL ORDER BY fixture_id,captured_at DESC""",con)
GT['t']=pd.to_datetime(GT.captured_at,utc=True); GT['mn']=pd.to_numeric(GT.minute,errors='coerce')
GT=GT[GT.status.isin(['FT','AET','PEN','Match Finished','FINISHED'])|(GT.mn>=88)].sort_values('t').reset_index(drop=True)
GT['H']=GT.home_team.map(norm); GT['A']=GT.away_team.map(norm); tt=GT.t.values.astype('datetime64[ns]')
HTF=pd.read_sql("""SELECT DISTINCT ON (fixture_id) fixture_id,score_home h,score_away a FROM goal_timeline WHERE captured_at>='2026-08-31' AND captured_at<'2026-10-03' AND status='HT' AND score_home IS NOT NULL AND score_away IS NOT NULL ORDER BY fixture_id,captured_at DESC""",con)
HTD={int(r.fixture_id):int(r.h)+int(r.a) for r in HTF.itertuples()}
def match(ev,mt):
    h,_,a=ev.partition(' v '); lo=np.searchsorted(tt,np.datetime64(mt.tz_convert(None))); hi=np.searchsorted(tt,np.datetime64((mt+pd.Timedelta(minutes=240)).tz_convert(None)),side='right')
    return loose(norm(h),norm(a),[(r.H,r.A,(int(r.fixture_id),int(r.score_home),int(r.score_away))) for r in GT.iloc[lo:hi].itertuples()])
LN={'OVER_UNDER_55':5.5,'OVER_UNDER_65':6.5,'OVER_UNDER_75':7.5,'FIRST_HALF_GOALS_25':2.5}
cur.execute("""SELECT DISTINCT market_id,market_type,event_name,market_time FROM bf_hist_other WHERE sport='Soccer' AND market_type = ANY(%s) AND market_time>='2026-09-01' AND market_time<'2026-10-02'""",(list(LN),))
MK={}; SK=Counter()
for mid,mty,ev,mt in cur.fetchall(): SK[mty+' markets']+=1; MK.setdefault((ev,pd.Timestamp(mt).tz_convert('UTC')),{})[mty]=mid
Games=[]
for (ev,mt),v in MK.items():
    m=match(ev,mt)
    if m is None: SK['event: no score']+=1; continue
    Games.append(dict(ev=ev,mt=mt,fx=m[0],tot=m[1]+m[2],mk=v))
print(f"events {len(MK)}, scored {len(Games)}, {dict(SK)}, {time.time()-T0:.0f}s",flush=True)
if len(Games)<500: sys.exit("too few games: a code fault")
rows=[]
def add(mk,tag,line,side,p,g,w):
    if p>200: SK['over 200, not traded']+=1; return
    v=pnl(side,p,w)
    if np.isnan(v): SK['back fills at 1.01, no bet']+=1; return
    rows.append((mk,tag,line,side,g['ev'],g['mt'].timestamp(),p,w,v))
for c in range(0,len(Games),300):
    sub=Games[c:c+300]
    F=pd.read_sql("SELECT fixture_id,captured_at,minute,score_home,score_away FROM goal_timeline WHERE fixture_id=ANY(%s) AND score_home IS NOT NULL AND score_away IS NOT NULL ORDER BY fixture_id,captured_at",con,params=([g['fx'] for g in sub],))
    F['tt']=secs(F.captured_at); F['mn']=pd.to_numeric(F.minute,errors='coerce'); FF={k:x for k,x in F.groupby('fixture_id')}
    ids=[v for g in sub for v in g['mk'].values()]
    P=pd.read_sql("SELECT market_id,sel,ts,ltp::float8 ltp,inplay FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s) AND ltp>=1.01 AND ltp<1000",con,params=(ids,))
    P['tt']=secs(P.ts); P=P.drop_duplicates(['market_id','sel','tt']).sort_values('tt',kind='stable'); PX={k:x for k,x in P.groupby('market_id')}
    for g in sub:
        off=g['mt'].timestamp(); fd=FF.get(g['fx']); fd=fd[fd.mn.notna()] if fd is not None else None; ok=fd is not None and len(fd)>=5
        if ok: ft,fm,fh,fa=fd.tt.values,fd.mn.values,fd.score_home.values.astype(int),fd.score_away.values.astype(int)
        for mty,mid in g['mk'].items():
            if mid not in PX: continue
            ln=LN[mty]; fh_mkt=mty.startswith('FIRST')
            if fh_mkt:
                ht=HTD.get(g['fx'])
                if ht is None: SK['FH market, no HT row, not traded']+=1; continue
                settle=ht
            else: settle=g['tot']
            for s,y in PX[mid].groupby('sel',sort=False):
                o=side_of(s)
                if o is None: SK['unknown runner']+=1; continue
                w=(settle>ln)==(o=='OVER'); ipm=y.inplay.values.astype(bool); ts,px=y.tt.values,y.ltp.values; ti,pi=ts[ipm],px[ipm]
                pre=np.where((~ipm)&(ts>=off-900)&(ts<=off))[0]
                if len(pre):
                    tp,pp=ts[pre],px[pre]
                    for side in 'BL': add(mty,'PRE',o,side,fill(tp,pp,0,side),g,w)
                if not ok: continue
                for T in ((15,25,35) if fh_mkt else (46,60,75)):
                    e=first_in_window(ti,T,ft,fm,fh,fa)
                    if e is None: continue
                    tot=e[1]+e[2]
                    if fh_mkt:
                        if tot>2: continue
                        lab=f'{o} G{tot}'
                    else:
                        n=short_by(ln,tot)
                        if n not in (1,2): continue
                        lab=f'{o} short{n}'
                    for side in 'BL': add(mty,f'T{T}',lab,side,fill(ti,pi,e[0],side),g,w)
    print(f"  {min(c+300,len(Games))}/{len(Games)} rows {len(rows)} {time.time()-T0:.0f}s",flush=True)
con.close(); print("counts:",dict(sorted(SK.items())),flush=True)
R=pd.DataFrame(rows,columns=['mk','tag','line','side','ev','when','p','won','v'])
out=[]
for k,d in R.groupby(['mk','tag','line','side']):
    v=d.v.values.astype(float); md=np.median(d.when.values); a=v[d.when.values<md]; b=v[d.when.values>=md]; fp=d.p.map(lambda q:step(q,-1)) if k[3]=='B' else d.p.map(lambda q:step(q,1))
    out.append(dict(mk=k[0],tag=k[1],line=k[2],side=k[3],n=len(v),games=d.ev.nunique(),per10=v.mean(),t=tstat(v),h1=a.mean() if len(a) else np.nan,h2=b.mean() if len(b) else np.nan,won=d.won.mean(),imp=(1/fp).mean(),med_p=d.p.median(),PASS=passes(len(v),len(a),len(b),tstat(v),a.mean() if len(a) else -1,b.mean() if len(b) else -1,v.mean())))
S=pd.DataFrame(out); print(f"\ndates {pd.Timestamp(R.when.min(),unit='s'):%Y-%m-%d} to {pd.Timestamp(R.when.max(),unit='s'):%Y-%m-%d}; games {R.ev.nunique()}; lines {len(S)}, n>=300 {(S.n>=300).sum()}")
print("\n== TOP 15 by t, n>=100\n",S[S.n>=100].sort_values('t',ascending=False).head(15).round(3).to_string(index=False))
print("\n== BOTTOM 6 by t, n>=100\n",S[S.n>=100].sort_values('t').head(6).round(3).to_string(index=False))
Y=S[S.PASS]; print(f"\n== SURVIVORS: {len(Y)} of {len(S)}\n",Y.round(3).to_string(index=False) if len(Y) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
