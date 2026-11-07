#!/bin/bash
set -o pipefail
# 499_xx_lead (Finder 2026-11-07, queue item 329, Finder's own, source c): does Smarkets or Matchbook lead Betfair before the off? Rule pushed in the queue before any trade.
# Football match odds, T-30 to T-2, entry at a Betfair row of liq_sample. Other book's mid: last row at or before the Betfair row, within 60 s, so no look-ahead.
# STILL: a Betfair row 240-360 s back exists, and the range of Betfair's mid over the last 300 s is under 0.5% of the current mid. LEAD: STILL and gap >= 2%. FLAT: STILL and gap under 0.5%, control, cannot pass.
# Other book higher: lay Betfair at the lay touch plus one tick, back out at the back touch less one tick. Other book lower: the reverse. First trigger per class per runner per game.
# Exit: first Betfair row with a usable touch at or after entry + 300 s, in play or not, counted. No later row: settled at the last prints. Over 50 not traded. 2%, £10 risk, greened at exit.
# Matching: exact normalised names first, then lib_cand.loose among Betfair markets alive at the kick-off; first run, exact only, read n 48 -0.551 t -6.99 with 84 same-fixture games lost to spelling. A game whose median gap is over 15% on any runner is a wrong pairing and is dropped, counted.
# Writes one local table, xx_pre_329, keyed so a second run adds nothing; never dropped here. Tape is days long: a pass earns a re-read, not a stake.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_000_000_000,2_000_000_000))
import sys,time,datetime as dt,psycopg2,psycopg2.extras,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,back_hedge,lay_hedge,back_settle,lay_settle,tstat,passes,norm
from lib_official import secs
from lib_xx import pair,side_of,pick,median_gap,LABS
import lib_xx; lib_xx.checks()
pd.set_option('display.width',220); pd.set_option('display.max_columns',30)
START=dt.datetime(2026,11,4,22,0,tzinfo=dt.timezone.utc)   # liq_sample keeps a pre-off path only from 5 Nov
BOOKS={'matchbook':'Match Odds','smarkets':'Full-time result'}
def klass(o,b,hist):
    """o other mid, b Betfair mid, hist Betfair mids in the last 300 s with b. Returns (class,gap)."""
    g=round(o/b-1,9)
    if (max(hist)-min(hist))/b>=0.005: return None,g
    if abs(g)>=0.02: return 'LEAD',g
    if abs(g)<0.005 and g!=0: return 'FLAT',g
    return None,g
def pnl(side,b,l,bx,lx):
    """Touch b,l at entry, bx,lx at exit, greened. None when the ladder floor stops the back."""
    if side=='B':
        a=step(b,-1)
        return None if a<=1.01 else back_hedge(a,lx)
    return lay_hedge(step(l,1),bx)
def settle_last(side,b,l,last,s):
    """No later row: last prints, one under 1.10 is the winner, else share of the book."""
    a=step(b,-1) if side=='B' else step(l,1)
    if side=='B' and a<=1.01: return None
    f=(lambda w: back_settle(a,w)) if side=='B' else (lambda w: lay_settle(a,w))
    w=[k for k,v in last.items() if v<=1.10]
    if len(w)==1: return f(w[0]==s)
    t=sum(1/v for v in last.values()); p=(1/last[s])/t
    return p*f(True)+(1-p)*f(False)
