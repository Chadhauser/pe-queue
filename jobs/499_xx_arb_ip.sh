#!/bin/bash
set -o pipefail
# 499_xx_arb_ip (Finder 2026-11-07, queue items 330 and 331, Finder's own, source c, from jobs/499_xx_lead.sh): pre-off two-book arb on Betfair and Matchbook; other book's lead over Betfair in play. Rules pushed in the queue before any price. Writes one local table, xx_ip_331, keyed so a second run adds nothing; never dropped here. Days of tape: a pass earns a re-read, not a stake.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,datetime as dt,psycopg2,psycopg2.extras,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,back_hedge,lay_hedge,back_settle,lay_settle,tstat,passes
from lib_official import secs
from lib_xx import pair,side_of,pick,median_gap,LABS
import lib_xx; lib_xx.checks()
pd.set_option('display.width',220); pd.set_option('display.max_columns',30)
BOOKS={'matchbook':'Match Odds','smarkets':'Full-time result'}
def arb(ba,la,c=0.02):
    """Back £10 at ba on one book, lay 10*ba/la at la on the other, commission c on each book's win. Worse of the two outcomes."""
    s=10*ba/la
    return min(10*(ba-1)*(1-c)-s*(la-1), -10+s*(1-c))
def klass(o,b,hist):
    g=round(o/b-1,9)
    if (max(hist)-min(hist))/b>=0.005: return None,g
    if abs(g)>=0.02: return 'LEAD',g
    if abs(g)<0.005 and g!=0: return 'FLAT',g
    return None,g
def pnl(side,b,l,bx,lx):
    if side=='B':
        a=step(b,-1)
        return None if a<=1.01 else back_hedge(a,lx)
    return lay_hedge(step(l,1),bx)
def settle_last(side,b,l,last,s):
    a=step(b,-1) if side=='B' else step(l,1)
    if side=='B' and a<=1.01: return None
    f=(lambda w: back_settle(a,w)) if side=='B' else (lambda w: lay_settle(a,w))
    w=[k for k,v in last.items() if v<=1.10]
    if len(w)==1: return f(w[0]==s)
    t=sum(1/v for v in last.values()); p=(1/last[s])/t
    return p*f(True)+(1-p)*f(False)
# known answers, worked by hand. Back 10 at 3.0, lay 10.714 at 2.8. Wins: 20*.98-10.714*1.8=+0.314. Loses: -10+10.714*.98=+0.5. Worse +0.314.
assert abs(arb(3.0,2.8)-(19.6-(30/2.8)*1.8))<1e-9 and arb(3.0,2.8)>0
# Back 3.0, lay 3.0: both outcomes lose commission. Wins 19.6-20=-0.4; loses -10+9.8=-0.2. Worse -0.4.
assert abs(arb(3.0,3.0)+0.4)<1e-9
assert secs(pd.Series([pd.Timestamp('2026-01-01',tz='UTC')])).iloc[0]==1767225600
assert klass(2.04,2.0,[2.0,2.0])==('LEAD',0.02) and klass(2.04,2.0,[1.99,2.0])[0] is None and klass(2.005,2.0,[2.0])[0]=='FLAT'
assert abs(pnl('B',2.04,2.06,1.96,1.98)-10*(2.02/1.99-1)*.98)<1e-9 and pnl('L',1.98,2.0,1.90,1.92)<0
print("checks: OK",flush=True); T0=time.time()
MODE=sys.argv[1] if len(sys.argv)>1 else 'all'
if MODE=='asserts-only': sys.exit(0)
L=psycopg2.connect(creds.pg_local()); L.autocommit=True; lc=L.cursor(); lc.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
B=pd.read_sql("SELECT DISTINCT ts,market_id,event_name,sel,minute,back_px::float8 b,back_sz::float8 bs,lay_px::float8 l,lay_sz::float8 ls,ltp::float8 ltp FROM liq_sample WHERE mkt='MO'",L)
print(f"Betfair rows {len(B):,}, markets {B.market_id.nunique():,}, {B.ts.min()} to {B.ts.max()}; {time.time()-T0:.0f}s",flush=True)
B['tt']=secs(B.ts); B=B.sort_values('tt')
BM={m:g for m,g in B.groupby('market_id')}
LAST={m:g.dropna(subset=['ltp']).groupby('sel').ltp.last().to_dict() for m,g in BM.items()}
SPAN={m:(g.tt.min(),g.tt.max()) for m,g in BM.items()}
PAIRS=[(pair(ev),m) for m,ev in B[['market_id','event_name']].drop_duplicates().itertuples(index=False) if pair(ev)]
out=[]
def rd(name,d,can=True,val='v',game='m'):
    if not len(d): return
    n=len(d); a=d[d.h==1][val]; b=d[d.h==2][val]; mean=d[val].mean(); t=tstat(d[val]); tg=tstat(d.groupby(game)[val].sum())
    ok=can and passes(n,len(a),len(b),t,a.mean() if len(a) else -1,b.mean() if len(b) else -1,mean) and tg>=3.5
    out.append(dict(line=name,n=n,per10=round(mean,3),t=round(t,2),t_game=round(tg,2),h1=round(a.mean(),3) if len(a) else None,n1=len(a),h2=round(b.mean(),3) if len(b) else None,n2=len(b),games=d[game].nunique(),PASS='PASS' if ok else ''))
