#!/bin/bash
set -o pipefail
# 499_greyhound_card_form (Finder 2026-11-06, queue items 233, 234, 235; Finder's own, source d; from jobs/499_greyhound_meeting_trap.sh): form, best time, class, age and trainer off the greyhound card, against the T-5 price. Read only. The number 499 is reused: 450-499 are all taken.
# TAPE: bf_hist_other Greyhound WIN, pre-off last-traded prints, so a pass is an upper bound. TRUTH: greyhound_racecards_today (Railway, this one table read). Join and gate as item 61/175: London date, track, dog name; >= 80% of card races with a winner must join to one market with one winner, else BLOCKED. Dead heats out, counted. A race with a tape runner missing from the card goes, counted.
# ENTRY: last print 5 to 20 min before the scheduled off, one tick adverse, over 50 not traded, settled at the result, 2%, £10.
# LOOK-AHEAD: cards are mostly saved after the race. Form, best time, class, age and trainer come from the dog's EARLIEST saved row in the race; the finish from any row that has one; a race whose rows disagree on a dog's finish goes, counted. Gate: this race's finish must not equal the form's latest digit above 0.35 of the time (a card holding tonight's run would read near 1; the census read 0.216).
# RULE, fixed before any price was read: see queue items 233, 234, 235.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(3_500_000_000,3_500_000_000))  # this job only
import sys,re,time,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter
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
def form5(s):
    s=str(s).strip()
    return [int(c) for c in s[-5:]] if re.fullmatch(r'[1-6]{5,}',s) else None
def form_states(f):
    if f is None: return []
    out=[]; m=sum(f)/5
    if f[-1]==1: out.append('WONLAST')
    if f[-1]>=5: out.append('LASTBAD')
    if m<=2.6+1e-9: out.append('FORMGOOD')
    if m>=4.4-1e-9: out.append('FORMBAD')
    return out
def sec(s):
    m=re.search(r'(\d+\.\d+)',str(s)); return float(m.group(1)) if m else np.nan
def time_states(ts):
    """ts: best times of one race's runners, nan if none. Returns {index: state}."""
    v=[(x,i) for i,x in enumerate(ts) if x==x]
    if len(v)<5: return {}
    lo=min(x for x,_ in v); hi=max(x for x,_ in v)
    if hi-lo>3+1e-9: return {}
    out={}; a=[i for x,i in v if x==lo]; b=[i for x,i in v if x==hi]
    if len(a)==1: out[a[0]]='FASTEST'
    if len(b)==1: out[b[0]]='SLOWEST'
    return out
def class_state(c):
    c=str(c).strip()
    if re.fullmatch(r'A\d+',c): return 'CLASS_A'
    if re.fullmatch(r'D\d+',c): return 'CLASS_D'
    if re.fullmatch(r'OR\d*',c): return 'CLASS_OR'
    if c=='HP': return 'CLASS_HP'
    return None
def age_state(a):
    if a!=a: return None
    return 'AGE1' if a==1 else 'AGE4' if 4<=a<=8 else None
def zdiff(a,b):
    a=np.asarray(a,float); b=np.asarray(b,float)
    return (a.mean()-b.mean())/np.sqrt(a.var(ddof=1)/len(a)+b.var(ddof=1)/len(b))