# known answers, worked by hand
assert secs(pd.Series([pd.Timestamp('2026-01-01',tz='UTC')])).iloc[0]==1767225600
assert pair('Smouha SC vs El Minya')==pair('Smouha v El Minya') and pair('no separator') is None
assert side_of('Draw','Smouha SC vs El Minya')=='DRAW' and side_of('Smouha SC','Smouha SC vs El Minya')=='HOME' and side_of('El Minya','Smouha SC vs El Minya')=='AWAY' and side_of('Other','Smouha SC vs El Minya') is None
assert side_of('Atlético Tucumán','Banfield vs Atlético Tucumán')=='AWAY'
assert klass(2.04,2.0,[2.0,2.0])==('LEAD',0.02) and klass(1.96,2.0,[2.0])==('LEAD',-0.02)
assert klass(2.04,2.0,[1.99,2.0])[0] is None   # Betfair moved 0.5%: not still
assert klass(2.005,2.0,[2.0])[0]=='FLAT' and klass(2.0,2.0,[2.0])[0] is None and klass(2.02,2.0,[2.0])[0] is None
# Back 2.04 touch: fill 2.02. Lay out at 1.98 touch: fill 1.99. 10*(2.02/1.99-1)=0.15075, after 2% 0.14774
assert abs(pnl('B',2.04,2.06,1.96,1.98)-10*(2.02/1.99-1)*.98)<1e-9
# Lay 2.00 touch: fill 2.02, stake 10/1.02. Price rises, back out at 2.10 touch: fill 2.08. Profit 10/1.02*(1-2.02/2.08)=0.28281, after 2% 0.27715
assert abs(pnl('L',1.98,2.0,2.10,2.12)-10/1.02*(1-2.02/2.08)*.98)<1e-9 and pnl('L',1.98,2.0,2.10,2.12)>0
# Price falls, back out at 1.90 touch: fill 1.89. Loss 10/1.02*(1-2.02/1.89)=-0.67434, no commission on a loss
assert abs(pnl('L',1.98,2.0,1.90,1.92)-10/1.02*(1-2.02/1.89))<1e-9 and pnl('L',1.98,2.0,1.90,1.92)<0
assert pnl('B',1.02,1.03,1.02,1.03) is None
assert settle_last('B',2.04,2.06,{'A':1.05,'B':30.},'A')==back_settle(2.02,True) and settle_last('L',1.98,2.0,{'A':1.05,'B':30.},'A')==-10.0
_v=settle_last('L',1.98,2.0,{'A':2.,'B':2.},'A'); assert abs(_v-(lay_settle(2.02,True)+lay_settle(2.02,False))/2)<1e-9
print("checks: OK",flush=True); T0=time.time()
MODE=sys.argv[1] if len(sys.argv)>1 else 'trade'   # pull is opt-in, cron's runner re-runs this file with no arguments
if MODE=='asserts-only': sys.exit(0)
L=psycopg2.connect(creds.pg_local()); L.autocommit=True; lc=L.cursor(); lc.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
if MODE=='pull':
    R=psycopg2.connect(creds.pg_railway()); R.autocommit=True; rc=R.cursor(); rc.execute("SET statement_timeout='600s'")
    rc.execute("select count(*) filter (where state='active' and now()-query_start>interval '5 minutes') from pg_stat_activity"); busy=rc.fetchone()[0]; print("railway queries over 5 min:",busy,flush=True)
    if busy>3: print("railway busy, pull stopped"); sys.exit(0)
    lc.execute("""CREATE TABLE IF NOT EXISTS xx_pre_329(ts timestamptz,exchange text,event_name text,market_id text,start_ts timestamptz,sel_name text,
                  back_px float8,back_sz float8,lay_px float8,lay_sz float8,PRIMARY KEY(exchange,market_id,sel_name,ts))""")
    t=START; now=dt.datetime.now(dt.timezone.utc); tot=Counter()
    while t<now:
        e=t+dt.timedelta(hours=3)
        for ex,mk in BOOKS.items():
            rc.execute("""SELECT ts,exchange,event_name,market_id,start_ts,sel_name,back_px::float8,back_sz::float8,lay_px::float8,lay_sz::float8 FROM xx_tape
                          WHERE exchange=%s AND ts>=%s AND ts<%s AND sport='football' AND market_name=%s AND NOT inplay AND start_ts-ts BETWEEN interval '0' AND interval '37 minutes'""",(ex,t,e,mk))
            rows=rc.fetchall(); tot[ex]+=len(rows)
            if rows: psycopg2.extras.execute_values(lc,"INSERT INTO xx_pre_329 VALUES %s ON CONFLICT DO NOTHING",rows,page_size=2000)
        print(t.strftime('%m-%d %H:%M'),dict(tot),f"{time.time()-T0:.0f}s",flush=True); t=e
    R.close()
lc.execute("select exchange,count(*),count(distinct market_id),count(distinct event_name),min(ts),max(ts),count(*) filter (where back_px is not null and lay_px is not null) from xx_pre_329 group by 1"); print("xx_pre_329:",lc.fetchall(),flush=True)
if MODE=='pull': sys.exit(0)
X=pd.read_sql("SELECT DISTINCT ts,exchange,event_name,market_id,start_ts,sel_name,back_px,back_sz,lay_px,lay_sz FROM xx_pre_329",L)
B=pd.read_sql("""SELECT DISTINCT ts,market_id,event_name,sel,minute,back_px::float8 b,lay_px::float8 l,ltp::float8 ltp FROM liq_sample
                 WHERE mkt='MO' AND market_id IN (SELECT market_id FROM liq_sample WHERE mkt='MO' AND minute=0 AND ts>=%s GROUP BY 1 HAVING count(*)>=30)""",L,params=(START,))
