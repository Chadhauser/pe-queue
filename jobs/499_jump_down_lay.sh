#!/bin/bash
set -o pipefail
# 499_jump_down_lay (Finder 2026-11-08, queue item 445, from items 414 and 444's controls; built from jobs/499_jump_up_ou25.sh and jobs/499_jump_up_delay.sh, rule as pushed in the queue before this job read a price).
# Lay a runner whose first in-play print sits 2 to under 4 implied points UNDER its last pre-off print (DN24, shortened at the off), MO and OU25, to the official result.
# Scored only on months before Mar 2023 (UNSEEN); every earlier read of DN24 was a control on months chosen for the UP signal, so Mar 2023 on is printed as an audit that cannot pass.
# Interim tonight: only Soccer 2023-02 is loaded before Mar 2023, so n cannot reach 300; the read says n. Read only, no tables written. Prints only, so a pass earns a real-touch read on liq_sample, not a stake.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,gc,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line
from lib_official import ly,fill,last_in,first_in,secs,checks,group,load_results
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',230); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',200)
WIDTH=300; CUT=pd.Timestamp('2023-03-01',tz='UTC').timestamp()
OUS={'Over 2.5 Goals':'OVER','Under 2.5 Goals':'UNDER'}
def gap_pts(pre,ip): return 100*(1/pre-1/ip)
def dn24(g): return -4<g<=-2
def delayed(ts,t0,D): return first_in(ts,t0+D*60,t0+D*60+WIDTH)
# known answers, worked by hand
# pre 2.0, first in-play 1.9: 100*(0.5-0.52632) = -2.632 -> DN24; 1.95 -> -1.282 no; 1.85 -> -4.054 no; 2.1 -> +2.381 no (that is UP24)
assert abs(gap_pts(2.0,1.9)+2.6316)<1e-3 and dn24(gap_pts(2.0,1.9)) and not dn24(gap_pts(2.0,1.95)) and not dn24(gap_pts(2.0,1.85)) and not dn24(gap_pts(2.0,2.1))
assert dn24(-2.0) and dn24(-3.999) and not dn24(-4.0) and not dn24(-1.999)
# lay fill: higher of print and next within 120 s, then one tick adverse. 1.9 then 1.95 at +60 s -> 1.95 -> 1.96: stake 10/0.96; runner loses +10.208*0.98=10.2083; wins -10
t=np.array([0.,60.]); p=np.array([1.9,1.95]); f=fill(t,p,0,'L'); assert f==1.95
assert abs(ly(f,False)-10/0.96*0.98)<1e-9 and ly(f,True)==-10.0
assert fill(np.array([0.,200.]),np.array([1.9,1.95]),0,'L')==1.9
_t=np.array([0.,100.,300.,700.]); assert delayed(_t,0.,5)==2 and delayed(_t,100.,5)==3 and delayed(_t,700.,5) is None
print("checks: OK",flush=True); T0=time.time()
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
RS={}
for mt in ('MATCH_ODDS','OVER_UNDER_25'):
    r,dr=load_results(con,[mt]); RS.update(r); print("official",mt,len(r),"dropped (no single winner)",dr,flush=True)
C=Counter(); rows=[]
def chunks():
    for y,ms in ((2022,range(8,13)),(2023,range(1,13)),(2024,range(1,11)),(2026,range(5,11))):
        for m in ms:
            a=pd.Timestamp(y,m,1); e=a+pd.offsets.MonthBegin(1)
            while a<e:
                b=min(a+pd.Timedelta(days=10),e); yield str(a.date()),str(b.date()); a=b
for lo,hi in chunks():
    for mkt in ('MATCH_ODDS','OVER_UNDER_25'):
        X=pd.read_sql("""SELECT market_id,event_name ev,market_time mt,sel,inplay,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type=%s AND ltp>=1.01 AND ltp<1000
                         AND ts>=market_time-interval '11 minutes' AND ts<=market_time+interval '14 minutes' AND market_time>=%s AND market_time<%s""",con,params=(mkt,lo,hi))
        if X.empty: continue
        X['tt']=secs(X.ts); X['off']=secs(X.mt); X=X.sort_values('tt',kind='stable').drop_duplicates(['market_id','sel','tt'])
        for (ev,off),G_ in X.groupby(['ev','off'],sort=False):
            C[mkt+' games']+=1; mk=sorted(G_.market_id.unique())[0]
            if not isinstance(ev,str) or ' v ' not in ev: C['no H v A']+=1; continue
            if group(ev): C['women or youth']+=1; continue
            if mk not in RS: C[mkt+' no official']+=1; continue
            g0=G_[G_.market_id==mk]; legs={}
            for s,y in g0.groupby('sel',sort=False):
                pm=y[~y.inplay]; ip=y[y.inplay]; legs[s]=(pm.tt.values,pm.ltp.values,ip.tt.values,ip.ltp.values)
            if mkt=='MATCH_ODDS':
                last={}
                for s,(a,b,_,_) in legs.items():
                    i=last_in(a,off-600,off+360)
                    if i is not None: last[s]=float(b[i])
                ru=[s for s in last if s!='The Draw']
                if len(ru)<2 or last[ru[0]]==last[ru[1]]: C['MO roles unknown']+=1; continue
                roles={min(ru,key=lambda s:last[s]):'FAV',max(ru,key=lambda s:last[s]):'OUT'}
                if 'The Draw' in last: roles['The Draw']='DRAW'
            else:
                roles={s:OUS[s] for s in legs if s in OUS}
            for s,r in roles.items():
                if s not in RS[mk]: C['sel not in result']+=1; continue
                a,b,c,d=legs[s]; i=first_in(c,off-300,off+180)
                if i is None: continue
                pre=last_in(a,off-600,float(c[i]))
                if pre is None: continue
                g=gap_pts(float(b[pre]),float(d[i]))
                if not dn24(g): continue
                won=RS[mk][s]; t0=float(c[i]); j=delayed(c,t0,5)
                rows.append(dict(m='MO' if mkt=='MATCH_ODDS' else 'OU25',r=r,ev=ev,off=off,g=abs(g),px=float(d[i]),pl=fill(c,d,i,'L'),
                                 p5=np.nan if j is None else fill(c,d,j,'L'),won=won,unseen=off<CUT))
        del X; gc.collect()
    print(lo,"cands",len(rows),f"{time.time()-T0:.0f}s",flush=True)
