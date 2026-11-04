#!/bin/bash
set -o pipefail
# 499_final_print_bias (Finder 2026-11-04, queue item 67): does "a runner's final print <= 1.05 (or 1.10) means it won" fire evenly across true outcomes, and do verdicts change when the lines are rescored on real results?
# SECTIONS (argv: any of football racing cricket tennis; default all; asserts-only stops after the checks):
#  football = job 464 (bf_hist_price, MO, first print in minutes 0-2, rule: last print at minute >= 88 is <= 1.10 and every other >= 5). Truth: af_price_map, then unique name + date match in af_fixtures status FT, then fd_matches. AET/PEN excluded: Match Odds settles at 90 min.
#  racing   = jobs 481, 497 (ip_tape WIN, rule: one runner <= 1.05 on the last OPEN snapshot). Truth: racing_results, exact market_id + selection_id, one winner only (dead heats counted, excluded). UK/IE races only: racing_results records nothing else, so about 83% of the worldwide tape has no truth. The first run applied the 80% gate to all tape races and failed at 0.168; the gate was then changed to UK/IE races, see the code.
#  Differences from the jobs: 493's P25/P50/P75 states are left out (look-ahead, could never pass). Football uses the real ladder at tick boundaries (2.0 fills 1.99, 464 used 1.98), so old_known can differ slightly from 464's own figures.
#  cricket  = job 493 (bf_hist_other MATCH_ODDS to the end of cricket_matches). Truth: cricket_matches by team names + date; NULL winner excluded.
#  tennis   = PROXY for jobs 482, 495 (458 excludes tennis): ip_tape starts 30 Oct and tennis_results_2026 ends 25 Sep, so those tapes have NO results; firing is measured on bf_hist_other Tennis singles instead. No rescoring.
#  basketball (458, 497): no results table on the box. Said here, not tested.
# COST as the jobs: one tick adverse, 2% commission on profit, £10 risk. A rescored line settles at the real result; nothing is dropped except markets with no real result, which are counted. Read only.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,re,time,random,unicodedata,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
warnings.filterwarnings('ignore')
pd.set_option('display.width',230); pd.set_option('display.max_rows',120); pd.set_option('display.max_columns',30)
sys.path.insert(0,'/root/pe-queue/runner'); import creds
T0=time.time()
ARGS=[a for a in sys.argv[1:]]; ONLY=set(ARGS)-{'asserts-only'}
def want(s): return not ONLY or s in ONLY
LAD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    x=lo
    while x<hi-1e-9: LAD.append(round(x,2)); x+=st
LAD.append(1000.0); LADA=np.array(LAD)
def pos(p): return int(np.searchsorted(LADA,round(float(p),2)-1e-9))
def dn(p): return float(LADA[max(pos(p)-1,0)])
def up(p): return float(LADA[min(pos(p)+1,len(LADA)-1)])
def comm(x): return x*0.98 if x>0 else x
def back_settle(p,won):
    a=dn(p)
    if a<=1.01: return np.nan
    return comm(10*(a-1)) if won else -10.0
def lay_settle(p,won):
    a=up(p); return -10.0 if won else comm(10/(a-1))
def back_scalp(p,q):
    a=dn(p)
    return np.nan if a<=1.01 else comm(10*(a/up(q)-1))
def lay_scalp(p,q):
    a=up(p); return comm(10/(a-1)*(1-a/dn(q)))
def tstat(v):
    v=np.asarray(v,dtype=float); v=v[np.isfinite(v)]
    if len(v)<2: return 0.0
    s=v.std(ddof=1); return float(v.mean()/(s/len(v)**0.5)) if s>0 else 0.0