L.close()
print(f"xx rows {len(X):,}; Betfair rows {len(B):,}, markets {B.market_id.nunique():,}; {time.time()-T0:.0f}s",flush=True)
X['tt']=secs(X.ts); X['st']=secs(X.start_ts); B['tt']=secs(B.ts); C=Counter()
PAIRS=[(pair(ev),m) for m,ev in B[['market_id','event_name']].drop_duplicates().itertuples(index=False) if pair(ev)]
BM={m:g.sort_values('tt') for m,g in B.groupby('market_id')}
LAST={m:g.dropna(subset=['ltp']).groupby('sel').ltp.last().to_dict() for m,g in BM.items()}
SPAN={m:(g.tt.min(),g.tt.max()) for m,g in BM.items()}
rows=[]; fl=[]
for (ex,xm,ev,st),gx in X.groupby(['exchange','market_id','event_name','st'],sort=False):
    C[ex+' markets']+=1; p=pair(ev)
    got=pick(p,[(q,m) for q,m in PAIRS if SPAN[m][0]<=st and SPAN[m][1]>=st-1800])
    if got is None: C[ex+' no Betfair market']+=1; continue
    m,how=got; gb=BM[m]; C[ex+' match '+how]+=1
    if set(gb.sel.unique())!=LABS: C[ex+' Betfair labels not as expected']+=1; continue
    if gb.duplicated(['sel','tt']).any(): C[ex+' two rows one label one time']+=1; continue
    C[ex+' matched']+=1; gx=gx.assign(side=[side_of(s,ev) for s in gx.sel_name])
    if gx.side.isna().any(): C[ex+' runner name not matched']+=1; continue
    if set(gx.side.unique())!=LABS: C[ex+' runner set short']+=1; continue
    last=LAST.get(m,{}); bad=False
    for s,bs in gb.groupby('sel'):
        o=gx[(gx.side==s)&gx.back_px.notna()&gx.lay_px.notna()].sort_values('tt'); v=bs[bs.b.notna()&bs.l.notna()&(bs.minute==0)]
        mg=median_gap(o.tt.values,((o.back_px+o.lay_px)/2).values,v.tt.values,((v.b+v.l)/2).values)
        if mg is not None and mg>0.15: bad=True
    if bad: C[ex+' wrong pairing, gap over 15%']+=1; continue
    for s,bs in gb.groupby('sel'):
        o=gx[(gx.side==s)&gx.back_px.notna()&gx.lay_px.notna()&(gx.lay_px>gx.back_px)&(gx.back_px>=1.01)].sort_values('tt')
        v=bs[bs.b.notna()&bs.l.notna()&(bs.l>bs.b)&(bs.b>=1.01)]
        if not len(o) or not len(v): C[ex+' runner no two-sided rows']+=1; continue
        ot=o.tt.values; om=((o.back_px+o.lay_px)/2).values; osp=((o.lay_px-o.back_px)/o.back_px).values; obs=o.back_sz.values; ols=o.lay_sz.values
        vt=v.tt.values; vb=v.b.values; vl=v.l.values; vm=(vb+vl)/2; vmin=v.minute.values
        done=set()
        for i in np.where((vt>=st-1800)&(vt<=st-120)&(vmin==0))[0]:
            if len(done)==2: break
            t=vt[i]; j=int(np.searchsorted(ot,t,side='right'))-1
            if j<0 or ot[j]<t-60: C[ex+' row no other mid in 60 s']+=1; continue
            if not ((vt>=t-360)&(vt<=t-240)).any(): C[ex+' row no 5 min history']+=1; continue
            h=vm[(vt>=t-300)&(vt<=t)]
            k,g=klass(om[j],vm[i],h)
            if k is None or k in done: continue
            done.add(k)
            side='L' if g>0 else 'B'
            if (vl[i] if side=='L' else vb[i])>50: C[ex+' over 50']+=1; continue
            q=np.where(vt>=t+300)[0]
            if len(q):
                e=q[0]; val=pnl(side,vb[i],vl[i],vb[e],vl[e]); ip=int(vmin[e]>0); late=int(vt[e]>t+420); ex_t=vt[e]
                gross=(vm[e]/vm[i]-1)*(1 if g>0 else -1)
                jx=int(np.searchsorted(ot,vt[e],side='right'))-1
                omove=((om[jx]/om[j]-1)*(-1 if g>0 else 1)) if jx>j and ot[jx]>=vt[e]-60 else np.nan
            else:
                val=settle_last(side,vb[i],vl[i],last,s) if s in last and len(last)==3 else None; ip=-1; late=0; gross=np.nan; omove=np.nan
                if val is None: C[ex+' no exit and no last prints']+=1
            if val is None: C[ex+' no fill']+=1; continue
            rows.append((ex,k,side,m,ev,s,t,val,abs(g),vm[i],omove,gross,ip,late,osp[j],min(obs[j],ols[j]),(vl[i]-vb[i])/vb[i],how))