con.close(); print("counts",dict(sorted(C.items())),flush=True)
T=pd.DataFrame(rows); T=T[T.pl<=50].copy()
T['vl']=[ly(p,w) for p,w in zip(T.pl,T.won)]
T['v5']=[np.nan if p!=p or p>50 else ly(p,w) for p,w in zip(T.p5,T.won)]
ONE=T.sort_values(['g','r'],ascending=[False,True]).drop_duplicates(['m','ev','off']).sort_values('off').copy()   # one bet per game per market, the larger gap
def row(nm,x,col='vl'):
    x=x.dropna(subset=[col]); v=x[col].astype(float).values
    if len(v)<2: return dict(line=nm,n=len(v))
    med=x.off.median(); h=np.where(x.off<=med,1,2); d=line(v,h)
    return dict(line=nm,n=d['n'],games=x[['ev','off']].drop_duplicates().shape[0],per10=round(d['per10'],3),t=round(d['t'],2),h1=round(d['h1'],3),h2=round(d['h2'],3),n1=d['n1'],n2=d['n2'],
                won=round(x.won.astype(float).mean(),3),imp=round((1/x.px).mean(),3),PASS=d['PASS'])
U=ONE[ONE.unseen]; A=ONE[~ONE.unseen]
print(f"\nUNSEEN months: {sorted(pd.to_datetime(U.off,unit='s').dt.strftime('%Y-%m').unique())}; halves by date median within each line")
o=[row('UNSEEN MO ONE lay *',U[U.m=='MO']),row('UNSEEN OU25 OVER lay *',U[(U.m=='OU25')&(U.r=='OVER')]),row('UNSEEN OU25 UNDER lay',U[(U.m=='OU25')&(U.r=='UNDER')])]
for r_ in ('FAV','OUT','DRAW'): o.append(row(f'UNSEEN MO {r_} lay',U[(U.m=='MO')&(U.r==r_)]))
o+= [row('UNSEEN MO ONE D5 lay',U[U.m=='MO'],'v5'),row('UNSEEN OU25 OVER D5 lay',U[(U.m=='OU25')&(U.r=='OVER')],'v5')]
print("== ITEM 445, scored lines marked *\n",pd.DataFrame(o).to_string(index=False))
a=[row('AUDIT MO ONE lay',A[A.m=='MO']),row('AUDIT OU25 OVER lay',A[(A.m=='OU25')&(A.r=='OVER')]),row('AUDIT OU25 UNDER lay',A[(A.m=='OU25')&(A.r=='UNDER')])]
for r_ in ('FAV','OUT','DRAW'): a.append(row(f'AUDIT MO {r_} lay',A[(A.m=='MO')&(A.r==r_)]))
a+= [row('AUDIT MO ONE D5 lay',A[A.m=='MO'],'v5'),row('AUDIT OU25 OVER D5 lay',A[(A.m=='OU25')&(A.r=='OVER')],'v5')]
for y in (2023,2024,2026):
    yy=A[pd.to_datetime(A.off,unit='s').dt.year==y]; a+=[row(f'AUDIT {y} MO ONE lay',yy[yy.m=='MO']),row(f'AUDIT {y} OU25 OVER lay',yy[(yy.m=='OU25')&(yy.r=='OVER')])]
print("\n-- audit, Mar 2023 to Sep 2026, months that chose the UP signal; cannot pass\n",pd.DataFrame(a).to_string(index=False))
S=[s for s in o[:2] if s.get('PASS')]
print("\n== SURVIVORS"); print(pd.DataFrame(S).to_string(index=False) if S else "none",flush=True); print(f"total {time.time()-T0:.0f}s")
PY
