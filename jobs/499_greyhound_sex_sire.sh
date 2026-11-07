#!/bin/bash
set -o pipefail
# 499_greyhound_sex_sire (Finder 2026-11-07, queue item 377, Finder's own, source d; engine from jobs/499_greyhound_card_form.sh): sex, colour, reserve and sire off the greyhound card against the T-5 price. Rule pushed before any price. Read only.
# TAPE bf_hist_other Greyhound WIN, last pre-off print 5-20 min before the scheduled off, last-traded so an upper bound. TRUTH greyhound_racecards_today (Railway, this one table read). Static card fields, so no look-ahead from the save time. Join as item 233: London date, track, dog; a race with a tape runner missing goes; dead heats out. Over 50 not traded. One tick adverse, 2%, £10, to result. Halves by date median.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_500_000_000,1_500_000_000))  # this job only
import sys,re,time,warnings,psycopg2,pandas as pd,numpy as np
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,line,back_settle,lay_settle,tstat
pd.set_option('display.width',230); pd.set_option('display.max_rows',150); pd.set_option('display.max_columns',30)
T0=time.time()
def dog(s): return re.sub(r'[^a-z0-9]','',re.sub(r'^\s*\d+\.\s*','',str(s)).lower())
def track(e):
    m=re.match(r'^(.*?)\s+\d+(st|nd|rd|th)\s+\w+$',str(e)); return (m.group(1) if m else str(e)).strip().lower()
def band(p): return '<3' if p<3 else '3-6' if p<6 else '6-12' if p<12 else None
def value(side,x,won):
    if x>50: return np.nan
    if side=='B':
        a=step(x,-1)
        return np.nan if a<=1.01 else back_settle(a,won)
    return lay_settle(step(x,1),won)