def halves(T):
    med=T.tt.median(); T['h']=np.where(T.tt<=med,1,2); print("halves split at",pd.Timestamp(med,unit='s',tz='UTC'),"entries",pd.Timestamp(T.tt.min(),unit='s',tz='UTC'),"to",pd.Timestamp(T.tt.max(),unit='s',tz='UTC'),flush=True)
def show(title):
    global out
    if out:
        R=pd.DataFrame(out).sort_values('t',ascending=False); print(R.to_string(index=False),flush=True); print(f"== SURVIVORS {title}:",[r for r in R[R.PASS=='PASS'].line] or 'none',flush=True)
    else: print(f"== SURVIVORS {title}: none, no trades",flush=True)
    out=[]
def games(X,C,minute_ok):
    """Yields ex,market,how,ev,st,gx,gb for matched games with good labels and a sane median gap."""
    X=X.copy(); X['tt']=secs(X.ts); X['st']=secs(X.start_ts)
    for (ex,xm,ev,st),gx in X.groupby(['exchange','market_id','event_name','st'],sort=False):
        C[ex+' markets']+=1
        got=pick(pair(ev),[(q,m) for q,m in PAIRS if SPAN[m][0]<=st+7200 and SPAN[m][1]>=st-1800])
        if got is None: C[ex+' no Betfair market']+=1; continue
        m,how=got; gb=BM[m]; C[ex+' match '+how]+=1
        if set(gb.sel.unique())!=LABS: C[ex+' Betfair labels not as expected']+=1; continue
        if gb.duplicated(['sel','tt']).any(): C[ex+' two rows one label one time']+=1; continue
        gx=gx.assign(side=[side_of(s,ev) for s in gx.sel_name])
        if gx.side.isna().any() or set(gx.side.unique())!=LABS: C[ex+' runner names not matched']+=1; continue
        bad=False
        for s,bs in gb.groupby('sel'):
            o=gx[(gx.side==s)&gx.back_px.notna()&gx.lay_px.notna()].sort_values('tt'); v=bs[bs.b.notna()&bs.l.notna()&minute_ok(bs.minute)]
            mg=median_gap(o.tt.values,((o.back_px+o.lay_px)/2).values,v.tt.values,((v.b+v.l)/2).values)
            if mg is not None and mg>0.15: bad=True
        if bad: C[ex+' wrong pairing, gap over 15%']+=1; continue
        yield ex,m,how,ev,st,gx,gb