T=pd.DataFrame(rows,columns=['ex','k','side','m','ev','s','tt','v','gap','mid','omove','gross','ip','late','osp','osz','bsp','how'])
print("counts",dict(sorted(C.items())),flush=True)
if not len(T): print("no trades"); print("== SURVIVORS: none"); sys.exit(0)
med=T.tt.median(); T['h']=np.where(T.tt<=med,1,2); print("halves split at",pd.Timestamp(med,unit='s',tz='UTC'),"entries from",pd.Timestamp(T.tt.min(),unit='s',tz='UTC'),"to",pd.Timestamp(T.tt.max(),unit='s',tz='UTC'),flush=True)
out=[]
def rd(name,d,can=True):
    if not len(d): return
    n=len(d); a=d[d.h==1].v; b=d[d.h==2].v; mean=d.v.mean(); t=tstat(d.v)
    gm=d.groupby('m').v.sum(); tg=tstat(gm)    # one number per game: three runners of one game are not independent
    ok=can and passes(n,len(a),len(b),t,a.mean() if len(a) else -1,b.mean() if len(b) else -1,mean) and tg>=3.5
    out.append(dict(line=name,n=n,per10=round(mean,3),t=round(t,2),t_game=round(tg,2),h1=round(a.mean(),3) if len(a) else None,n1=len(a),h2=round(b.mean(),3) if len(b) else None,n2=len(b),games=d.m.nunique(),
        gross_pct=round(100*d.gross.mean(),2),other_to_bf_pct=round(100*d.omove.mean(),2),exit_ip=round((d.ip==1).mean(),3),no_row=int((d.ip==-1).sum()),late=round(d.late.mean(),3),PASS='PASS' if ok else ''))
for ex in sorted(T.ex.unique()):
    E=T[T.ex==ex]
    for k in ('LEAD','FLAT'):
        K=E[E.k==k]; can=k=='LEAD'
        rd(f"{ex} {k} ALL",K,can)
        rd(f"{ex} {k} BACK",K[K.side=='B'],can); rd(f"{ex} {k} LAY",K[K.side=='L'],can)
    K=E[E.k=='LEAD']
    for lo,hi in ((1,2),(2,4),(4,10),(10,50)):
        rd(f"{ex} ctx LEAD mid {lo}-{hi}",K[(K.mid>=lo)&(K.mid<hi)],False)
    rd(f"{ex} ctx LEAD gap 2-5%",K[K.gap<0.05],False); rd(f"{ex} ctx LEAD gap 5%+",K[K.gap>=0.05],False)
    rd(f"{ex} ctx LEAD other spread <=3%",K[K.osp<=0.03],False); rd(f"{ex} ctx LEAD other spread >3%",K[K.osp>0.03],False)
    rd(f"{ex} ctx LEAD other size >=£20",K[K.osz>=20],False); rd(f"{ex} ctx LEAD Betfair spread <=2%",K[K.bsp<=0.02],False)
    rd(f"{ex} ctx LEAD exit pre-off",K[K.ip==0],False)
    rd(f"{ex} ctx LEAD exact names",K[K.how=='exact'],False); rd(f"{ex} ctx LEAD loose names",K[K.how=='loose'],False)
    print(ex,"t of LEAD gross move v zero",round(tstat(K.gross.dropna()),2),"; FLAT",round(tstat(E[E.k=='FLAT'].gross.dropna()),2),flush=True)
R=pd.DataFrame(out).sort_values('t',ascending=False); print(R.to_string(index=False),flush=True)
print("gross_pct: Betfair mid move toward the other book over the hold, before spread and ticks. other_to_bf_pct: the other book's mid move toward Betfair over the same hold.")
print(f"run {time.time()-T0:.0f}s")
print("== SURVIVORS:",[r for r in R[R.PASS=='PASS'].line] or 'none')
PY
