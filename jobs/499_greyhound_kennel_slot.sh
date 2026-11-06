#!/bin/bash
set -o pipefail
# 499_greyhound_kennel_slot (Finder 2026-11-06, queue items 242, 243, 244; Finder's own, sources d and c; from jobs/499_greyhound_meeting_fixed.sh): a trainer's night so far, session and race order, two dogs from one kennel. Read only. Rules pushed before any price was read, in the queue. The number 499 is reused: 450-499 are all taken.
# TAPE: bf_hist_other Greyhound WIN, pre-off last-traded prints, so a pass is an upper bound. TRUTH: greyhound_racecards_today (Railway, this one table read). Cards corrected and races joined as item 241, gate as job 499_greyhound_card_form.
# ENTRY: last print 5 to 20 min before the scheduled off, one tick adverse, settled at the result, 2%, £10. Bands <3, 3-6, 6-12; 12 and over not traded.
# NO LOOK-AHEAD: an earlier race counts only if scored and off at least 5 min before this entry print. Trainer is taken from the earliest save and checked for stability between saves. First and last race of a meeting are read from the tape's market schedule, known before the card starts.
# BAR: standard. Items 242, 244 can hold two dogs of a race in one line, so they also need t by race >= 3.5.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(3_500_000_000,3_500_000_000))  # this job only
import sys,re,time,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
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
    if side=='B':
        a=step(x,-1)
        return np.nan if a<=1.01 else back_settle(a,won)
    return lay_settle(step(x,1),won)
def trainer_states(runners,wins):
    """Counted earlier runners and wins of this trainer tonight."""
    out=[]
    if wins>=1: out.append('TR_WON')
    if wins>=2: out.append('TR_WON2')
    if runners>=4 and wins==0: out.append('TR_COLD')
    return out
def session(h): return 'AM' if h<13 else 'PM' if h<18 else 'EVE'
def kennel_pair(prices):
    """prices of one trainer's runners in a race, nan if no print. {index: state}, only for exactly two printed runners at different prices."""
    if len(prices)!=2 or any(p!=p for p in prices) or prices[0]==prices[1]: return {}
    s=0 if prices[0]<prices[1] else 1
    return {s:'KENNEL_SHORT',1-s:'KENNEL_LONG'}
def zdiff(a,b):
    a=np.asarray(a,float); b=np.asarray(b,float)
    return (a.mean()-b.mean())/np.sqrt(a.var(ddof=1)/len(a)+b.var(ddof=1)/len(b))
def correct_cards(C):
    """As job 499_greyhound_meeting_fixed."""
    fin=C.dropna(subset=['finish_position']).groupby(['race_id','d']).finish_position.agg(['nunique','first'])
    bad=set(fin[fin['nunique']>1].index.get_level_values(0))
    X=C[~C.race_id.isin(bad)].sort_values('fa',kind='stable')
    RF=X.dropna(subset=['finish_position']).drop_duplicates(['race_id','d'],keep='last')[['race_id','d','date','tk']].rename(columns={'date':'date_f','tk':'tk_f'})
    X=X.merge(RF,on=['race_id','d'],how='left').drop_duplicates(['race_id','d'],keep='first')
    k=X.date_f.notna(); X.loc[k,'date']=X.loc[k,'date_f']; X.loc[k,'tk']=X.loc[k,'tk_f']
    X=X.drop(columns=['finish_position','date_f','tk_f']).merge(fin[['first']].rename(columns={'first':'finish_position'}).reset_index(),on=['race_id','d'],how='left')
    return X,len(bad)
