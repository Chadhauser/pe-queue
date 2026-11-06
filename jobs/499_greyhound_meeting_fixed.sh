#!/bin/bash
set -o pipefail
# 499_greyhound_meeting_fixed (Finder 2026-11-06, queue item 241; from jobs/499_greyhound_meeting_trap.sh, jobs/499_greyhound_card_form.sh): item 175's 44 meeting lines on the corrected card rows. No new cuts. Rule pushed before any price was read, in the queue text of item 241.
# TAPE: bf_hist_other Greyhound WIN, pre-off last-traded prints, so a pass is an upper bound. TRUTH: greyhound_racecards_today (Railway, this one table read).
# ONLY CHANGE from job 175: date, track and finish as job 499_greyhound_card_form: finish from any row, a race whose rows disagree on a dog's finish goes, date and track from the result row, other fields (the trap) from the earliest save. Gate as that job: >= 80% of winner races the tape holds at that track and time.
# ENTRY, STATES, NO LOOK-AHEAD: as job 175, unchanged: last print 5 to 20 min before the off, one tick adverse, over 50 not traded, settled at the result, 2%, £10; an earlier race counts only if scored and off at least 5 min before the entry print.
# ENGINE CHECK: the same code on today's table-order rows, against the old log. One bet per race per line, so t is by race.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(3_500_000_000,3_500_000_000))  # this job only
import sys,re,os,time,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,line,back_settle,lay_settle,tstat
pd.set_option('display.width',230); pd.set_option('display.max_rows',150); pd.set_option('display.max_columns',30)
T0=time.time()
OLDLOG='/root/pe-queue-logs/499_greyhound_meeting_trap.log'
def dog(s): return re.sub(r'[^a-z0-9]','',re.sub(r'^\s*\d+\.\s*','',str(s)).lower())
def track(e):
    m=re.match(r'^(.*?)\s+\d+(st|nd|rd|th)\s+\w+$',str(e)); return (m.group(1) if m else str(e)).strip().lower()
def band(p): return '<3' if p<3 else '3-6' if p<6 else '6-12' if p<12 else '12-50' if p<=50 else None
def trap_states(wins,trap):
    """wins: winning traps of the counted earlier races, oldest first. States this trap is in."""
    k=len(wins); w=sum(1 for x in wins if x==trap); out=[]
    if k<4: return out
    if w>=3 and w/k>=0.40-1e-9: out.append('HOT')
    if w==0 and k>=6: out.append('COLD')
    if wins[-1]==trap: out.append('REPEAT1')
    if wins[-2:]==[trap,trap]: out.append('REPEAT2')
    return out
def fav_states(flags):
    """flags: did the favourite win, counted earlier races with a unique favourite, oldest first."""
    out=[]
    if len(flags)>=3 and all(flags[-3:]): out.append('FAVHOT')
    if len(flags)>=4 and not any(flags[-4:]): out.append('FAVCOLD')
    return out
def value(side,x,won):
    if x>50: return None
    if side=='B':
        a=step(x,-1)
        return None if a<=1.01 else back_settle(a,won)
    return lay_settle(step(x,1),won)
def correct_cards(C):
    """One row per race and dog, as job 499_greyhound_card_form: finish from any row, date and track from the result row, the rest from the earliest save; a race with two finishes for one dog goes."""
    fin=C.dropna(subset=['finish_position']).groupby(['race_id','d']).finish_position.agg(['nunique','first'])
    bad=set(fin[fin['nunique']>1].index.get_level_values(0))
    X=C[~C.race_id.isin(bad)].sort_values('fa',kind='stable')
    RF=X.dropna(subset=['finish_position']).drop_duplicates(['race_id','d'],keep='last')[['race_id','d','date','tk']].rename(columns={'date':'date_f','tk':'tk_f'})
    X=X.merge(RF,on=['race_id','d'],how='left').drop_duplicates(['race_id','d'],keep='first')
    k=X.date_f.notna(); X.loc[k,'date']=X.loc[k,'date_f']; X.loc[k,'tk']=X.loc[k,'tk_f']
    X=X.drop(columns=['finish_position','date_f','tk_f']).merge(fin[['first']].rename(columns={'first':'finish_position'}).reset_index(),on=['race_id','d'],how='left')
    return X,len(bad)