# known answers, worked by hand
assert band(2.99)=='<3' and band(3)=='3-6' and band(11.99)=='6-12' and band(12) is None
assert abs(value('B',3.0,True)-19.404)<1e-9 and value('B',3.0,False)==-10.0 and abs(value('L',3.0,False)-10/2.05*.98)<1e-9 and value('L',3.0,True)==-10.0 and np.isnan(value('B',51.,True)) and np.isnan(value('B',1.02,True))
assert form5('64122')==[6,4,1,2,2] and form5('164122')==[6,4,1,2,2] and form5('6412') is None and form5('64-22') is None and form5(None) is None
assert form_states([6,4,1,2,1])==['WONLAST'] and form_states([2,3,3,3,5])==['LASTBAD'] and form_states(None)==[]
assert form_states([2,2,3,3,3])==['FORMGOOD'] and form_states([2,2,3,3,4])==[]    # mean 2.6 in, 2.8 out
assert form_states([5,4,5,4,4])==['FORMBAD'] and form_states([5,4,5,4,3])==[]     # mean 4.4 in, 4.2 out
assert set(form_states([1,2,3,2,1]))=={'WONLAST','FORMGOOD'} and set(form_states([5,5,5,5,6]))=={'LASTBAD','FORMBAD'}
assert sec('29.88s')==29.88 and sec(None)!=sec(None)
n_=float('nan')
assert time_states([29.1,29.5,29.6,29.7,29.8,30.0])=={0:'FASTEST',5:'SLOWEST'} and time_states([29.1,29.1,29.6,29.7,29.8,30.0])=={5:'SLOWEST'}
assert time_states([29.1,n_,n_,29.7,29.8,30.0])=={} and time_states([26.0,29.5,29.6,29.7,29.8,30.0])=={}   # under 5 times; spread over 3 s
assert time_states([27.0,28.5,29.6,29.7,29.8,30.0])=={0:'FASTEST',5:'SLOWEST'}                              # spread exactly 3 s stays in
assert class_state('A7')=='CLASS_A' and class_state('A10')=='CLASS_A' and class_state('D5')=='CLASS_D' and class_state('OR')=='CLASS_OR' and class_state('OR3')=='CLASS_OR' and class_state('HP')=='CLASS_HP' and class_state('IV') is None and class_state('B2') is None
assert age_state(1)=='AGE1' and age_state(4)=='AGE4' and age_state(8)=='AGE4' and age_state(21) is None and age_state(2) is None and age_state(n_) is None
assert abs(zdiff([0,1]*50,[0,1]*50))<1e-9 and zdiff([0,1]*50,[0,0,0,1]*50)>2
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
rc=psycopg2.connect(creds.pg_railway(),sslmode='require')
C=pd.read_sql("SELECT race_date,track,race_id,race_time,greyhound,trap_number,finish_position,race_class,age,trainer,form_summary,best_run_time,fetched_at FROM greyhound_racecards_today",rc); rc.close()
C['tk']=C.track.str.strip().str.lower(); C['d']=C.greyhound.map(dog); C['date']=pd.to_datetime(C.race_date).dt.date; C['fa']=pd.to_datetime(C.fetched_at,utc=True)
_d=C[C.duplicated(['race_id','d'],keep=False)]; g_=_d.groupby(['race_id','d'])
print(f"card rows {len(C)}; rows in duplicated race and dog {len(_d)}; of those pairs form differs {(g_.form_summary.nunique()>1).mean():.3f}, best time differs {(g_.best_run_time.nunique()>1).mean():.3f}, two finishes {(g_.finish_position.nunique()>1).mean():.3f}",flush=True)
fin=C.dropna(subset=['finish_position']).groupby(['race_id','d']).finish_position.agg(['nunique','first']); bad=set(fin[fin['nunique']>1].index.get_level_values(0))
print(f"races with two finishes for one dog, removed: {len(bad)}",flush=True)
C=C[~C.race_id.isin(bad)].sort_values('fa',kind='stable').drop_duplicates(['race_id','d'],keep='first').drop(columns='finish_position')
C=C.merge(fin[['first']].rename(columns={'first':'finish_position'}).reset_index(),on=['race_id','d'],how='left')
print(f"card races {C.race_id.nunique()}, dates {C.date.min()} to {C.date.max()} | {time.time()-T0:.0f}s",flush=True)
_x=C.dropna(subset=['finish_position','form_summary']); _x=_x[_x.form_summary.astype(str).str.len()>0]; lk=(_x.form_summary.astype(str).str[-1]==_x.finish_position.astype(int).astype(str)).mean()
print(f"LOOK-AHEAD GATE: this finish == form's latest digit {lk:.3f} of {len(_x)}, stop above 0.35",flush=True)
if lk>0.35: print("\n== SURVIVORS: none; look-ahead gate SHUT, items BLOCKED"); sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
F=[]
for a,b in (('2026-05-01','2026-06-01'),('2026-06-01','2026-07-01'),('2026-07-01','2026-08-01'),('2026-08-01','2026-09-01'),('2026-09-01','2026-10-01'),('2026-10-01','2026-11-05')):
    cur.execute("""SELECT market_id,event_name,market_time,sel,ts,ltp::float8 FROM bf_hist_other WHERE sport='Greyhound Racing' AND market_type='WIN' AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND market_time>=%s AND market_time<%s""",(a,b))
    x=pd.DataFrame(cur.fetchall(),columns='market_id event_name market_time sel ts ltp'.split()); F.append(x); print(f"  {a} rows {len(x)} | {time.time()-T0:.0f}s",flush=True)