# known answers, worked by hand
assert band(2.99)=='<3' and band(3)=='3-6' and band(11.99)=='6-12' and band(12) is None
assert abs(value('B',3.0,True)-19.404)<1e-9 and value('B',3.0,False)==-10.0 and abs(value('L',3.0,False)-10/2.05*.98)<1e-9 and value('L',3.0,True)==-10.0 and np.isnan(value('B',1.02,True))
assert trainer_states(0,0)==[] and trainer_states(3,0)==[] and trainer_states(4,0)==['TR_COLD'] and trainer_states(1,1)==['TR_WON'] and trainer_states(5,2)==['TR_WON','TR_WON2'] and trainer_states(9,1)==['TR_WON']
assert session(12)=='AM' and session(13)=='PM' and session(17)=='PM' and session(18)=='EVE' and session(0)=='AM'
_n=float('nan')
assert kennel_pair([2.0,5.0])=={0:'KENNEL_SHORT',1:'KENNEL_LONG'} and kennel_pair([5.0,2.0])=={1:'KENNEL_SHORT',0:'KENNEL_LONG'}
assert kennel_pair([2.0,2.0])=={} and kennel_pair([2.0,_n])=={} and kennel_pair([2.0,3.0,4.0])=={} and kennel_pair([2.0])=={}
assert abs(zdiff([0,1]*50,[0,1]*50))<1e-9 and zdiff([0,1]*50,[0,0,0,1]*50)>2
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
rc=psycopg2.connect(creds.pg_railway(),sslmode='require')
C0=pd.read_sql("SELECT race_date,track,race_id,race_time,greyhound,trap_number,finish_position,trainer,fetched_at FROM greyhound_racecards_today",rc); rc.close()
C0['tk']=C0.track.str.strip().str.lower(); C0['d']=C0.greyhound.map(dog); C0['date']=pd.to_datetime(C0.race_date).dt.date; C0['fa']=pd.to_datetime(C0.fetched_at,utc=True)
C0['tr']=C0.trainer.astype(str).str.strip().str.lower().where(C0.trainer.notna()&(C0.trainer.astype(str).str.strip()!=''))
_d=C0[C0.duplicated(['race_id','d'],keep=False)].groupby(['race_id','d']); print(f"card rows {len(C0)}; pairs saved twice {_d.ngroups}, with two trainers {(_d.tr.nunique()>1).sum()}; trainers {C0.tr.nunique()}; rows no trainer {C0.tr.isna().mean():.4f} | {time.time()-T0:.0f}s",flush=True)
C,nbad=correct_cards(C0); print(f"races removed, two finishes {nbad}; rows {len(C)}",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
F=[]
for a,b in (('2026-05-01','2026-06-01'),('2026-06-01','2026-07-01'),('2026-07-01','2026-08-01'),('2026-08-01','2026-09-01'),('2026-09-01','2026-10-01'),('2026-10-01','2026-11-05')):
    cur.execute("""SELECT market_id,event_name,market_time,sel,ts,ltp::float8 FROM bf_hist_other WHERE sport='Greyhound Racing' AND market_type='WIN' AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND market_time>=%s AND market_time<%s""",(a,b))
    x=pd.DataFrame(cur.fetchall(),columns='market_id event_name market_time sel ts ltp'.split()); F.append(x)
con.close(); P=pd.concat(F,ignore_index=True); del F; P['mt']=pd.to_datetime(P.market_time,utc=True); P['t']=pd.to_datetime(P.ts,utc=True); P['mins']=(P.mt-P.t)/pd.Timedelta(minutes=1)
P=P.sort_values(['market_id','sel','t'],kind='stable')
Mk=P.drop_duplicates(['market_id','sel'])[['market_id','event_name','mt','sel']].copy(); Mk['tk']=Mk.event_name.map(track); Mk['d']=Mk.sel.map(dog); Mk['date']=Mk.mt.dt.tz_convert('Europe/London').dt.date
W=P[(P.mins>=5)&(P.mins<=20)].groupby(['market_id','sel'],sort=False).tail(1)[['market_id','sel','t','ltp']]; del P; print(f"tape loaded, markets {Mk.market_id.nunique()} | {time.time()-T0:.0f}s",flush=True)
J=Mk.merge(C[['date','tk','d','race_id','tr','finish_position','race_time']],on=['date','tk','d'],how='left')
first,last=Mk.date.min(),Mk.date.max(); Cw=C[(C.date>=first)&(C.date<=last)]
hit=J.dropna(subset=['race_id']); rc_per=hit.groupby('market_id').race_id.nunique(); hit=hit[hit.market_id.isin(rc_per[rc_per==1].index)]
wn=hit[hit.finish_position==1].groupby('market_id').d.nunique(); one=wn[wn==1].index; dead=int((wn>1).sum())
MM=Mk.drop_duplicates('market_id').copy(); MM['mm']=MM.mt.dt.hour*60+MM.mt.dt.minute; bytd={k:g.mm.values for k,g in MM.groupby(['date','tk'])}
good=set(hit[hit.market_id.isin(one)].race_id); U=Cw[Cw.finish_position==1].drop_duplicates('race_id').copy()
def holds(r):
    a=bytd.get((r.date,r.tk))
    if a is None: return False
    try: h,m=str(r.race_time).split(':')[:2]; x=int(h)*60+int(m)
    except Exception: return False
    return bool((np.abs(a-x)<=2).any())
U['ok']=U.race_id.isin(good); U['held']=[r.ok or holds(r) for r in U.itertuples()]; rate=U[U.held].ok.mean()
miss=set(J[J.market_id.isin(one)&J.race_id.isna()].market_id.unique()); use=[m for m in one if m not in miss]
print(f"GATE {rate:.3f} of {int(U.held.sum())} v 0.80; dead heats {dead}; tape runner not on card {len(miss)}; scored races {len(use)}; ENGINE CHECK item 241 read 5,638",flush=True)
if rate<0.80: print("\n== SURVIVORS: none; join gate SHUT, items BLOCKED"); sys.exit(0)
# meeting order from every tape market, scored or not
MM['lon']=MM.mt.dt.tz_convert('Europe/London'); MM['hr']=MM.lon.dt.hour; g=MM.sort_values('mt',kind='stable').groupby(['date','tk']); MM['rank']=g.cumcount()+1; MM['size']=g.market_id.transform('size')
print("tape markets a meeting, median",MM.groupby(['date','tk']).size().median(),"; meetings with one market",int((MM.groupby(['date','tk']).size()==1).sum()),flush=True)
ORD=MM.set_index('market_id')[['hr','rank','size']]
R=J[J.market_id.isin(use)].copy(); R['won']=R.finish_position==1
assert R.duplicated(['market_id','d']).sum()==0,"more than one row per dog per race"
assert (R.groupby('market_id').won.sum()==1).all(),"a scored race without exactly one winner"
R=R.merge(W,on=['market_id','sel'],how='left'); R=R.join(ORD,on='market_id')
SK=Counter(); rows=[]; ctrl=[]
for (tk,dt),G in R.groupby(['tk','date'],sort=False):
    races=[(g.mt.iloc[0],m,g) for m,g in G.groupby('market_id',sort=False)]; races.sort(key=lambda z:z[0])
    for ri,(mt,m,g) in enumerate(races):
        kp={}; byt=defaultdict(list)
        for r in g.itertuples():
            if r.tr==r.tr and r.tr is not None: byt[r.tr].append(r)
        for tr_,rs in byt.items():
            if len(rs)>=3: SK['trainers with 3 or more in a race']+=1
            if len(rs)==2:
                for idx,s in kennel_pair([float(x.ltp) if x.ltp==x.ltp else _n for x in rs]).items(): kp[rs[idx].d]=s
        for r in g.itertuples():
            if pd.isna(r.ltp): SK['runner no print 5 to 20 min before the off']+=1; continue
            p=float(r.ltp); b=band(p)
            if b is None: SK['runner 12 or over']+=1; continue
            st=[session(int(r.hr))]
            if r.rank==1 and r.size>=2: st.append('FIRST')
            if r.rank==r.size and r.size>=2: st.append('LAST')
            if r.d in kp: st.append(kp[r.d])
            if r.tr==r.tr and r.tr is not None:
                lim=r.t-pd.Timedelta(minutes=5); nr=nw=0
                for z in races[:ri]:
                    if z[0]>lim: continue
                    e=z[2][z[2].tr==r.tr]; nr+=len(e); nw+=int(e.won.sum())
                st+=trainer_states(nr,nw)
            else: SK['runner no trainer']+=1
            vb,vl=value('B',p,bool(r.won)),value('L',p,bool(r.won)); err=float(r.won)-1/p; w=mt.value
            ctrl.append((b,m,r.d,vb,vl,err,w,bool(r.won),p))
            for s in st: rows.append((s,b,m,r.d,vb,vl,err,w,bool(r.won),p))
print(f"counts {dict(sorted(SK.items()))} | {time.time()-T0:.0f}s",flush=True)
D=pd.DataFrame(rows,columns='state bd m d B L err when won p'.split()); Cc=pd.DataFrame(ctrl,columns='bd m d B L err when won p'.split())
assert Cc.duplicated(['m','d']).sum()==0 and D.duplicated(['state','m','d']).sum()==0
ITEM={'TR_WON':242,'TR_WON2':242,'TR_COLD':242,'AM':243,'PM':243,'EVE':243,'FIRST':243,'LAST':243,'KENNEL_SHORT':244,'KENNEL_LONG':244}
print("state runners in bands before any price is scored:",D.groupby('state').size().to_dict(),flush=True)
def mk(x,side,**k):
    x=x.assign(v=x[side]).dropna(subset=['v']); md=np.median(x.when.values); l=line(x.v.values,np.where(x.when.values<md,1,2)); tr=tstat(x.groupby('m').v.sum().values)
    return dict(**k,side=side,n=l['n'],races=x.m.nunique(),per10=l['per10'],t=l['t'],t_race=tr,h1=l['h1'],h2=l['h2'],n1=l['n1'],n2=l['n2'],won=x.won.mean(),implied=(1/x.p).mean(),PASS=l['PASS'] and tr>=3.5)
out=[]
for s,it in ITEM.items():
    for b in ('<3','3-6','6-12'):
        x=D[(D.state==s)&(D.bd==b)]
        if not len(x): continue
        c=Cc[Cc.bd==b]; keys=set(zip(x.m,x.d)); f=np.array([k in keys for k in zip(c.m,c.d)]); z=zdiff(c.err[f],c.err[~f]) if f.sum()>1 and (~f).sum()>1 else np.nan
        for side in 'BL': out.append(mk(x,side,item=it,state=s,band=b,z=z))
T=pd.DataFrame(out).sort_values('t',ascending=False)
print(f"\n== ALL {len(T)} LINES (18 + 30 + 12), by t; z is won minus 1/print against the rest of the band\n",T.round(3).to_string(index=False))
print("\n== CONTROL every runner in the band, cannot pass")
print(pd.DataFrame([mk(Cc[Cc.bd==b],side,band=b) for b in ('<3','3-6','6-12') for side in 'BL']).drop(columns='PASS').round(3).to_string(index=False))
Wn=T[T.PASS]; print(f"\n== SURVIVORS: {len(Wn)} of {len(T)}\n",Wn.round(3).to_string(index=False) if len(Wn) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