STOP=r"\b(fc|cf|afc|sc|ac|as|ss|us|sv|vfb|vfl|tsg|fk|club|de|the|cd|ud|sd|rcd|calcio|if|bk|ff|aif|sk|fsv)\b"
def norm(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
    s=re.sub(STOP," ",s)
    return frozenset(w for w in re.sub(r"[^a-z0-9 ]"," ",s).split() if len(w)>1)
def fold(s): return re.sub(r"[^a-z]","",unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower())
def infer_464(last):
    """last: selection -> last print at minute >= 88. 464's rule."""
    v={k:x for k,x in last.items() if x==x}
    if len(v)<2: return None
    w=[k for k,x in v.items() if x<=1.10]
    return w[0] if len(w)==1 and all(x>=5 for k,x in v.items() if k!=w[0]) else None
def winner_105(last):
    w=[k for k,v in last.items() if v is not None and v<=1.05]
    return w[0] if len(w)==1 else None
def result_of(fin):
    w=[s for s,p in fin.items() if p<=1.05]
    if len(w)==1: return {s:s==w[0] for s in fin},False
    if len(w)>1: return {s:None for s in fin},True
    return {s:(False if p>=100 else None) for s,p in fin.items()},False
def hda(h,a): return 'HOME' if h>a else ('AWAY' if h<a else 'DRAW')
def home_race(ev,venues):
    """UK/IE: no country tag in the event name, and the venue is one racing_results records."""
    ev=str(ev)
    if '(' in ev: return False
    return re.sub(r"\s+\d.*$","",ev).strip() in venues
def early_end(score):
    return bool(re.search(r"RET|W/O|WO|DEF|ABN",str(score).upper()))
def trigger(ser,x):
    off=ser[0]
    for i in range(1,len(ser)):
        if ser[i]<=off*(1-x)+1e-9: return i
    return None
def clean_mask(tm):
    tm=np.asarray(tm,dtype=float); out=np.ones(len(tm),dtype=bool); mx=-np.inf
    for i,v in enumerate(tm):
        if np.isnan(v): continue
        if v<mx: out[i]=False
        else: mx=v
    return out
def frame_clean(d):
    f=d.groupby(['market_id','ts'],sort=True).tm.max().reset_index()
    f['ok']=np.concatenate([clean_mask(g.tm.values) for _,g in f.groupby('market_id',sort=False)])
    return d[['market_id','ts']].merge(f[['market_id','ts','ok']],on=['market_id','ts'],how='left').ok.values
def gate(v,when):
    """v: P&L, when: sortable. Returns n, mean, t, h1, h2, PASS by the house gate, halves at the median of when."""
    m=np.isfinite(v); v=v[m]; when=when[m]
    if len(v)==0: return dict(n=0,mean=np.nan,t=0.0,n1=0,h1=np.nan,n2=0,h2=np.nan,PASS=False)
    md=np.median(when); a=v[when<md]; b=v[when>=md]; t=tstat(v)
    return dict(n=len(v),mean=v.mean(),t=t,n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,
                PASS=bool(len(v)>=300 and len(a)>=150 and len(b)>=150 and t>=3.5 and len(a) and a.mean()>0 and len(b) and b.mean()>0 and v.mean()>=0.15))
# known answers, worked by hand
assert dn(2.0)==1.99 and up(2.0)==2.02 and dn(3.0)==2.98 and up(3.0)==3.05 and up(1.99)==2.0
assert abs(back_settle(2.0,True)-9.702)<1e-9 and back_settle(2.0,False)==-10.0 and np.isnan(back_settle(1.02,True))   # 10 x 0.99 x 0.98
assert abs(lay_settle(3.0,False)-10/2.05*0.98)<1e-9 and lay_settle(3.0,True)==-10.0
assert abs(back_scalp(2.0,1.8)-0.97459)<1e-4 and abs(lay_scalp(2.0,2.5)-1.78210)<1e-4
assert infer_464(dict(HOME=1.05,AWAY=30.0,DRAW=12.0))=='HOME' and infer_464(dict(HOME=1.05,AWAY=4.0,DRAW=12.0)) is None      # another runner under 5: no call
assert infer_464(dict(HOME=1.5,AWAY=7.0,DRAW=3.0)) is None and infer_464(dict(HOME=1.05)) is None and infer_464(dict(HOME=1.05,AWAY=float('nan'),DRAW=9.0))=='HOME'
assert infer_464(dict(HOME=1.10,AWAY=5.0,DRAW=5.0))=='HOME'                                                                 # both limits inclusive
assert winner_105({'a':1.03,'b':40.0})=='a' and winner_105({'a':1.03,'b':1.04}) is None and winner_105({'a':2.0,'b':3.0}) is None and winner_105({'a':None,'b':1.05})=='b'
assert result_of({'A':1.03,'B':40.0})==({'A':True,'B':False},False) and result_of({'A':1.03,'B':1.04})==({'A':None,'B':None},True) and result_of({'A':2.0,'B':150.0})==({'A':None,'B':False},False)
assert hda(2,1)=='HOME' and hda(0,1)=='AWAY' and hda(1,1)=='DRAW' and hda(0,0)=='DRAW'
assert norm('FC Porto')==norm('Porto') and norm('Leeds')!=norm('Hull') and norm('India Women')!=norm('India') and fold('Tommy Paul')=='tommypaul' and fold('Jiří Lehečka')=='jirilehecka'
assert trigger([10.0,9.0,8.5,7.0],0.15)==2 and trigger([10.0,9.0],0.25) is None
assert home_race('Newmarket 31st Oct',{'Newmarket'}) and not home_race('Newcastle (AUS) 31st Oct',{'Newcastle'}) and not home_race('Philadelphia 31st Oct',{'Newmarket'})
assert early_end('6-1 3-2 RET') and early_end('W/O') and not early_end('6-1 6-4') and not early_end(None)
assert clean_mask([10,12,11,12,13,12.5]).tolist()==[True,True,False,True,True,False]
assert abs(tstat([1,3])-2.0)<1e-9
_g=gate(np.array([1.0]*300+[0.0]*300),np.arange(600.0)); assert _g['n']==600 and _g['n1']==300 and _g['n2']==300 and _g['h1']==1.0 and _g['h2']==0.0 and _g['PASS'] is False      # second half not positive
_g=gate(np.array([1.0,0.5]*200),np.arange(400.0)); assert _g['PASS'] is True and abs(_g['mean']-0.75)<1e-9
_g=gate(np.array([1.0,np.nan]),np.array([1.0,2.0])); assert _g['n']==1
print("known-answer checks: OK",flush=True)

def racing(A,lab,truth):
    """As job 497's racing(), plus the real winner. truth: market -> winning sel_id, absent = no real result."""
    SK=Counter(); rows=[]; fire=[]
    for mid,g in A.groupby('market_id',sort=False):
        tss=np.sort(g.ts.unique()); tidx={t:i for i,t in enumerate(tss)}
        if len(tss)<3:
            SK['under 3 snapshots']+=1
            if truth.get(mid) is not None: fire.append(dict(mode=lab,mid=mid,fired=False,agree=False,field='short',winner_off=np.nan,fav_won=np.nan,last_winner=np.nan))   # the job skips it, so the rule cannot call it; keeps the firing denominator honest
            continue
        la=g[g.ts==tss[-1]]; last={r.sel_id:(r.bp if pd.notna(r.bp) and r.bp>1 else (r.ltp if pd.notna(r.ltp) else None)) for r in la.itertuples()}
        win=winner_105(last); real=truth.get(mid); SK['clean single winner' if win is not None else 'unknown winner']+=1
        field=g[g.ts==tss[0]].sel_id.nunique(); fb='<=8' if field<=8 else '9-12' if field<=12 else '13+'
        two=g[(g.bp>1)&(g.lp>1)&(g.lp<1000)]; tr=[]; offs={}
        for sid,s in two.groupby('sel_id',sort=False):
            if s.ts.iloc[0]!=tss[0]: continue
            b=s.bp.values.astype(float); l=s.lp.values.astype(float); tt=s.ts.values; offs[sid]=b[0]
            if b[0]>50: SK['off over 50']+=1; continue
            for x,xl in ((0.15,'15%'),(0.25,'25%')):
                i=trigger(b,x)
                if i is None: continue
                ni=min(i+1,len(b)-1)
                tr.append(dict(x=xl,k=tidx[tt[i]],ts=tt[i],sid=sid,off=b[0],bn=b[ni],ln=l[ni],bw=min(b[i],b[ni]),lw=max(l[i],l[ni])))
        if real is not None:
            fav=min(offs,key=offs.get) if offs else None; op=offs.get(real,np.nan)
            fire.append(dict(mode=lab,mid=mid,fired=win is not None,agree=win==real,field=fb,winner_off=op,fav_won=real==fav,last_winner=last.get(real,np.nan) if last.get(real) is not None else np.nan))
        for xl in ('15%','25%'):
            for j,t in enumerate(sorted([t for t in tr if t['x']==xl],key=lambda t:t['k'])):
                w=None if win is None else t['sid']==win; wr=None if real is None else t['sid']==real
                ob='<3' if t['off']<3 else '3-6' if t['off']<6 else '6-12' if t['off']<12 else '12-50'
                for side,fill,v in (('BACK','NEXT',t['bn']),('BACK','WORSE',t['bw']),('LAY','NEXT',t['ln']),('LAY','WORSE',t['lw'])):
                    f=back_settle if side=='BACK' else lay_settle
                    rows.append(dict(mode=lab,x=xl,side=side,fill=fill,mid=mid,ts=t['ts'],first=j==0,off=ob,field=fb,worst=(f(v,w) if w is not None else -10.0),real=(f(v,wr) if wr is not None else np.nan)))
    print(f"{lab} racing:",dict(SK),flush=True)
    return rows,fire
# end-to-end on a tiny race, worked by hand: a trades 10, 8, 7, 1.03; next print after the 15% trigger at 8 is 7, fills 6.8. Rule says a won; the truth says b won, so inferred +56.84, real -10
_A=pd.DataFrame(dict(market_id=['m']*8,ts=[1,2,3,4]*2,sel_id=['a']*4+['b']*4,bp=[10.,8.,7.,1.03,5.,6.,7.,40.],lp=[11.,8.2,7.2,1.04,5.2,6.2,7.2,50.],ltp=[10.,8.,7.,1.03,5.,6.,7.,40.]))
_x,_f=racing(_A,'T',{'m':'b'}); _x=pd.DataFrame(_x); _y=_x[(_x.x=='15%')&(_x.side=='BACK')&(_x.fill=='NEXT')]
assert len(_y)==1 and abs(_y.worst.iloc[0]-10*5.8*0.98)<1e-9 and _y.real.iloc[0]==-10.0 and _f[0]['fired'] is True and _f[0]['agree'] is False and _f[0]['fav_won'] is True and _f[0]['winner_off']==5.0
_x,_f=racing(_A,'T',{}); assert np.isnan(pd.DataFrame(_x).real).all() and _f==[]                                    # no real result: not scored on it, and not in the firing table
_x,_f=racing(_A[_A.ts<=2],'T',{'m':'b'}); assert _x==[] and len(_f)==1 and _f[0]['fired'] is False                  # 2 snapshots: no trades, but counted as not fired
print("end-to-end checks: OK",flush=True)
if 'asserts-only' in ARGS: sys.exit(0)
def loc():
    c=psycopg2.connect(creds.pg_local()); c.autocommit=True; k=c.cursor(); k.execute("SET work_mem='64MB'; SET statement_timeout='2400s'"); return c,k
def rly():
    c=psycopg2.connect(creds.pg_railway(),sslmode='require'); c.autocommit=True; k=c.cursor(); k.execute("SET work_mem='64MB'; SET statement_timeout='2400s'; SET max_parallel_workers_per_gather=0"); return c,k
ALLS=[]   # every rescored line, for the final tally

def football():
    print("\n################ FOOTBALL (job 464)",flush=True)
    con,cur=loc()
    K=pd.read_sql("""SELECT DISTINCT ON (event_id, sel) event_id, country, hw, aw, sel, ltp::float ltp, m FROM bf_hist_price WHERE mkt='MO' AND minute BETWEEN 0 AND 2 AND ltp>=1.01 AND ltp<1000 ORDER BY event_id, sel, minute, m""",con)
    L=pd.read_sql("""SELECT DISTINCT ON (event_id, sel) event_id, sel, ltp::float lastp FROM bf_hist_price WHERE mkt='MO' AND minute>=88 AND ltp>=1.01 ORDER BY event_id, sel, minute DESC, m DESC""",con)
    print(f"kick-off prints {len(K)} ({K.event_id.nunique()} events) | late prints {len(L)} ({L.event_id.nunique()} events) | {time.time()-T0:.0f}s",flush=True)
    inf={}
    for eid,g in L.groupby('event_id'):
        r=infer_464(dict(zip(g.sel,g.lastp)))
        if r: inf[eid]=r
    E=K.drop_duplicates('event_id')[['event_id','hw','aw','m']].copy(); E['t']=pd.to_datetime(E.m,utc=True); E['H']=E.hw.map(norm); E['A']=E.aw.map(norm); E['d']=E.t.dt.date
    MP=pd.read_sql("""SELECT m.event_id, f.hg, f.ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL""",con)
    MP['res']=[hda(h,a) for h,a in zip(MP.hg,MP.ag)]; mp=dict(zip(MP.event_id,MP.res))
    F=pd.read_sql("SELECT home,away,kickoff,hg,ag FROM af_fixtures WHERE status='FT' AND hg IS NOT NULL AND kickoff>='2024-01-01'",con)
    D=pd.read_sql("SELECT home,away,date,fthg,ftag FROM fd_matches WHERE fthg IS NOT NULL",con)
    con.close()
    def build(df,kh,ka,kd,kg,kq):
        ix=defaultdict(list); dd=pd.to_datetime(df[kd],utc=True,errors='coerce').dt.date
        for h,a,d_,g,q in zip(df[kh],df[ka],dd,df[kg],df[kq]):
            if d_==d_ and d_ is not None: ix[(norm(h),norm(a))].append((d_,hda(g,q)))
        return ix
    IA=build(F,'home','away','kickoff','hg','ag'); ID=build(D,'home','away','date','fthg','ftag')
    def find(ix,H,A,d):
        hit=[r for dd,r in ix.get((H,A),[]) if abs((dd-d).days)<=1]
        return hit[0] if len(hit)==1 else None
    E['af']=[find(IA,h,a,d) for h,a,d in zip(E.H,E.A,E.d)]; E['fd']=[find(ID,h,a,d) for h,a,d in zip(E.H,E.A,E.d)]
    E['mapres']=E.event_id.map(mp)
    for s in ('af','fd'):
        g=E[E.mapres.notna()&E[s].notna()]; print(f"gate: {s} name match v af_price_map result on mapped events: n {len(g)}, agree {(g[s]==g.mapres).mean():.4f}",flush=True)
    g2=E[E.af.notna()&E.fd.notna()]; print(f"af v fd where both match: n {len(g2)}, agree {(g2.af==g2.fd).mean():.4f}",flush=True)
    E['true']=E.mapres.fillna(E.af).fillna(E.fd); E['src']=np.where(E.mapres.notna(),'map',np.where(E.af.notna(),'af_name',np.where(E.fd.notna(),'fd_name','none')))
    print("result source, events:",E.src.value_counts().to_dict(),f"| events with no real result {(E.src=='none').mean():.3f}",flush=True)
    E['inf']=E.event_id.map(inf); T=E[E.true.notna()]; Fi=T[T.inf.notna()]
    print(f"\n== RULE v TRUTH: events with truth {len(T)}, rule fires {T.inf.notna().mean():.3f}, agrees when it fires {(Fi.inf==Fi.true).mean():.4f} (n {len(Fi)})")
    for o,x in T.groupby('true'): print(f"  true {o:5s} n {len(x):6d} fires {x.inf.notna().mean():.3f} agrees-when-fires {(x[x.inf.notna()].inf==o).mean():.4f}")
    print(f"  true share of draws: all with truth {(T.true=='DRAW').mean():.3f} v where rule fires {(Fi.true=='DRAW').mean():.3f}; home {(T.true=='HOME').mean():.3f} v {(Fi.true=='HOME').mean():.3f}",flush=True)
    K['true']=K.event_id.map(dict(zip(T.event_id,T.true))); K['inf']=K.event_id.map(inf)
    K=K[K.true.notna()].copy(); K['when']=pd.to_datetime(K.m,utc=True).astype('int64')
    W=K[K.sel==K.true]; W=W.assign(band=pd.cut(W.ltp,[1,1.5,2.2,3.5,6,12,1000],labels=['<1.5','1.5-2.2','2.2-3.5','3.5-6','6-12','12+']))
    print("\nrule fires, by the winner's kick-off price:\n",W.groupby(['true','band'],observed=True).apply(lambda x:pd.Series(dict(n=len(x),fires=x.inf.notna().mean()))).round(3).unstack(0).to_string(),flush=True)
    K['band']=pd.cut(K.ltp,[1,1.5,2.2,3.5,6,12,1000],labels=['<1.5','1.5-2.2','2.2-3.5','3.5-6','6-12','12+'])
    won=K.sel==K.true
    K['B']=[back_settle(p,w) for p,w in zip(K.ltp,won)]; K['L']=[lay_settle(p,w) for p,w in zip(K.ltp,won)]
    K['B_inf']=np.where(K.inf.notna(),[back_settle(p,w) for p,w in zip(K.ltp,K.sel==K.inf)],np.nan); K['L_inf']=np.where(K.inf.notna(),[lay_settle(p,w) for p,w in zip(K.ltp,K.sel==K.inf)],np.nan)
    rows=[]
    for keys in (['sel','band'],['country','sel','band'],['country','band']):
        for side,col in (('BACK','B'),('LAY','L')):
            for k,x in K.groupby(keys,observed=True):
                if len(x)<50: continue
                r=gate(x[col].values.astype(float),x.when.values.astype(float)); ki=x[col+'_inf'].values.astype(float); ki=ki[np.isfinite(ki)]
                rows.append(dict(side=side,cell=' '.join(map(str,k)),**r,events=x.event_id.nunique(),old_known=ki.mean() if len(ki) else np.nan,n_known=len(ki),t_known=tstat(ki)))
    R=pd.DataFrame(rows); R['shift']=R['mean']-R.old_known
    print(f"\n== RESCORED on real results: {len(R)} cells (mean = real, old_known = 464's known-only on the same events)")
    print("selection x band:\n",R[R.cell.str.match(r'^(HOME|DRAW|AWAY) ')].round(3).to_string(index=False))
    print(f"\nabs shift, real v known-only, n>=300: median {R[R.n>=300]['shift'].abs().median():.3f}, p90 {R[R.n>=300]['shift'].abs().quantile(.9):.3f}")
    print("\ntop 15 by t, n>=300:\n",R[R.n>=300].sort_values('t',ascending=False).head(15).round(3).to_string(index=False))
    print("\n464's best: BACK IT DRAW 2.2-3.5:\n",R[(R.side=='BACK')&(R.cell=='IT DRAW 2.2-3.5')].round(3).to_string(index=False))
    W=R[R.PASS]; print(f"\n== FOOTBALL SURVIVORS: {len(W)} of {len(R)}\n",W.round(3).to_string(index=False) if len(W) else "none",flush=True)
    ALLS.append(('football 464',len(R),len(W)))

def racing_section():
    print("\n################ RACING (jobs 481, 497)",flush=True)
    con,cur=rly(); t0=time.time(); fr=[]
    now=pd.Timestamp.now(tz='UTC'); b=now.floor('6h')+pd.Timedelta(hours=6); oldest=pd.Timestamp('2026-10-20',tz='UTC'); empty=0
    while b>oldest and empty<8 and time.time()-t0<1200:
        a=b-pd.Timedelta(hours=6)
        cur.execute("""SELECT market_id,ts,sel_id,back_px::float8,lay_px::float8,ltp::float8,total_matched::float8 FROM ip_tape WHERE sport=ANY(%s) AND market_type='WIN' AND status='OPEN' AND secs_since_start>0 AND ts>=%s AND ts<%s""",(['Horse Racing','horse_racing','7','Horse racing'],a,b))
        d=pd.DataFrame(cur.fetchall(),columns=['market_id','ts','sel_id','bp','lp','ltp','tm']); b=a
        if len(d): fr.append(d); empty=0
        else: empty+=1
    if not fr: print("ERROR: no racing rows, no verdict",flush=True); return
    A=pd.concat(fr,ignore_index=True); fr=None
    print(f"pulled rows {len(A)}, markets {A.market_id.nunique()}, {A.ts.min()} .. {A.ts.max()} | {time.time()-t0:.0f}s",flush=True)
    cur.execute("SELECT market_id,selection_id FROM racing_results WHERE won AND market_id=ANY(%s)",(list(A.market_id.unique()),))
    w=defaultdict(list)
    for m,s in cur.fetchall(): w[m].append(str(s))
    cur.execute("SELECT count(DISTINCT market_id) FROM racing_results WHERE market_id=ANY(%s)",(list(A.market_id.unique()),)); inres=cur.fetchone()[0]; con.close()
    truth={m:v[0] for m,v in w.items() if len(v)==1}; A['sel_id']=A.sel_id.astype(str).str.replace(r'\.0$','',regex=True)
    nm=A.market_id.nunique(); print(f"racing_results: markets on tape {nm}, in results {inres}, one winner {len(truth)} ({len(truth)/nm:.3f}), dead heat or several {sum(len(v)>1 for v in w.values())}, none flagged {inres-len(w)}",flush=True)
    # GATE, changed after the first run failed it at 0.168 of ALL tape races: the tape is worldwide and racing_results records UK/IE only. Denominator is now tape races at a venue racing_results knows, with no "(AUS)"-style country tag in the event name. Foreign races have no truth and are not scored; their firing rate is unmeasured.
    con,cur=rly(); cur.execute("SELECT DISTINCT venue FROM racing_results"); VEN={r[0] for r in cur.fetchall()}
    cur.execute("SELECT DISTINCT market_id,event_name FROM ip_tape WHERE sport=ANY(%s) AND market_type='WIN' AND status='OPEN' AND secs_since_start>0 AND market_id=ANY(%s)",(['Horse Racing','horse_racing','7','Horse racing'],list(A.market_id.unique()))); EV=cur.fetchall(); con.close()
    home={m for m,e in EV if home_race(e,VEN)}; cov=sum(m in truth for m in home)/max(len(home),1); stray=[m for m in truth if m not in home]
    print(f"gate: UK/IE races on tape {len(home)}, with one real winner {cov:.3f} (bar 0.80); races with a result not counted as UK/IE {len(stray)}; foreign races with no truth {nm-len(home)}",flush=True)
    if cov<0.8: print("GATE FAILED: under 80% of UK/IE races have one real winner, not rescored",flush=True); return
    A=A[A.market_id.isin(truth)].reset_index(drop=True); print(f"scored population: {A.market_id.nunique()} UK/IE races, so old_worst below is on these races, not 481/497's worldwide set",flush=True)
    for c in ('bp','lp','ltp','tm'): A[c]=pd.to_numeric(A[c],errors='coerce')
    A['ts']=pd.to_datetime(A.ts,utc=True); A=A.sort_values(['market_id','ts'],kind='stable').reset_index(drop=True); A['ts']=A.ts.dt.tz_localize(None).astype('datetime64[ns]').astype('int64')
    A['ok']=frame_clean(A); print(f"rows in replay frames {(~A.ok).mean():.1%}",flush=True)
    r1,f1=racing(A,'RAW',truth); r2,f2=racing(A[A.ok],'CLEAN',truth)
    R=pd.DataFrame(r1+r2); Fi=pd.DataFrame(f1+f2)
    Fi['ob']=pd.cut(Fi.winner_off,[1,3,6,12,50,1001],labels=['<3','3-6','6-12','12-50','50+'])
    for lab,x in Fi.groupby('mode'):
        y=x[x.fired]; print(f"\n== RULE v TRUTH {lab}: races {len(x)}, fires {x.fired.mean():.3f}, agrees when it fires {y.agree.mean():.4f} (n {len(y)}); favourite won: all {x.fav_won.mean():.3f} v where it fires {y.fav_won.mean():.3f}")
        print(x.groupby('ob',observed=True).agg(n=('fired','size'),fires=('fired','mean'),agree=('agree','mean')).round(3).to_string()); print(x.groupby('field').agg(n=('fired','size'),fires=('fired','mean')).round(3).to_string())
        print("winner's price on the last snapshot, quantiles:",x.last_winner.quantile([.1,.5,.75,.9,.99]).round(3).to_dict(),flush=True)
    out=[]
    for (m,x,sd,fl),d in R.groupby(['mode','x','side','fill']):
        for setn,dd in (('ALL',d),('FIRST',d[d['first']])):
            for cut,ee in [('-',dd)]+[(f'off {k}',v) for k,v in dd.groupby('off')]+[(f'field {k}',v) for k,v in dd.groupby('field')]:
                r=gate(ee.real.values.astype(float),ee.ts.values.astype(float)); wo=ee.worst.values.astype(float); wo=wo[np.isfinite(wo)]
                out.append(dict(mode=m,x=x,side=sd,fill=fl,set=setn,cut=cut,**r,races=ee.mid.nunique(),old_worst=wo.mean() if len(wo) else np.nan,t_worst=tstat(wo)))
    S=pd.DataFrame(out); h=S[S.cut=='-'].sort_values(['mode','x','side','fill','set'])
    print(f"\n== RESCORED on real results: {len(S)} lines. mean = real result, old_worst = job's verdict number (unknown = -£10). Headline lines:\n",h.drop(columns=['cut']).round(3).to_string(index=False))
    print("\ntop 15 by t, n>=100:\n",S[S.n>=100].sort_values('t',ascending=False).head(15).round(3).to_string(index=False))
    E=S[(S['mode']=='CLEAN')&(S.fill=='NEXT')&(S.set=='FIRST')]; W=S[S.PASS]
    print(f"\neligible as 497 (CLEAN, NEXT, FIRST) best:\n",E.sort_values('t',ascending=False).head(6).round(3).to_string(index=False))
    print(f"\n== RACING SURVIVORS: {len(W)} of {len(S)}\n",W.round(3).to_string(index=False) if len(W) else "none",flush=True)
    ALLS.append(('racing 481/497',len(S),len(W)))

def band(p):
    for hi,lab in ((1.1,'<1.1'),(1.25,'1.1-1.25'),(1.5,'1.25-1.5'),(2,'1.5-2'),(3,'2-3'),(5,'3-5'),(10,'5-10'),(25,'10-25')):
        if p<hi: return lab
    return '25+'
def mom_first(p,k=20,x=0.15):
    for i in range(k,len(p)):
        if p[i]<=p[i-k]*(1-x)+1e-9: return i
    return None
def cricket():
    print("\n################ CRICKET (job 493)",flush=True)
    rc,rk=rly(); CM=pd.read_sql("SELECT match_date,team1,team2,winner,competition FROM cricket_matches WHERE match_date>='2024-08-25'",rc); rc.close()
    print(f"cricket_matches {len(CM)}, {CM.match_date.min()}..{CM.match_date.max()}, winner NULL {CM.winner.isna().mean():.3f}",flush=True); end=pd.Timestamp(CM.match_date.max())
    ix=defaultdict(list)
    for r in CM.itertuples(): ix[frozenset((norm(r.team1),norm(r.team2)))].append((r.match_date,r.winner))
    con,cur=loc()
    cur.execute("""WITH RECURSIVE t AS ((SELECT market_id FROM bf_hist_other WHERE sport='Cricket' ORDER BY market_id LIMIT 1)
      UNION ALL SELECT (SELECT market_id FROM bf_hist_other WHERE sport='Cricket' AND market_id>t.market_id ORDER BY market_id LIMIT 1) FROM t WHERE t.market_id IS NOT NULL)
      SELECT market_id FROM t WHERE market_id IS NOT NULL""")
    MID=[r[0] for r in cur.fetchall() if r[0].startswith('MATCH_ODDS|')]
    def mdate(m):
        try: return pd.Timestamp(m.rsplit('|',1)[1][:10])
        except Exception: return pd.NaT
    S2=[m for m in MID if pd.notna(mdate(m)) and pd.Timestamp('2024-09-01')<=mdate(m)<=end+pd.Timedelta(days=1)]
    print(f"MATCH_ODDS markets {len(MID)}, in the results window {len(S2)} | {time.time()-T0:.0f}s",flush=True)
    SK=Counter(); rows=[]; fire=[]
    STATES={'FIRST':None,'E30':30,'E60':60,'E120':120,'E240':240}
    for c_ in range(0,len(S2),400):
        cur.execute("""SELECT market_id,event_name,market_time,sel,extract(epoch from ts)::float8,ltp::float8 FROM bf_hist_other WHERE sport='Cricket' AND market_id=ANY(%s) AND market_type='MATCH_ODDS' AND inplay AND ltp IS NOT NULL AND ltp>=1.01 AND ltp<=1000""",(S2[c_:c_+400],))
        d=pd.DataFrame(cur.fetchall(),columns=['mid','ev','mt','sel','ts','ltp'])
        if d.empty: continue
        d=d.drop_duplicates(['mid','sel','ts']).sort_values(['mid','ts','sel'],kind='stable')
        for mk,g in d.groupby('mid',sort=False):
            SK['market']+=1; h,_,a=str(g.ev.iloc[0]).partition(' v '); day=pd.Timestamp(g.mt.iloc[0]).date()
            hits=[w for dd,w in ix.get(frozenset((norm(h),norm(a))),[]) if abs((dd-day).days)<=1]
            if len(hits)!=1: SK['no unique results match']+=1; continue
            if hits[0] is None: SK['matched, no winner (no result or tie)']+=1; continue
            run={s:(x.ts.values,x.ltp.values) for s,x in g.groupby('sel',sort=False)}
            tw=[s for s in run if norm(s)==norm(hits[0])]
            if len(tw)!=1: SK['winner not a runner with prints']+=1; continue
            tw=tw[0]; SK['scored']+=1
            res,conf=result_of({s:float(v[1][-1]) for s,v in run.items()}); fw=[s for s,v in res.items() if v is True]
            f0={s:float(v[1][0]) for s,v in run.items()}; fav=min(f0,key=f0.get)
            fire.append(dict(mk=mk,day=day,fired=len(fw)==1,agree=(fw[0]==tw) if fw else False,conflict=conf,fav_won=tw==fav,first_w=f0[tw],last_w=float(run[tw][1][-1])))
            real={s:s==tw for s in run}
            allt=np.sort(g.ts.values); T_=allt[0]
            def add(st,side,s,p,xi,xr): rows.append((st,side,mk,day,s,p,band(p),xi,xr))
            for st,v in STATES.items():
                ts_=T_ if st=='FIRST' else T_+v*60
                for s,(ts,p) in run.items():
                    i=int(np.searchsorted(ts,ts_,'right'))
                    if i>=len(ts): continue
                    x=float(p[i])
                    bi=-10.0 if res[s] is None else back_settle(x,res[s]); li=-10.0 if res[s] is None else lay_settle(x,res[s])
                    if dn(x)>1.01: add(st,'B',s,x,bi,back_settle(x,real[s]))
                    add(st,'L',s,x,li,lay_settle(x,real[s]))
            trig=[(run[s][0][mom_first(run[s][1])],s,mom_first(run[s][1])) for s in run if mom_first(run[s][1]) is not None]
            if trig:
                _,s,i=min(trig,key=lambda z:(z[0],z[1])); ts,p=run[s]
                if i+1<len(p):
                    x=float(p[i+1]); bi=-10.0 if res[s] is None else back_settle(x,res[s]); li=-10.0 if res[s] is None else lay_settle(x,res[s]); br=back_settle(x,real[s]); lr=lay_settle(x,real[s])
                    if dn(x)>1.01: add('M15SET','B',s,x,bi,br)
                    add('M15SET','L',s,x,li,lr)
                    if i+21<len(p):
                        q=float(p[i+21]); b2=back_scalp(x,q); l2=lay_scalp(x,q)
                        if dn(x)>1.01: add('M15X20','B',s,x,b2,b2)
                        add('M15X20','L',s,x,l2,l2)
                    else:
                        if dn(x)>1.01: add('M15X20','B',s,x,bi,br)
                        add('M15X20','L',s,x,li,lr)
    con.close(); print("counts:",dict(SK),f"| {time.time()-T0:.0f}s",flush=True)
    if not fire: print("ERROR: nothing joined, cricket not tested",flush=True); return
    Fi=pd.DataFrame(fire); y=Fi[Fi.fired]
    print(f"\n== RULE v TRUTH: markets {len(Fi)}, {Fi.day.min()}..{Fi.day.max()}; fires {Fi.fired.mean():.3f}, agrees when it fires {y.agree.mean():.4f} (n {len(y)}), conflicts {Fi.conflict.mean():.3f}; favourite won: all {Fi.fav_won.mean():.3f} v where it fires {y.fav_won.mean():.3f}")
    print(f"fires when the first-print favourite won {Fi[Fi.fav_won].fired.mean():.3f}, when the outsider won {Fi[~Fi.fav_won].fired.mean():.3f}; winner's last print quantiles {Fi.last_w.quantile([.1,.5,.75,.9,.99]).round(3).to_dict()}",flush=True)
    D=pd.DataFrame(rows,columns=['state','side','mk','day','sel','p','band','xi','xr']); D['when']=pd.to_datetime(D.day).astype('int64')
    out=[]
    for (st,sd),b in D.groupby(['state','side']):
        for cut,x in [('all',b)]+list(b.groupby('band')):
            r=gate(x.xr.values.astype(float),x.when.values.astype(float)); e=x[x.p>=1.10].xr.astype(float); e=e[np.isfinite(e)]
            r['PASS']=bool(r['PASS'] and len(e) and e.mean()>=0.15)
            out.append(dict(state=st,side=sd,cut=cut,**r,mkts=x.mk.nunique(),x110=e.mean() if len(e) else np.nan,old_worst=x.xi.astype(float).mean(),t_worst=tstat(x.xi.values.astype(float)),t_c=tstat(x.groupby('mk').xr.sum().values)))
    R=pd.DataFrame(out)
    print(f"\n== RESCORED on real results: {len(R)} cells, {int((R.n>=300).sum())} at n>=300. Headline:\n",R[R.cut=='all'].round(3).to_string(index=False))
    print("\ntop 15 by t, n>=300:\n",R[R.n>=300].sort_values('t',ascending=False).head(15).round(3).to_string(index=False))
    W=R[R.PASS]; print(f"\n== CRICKET SURVIVORS: {len(W)} of {len(R)}\n",W.round(3).to_string(index=False) if len(W) else "none",flush=True)
    ALLS.append(('cricket 493',len(R),len(W)))

def tennis():
    print("\n################ TENNIS, firing proxy only, no rescoring (jobs 482, 495: ip_tape has no result overlap)",flush=True)
    rc,rk=rly(); TR=pd.read_sql("SELECT tourney_date,winner_norm,loser_norm,score FROM tennis_results_2026 WHERE tourney_date>='2024-08-01'",rc); rc.close()
    print(f"tennis_results_2026 {len(TR)}, {TR.tourney_date.min()}..{TR.tourney_date.max()}",flush=True)
    ix=defaultdict(list)
    for r in TR.itertuples(): ix[frozenset((fold(r.winner_norm),fold(r.loser_norm)))].append((r.tourney_date,(fold(r.winner_norm),early_end(r.score))))
    con,cur=loc()
    cur.execute("""WITH RECURSIVE t AS ((SELECT market_id FROM bf_hist_other WHERE sport='Tennis' ORDER BY market_id LIMIT 1)
      UNION ALL SELECT (SELECT market_id FROM bf_hist_other WHERE sport='Tennis' AND market_id>t.market_id ORDER BY market_id LIMIT 1) FROM t WHERE t.market_id IS NOT NULL)
      SELECT market_id FROM t WHERE market_id IS NOT NULL""")
    MID=[r[0] for r in cur.fetchall() if r[0].startswith('MATCH_ODDS|') and '/' not in r[0]]; random.Random(7).shuffle(MID); MID=MID[:8000]
    SK=Counter(); fire=[]
    for c_ in range(0,len(MID),500):
        cur.execute("""SELECT market_id,market_time,sel,extract(epoch from ts)::float8,ltp::float8 FROM bf_hist_other WHERE sport='Tennis' AND market_id=ANY(%s) AND market_type='MATCH_ODDS' AND inplay AND ltp>=1.01 AND ltp<=1000""",(MID[c_:c_+500],))
        d=pd.DataFrame(cur.fetchall(),columns=['mid','mt','sel','ts','ltp'])
        if d.empty: continue
        d=d.sort_values(['mid','ts'],kind='stable')
        for mk,g in d.groupby('mid',sort=False):
            SK['market']+=1; ff=g.groupby('sel').ltp.first(); ll=g.groupby('sel').ltp.last()
            if len(ll)!=2: SK['not two runners with prints']+=1; continue
            names={fold(s):s for s in ll.index}; day=pd.Timestamp(g.mt.iloc[0]).date()
            hits=[w for dd,w in ix.get(frozenset(names),[]) if -2<=(day-dd).days<=21]
            if len(hits)!=1: SK['no unique results match']+=1; continue
            tw=names[hits[0][0]]; SK['scored']+=1; lw=[s for s in ll.index if ll[s]<=1.05]; fav=ff.idxmin()
            fire.append(dict(fired=len(lw)==1,agree=len(lw)==1 and lw[0]==tw,fav_won=tw==fav,early=hits[0][1],last_w=float(ll[tw]),first_w=float(ff[tw])))
    con.close(); print("counts:",dict(SK),f"| {time.time()-T0:.0f}s",flush=True)
    if not fire: print("nothing joined, tennis proxy not measured",flush=True); return
    Fi=pd.DataFrame(fire); y=Fi[Fi.fired]
    print(f"\n== RULE v TRUTH (LTP tape, not the ip_tape touch): matches {len(Fi)}; fires {Fi.fired.mean():.3f}, agrees when it fires {y.agree.mean():.4f}; favourite won: all {Fi.fav_won.mean():.3f} v where it fires {y.fav_won.mean():.3f}")
    print(f"fires when the first-print favourite won {Fi[Fi.fav_won].fired.mean():.3f}, when the outsider won {Fi[~Fi.fav_won].fired.mean():.3f}; winner's last print quantiles {Fi.last_w.quantile([.1,.5,.75,.9,.99]).round(3).to_dict()}",flush=True)
    print("fires by retirement or walkover x who won (n, fires, winner's last print median):\n",Fi.groupby(['early','fav_won']).agg(n=('fired','size'),fires=('fired','mean'),last_w=('last_w','median'),first_w=('first_w','median')).round(3).to_string(),flush=True)

for nm,fn in (('football',football),('racing',racing_section),('cricket',cricket),('tennis',tennis)):
    if not want(nm): continue
    try: fn()
    except Exception as e:
        import traceback; print(f"ERROR in {nm}: {e}"); print(traceback.format_exc()[-1500:],flush=True)
print("\nbasketball (jobs 458, 497): no results table on the box, not tested.")
print("\n== SURVIVORS (all sections): "+("; ".join(f"{a}: {c} of {b}" for a,b,c in ALLS) if ALLS else "none scored"))
print(f"total {time.time()-T0:.0f}s")
PY
