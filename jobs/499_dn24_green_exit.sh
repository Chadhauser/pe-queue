#!/bin/bash
set -o pipefail
# 499_dn24_green_exit (Finder 2026-11-09, queue item 479, next door of item 445; built from jobs/499_jump_down_lay.sh, rule pushed to the queue before this job read a price).
# Lay the Match Odds runner whose first in-play print sits 2 to under 4 implied points UNDER its last pre-off print (DN24, item 445's signal, code unchanged),
# then back out at the first in-play print 10 to 15 min after entry, greened to equal profit; no print in that window -> held to the official result, never dropped.
# Scored: MO ONE green, MO FAV green, every loaded month, halves by date median, standard bar; months before Mar 2023 printed apart and must be positive too.
# Control FLAT: runners whose first in-play print sits under 1 point either way from the last pre-off print, same entry and exit, for the round-trip cost.
# Read only, no tables written. Prints only, so a pass earns a real-touch read on liq_sample, not a stake.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,gc,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,lay_hedge,step
from lib_official import ly,fill,last_in,first_in,secs,checks,group,load_results
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',230); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',200)
CUT=pd.Timestamp('2023-03-01',tz='UTC').timestamp()
EX0,EX1=600,900
def gap_pts(pre,ip): return 100*(1/pre-1/ip)
def dn24(g): return -4<g<=-2
def flat(g): return -1<g<1
def exit_ix(ts,t0): return first_in(ts,t0+EX0,t0+EX1)
def green(pl,ts,px,t0,won):
    """Lay filled at pl (raw, before the adverse tick). Out at the worse (lower) of the first print 10-15 min on and the next within 120 s; else held to the result."""
    j=exit_ix(ts,t0)
    if j is None: return ly(pl,won),0
    q=fill(ts,px,j,'B'); return lay_hedge(step(pl,1),q),1
# known answers, worked by hand
assert abs(gap_pts(2.0,1.9)+2.6316)<1e-3 and dn24(gap_pts(2.0,1.9)) and not dn24(gap_pts(2.0,1.85))
assert flat(0.5) and flat(-0.99) and not flat(1.0) and not flat(-1.0)
# lay 1.9 -> filled 1.91 (one tick adverse): stake 10/0.91=10.989; out by backing at print 2.2 -> 2.18 (one tick adverse): 10.989*(1-1.91/2.18)=1.36103, x0.98 = 1.33381
_t=np.array([0.,700.,760.]); _p=np.array([1.9,2.2,2.3])
v,e=green(1.9,_t,_p,0.,True); assert e==1 and abs(v-10/0.91*(1-1.91/2.18)*0.98)<1e-6, v
# exit print lower than the entry: 1.9 -> 1.91 laid, out at 1.7 -> 1.69: 10.989*(1-1.91/1.69) = -1.43053, no commission on a loss
v,e=green(1.9,np.array([0.,650.]),np.array([1.9,1.7]),0.,False); assert e==1 and abs(v-10/0.91*(1-1.91/1.69))<1e-6
# worse of the exit print and the next within 120 s: 2.2 then 2.0 at +60 s -> 2.0 -> 1.99
v,e=green(1.9,np.array([0.,700.,760.]),np.array([1.9,2.2,2.0]),0.,True); assert abs(v-10/0.91*(1-1.91/1.99)*0.98)<1e-6
# no print 10-15 min on -> held to the result: runner wins -10, loses +10/0.91*0.98
v,e=green(1.9,np.array([0.,300.,1000.]),np.array([1.9,2.0,2.1]),0.,True); assert e==0 and v==-10.0
v,e=green(1.9,np.array([0.,300.]),np.array([1.9,2.0]),0.,False); assert e==0 and abs(v-10/0.91*0.98)<1e-9
print("checks: OK",flush=True); T0=time.time()
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
RS,dr=load_results(con,['MATCH_ODDS']); print("official MATCH_ODDS",len(RS),"dropped (no single winner)",dr,flush=True)
C=Counter(); rows=[]
def chunks():
    for y,ms in ((2022,range(8,13)),(2023,range(1,13)),(2024,range(1,11)),(2026,range(5,11))):
        for m in ms:
            a=pd.Timestamp(y,m,1); e=a+pd.offsets.MonthBegin(1)
            while a<e:
                b=min(a+pd.Timedelta(days=10),e); yield str(a.date()),str(b.date()); a=b
