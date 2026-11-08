#!/bin/bash
set -o pipefail
# 499_xx_rest (Finder 2026-11-08, queue item 437, Finder's own, source c, from items 330, 339, 436, jobs/499_xx_stale.sh): rest inside Matchbook's spread pre-off, hedge on Betfair.
# Rule fixed in the queue before any price was read. Matchbook football match odds, T-30 to T-2, at each Betfair (liq_sample) row, Matchbook's last row at or before it within 60 s.
# Resting BACK at P = Matchbook lay touch less one tick (must stay above its back touch); resting LAY at Q = Matchbook back touch plus one tick (must stay under its lay touch).
# Post only if P >= 1.01 x (Betfair lay touch + 1 tick), the hedge lay; or Q <= (Betfair back touch - 1 tick) / 1.01, the hedge back.
# Fill: a later Matchbook row within 120 s whose ltp CHANGED from the row before and is strictly through the posted price. A resting back at P fills only when a layer traded ABOVE P
#   (layers take the lowest back first, so a print above P means P was used up); a resting lay at Q fills only on a print BELOW Q. Unfilled posts counted, not traded.
# On a fill, hedge on Betfair at its first row at or after the fill row (within 120 s, else counted), one tick adverse, size at least £10 at that Betfair touch, greened, worse outcome, 2% each side.
# One post per runner per game per side. CONTROL (cannot pass): posts where Betfair's mid moved 1% or more over the last 60 s toward making the post look good
#   (fell for a resting back, rose for a resting lay), so Matchbook's quote is just stale. QUIET: the rest. Standard bar, halves by date, t by game. Ladder: Betfair's ticks on both books.
# Modes: no argument = known-answer checks only (cron's runner); pull = copy Matchbook pre-off rows with ltp and sizes from Railway into local xx_pre_437 (keyed, never dropped), stops if Railway is busy or after 30 min; trade = the test.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,datetime as dt,psycopg2,psycopg2.extras,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,tstat,passes
from lib_official import secs
from lib_xx import pair,side_of,pick,median_gap,LABS
import lib_xx; lib_xx.checks()
pd.set_option('display.width',240); pd.set_option('display.max_columns',30)
START=dt.datetime(2026,11,4,22,0,tzinfo=dt.timezone.utc)
def green_back_other(a,lb,c=0.02):
    s=10*a/lb
    return min(10*(a-1)*(1-c)-s*(lb-1), -10+s*(1-c))
def green_lay_other(l,bb,c=0.02):
    k=10/(l-1); s=k*l/bb
    return min(-10+s*(bb-1)*(1-c), k*(1-c)-s)
def posts(mb,ml,bb,bl):
    """Matchbook touch mb<ml, Betfair touch bb<bl. Returns dict side->price for posts that qualify."""
    out={}
    P=step(ml,-1)
    if P>mb and P>=1.01*step(bl,1): out['BACK']=P
    Q=step(mb,1)
    if Q<ml and step(bb,-1)>1.01 and Q<=step(bb,-1)/1.01 and Q>1.01: out['LAY']=Q
    return out
def filled(side,price,ltp_prev,ltp_now):
    if ltp_now is None or ltp_prev is None or not np.isfinite(ltp_now) or ltp_now==ltp_prev: return False
    return ltp_now>price if side=='BACK' else ltp_now<price
def touched(side,price,back_now,lay_now):
    """Item 438: a resting back at P fills when Matchbook's back touch (a resting lay offer) is strictly above P; a resting lay at Q when its lay touch is strictly below Q."""
    if side=='BACK': return bool(np.isfinite(back_now) and back_now>price)
    return bool(np.isfinite(lay_now) and lay_now<price)