if MODE in ('all','330'):
    print("===== ITEM 330: pre-off two-book arb",flush=True)
    X=pd.read_sql("SELECT DISTINCT ts,exchange,event_name,market_id,start_ts,sel_name,back_px,back_sz,lay_px,lay_sz FROM xx_pre_329",L)
    C=Counter(); rows=[]
    for ex,m,how,ev,st,gx,gb in games(X,C,lambda s:s==0):
        for s,bs in gb.groupby('sel'):
            o=gx[(gx.side==s)&gx.back_px.notna()&gx.lay_px.notna()&(gx.lay_px>gx.back_px)].sort_values('tt')
            v=bs[bs.b.notna()&bs.l.notna()&(bs.l>bs.b)&(bs.b>=1.01)]
            if not len(o) or not len(v): continue
            ot=o.tt.values; ob=o.back_px.values; ol=o.lay_px.values; obs=o.back_sz.values; ols=o.lay_sz.values
            vt=v.tt.values; vb=v.b.values; vl=v.l.values; vbs=v.bs.values; vls=v.ls.values; vm=v.minute.values
            done=set()
            for i in np.where((vt>=st-1800)&(vt<=st-120)&(vm==0))[0]:
                t=vt[i]; j=int(np.searchsorted(ot,t,side='right'))-1
                if j<0 or ot[j]<t-60: continue
                C[ex+' rows looked at']+=1
                for d,ba,la,sz in (('BACK other LAY Betfair',step(ob[j],-1),step(vl[i],1),min(obs[j],vls[i])),('BACK Betfair LAY other',step(vb[i],-1),step(ol[j],1),min(vbs[i],ols[j]))):
                    if d in done or ba<=1.01 or ba>50 or la>50 or not sz>=10: continue
                    same=arb(ba,la)
                    if same<=0: continue
                    done.add(d); C[ex+' signals']+=1
                    i2=i+1; j2=j+1
                    if i2>=len(vt) or j2>=len(ot) or vt[i2]>t+120 or ot[j2]>t+120 or ot[j2]<t: C[ex+' no next row']+=1; continue
                    if d.startswith('BACK other'): nb,nl=step(ob[j2],-1),step(vl[i2],1)
                    else: nb,nl=step(vb[i2],-1),step(ol[j2],1)
                    if nb<=1.01: C[ex+' no next row']+=1; continue
                    rows.append((ex,d,m,ev,s,t,arb(nb,nl),same,sz,vl[i]-vb[i]))
    print("counts",dict(sorted(C.items())),flush=True)
    if rows:
        T=pd.DataFrame(rows,columns=['ex','d','m','ev','s','tt','v','same','sz','sp']); halves(T)
        print("share of next-row fills still positive",round((T.v>0).mean(),3),"; median size on the thinner leg",round(T.sz.median(),1),flush=True)
        for ex in sorted(T.ex.unique()):
            E=T[T.ex==ex]; rd(f"{ex} ARB ALL next row",E)
            for d in sorted(E.d.unique()): rd(f"{ex} {d} next row",E[E.d==d])
            rd(f"{ex} ctx ARB ALL same row, cannot pass",E,False,val='same')
    show("item 330")