con.close(); P=pd.concat(F,ignore_index=True); del F; P['mt']=pd.to_datetime(P.market_time,utc=True); P['t']=pd.to_datetime(P.ts,utc=True); P['mins']=(P.mt-P.t)/pd.Timedelta(minutes=1)
P=P.sort_values(['market_id','sel','t'],kind='stable')
Mk=P.drop_duplicates(['market_id','sel'])[['market_id','event_name','mt','sel']].copy(); Mk['tk']=Mk.event_name.map(track); Mk['d']=Mk.sel.map(dog); Mk['date']=Mk.mt.dt.tz_convert('Europe/London').dt.date
J=Mk.merge(C[['date','tk','d','race_id','finish_position','race_class','age','trainer','form_summary','best_run_time']],on=['date','tk','d'],how='left')
first,last=Mk.date.min(),Mk.date.max(); Cw=C[(C.date>=first)&(C.date<=last)]; cards_w=Cw[Cw.finish_position==1].race_id.unique()
hit=J.dropna(subset=['race_id']); rc_per=hit.groupby('market_id').race_id.nunique(); hit=hit[hit.market_id.isin(rc_per[rc_per==1].index)]
wn=hit[hit.finish_position==1].groupby('market_id').d.nunique(); one=wn[wn==1].index; dead=int((wn>1).sum()); joined=hit[hit.market_id.isin(one)].race_id.nunique(); rate=joined/max(1,len(cards_w))
print(f"card races with a winner in the tape's dates {len(cards_w)}; joined {joined}; dead heats {dead}; GATE {rate:.3f} v 0.80; tape markets {Mk.market_id.nunique()}",flush=True)
if rate<0.80: print("\n== SURVIVORS: none; join gate SHUT, item BLOCKED"); sys.exit(0)
miss=set(J[J.market_id.isin(one)&J.race_id.isna()].market_id.unique()); use=[m for m in one if m not in miss]; print(f"races removed, tape runner not on the card {len(miss)}; scored races {len(use)} (item 175 read 4,507 with one row per dog chosen by table order)",flush=True)
R=J[J.market_id.isin(use)].copy(); R['won']=R.finish_position==1
W=P[P.market_id.isin(use)&(P.mins>=5)&(P.mins<=20)].groupby(['market_id','sel'],sort=False).tail(1)[['market_id','sel','ltp']]; del P
R=R.merge(W,on=['market_id','sel'],how='left'); n_all=len(R)
R['allp']=R.groupby('market_id').ltp.transform(lambda s:s.notna().all())
R['bt']=R.best_run_time.map(sec); R['f5']=R.form_summary.map(form5)
tst={}
for m,g in R.groupby('market_id',sort=False):
    idx=list(g.index)
    for k,s in time_states(list(g.bt.values)).items(): tst[idx[k]]=s
R['ts']=R.index.map(tst)
nop=int(R.ltp.isna().sum()); R=R[R.ltp.notna()].copy()
R['p']=R.ltp; R['bd']=R.p.map(band); over=int(R.bd.isna().sum())
R['fair']=(1/R.p)/R.groupby('market_id').p.transform(lambda s:(1/s).sum()); R.loc[~R.allp,'fair']=np.nan
R['err']=R.won.astype(float)-R.fair
print(f"runners {n_all}; no print 5 to 20 min before the off {nop}; 12 or over, or no band {over}; races with every runner priced {R[R.allp].market_id.nunique()} | {time.time()-T0:.0f}s",flush=True)
R['B']=[value('B',p,w) for p,w in zip(R.p,R.won)]; R['L']=[value('L',p,w) for p,w in zip(R.p,R.won)]
R['when']=R.mt.astype('int64')
S=R[R.bd.notna()].copy(); ST={}
ST['WONLAST']=S.f5.map(lambda f:'WONLAST' in form_states(f)); ST['LASTBAD']=S.f5.map(lambda f:'LASTBAD' in form_states(f)); ST['FORMGOOD']=S.f5.map(lambda f:'FORMGOOD' in form_states(f)); ST['FORMBAD']=S.f5.map(lambda f:'FORMBAD' in form_states(f))
ST['FASTEST']=S.ts=='FASTEST'; ST['SLOWEST']=S.ts=='SLOWEST'
cs=S.race_class.map(class_state); ag=pd.to_numeric(S.age,errors='coerce').map(age_state)
for k in ('CLASS_A','CLASS_D','CLASS_OR','CLASS_HP'): ST[k]=cs==k
for k in ('AGE1','AGE4'): ST[k]=ag==k
assert all((v.index==S.index).all() for v in ST.values())
ITEM={'WONLAST':233,'LASTBAD':233,'FORMGOOD':233,'FORMBAD':233,'FASTEST':233,'SLOWEST':233,'CLASS_A':234,'CLASS_D':234,'CLASS_OR':234,'CLASS_HP':234,'AGE1':234,'AGE4':234}
print("state runners, in bands, before any price is scored:",{k:int(v.sum()) for k,v in ST.items()},flush=True)
assert S.duplicated(['market_id','d']).sum()==0,"more than one row per dog per race"
def mk(x,**k):
    x=x.dropna(subset=['v']); md=np.median(x.when.values); l=line(x.v.values,np.where(x.when.values<md,1,2)); tr=tstat(x.groupby('market_id').v.sum().values)
    return dict(**k,n=l['n'],races=x.market_id.nunique(),per10=l['per10'],t=l['t'],t_race=tr,h1=l['h1'],h2=l['h2'],n1=l['n1'],n2=l['n2'],won=x.won.mean(),implied=(1/x.p).mean(),PASS=l['PASS'])