# known answers, worked by hand
# Matchbook 2.10/2.20, Betfair 2.00/2.02. P=2.18 (one tick under 2.20), hedge lay 2.04, 1.01*2.04=2.0604 <= 2.18: post. Q=2.12, hedge back 1.99, 1.99/1.01=1.970 < 2.12: no lay post.
assert posts(2.10,2.20,2.00,2.02)=={'BACK':2.18}
# Matchbook 1.90/2.00, Betfair 2.04/2.06: Q=1.91, hedge back 2.02, 2.02/1.01=2.0 >= 1.91: post lay. P=1.99, hedge lay 2.08: no.
assert posts(1.90,2.00,2.04,2.06)=={'LAY':1.91}
assert posts(2.00,2.02,2.00,2.02)=={}            # one-tick Matchbook spread: nothing inside it
assert touched('BACK',2.18,2.20,2.24) and not touched('BACK',2.18,2.18,2.22) and touched('LAY',1.91,1.86,1.90) and not touched('LAY',1.91,1.86,1.91) and not touched('BACK',2.18,float('nan'),2.3)
assert filled('BACK',2.18,2.16,2.20) and not filled('BACK',2.18,2.20,2.20) and not filled('BACK',2.18,2.10,2.18) and filled('LAY',1.91,1.92,1.90) and not filled('LAY',1.91,1.92,1.91)
# Back 2.18 £10, lay Betfair 2.04: stake 10.686. Wins: 11.8*.98=11.564-10.686*1.04=0.4505. Loses: -10+10.686*.98=0.4725. Worse 0.4505.
assert abs(green_back_other(2.18,2.04)-(11.8*.98-(21.8/2.04)*1.04))<1e-9 and green_back_other(2.18,2.04)>0
print("checks: OK",flush=True); T0=time.time()
MODE=sys.argv[1] if len(sys.argv)>1 else 'asserts-only'
if MODE not in ('pull','trade','trade-touch'): print("== SURVIVORS: not run, asserts only"); sys.exit(0)
L=psycopg2.connect(creds.pg_local()); L.autocommit=True; lc=L.cursor(); lc.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
if MODE=='pull':
    lc.execute("""CREATE TABLE IF NOT EXISTS xx_pre_437(ts timestamptz,exchange text,event_name text,market_id text,start_ts timestamptz,sel_name text,
                  back_px float8,back_sz float8,lay_px float8,lay_sz float8,ltp float8,PRIMARY KEY(exchange,market_id,sel_name,ts))""")
    lc.execute("select max(ts) from xx_pre_437"); mx=lc.fetchone()[0]
    t=max(START,mx-dt.timedelta(hours=1)) if mx else START
    R=psycopg2.connect(creds.pg_railway()); R.autocommit=True; rc=R.cursor(); rc.execute("SET statement_timeout='600s'")
    now=dt.datetime.now(dt.timezone.utc); tot=0
    while t<now:
        if time.time()-T0>1800: print("30 min reached, pull stopped at",t,"; re-run pull to go on",flush=True); break
        rc.execute("select count(*) filter (where state='active' and now()-query_start>interval '5 minutes') from pg_stat_activity"); busy=rc.fetchone()[0]
        if busy>3: print("railway busy",busy,"pull stopped at",t,flush=True); break
        e=min(t+dt.timedelta(hours=6),now)
        rc.execute("""SELECT ts,exchange,event_name,market_id,start_ts,sel_name,back_px::float8,back_sz::float8,lay_px::float8,lay_sz::float8,ltp::float8 FROM xx_tape
                      WHERE exchange='matchbook' AND ts>=%s AND ts<%s AND sport='football' AND market_name='Match Odds' AND NOT inplay AND start_ts-ts BETWEEN interval '0' AND interval '37 minutes'""",(t,e))
        rows=rc.fetchall(); tot+=len(rows)
        if rows: psycopg2.extras.execute_values(lc,"INSERT INTO xx_pre_437 VALUES %s ON CONFLICT DO NOTHING",rows,page_size=2000)
        print(t.strftime('%m-%d %H:%M'),len(rows),tot,f"{time.time()-T0:.0f}s",flush=True); t=e
    R.close()
    lc.execute("select count(*),count(distinct market_id),min(ts),max(ts),count(ltp) from xx_pre_437"); print("xx_pre_437:",lc.fetchall(),flush=True)
    print("== SURVIVORS: pull only"); sys.exit(0)