assert band(2.99)=='<3' and band(3)=='3-6' and band(11.99)=='6-12' and band(12) is None
assert abs(value('B',3.0,True)-19.404)<1e-9 and value('B',3.0,False)==-10.0 and abs(value('L',3.0,False)-10/2.05*.98)<1e-9 and value('L',3.0,True)==-10.0 and np.isnan(value('B',51.,True)) and np.isnan(value('B',1.02,True))
assert dog('1. Ballymac Tom')=='ballymactom' and track('Romford 5th Nov')=='romford'
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
rc=psycopg2.connect(creds.pg_railway(),sslmode='require')
C=pd.read_sql("SELECT race_date,track,race_id,greyhound,finish_position,sex,colour,sire,dam,reserve,fetched_at FROM greyhound_racecards_today",rc); rc.close()
C['tk']=C.track.str.strip().str.lower(); C['d']=C.greyhound.map(dog); C['date']=pd.to_datetime(C.race_date).dt.date; C['fa']=pd.to_datetime(C.fetched_at,utc=True)
print(f"card rows {len(C)}; sex {C.sex.value_counts(dropna=False).head(6).to_dict()}; colour {C.colour.value_counts(dropna=False).head(10).to_dict()}; reserve {C.reserve.value_counts(dropna=False).head(4).to_dict()}; sires {C.sire.nunique()}",flush=True)
fin=C.dropna(subset=['finish_position']).groupby(['race_id','d']).finish_position.agg(['nunique','first']); bad=set(fin[fin['nunique']>1].index.get_level_values(0))
C=C[~C.race_id.isin(bad)].sort_values('fa',kind='stable')
RF=C.dropna(subset=['finish_position']).drop_duplicates(['race_id','d'],keep='last')[['race_id','d','date','tk']].rename(columns={'date':'date_f','tk':'tk_f'})
C=C.merge(RF,on=['race_id','d'],how='left').drop_duplicates(['race_id','d'],keep='first')
_k=C.date_f.notna(); C.loc[_k,'date']=C.loc[_k,'date_f']; C.loc[_k,'tk']=C.loc[_k,'tk_f']; C=C.drop(columns=['finish_position','date_f','tk_f'])
C=C.merge(fin[['first']].rename(columns={'first':'finish_position'}).reset_index(),on=['race_id','d'],how='left')
print(f"card races {C.race_id.nunique()}, {C.date.min()} to {C.date.max()}, {time.time()-T0:.0f}s",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
# CORRECTED before any line was used: the first run built the race from runners with a print in the T-20 to T-5 window, so a race survived only if its winner had printed there, and every band read about +£2 back at t 8 with the control the same. The market's runners now come from every pre-off print; the T-5 price joins on afterwards.
F=[];W_=[]
for a,b in (('2026-05-01','2026-06-01'),('2026-06-01','2026-07-01'),('2026-07-01','2026-08-01'),('2026-08-01','2026-09-01'),('2026-09-01','2026-10-01'),('2026-10-01','2026-11-05')):
    cur.execute("""SELECT DISTINCT market_id,event_name,market_time,sel FROM bf_hist_other WHERE sport='Greyhound Racing' AND market_type='WIN' AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND market_time>=%s AND market_time<%s""",(a,b))
    x=pd.DataFrame(cur.fetchall(),columns='market_id event_name market_time sel'.split()); F.append(x)
    cur.execute("""SELECT DISTINCT ON (market_id,sel) market_id,sel,ltp::float8 FROM bf_hist_other WHERE sport='Greyhound Racing' AND market_type='WIN' AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND market_time>=%s AND market_time<%s AND ts>=market_time-interval '20 minutes' AND ts<=market_time-interval '5 minutes' ORDER BY market_id,sel,ts DESC""",(a,b))
    y=pd.DataFrame(cur.fetchall(),columns='market_id sel ltp'.split()); W_.append(y); print(f"  {a} runners {len(x)}, priced at T-5 {len(y)} | {time.time()-T0:.0f}s",flush=True)
con.close(); P=pd.concat(F,ignore_index=True); W_=pd.concat(W_,ignore_index=True); del F; P['mt']=pd.to_datetime(P.market_time,utc=True)
P['tk']=P.event_name.map(track); P['d']=P.sel.map(dog); P['date']=P.mt.dt.tz_convert('Europe/London').dt.date
J=P.merge(C[['date','tk','d','race_id','finish_position','sex','colour','sire','dam','reserve']],on=['date','tk','d'],how='left').merge(W_,on=['market_id','sel'],how='left')
hit=J.dropna(subset=['race_id']); pr=hit.groupby('market_id').race_id.nunique(); hit=hit[hit.market_id.isin(pr[pr==1].index)]
wn=hit[hit.finish_position==1].groupby('market_id').d.nunique(); one=set(wn[wn==1].index); miss=set(J[J.market_id.isin(one)&J.race_id.isna()].market_id.unique()); use=one-miss
print(f"tape markets {P.market_id.nunique()}; one winner {len(one)}; dead heats {int((wn>1).sum())}; tape runner off the card {len(miss)}; scored races {len(use)}; item 233 read about 4,500",flush=True)
if len(use)<1000: print("\n== SURVIVORS: none; join too small, BLOCKED"); sys.exit(0)
R=J[J.market_id.isin(use)].copy(); R['won']=R.finish_position==1; nop=int(R.ltp.isna().sum()); R=R[R.ltp.notna()].copy(); R['p']=R.ltp; R['bd']=R.p.map(band); R=R[R.bd.notna()].copy(); print('runners with no T-5 print',nop,flush=True)
assert not R.duplicated(['market_id','d']).any()
R['B']=[value('B',p,w) for p,w in zip(R.p,R.won)]; R['L']=[value('L',p,w) for p,w in zip(R.p,R.won)]; R['when']=(R.mt-pd.Timestamp('1970-01-01',tz='UTC'))/pd.Timedelta(seconds=1)
def mk(x,**k):
    x=x.dropna(subset=['v']); md=np.median(x.when.values); l=line(x.v.values,np.where(x.when.values<md,1,2)); tr=tstat(x.groupby('market_id').v.sum().values)
    return dict(**k,n=l['n'],races=x.market_id.nunique(),per10=l['per10'],t=l['t'],t_race=tr,h1=l['h1'],h2=l['h2'],n1=l['n1'],n2=l['n2'],won=x.won.mean(),implied=(1/x.p).mean(),PASS=l['PASS'])
ST={}
for s in R.sex.dropna().unique():
    if (R.sex==s).sum()>=300: ST['SEX_'+str(s)]=R.sex==s
for s in R.colour.value_counts().head(5).index: ST['COL_'+str(s)]=R.colour==s
ST['RESERVE']=R.reserve.astype(str).str.lower().isin(['true','t','1','y','yes','r'])
print("state runners before any price is scored:",{k:int(v.sum()) for k,v in ST.items()},flush=True)
out=[]
for k,fl in ST.items():
    a=R[fl]
    for b in ('<3','3-6','6-12'):
        for side in 'BL':
            x=a[a.bd==b].assign(v=lambda d:d[side])
            if len(x.dropna(subset=['v']))>=20: out.append(mk(x,state=k,band=b,side=side))
T=pd.DataFrame(out).sort_values('t',ascending=False)
print(f"\n== ITEM 377 card fields: {len(T)} lines, by t\n",T.round(3).to_string(index=False),flush=True)
ctl=[mk(R[R.bd==b].assign(v=lambda d:d[side]),band=b,side=side) for b in ('<3','3-6','6-12') for side in 'BL']
print("\n== CONTROL every runner in the band, cannot pass\n",pd.DataFrame(ctl).drop(columns='PASS').round(3).to_string(index=False))
# sire and dam chosen on dates up to the median, traded after it, err = won minus 1/print
Wz=[]
for col in ('sire','dam'):
    E=R[R[col].notna()].assign(err=lambda d:d.won.astype(float)-1/d.p); med=np.median(E.when.values); A=E[E.when<=med]; Bb=E[E.when>med]
    g1=A.groupby(col).err.agg(['mean','size']); g1=g1[g1['size']>=100].sort_values('mean')
    print(f"\n== {col.upper()}: runners {len(A)} + {len(Bb)}; with 100+ runners before the split {len(g1)}",flush=True)
    if len(g1)<20: print("  fewer than 20, no lines scored"); continue
    HOT=list(g1.index[-10:]); COLD=list(g1.index[:10]); g2=Bb.groupby(col).err.agg(['mean','size']); j=g1.join(g2,rsuffix='2',how='inner'); j=j[j.size2>=30]
    print(f"  rank corr first half v second {j['mean'].corr(j['mean2'],method='spearman'):.3f} on {len(j)}; second-half err HOT {Bb[Bb[col].isin(HOT)].err.mean():+.4f} COLD {Bb[Bb[col].isin(COLD)].err.mean():+.4f} all {Bb.err.mean():+.4f}")
    o2=[mk(Bb[Bb[col].isin(tt)].assign(v=lambda d:d[side]),group=col+' '+nm,side=side) for nm,tt,side in (('HOT',HOT,'B'),('COLD',COLD,'L'))]
    Z=pd.DataFrame(o2); print(Z.round(3).to_string(index=False)); Wz.append(Z[Z.PASS])
Wn=T[T.PASS]; Wz=pd.concat(Wz) if Wz else pd.DataFrame()
print(f"\n== SURVIVORS: {len(Wn)} of {len(T)} card fields, {len(Wz)} sire or dam\n",Wn.round(3).to_string(index=False) if len(Wn) else "none",Wz.round(3).to_string(index=False) if len(Wz) else "")
print(f"total {time.time()-T0:.0f}s")
PY