out=[]
for k,fl in ST.items():
    a=S[fl]
    for b in ('<3','3-6','6-12'):
        for side in 'BL':
            x=a[a.bd==b].assign(v=lambda d:d[side])
            if len(x.dropna(subset=['v'])): out.append(mk(x,item=ITEM[k],state=k,band=b,side=side))
T=pd.DataFrame(out).sort_values('t',ascending=False)
print(f"\n== ITEMS 233, 234: {len(T)} lines, by t\n",T.round(3).to_string(index=False))
ctl=[mk(S[S.bd==b].assign(v=lambda d:d[side]),band=b,side=side) for b in ('<3','3-6','6-12') for side in 'BL']
print("\n== CONTROL every runner in the band, cannot pass\n",pd.DataFrame(ctl).drop(columns='PASS').round(3).to_string(index=False))
print("\n== won minus overround-free print v the rest of the band, races with every runner priced")
for k,fl in ST.items():
    for b in ('<3','3-6','6-12'):
        x=S[(S.bd==b)&S.err.notna()]; f=fl.reindex(x.index); o=x[f]; c=x[~f]
        if len(o)>1 and len(c)>1: print(f"  {k} {b}: n {len(o)} err {o.err.mean():+.4f} v rest n {len(c)} {c.err.mean():+.4f}; z {zdiff(o.err,c.err):.2f}")
# item 235: choose on dates up to the median, trade after it
E=R[(R.p<12)&R.err.notna()&R.trainer.notna()].copy(); med=np.median(E.when.values); A=E[E.when<=med]; Bb=E[E.when>med]
g1=A.groupby('trainer').err.agg(['mean','size']); g1=g1[g1['size']>=100].sort_values('mean')
print(f"\n== ITEM 235: median {pd.Timestamp(med,tz='UTC'):%Y-%m-%d}; trainers with 100+ runners before it {len(g1)}",flush=True)
HOT=list(g1.index[-10:]); COLD=list(g1.index[:10])
print(f"  HOT mean err first half {g1.loc[HOT,'mean'].mean():+.4f}, COLD {g1.loc[COLD,'mean'].mean():+.4f}; names are not printed in the report, only here for the log: HOT {HOT}; COLD {COLD}")
g2=Bb.groupby('trainer').err.agg(['mean','size']); j=g1.join(g2,rsuffix='2',how='inner'); j=j[j.size2>=30]
print(f"  persistence: rank corr of trainer err, first half v second, {j['mean'].corr(j['mean2'],method='spearman'):.3f} on {len(j)} trainers; second-half err HOT {Bb[Bb.trainer.isin(HOT)].err.mean():+.4f} COLD {Bb[Bb.trainer.isin(COLD)].err.mean():+.4f} all {Bb.err.mean():+.4f}")
o2=[]
for nm,tt,side in (('HOT',HOT,'B'),('COLD',COLD,'L'),('HOT',HOT,'L'),('COLD',COLD,'B')):
    x=Bb[Bb.trainer.isin(tt)].assign(v=lambda d:d[side])
    if len(x): o2.append(mk(x,group=nm,side=side,scored=(nm,side) in (('HOT','B'),('COLD','L'))))
Z=pd.DataFrame(o2); Z.loc[~Z.scored,'PASS']=False; print(Z.round(3).to_string(index=False))
Wn=T[T.PASS]; Wz=Z[Z.PASS]
print(f"\n== SURVIVORS: {len(Wn)} of {len(T)} (233, 234), {len(Wz)} of 2 (235)\n",Wn.round(3).to_string(index=False) if len(Wn) else "none",Wz.round(3).to_string(index=False) if len(Wz) else "")
print(f"total {time.time()-T0:.0f}s")
PY