X=pd.read_sql("SELECT ts,exchange,event_name,market_id,start_ts,sel_name,back_px,back_sz,lay_px,lay_sz,ltp FROM xx_pre_437",L)
B=pd.read_sql("""SELECT DISTINCT ts,market_id,event_name,sel,minute,back_px::float8 b,back_sz::float8 bs,lay_px::float8 l,lay_sz::float8 ls,total_matched::float8 tm FROM liq_sample
                 WHERE mkt='MO' AND ts>=%s AND market_id IN (SELECT market_id FROM liq_sample WHERE mkt='MO' AND minute=0 AND ts>=%s GROUP BY 1 HAVING count(*)>=30)""",L,params=(START,START))
L.close(); C=Counter()
B['tt']=secs(B.ts); B=B.sort_values(['market_id','tt'])
hi=B.groupby('market_id').tm.cummax(); keep=B.tm.isna()|(B.tm>=0.999*hi); C['betfair rows replay dropped']=int((~keep).sum()); B=B[keep]
print(f"Matchbook rows {len(X):,}, markets {X.market_id.nunique():,}, ltp present {X.ltp.notna().mean():.3f}; Betfair rows {len(B):,}, markets {B.market_id.nunique():,}; {time.time()-T0:.0f}s",flush=True)
BM={m:g for m,g in B.groupby('market_id')}
SPAN={m:(g.tt.min(),g.tt.max()) for m,g in BM.items()}
PAIRS=[(pair(ev),m) for m,ev in B[['market_id','event_name']].drop_duplicates().itertuples(index=False) if pair(ev)]
X['tt']=secs(X.ts); X['st']=secs(X.start_ts); rows=[]
for (xm,ev,st),gx in X.groupby(['market_id','event_name','st'],sort=False):
    C['markets']+=1
    got=pick(pair(ev),[(q,m) for q,m in PAIRS if SPAN[m][0]<=st and SPAN[m][1]>=st-1800])
    if got is None: C['no Betfair market']+=1; continue
    m,how=got; gb=BM[m]
    if set(gb.sel.unique())!=LABS or gb.duplicated(['sel','tt']).any(): C['Betfair labels or rows not as expected']+=1; continue
    gx=gx.assign(side=[side_of(s,ev) for s in gx.sel_name])
    if gx.side.isna().any() or set(gx.side.unique())!=LABS: C['runner names not matched']+=1; continue
    bad=False
    for s,bs in gb.groupby('sel'):
        o=gx[(gx.side==s)&gx.back_px.notna()&gx.lay_px.notna()].sort_values('tt'); v=bs[bs.b.notna()&bs.l.notna()&(bs.minute==0)]
        mg=median_gap(o.tt.values,((o.back_px+o.lay_px)/2).values,v.tt.values,((v.b+v.l)/2).values)
        if mg is not None and mg>0.15: bad=True
    if bad: C['wrong pairing, gap over 15%']+=1; continue
    C['matched']+=1
    for s,bs in gb.groupby('sel'):
        o=gx[gx.side==s].sort_values('tt'); v=bs[bs.b.notna()&bs.l.notna()&(bs.l>bs.b)&(bs.b>=1.01)]
        if len(o)<2 or not len(v): continue
        ot=o.tt.values; ob=o.back_px.values; ol=o.lay_px.values; olt=o.ltp.values
        vt=v.tt.values; vb=v.b.values; vl=v.l.values; vbs=v.bs.values; vls=v.ls.values; vm=(vb+vl)/2; vmin=v.minute.values
        done=set()
        for i in np.where((vt>=st-1800)&(vt<=st-120)&(vmin==0))[0]:
            if len(done)==2: break
            t=vt[i]; j=int(np.searchsorted(ot,t,side='right'))-1
            if j<0 or ot[j]<t-60 or not (np.isfinite(ob[j]) and np.isfinite(ol[j]) and ol[j]>ob[j]>=1.01): continue
            pp={k:p for k,p in posts(ob[j],ol[j],vb[i],vl[i]).items() if k not in done}
            if not pp: continue
            h60=np.where((vt>=t-60)&(vt<t))[0]; mv=(vm[i]/vm[h60[0]]-1) if len(h60) else 0.0
            for side,price in pp.items():
                done.add(side); C['posts '+side]+=1
                cls='CONTROL' if (mv<=-0.01 if side=='BACK' else mv>=0.01) else 'QUIET'
                k=None
                for f in range(j+1,len(ot)):
                    if ot[f]>t+120: break
                    if (touched(side,price,ob[f],ol[f]) if MODE=='trade-touch' else filled(side,price,olt[f-1],olt[f])): k=f; break
                if k is None: C['unfilled '+side+' '+cls]+=1; continue
                q=np.where(vt>=ot[k])[0]
                if not len(q) or vt[q[0]]>ot[k]+120: C['no Betfair hedge row in 120 s']+=1; continue
                e=q[0]
                if side=='BACK':
                    h=step(vl[e],1); ok=vls[e]>=10; val=green_back_other(price,h)
                else:
                    h=step(vb[e],-1); ok=vbs[e]>=10 and h>1.01; val=green_lay_other(price,h) if h>1.01 else None
                if not ok or val is None: C['hedge touch under £10 or at floor']+=1; continue
                C['fills '+side+' '+cls]+=1
                rows.append((cls,side,m,s,t,val,vm[i],ot[k]-t,price,h,(ol[j]-ob[j])/ob[j]))