for lo,hi in chunks():
    X=pd.read_sql("""SELECT market_id,event_name ev,market_time mt,sel,inplay,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND ltp>=1.01 AND ltp<1000
                     AND ts>=market_time-interval '11 minutes' AND ts<=market_time+interval '22 minutes' AND market_time>=%s AND market_time<%s""",con,params=(lo,hi))
    if X.empty: continue
    X['tt']=secs(X.ts); X['off']=secs(X.mt); X=X.sort_values('tt',kind='stable').drop_duplicates(['market_id','sel','tt'])
    for (ev,off),G_ in X.groupby(['ev','off'],sort=False):
        C['games']+=1; mk=sorted(G_.market_id.unique())[0]
        if not isinstance(ev,str) or ' v ' not in ev: C['no H v A']+=1; continue
        if group(ev): C['women or youth']+=1; continue
        if mk not in RS: C['no official']+=1; continue
        g0=G_[G_.market_id==mk]; legs={}
        for s,y in g0.groupby('sel',sort=False):
            pm=y[~y.inplay]; ip=y[y.inplay]; legs[s]=(pm.tt.values,pm.ltp.values,ip.tt.values,ip.ltp.values)
        last={}
        for s,(a,b,_,_) in legs.items():
            i=last_in(a,off-600,off+360)
            if i is not None: last[s]=float(b[i])
        ru=[s for s in last if s!='The Draw']
        if len(ru)<2 or last[ru[0]]==last[ru[1]]: C['MO roles unknown']+=1; continue
        roles={min(ru,key=lambda s:last[s]):'FAV',max(ru,key=lambda s:last[s]):'OUT'}
        if 'The Draw' in last: roles['The Draw']='DRAW'
        for s,r in roles.items():
            if s not in RS[mk]: C['sel not in result']+=1; continue
            a,b,c,d=legs[s]; i=first_in(c,off-300,off+180)
            if i is None: continue
            pre=last_in(a,off-600,float(c[i]))
            if pre is None: continue
            g=gap_pts(float(b[pre]),float(d[i]))
            k='DN24' if dn24(g) else ('FLAT' if flat(g) else None)
            if k is None: continue
            won=RS[mk][s]; t0=float(c[i]); pl=fill(c,d,i,'L')
            if pl>50: continue
            v,e=green(pl,c,d,t0,won)
            rows.append(dict(k=k,r=r,ev=ev,off=off,g=abs(g),px=float(d[i]),pl=pl,won=won,vg=v,ex=e,vl=ly(pl,won),unseen=off<CUT))
    del X; gc.collect()
    print(lo,"cands",len(rows),f"{time.time()-T0:.0f}s",flush=True)
con.close(); print("counts",dict(sorted(C.items())),flush=True)
T=pd.DataFrame(rows)
def one(x): return x.sort_values(['g','r'],ascending=[False,True]).drop_duplicates(['ev','off']).sort_values('off').copy()   # one bet a game, the larger gap
D=T[T.k=='DN24']; F=T[T.k=='FLAT']
ONE=one(D); FONE=F.sort_values(['g','r']).drop_duplicates(['ev','off']).sort_values('off')   # control: one a game, the flattest runner
def row(nm,x,col='vg'):
    v=x[col].astype(float).values
    if len(v)<2: return dict(line=nm,n=len(v))
    med=x.off.median(); h=np.where(x.off<=med,1,2); d_=line(v,h)
    return dict(line=nm,n=d_['n'],games=x[['ev','off']].drop_duplicates().shape[0],per10=round(d_['per10'],3),t=round(d_['t'],2),h1=round(d_['h1'],3),h2=round(d_['h2'],3),n1=d_['n1'],n2=d_['n2'],
                exited=round(x.ex.mean(),3),won=round(x.won.astype(float).mean(),3),imp=round((1/x.px).mean(),3),PASS=d_['PASS'])
print(f"\nmonths: {sorted(pd.to_datetime(T.off,unit='s').dt.strftime('%Y-%m').unique())}; halves by date median within each line")
o=[row('MO ONE green *',ONE),row('MO FAV green *',ONE[ONE.r=='FAV'])]
for r_ in ('OUT','DRAW'): o.append(row(f'MO {r_} green',ONE[ONE.r==r_]))
o+=[row('MO ONE to result (445 as read)',ONE,'vl'),row('MO FAV to result (445 as read)',ONE[ONE.r=='FAV'],'vl'),
    row('MO ONE green, exited only',ONE[ONE.ex==1]),row('MO FAV green, exited only',ONE[(ONE.ex==1)&(ONE.r=='FAV')])]
for nm,x in (('before Mar 2023',ONE[ONE.unseen]),('Mar 2023 on',ONE[~ONE.unseen])):
    o+=[row(f'{nm}: MO ONE green',x),row(f'{nm}: MO FAV green',x[x.r=='FAV'])]
for y in (2022,2023,2024,2026):
    yy=ONE[pd.to_datetime(ONE.off,unit='s').dt.year==y]; o+=[row(f'{y} MO ONE green',yy),row(f'{y} MO FAV green',yy[yy.r=='FAV'])]
o+=[row('CONTROL FLAT one a game green',FONE),row('CONTROL FLAT FAV green',F[F.r=='FAV']),row('CONTROL FLAT DRAW green',F[F.r=='DRAW'])]
print("== ITEM 479, scored lines marked *\n",pd.DataFrame(o).to_string(index=False))
S=[s for s in o[:2] if s.get('PASS')]
U=ONE[ONE.unseen]; uu=[row('u',U),row('u',U[U.r=='FAV'])]
S=[s for s,u in zip(o[:2],uu) if s.get('PASS') and u.get('per10',-1)>0]
print("\n== SURVIVORS (bar on all months AND months before Mar 2023 positive)"); print(pd.DataFrame(S).to_string(index=False) if S else "none",flush=True); print(f"total {time.time()-T0:.0f}s")
PY