# known answers, worked by hand
assert dog('1. Insane View')==dog('Insane  View') and track('Central Park 15th Sep')=='central park'
assert band(2.99)=='<3' and band(3)=='3-6' and band(12)=='12-50' and band(50)=='12-50' and band(51) is None
assert trap_states([1,2,3],1)==[] and trap_states([1,1,1,2,3],1)==['HOT'] and trap_states([1,1,2,3,4,5,6,2],1)==[] and trap_states([1,1,1,2,3,4,5,6],1)==[]
assert trap_states([2,3,4,5,6,2],1)==['COLD'] and trap_states([2,3,4,5,6],1)==[] and trap_states([2,3,4,1],1)==['REPEAT1'] and trap_states([2,3,1,1],1)==['REPEAT1','REPEAT2']
assert fav_states([True,True,True])==['FAVHOT'] and fav_states([False,True,True,True])==['FAVHOT'] and fav_states([True,True])==[]
assert fav_states([False]*4)==['FAVCOLD'] and fav_states([False]*3)==[] and fav_states([True,False,False,False,False])==['FAVCOLD']
assert abs(value('B',3.0,True)-19.404)<1e-9 and value('B',3.0,False)==-10.0 and abs(value('L',3.0,False)-10/2.05*.98)<1e-9 and value('L',3.0,True)==-10.0 and value('B',51.,True) is None and value('B',1.02,True) is None
# Card rows: a: stale row on 1 Jan at X saved first, trap 2; result row on 2 Jan at Y, trap 3 -> 2 Jan, Y, finish 1, trap 2. b: earlier row has the finish, later row none -> finish 4. c: two finishes -> race 2 goes whole, with its other dog e. d: no finish -> own date, finish missing.
_t=pd.to_datetime(['2026-01-01 10:00','2026-01-02 20:00','2026-01-02 10:00','2026-01-02 11:00','2026-01-02 10:00','2026-01-02 11:00','2026-01-02 10:00','2026-01-03 10:00'],utc=True)
_C=pd.DataFrame(dict(race_id=[1,1,1,1,2,2,2,3],d=list('aabbcced'),date=['01','02','02','02','02','02','02','03'],tk=list('XYYYYYYZ'),fa=_t,trap_number=[2,3,5,5,1,1,6,4],finish_position=[np.nan,1,4,np.nan,2,3,5,np.nan]))
_X,_b=correct_cards(_C); assert _b==1 and sorted(_X.race_id.unique())==[1,3] and len(_X)==3
_a=_X[_X.d=='a'].iloc[0]; assert _a.date=='02' and _a.tk=='Y' and _a.finish_position==1 and _a.trap_number==2
assert _X[_X.d=='b'].iloc[0].finish_position==4
_e=_X[_X.d=='d'].iloc[0]; assert _e.date=='03' and _e.tk=='Z' and _e.finish_position!=_e.finish_position
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
rc=psycopg2.connect(creds.pg_railway(),sslmode='require')
C0=pd.read_sql("SELECT race_date,track,race_id,race_time,greyhound,trap_number,finish_position,fetched_at FROM greyhound_racecards_today",rc); rc.close()
C0['tk']=C0.track.str.strip().str.lower(); C0['d']=C0.greyhound.map(dog); C0['date']=pd.to_datetime(C0.race_date).dt.date; C0['fa']=pd.to_datetime(C0.fetched_at,utc=True)
print(f"card rows {len(C0)}, races {C0.race_id.nunique()}, dates {C0.date.min()} to {C0.date.max()} | {time.time()-T0:.0f}s",flush=True)
_d=C0[C0.duplicated(['race_id','d'],keep=False)].groupby(['race_id','d']); print(f"race and dog pairs saved twice {_d.ngroups}; of those with two traps {(_d.trap_number.nunique()>1).sum()}",flush=True)
OLDC=C0.drop_duplicates(['race_id','d']).copy()   # job 175's reading: first row by table order
NEWC,nbad=correct_cards(C0); print(f"races removed, two finishes for one dog {nbad}; one row per race and dog: table order {len(OLDC)}, corrected {len(NEWC)}",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
F=[]
for a,b in (('2026-05-01','2026-06-01'),('2026-06-01','2026-07-01'),('2026-07-01','2026-08-01'),('2026-08-01','2026-09-01'),('2026-09-01','2026-10-01'),('2026-10-01','2026-11-05')):
    cur.execute("""SELECT market_id,event_name,market_time,sel,ts,ltp::float8 FROM bf_hist_other WHERE sport='Greyhound Racing' AND market_type='WIN' AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND market_time>=%s AND market_time<%s""",(a,b))
    x=pd.DataFrame(cur.fetchall(),columns='market_id event_name market_time sel ts ltp'.split()); F.append(x); print(f"  {a} rows {len(x)} | {time.time()-T0:.0f}s",flush=True)
con.close(); P=pd.concat(F,ignore_index=True); del F; P['mt']=pd.to_datetime(P.market_time,utc=True); P['t']=pd.to_datetime(P.ts,utc=True); P['mins']=(P.mt-P.t)/pd.Timedelta(minutes=1)
P=P.sort_values(['market_id','sel','t'],kind='stable')
Mk=P.drop_duplicates(['market_id','sel'])[['market_id','event_name','mt','sel']].copy(); Mk['tk']=Mk.event_name.map(track); Mk['d']=Mk.sel.map(dog); Mk['date']=Mk.mt.dt.tz_convert('Europe/London').dt.date
W=P[(P.mins>=5)&(P.mins<=20)].groupby(['market_id','sel'],sort=False).tail(1)[['market_id','sel','t','ltp']]; del P   # sorted by time, so tail = last print in the window
MM=Mk.drop_duplicates('market_id').copy(); MM['mm']=MM.mt.dt.hour*60+MM.mt.dt.minute; bytd={k:g.mm.values for k,g in MM.groupby(['date','tk'])}
def score(C,label):
    print(f"\n#### {label}",flush=True)
    J=Mk.merge(C[['date','tk','d','race_id','trap_number','finish_position','race_time']],on=['date','tk','d'],how='left')
    first,last=Mk.date.min(),Mk.date.max(); Cw=C[(C.date>=first)&(C.date<=last)]; cards_w=Cw[Cw.finish_position==1].race_id.unique()
    hit=J.dropna(subset=['race_id']); rc_per=hit.groupby('market_id').race_id.nunique(); hit=hit[hit.market_id.isin(rc_per[rc_per==1].index)]
    wn=hit[hit.finish_position==1].groupby('market_id').d.nunique(); one=wn[wn==1].index; dead=int((wn>1).sum()); joined=hit[hit.market_id.isin(one)].race_id.nunique()
    good=set(hit[hit.market_id.isin(one)].race_id); U=Cw[Cw.finish_position==1].drop_duplicates('race_id').copy()
    def holds(r):
        a=bytd.get((r.date,r.tk))
        if a is None: return False
        try: h,m=str(r.race_time).split(':')[:2]; x=int(h)*60+int(m)
        except Exception: return False
        return bool((np.abs(a-x)<=2).any())
    U['ok']=U.race_id.isin(good); U['held']=[r.ok or holds(r) for r in U.itertuples()]
    rate=U[U.held].ok.mean(); print(f"card races with a winner in the tape's dates {len(cards_w)}; joined {joined} = {joined/max(1,len(cards_w)):.3f}; dead heats {dead}; GATE, tape holds the race, {rate:.3f} of {int(U.held.sum())} v 0.80; tape markets {Mk.market_id.nunique()}",flush=True)
    miss=set(J[J.market_id.isin(one)&J.race_id.isna()].market_id.unique()); use=[m for m in one if m not in miss]; print(f"races removed, tape runner not on the card {len(miss)}; scored races {len(use)}",flush=True)
    _h=hit[hit.market_id.isin(use)].groupby('race_id').market_id.nunique(); print(f"card races joined to more than one scored market: {int((_h>1).sum())} of {len(_h)}",flush=True)
    R0=J[J.market_id.isin(use)].copy(); R0['won']=R0.finish_position==1; R0['trap']=pd.to_numeric(R0.trap_number,errors='coerce')
    assert R0.duplicated(['market_id','d']).sum()==0,"more than one row per dog per race"
    assert (R0.groupby('market_id').won.sum()==1).all(),"a scored race without exactly one winner"
    R0=R0.merge(W,on=['market_id','sel'],how='left'); SK=Counter(); rows=[]; ctrl=[]; RACES=0
    for (tk,dt),G in R0.groupby(['tk','date'],sort=False):
        races=[]
        for m,g in G.groupby('market_id',sort=False):
            pr=g.dropna(subset=['ltp']); fav=None
            if len(pr):
                lo=pr.ltp.min(); c=pr[pr.ltp==lo]
                if len(c)==1: fav=c.d.iloc[0]
            w=g[g.won]; races.append((g.mt.iloc[0],m,g,fav,int(w.trap.iloc[0]) if len(w)==1 and pd.notna(w.trap.iloc[0]) else None,None if fav is None else bool(g[g.d==fav].won.iloc[0])))
        races.sort(key=lambda z:z[0])
        for ri,(mt,m,g,fav,wt,fw) in enumerate(races):
            RACES+=1
            for r in g.itertuples():
                if pd.isna(r.ltp): SK['runner no print 5 to 20 min before the off']+=1; continue
                b=band(r.ltp)
                if b is None: SK['runner over 50']+=1; continue
                for side in 'BL':
                    v=value(side,float(r.ltp),bool(r.won))
                    if v is None: continue
                    ctrl.append((b,side,m,v,mt))
                if pd.isna(r.trap): SK['runner no trap']+=1; continue
                lim=r.t-pd.Timedelta(minutes=5); E=[z for z in races[:ri] if z[0]<=lim]
                wins=[z[4] for z in E if z[4] is not None]; st=trap_states(wins,int(r.trap))
                for s in st:
                    for side in 'BL':
                        v=value(side,float(r.ltp),bool(r.won))
                        if v is not None: rows.append((s,b,side,m,int(r.trap),v,mt,bool(r.won),float(r.ltp)))
                if r.d==fav:
                    for s in fav_states([z[5] for z in E if z[5] is not None]):
                        for side in 'BL':
                            v=value(side,float(r.ltp),bool(r.won))
                            if v is not None: rows.append((s,'ALL',side,m,int(r.trap),v,mt,bool(r.won),float(r.ltp)))
    print(f"races {RACES}; counts {dict(sorted(SK.items()))} | {time.time()-T0:.0f}s",flush=True)
    D=pd.DataFrame(rows,columns='state bd side m trap v mt won px'.split())
    if D.empty: print("ERROR: no entries, no verdict"); sys.exit(1)
    D['when']=[x.value for x in D.mt]; D=D.sort_values('trap',kind='stable'); out=[]
    def add(x,bd):
        x=x.drop_duplicates('m'); md=np.median(x.when.values); l=line(x.v.values,np.where(x.when.values<md,1,2))
        out.append(dict(state=x.state.iloc[0],band=bd,side=x.side.iloc[0],n=l['n'],races=x.m.nunique(),per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2'],n1=l['n1'],n2=l['n2'],won=x.won.mean(),implied=(1/x.px).mean(),maxwin=l['maxwin'],PASS=l['PASS']))
    for (s,side),A in D.groupby(['state','side']):
        if s.startswith('FAV'): add(A,'ALL'); continue
        add(A,'ALL')
        for bd in ('<3','3-6','6-12','12-50'):
            x=A[A.bd==bd]
            if len(x): add(x,bd)
    S=pd.DataFrame(out).sort_values('t',ascending=False)
    Cc=pd.DataFrame(ctrl,columns='bd side m v mt'.split()); print("CONTROL every runner by band, not scored")
    for (b,side),x in Cc.groupby(['bd','side']): print(f"  {b} {side} n {len(x)} per10 {x.v.mean():+.3f} t by race {tstat(x.groupby('m').v.sum().values):.2f}")
    return S,rate,set(use)
So,_,uo=score(OLDC,'ENGINE CHECK: table-order rows, as job 175')
Sn,rate,un=score(NEWC,'CORRECTED rows')
print(f"\nscored races: table order {len(uo)}, corrected {len(un)}, both {len(uo&un)}, only table order {len(uo-un)}, only corrected {len(un-uo)}")
if rate<0.80: print("\n== SURVIVORS: none; join gate SHUT, item BLOCKED"); sys.exit(0)
K=['state','band','side']
M=Sn.merge(So[K+['n','per10','t']],on=K,how='outer',suffixes=('','_tab'))
if os.path.exists(OLDLOG):
    rows=[]; on=False
    for s in open(OLDLOG):
        if s.startswith('== ALL'): on=True; continue
        if s.startswith('== CONTROL'): break
        f=s.split()
        if on and len(f)==15 and f[0]!='state': rows.append(dict(state=f[0],band=f[1],side=f[2],n_log=int(f[3]),per10_log=float(f[5]),t_log=float(f[6])))
    Lg=pd.DataFrame(rows); print(f"old log lines read {len(Lg)}"); M=M.merge(Lg,on=K,how='outer')
    x=M.dropna(subset=['n_tab','n_log']); print(f"ENGINE CHECK table-order today v old log: {len(x)} lines, n equal on {(x.n_tab==x.n_log).sum()}, largest n gap {(x.n_tab-x.n_log).abs().max()}, largest per10 gap {(x.per10_tab-x.per10_log).abs().max():.3f}")
M=M.sort_values('t',ascending=False); cols=K+['n','races','per10','t','h1','h2','n1','n2','won','implied','maxwin','PASS','n_tab','per10_tab','t_tab']+[c for c in ('n_log','per10_log','t_log') if c in M]
print(f"\n== {len(M)} LINES, corrected v table order v old log, by corrected t\n",M[cols].round(3).to_string(index=False))
Wn=Sn[Sn.PASS]; print(f"\n== SURVIVORS: {len(Wn)} of {len(Sn)}\n",Wn.round(3).to_string(index=False) if len(Wn) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