print("counts",dict(sorted(C.items())),flush=True)
T=pd.DataFrame(rows,columns=['k','side','m','s','tt','v','mid','lag','price','h','msp'])
if not len(T): print("no fills"); print("== SURVIVORS: none"); sys.exit(0)
out=[]
def rd(name,d,can=True):
    if not len(d): return
    med=d.tt.median(); hh=np.where(d.tt<=med,1,2)
    n=len(d); a=d.v[hh==1]; b=d.v[hh==2]; mean=d.v.mean(); t=tstat(d.v); tg=tstat(d.groupby('m').v.sum())
    ok=can and passes(n,len(a),len(b),t,a.mean() if len(a) else -1,b.mean() if len(b) else -1,mean) and tg>=3.5
    out.append(dict(line=name,n=n,per10=round(mean,3),t=round(t,2),t_game=round(tg,2),h1=round(a.mean(),3) if len(a) else None,n1=len(a),h2=round(b.mean(),3) if len(b) else None,n2=len(b),
        games=d.m.nunique(),win=round((d.v>0).mean(),3),fill_lag=round(d.lag.median(),0),PASS='PASS' if ok else ''))
rd("REST ALL",T); rd("REST BACK on Matchbook",T[T.side=='BACK']); rd("REST LAY on Matchbook",T[T.side=='LAY'])
for k in ('QUIET','CONTROL'):
    K=T[T.k==k]; rd(f"{k} ALL",K,k=='QUIET'); rd(f"{k} BACK",K[K.side=='BACK'],k=='QUIET'); rd(f"{k} LAY",K[K.side=='LAY'],k=='QUIET')
for lo,hi_ in ((1,2),(2,4),(4,10),(10,50)): rd(f"ctx mid {lo}-{hi_}",T[(T.mid>=lo)&(T.mid<hi_)],False)
rd("ctx Matchbook spread <=5%",T[T.msp<=0.05],False); rd("ctx Matchbook spread >5%",T[T.msp>0.05],False)
R_=pd.DataFrame(out).sort_values('t',ascending=False); print(R_.to_string(index=False),flush=True)
print(f"run {time.time()-T0:.0f}s")
print("== SURVIVORS:",[r for r in R_[R_.PASS=='PASS'].line] or 'none')
PY
