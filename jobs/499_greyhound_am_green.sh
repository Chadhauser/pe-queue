#!/bin/bash
set -o pipefail
# 499_greyhound_am_green (Finder 2026-11-06, queue item 247; Finder's own, source a; from jobs/499_greyhound_kennel_slot.sh): does item 243's morning lay show in the price before the off, on months with no result on the box? Rule pushed before any price was read, in the queue. Read only.
# TAPE: bf_hist_other Greyhound WIN, pre-off last-traded prints, so a pass is an upper bound. No results are read: both legs close before the off.
# ENTRY: lay at the last print 5 to 20 min before the scheduled off, one tick adverse. EXIT: back at the last print under 5 min before the off, one tick adverse (lay_hedge), 2%, £10 liability. NO EXIT PRINT: counted and shown, and a line over 10% cannot pass: with no result on the box these cannot be settled, and dropping them is a known bias.
# SETS: AM (London off before 13:00) 3-6 and FIRST (first tape market of that track's date, meeting of 2 or more) 6-12, entry-price bands as item 243. Every other runner in the band is the read-across. UNSEEN Sep 2024 to Apr 2026 can pass; CHOSEN May to Oct 2026 is shown and cannot.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(3_500_000_000,3_500_000_000))  # this job only
import sys,re,time,warnings,psycopg2,pandas as pd,numpy as np
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,line,lay_hedge,tstat
pd.set_option('display.width',230); pd.set_option('display.max_rows',150); pd.set_option('display.max_columns',30)
T0=time.time()
def track(e):
    m=re.match(r'^(.*?)\s+\d+(st|nd|rd|th)\s+\w+$',str(e)); return (m.group(1) if m else str(e)).strip().lower()
def zdiff(a,b):
    a=np.asarray(a,float); b=np.asarray(b,float)
    return (a.mean()-b.mean())/np.sqrt(a.var(ddof=1)/len(a)+b.var(ddof=1)/len(b))
def green(x,q):
    """Laid at print x one tick worse, out at print q one tick worse, £10 liability, 2%."""
    return lay_hedge(step(x,1),q)
# known answers: lay print 3.0 -> fill 3.05, stake 10/2.05 = 4.878049; out at print 5.0 -> back at 4.9: 4.878049*(1-3.05/4.9) = 1.841712, *0.98 = 1.804878, as lib_cand's check.
assert abs(green(3.0,5.0)-1.804878)<1e-5
# out at print 2.0 -> back at 1.99: 4.878049*(1-3.05/1.99) = -2.598358, no commission on a loss. Unchanged price loses two ticks: 3.0 -> 3.05, back at 2.98.
assert abs(green(3.0,2.0)+2.598358)<1e-5
assert abs(green(3.0,3.0)-(10/2.05)*(1-3.05/2.98))<1e-9 and green(3.0,3.0)<0
assert track('Central Park 15th Sep')=='central park'
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
rows=[]; mons=pd.date_range('2024-09-01','2026-11-01',freq='MS')
for a,b in zip(mons[:-1],mons[1:]):
    cur.execute("""SELECT market_id,event_name,market_time,sel,ts,ltp::float8 FROM bf_hist_other WHERE sport='Greyhound Racing' AND market_type='WIN' AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND market_time>=%s AND market_time<%s""",(a.date(),b.date()))
    x=pd.DataFrame(cur.fetchall(),columns='market_id event_name market_time sel ts ltp'.split())
    if not len(x): continue
    x['mt']=pd.to_datetime(x.market_time,utc=True); x['t']=pd.to_datetime(x.ts,utc=True); x['mins']=(x.mt-x.t)/pd.Timedelta(minutes=1)
    M=x.drop_duplicates('market_id')[['market_id','event_name','mt']]
    x=x[(x.mins>=0)&(x.mins<=20)].sort_values(['market_id','sel','t'],kind='stable')
    E=x[x.mins>=5].groupby(['market_id','sel'],sort=False).tail(1)[['market_id','sel','ltp']].rename(columns={'ltp':'p'})
    Q=x[x.mins<5].groupby(['market_id','sel'],sort=False).tail(1)[['market_id','sel','ltp']].rename(columns={'ltp':'q'})
    rows.append((M,E.merge(Q,on=['market_id','sel'],how='left'))); print(f"  {a.date()} markets {len(M)} entries {len(E)} | {time.time()-T0:.0f}s",flush=True)
con.close()
MM=pd.concat([r[0] for r in rows],ignore_index=True).drop_duplicates('market_id'); R=pd.concat([r[1] for r in rows],ignore_index=True); del rows
MM['lon']=MM.mt.dt.tz_convert('Europe/London'); MM['date']=MM.lon.dt.date; MM['hr']=MM.lon.dt.hour; MM['tk']=MM.event_name.map(track)
g=MM.sort_values('mt',kind='stable').groupby(['date','tk']); MM['rank']=g.cumcount()+1; MM['size']=g.market_id.transform('size')
R=R.merge(MM[['market_id','mt','hr','rank','size']],on='market_id'); assert R.duplicated(['market_id','sel']).sum()==0
R['era']=np.where(R.mt<pd.Timestamp('2026-05-01',tz='UTC'),'UNSEEN','CHOSEN'); R['when']=R.mt.astype('int64')
R['bd']=np.where(R.p<3,'<3',np.where(R.p<6,'3-6',np.where(R.p<12,'6-12','x')))
R['AM']=R.hr<13; R['FIRST']=(R['rank']==1)&(R['size']>=2)
R['v']=[green(a,b) if b==b else np.nan for a,b in zip(R.p,R.q)]
R['move']=1/R.p-1/R.q   # implied points the price lost; positive = it lengthened, good for a lay
print(f"entries {len(R)}; no exit print {R.q.isna().mean():.3f}; markets {R.market_id.nunique()}; by era {R.groupby('era').market_id.nunique().to_dict()} | {time.time()-T0:.0f}s",flush=True)
out=[]
for era in ('UNSEEN','CHOSEN'):
    for nm,fl,bd in (('AM 3-6',R.AM,'3-6'),('FIRST 6-12',R.FIRST,'6-12')):
        A=R[(R.era==era)&(R.bd==bd)]; f=fl.reindex(A.index); S=A[f]; C=A[~f]; x=S.dropna(subset=['v']); c=C.dropna(subset=['v'])
        md=np.median(x.when.values); l=line(x.v.values,np.where(x.when.values<md,1,2)); tr=tstat(x.groupby('market_id').v.sum().values); noex=S.q.isna().mean()
        out.append(dict(era=era,line=nm,n=l['n'],races=x.market_id.nunique(),per10=l['per10'],t=l['t'],t_race=tr,h1=l['h1'],h2=l['h2'],n1=l['n1'],n2=l['n2'],noexit=noex,move=x.move.mean(),rest_n=len(c),rest_per10=c.v.mean(),rest_move=c.move.mean(),z_move=zdiff(x.move,c.move),PASS=bool(era=='UNSEEN' and l['PASS'] and tr>=3.5 and noex<=0.10)))
T=pd.DataFrame(out); print("\n== LINES, lay then back before the off\n",T.round(4).to_string(index=False))
Wn=T[T.PASS]; print(f"\n== SURVIVORS: {len(Wn)} of 2 unseen lines\n",Wn.round(4).to_string(index=False) if len(Wn) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