if MODE in ('all','331'):
    print("===== ITEM 331: other book's lead in play",flush=True)
    if len(sys.argv)>2 and sys.argv[2]=='pull':   # opt-in: the first pull took 38 min on Railway, and cron's runner re-runs this file with no arguments
        R=psycopg2.connect(creds.pg_railway()); R.autocommit=True; rc=R.cursor(); rc.execute("SET statement_timeout='600s'")
        rc.execute("select count(*) filter (where state='active' and now()-query_start>interval '5 minutes') from pg_stat_activity"); busy=rc.fetchone()[0]; print("railway queries over 5 min:",busy,flush=True)
        if busy<=3:
            lc.execute("""CREATE TABLE IF NOT EXISTS xx_ip_331(ts timestamptz,exchange text,event_name text,market_id text,start_ts timestamptz,sel_name text,
                          back_px float8,lay_px float8,PRIMARY KEY(exchange,market_id,sel_name,ts))""")
            t=dt.datetime(2026,10,31,4,0,tzinfo=dt.timezone.utc); now=dt.datetime.now(dt.timezone.utc); tot=Counter()
            while t<now:
                e=t+dt.timedelta(hours=6)
                for ex,mk in BOOKS.items():
                    rc.execute("""SELECT ts,exchange,event_name,market_id,start_ts,sel_name,back_px::float8,lay_px::float8 FROM xx_tape
                                  WHERE exchange=%s AND ts>=%s AND ts<%s AND sport='football' AND market_name=%s AND inplay""",(ex,t,e,mk))
                    rows=rc.fetchall(); tot[ex]+=len(rows)
                    if rows: psycopg2.extras.execute_values(lc,"INSERT INTO xx_ip_331 VALUES %s ON CONFLICT DO NOTHING",rows,page_size=2000)
                print(t.strftime('%m-%d %H:%M'),dict(tot),f"{time.time()-T0:.0f}s",flush=True); t=e
            R.close()
        else: print("railway busy, pull skipped",flush=True)
    C=Counter(); rows=[]
    def book_games():
        # one exchange at a time, two-sided rows only: all 1.05m rows at once hit the memory cap on the first run. The key already makes rows unique.
        for bk_ in BOOKS:
            X=pd.read_sql("SELECT ts,exchange,event_name,market_id,start_ts,sel_name,back_px,lay_px FROM xx_ip_331 WHERE exchange=%s AND back_px IS NOT NULL AND lay_px IS NOT NULL",L,params=(bk_,))
            print("xx in-play rows",bk_,len(X),"markets",X.market_id.nunique(),flush=True)
            yield from games(X,C,lambda s:(s>=5)&(s<=85))
            del X
    for ex,m,how,ev,st,gx,gb in book_games():
        last=LAST.get(m,{})
        for s,bs in gb.groupby('sel'):
            o=gx[(gx.side==s)&gx.back_px.notna()&gx.lay_px.notna()&(gx.lay_px>gx.back_px)&(gx.back_px>=1.01)].sort_values('tt')
            v=bs[bs.b.notna()&bs.l.notna()&(bs.l>bs.b)&(bs.b>=1.01)]
            if not len(o) or not len(v): C[ex+' runner no two-sided rows']+=1; continue
            ot=o.tt.values; om=((o.back_px+o.lay_px)/2).values
            vt=v.tt.values; vb=v.b.values; vl=v.l.values; vmd=(vb+vl)/2; vm=v.minute.values
            done=set()
            for i in np.where((vm>=5)&(vm<=85))[0]:
                if len(done)==2: break
                t=vt[i]; j=int(np.searchsorted(ot,t,side='right'))-1
                if j<0 or ot[j]<t-60: C[ex+' row no other mid in 60 s']+=1; continue
                if not ((vt>=t-360)&(vt<=t-240)).any(): C[ex+' row no 5 min history']+=1; continue
                k,g=klass(om[j],vmd[i],vmd[(vt>=t-300)&(vt<=t)])
                if k is None or k in done: continue
                done.add(k); side='L' if g>0 else 'B'
                if (vl[i] if side=='L' else vb[i])>50: C[ex+' over 50']+=1; continue
                q=np.where(vt>=t+300)[0]
                if len(q):
                    e=q[0]; val=pnl(side,vb[i],vl[i],vb[e],vl[e]); ex_late=int(vt[e]>t+420); gross=(vmd[e]/vmd[i]-1)*(1 if g>0 else -1)
                else:
                    val=settle_last(side,vb[i],vl[i],last,s) if s in last and len(last)==3 else None; ex_late=-1; gross=np.nan
                if val is None: C[ex+' no fill']+=1; continue
                rows.append((ex,k,side,m,ev,s,t,val,abs(g),vmd[i],gross,ex_late,how,vm[i]))
    print("counts",dict(sorted(C.items())),flush=True)
    if rows:
        T=pd.DataFrame(rows,columns=['ex','k','side','m','ev','s','tt','v','gap','mid','gross','late','how','minute']); halves(T)
        for ex in sorted(T.ex.unique()):
            E=T[T.ex==ex]
            for k in ('LEAD','FLAT'):
                K=E[E.k==k]; can=k=='LEAD'
                rd(f"{ex} {k} ALL",K,can); rd(f"{ex} {k} BACK",K[K.side=='B'],can); rd(f"{ex} {k} LAY",K[K.side=='L'],can)
            K=E[E.k=='LEAD']
            for lo,hi in ((1,2),(2,4),(4,10),(10,50)): rd(f"{ex} ctx LEAD mid {lo}-{hi}",K[(K.mid>=lo)&(K.mid<hi)],False)
            rd(f"{ex} ctx LEAD gap 2-5%",K[K.gap<0.05],False); rd(f"{ex} ctx LEAD gap 5%+",K[K.gap>=0.05],False)
            rd(f"{ex} ctx LEAD exact names",K[K.how=='exact'],False)
            rd(f"{ex} ctx LEAD settled at last prints",K[K.late==-1],False)
            print(ex,"LEAD gross move toward other, %",round(100*K.gross.mean(),2),"t",round(tstat(K.gross.dropna()),2),"; FLAT %",round(100*E[E.k=='FLAT'].gross.mean(),2),flush=True)
    show("item 331")
print(f"run {time.time()-T0:.0f}s")
PY
