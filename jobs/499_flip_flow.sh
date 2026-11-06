#!/bin/bash
set -o pipefail
# 499_flip_flow (Finder 2026-11-06, queue items 294, 295, Finder's own, sources a, b; fills from jobs/lib_official.py): the jump between last pre-off and first in-play print; signed prints before the off. Rules pushed in the queue (fd41c8e) before any price. Read only, no tables written. Prints only, so a pass is an upper bound.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,step
from lib_official import bk,ly,fill,last_in,first_in,secs,checks,group,load_results
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',220); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',200)
def jump_band(pre,ip):
    """Implied points pre less in-play: price rose gives UP. Band 1-2, 2-4, 4-8, else None."""
    g=100*(1/pre-1/ip); a=abs(g)
    b='1-2' if 1<=a<2 else '2-4' if 2<=a<4 else '4-8' if 4<=a<8 else None
    return None if b is None else ('UP' if g>0 else 'DOWN',b)
def flow(px):
    """Prints in time order: (changes, imbalance). Down-prints count +, up-prints -, against the last different print."""
    d=u=0; l=None
    for p in px:
        if l is not None and p!=l:
            if p<l: d+=1
            else: u+=1
        l=p
    n=d+u
    return n,(d-u)/n if n else 0.0
def flow_state(px):
    n,im=flow(px)
    if n<6: return None
    return 'BUY' if im>=0.3 else 'SELL' if im<=-0.3 else None
def flat(px):
    a,b=float(px[0]),float(px[-1]); return step(a,-1)<=b<=step(a,1)
# known answers, worked by hand
assert jump_band(2.0,2.1)==('UP','2-4') and jump_band(2.0,1.9)==('DOWN','2-4')    # 50 v 47.62 is 2.38; 50 v 52.63 is 2.63
assert jump_band(2.0,2.02) is None and jump_band(2.0,2.5)is None                  # 0.99 points; 10 points
assert jump_band(2.0,2.06)==('UP','1-2') and jump_band(3.0,3.05) is None          # 50 v 48.54 is 1.46; 33.33 v 32.79 is 0.55
assert flow([2.0,1.9,1.9,1.8,1.9,1.7])==(4,0.5) and flow([2.0])==(0,0.0)
assert flow_state([2,1.9,1.8,1.7,1.6,1.5,1.4])=='BUY' and flow_state([1,2,3,4,5,6,7])=='SELL' and flow_state([2,1.9,2,1.9,2,1.9,2]) is None and flow_state([2,1.9,1.8]) is None
assert flat([2.0,1.5,2.02]) and flat([2.0,2.5,1.99]) and not flat([2.0,2.04])
print("checks: OK",flush=True); T0=time.time()
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
TY=['MATCH_ODDS','OVER_UNDER_25']
RS,dr=load_results(con,TY); print("official markets",len(RS),"dropped, not one winner",dr,f"{time.time()-T0:.0f}s",flush=True)
C=Counter(); rows=[]
def add(item,lab,off,ev,L,B,won):
    rows.append((item,lab,'lay',off,ev,None if L>50 else ly(L,won)))
    rows.append((item,lab,'back',off,ev,None if B>50 else bk(B,won)))
def month_chunks():
    for y,ms in ((2024,range(1,12)),(2026,range(5,12))):
        for m in ms:
            a=pd.Timestamp(y,m,1); e=a+pd.offsets.MonthBegin(1)
            if (y,m)>=(2026,8):   # Sep 2026 alone broke the 2.5 GB cap on the first run of 499_ht_break: read these by 5 days, no change to the rule
                while a<e:
                    b=min(a+pd.Timedelta(days=5),e); yield str(a.date()),str(b.date()); a=b
            else: yield str(a.date()),str(e.date())
for lo,hi in month_chunks():
    X=pd.read_sql("SELECT market_id,event_name ev,market_type ty,market_time mt,sel,inplay,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type=ANY(%s) AND ltp>=1.01 AND ltp<1000 AND ts>=market_time-interval '20 minutes' AND ts<=market_time+interval '6 minutes' AND market_time>=%s AND market_time<%s",con,params=(TY,lo,hi))
    if X.empty: print(lo,"no rows",flush=True); continue
    X['tt']=secs(X.ts); X['off']=secs(X.mt); X=X.sort_values('tt',kind='stable').drop_duplicates(['market_id','sel','tt'])
    seen=set(); nm=0
    for (ev,ty,off),G_ in X.groupby(['ev','ty','off'],sort=False):
        ids=sorted(G_.market_id.unique())
        if len(ids)>1: C['second id']+=1
        mk=ids[0]
        if ' v ' not in ev: C['no H v A']+=1; continue
        if group(ev): C['women or youth']+=1; continue
        if mk not in RS: C['no official, '+ty]+=1; continue
        nm+=1; g0=G_[G_.market_id==mk]; legs={}
        for s,y in g0.groupby('sel',sort=False):
            pm=y[~y.inplay]; ip=y[y.inplay]
            legs[s]=(pm.tt.values,pm.ltp.values,ip.tt.values,ip.ltp.values)
        # roles by the last pre-off print, T-10 to the off
        last={}
        for s,(a,b,_,_) in legs.items():
            i=last_in(a,off-600,off+360)   # NOT inplay rows only, so a late off is not cut
            if i is not None: last[s]=float(b[i])
        if ty=='MATCH_ODDS':
            ru=[s for s in last if s!='The Draw']
            if len(ru)<2 or last[ru[0]]==last[ru[1]]: C['MO roles unknown']+=1; roles={}
            else:
                f=min(ru,key=lambda s:last[s]); o=max(ru,key=lambda s:last[s]); roles={f:'FAV',o:'OUT'}
                if 'The Draw' in last: roles['The Draw']='DRAW'
        else: roles={'Over 2.5 Goals':'OVER','Under 2.5 Goals':'UNDER'}
        for s,r in roles.items():
            if s not in legs or s not in RS[mk]: continue
            a,b,c,d=legs[s]; won=RS[mk][s]
            # item 294
            if s in last:
                i=first_in(c,off-300,off+180)
                if i is None: C['294 no in-play print']+=1
                else:
                    pre=last_in(a,off-600,float(c[i]))
                    if pre is None: C['294 no pre-off print']+=1
                    else:
                        jb=jump_band(float(b[pre]),float(d[i])); C['294 read']+=1
                        if jb: add(294,f"{r} {jb[0]} {jb[1]}",off,ev,fill(c,d,i,'L'),fill(c,d,i,'B'),won)
        # item 295. Roles from prints at T-2 or earlier: the first run read 294's roles, which could see a print after this entry
        l295={}
        for s,(a,b,_,_) in legs.items():
            i=last_in(a,off-1200,off-120)
            if i is not None: l295[s]=float(b[i])
        if ty=='MATCH_ODDS':
            ru=[s for s in l295 if s!='The Draw']
            if len(ru)<2 or l295[ru[0]]==l295[ru[1]]: C['295 MO roles unknown']+=1; r295={}
            else: r295={min(ru,key=lambda s:l295[s]):'FAV',max(ru,key=lambda s:l295[s]):'OUT'}
        else: r295={'Over 2.5 Goals':'OVER','Under 2.5 Goals':'UNDER'}
        for s,r in r295.items():
            if s not in legs or s not in RS[mk]: continue
            a,b,c,d=legs[s]; won=RS[mk][s]
            m=(a>=off-1200)&(a<=off-120)
            if m.sum()<2: C['295 under 2 prints']+=1; continue
            st=flow_state(b[m])
            if st is None: C['295 no state']+=1; continue
            i=last_in(a,off-300,off-120)
            if i is None: C['295 no entry print']+=1; continue
            C['295 read']+=1; L,B=fill(a,b,i,'L'),fill(a,b,i,'B')
            add(295,f"{r} {st} ALL",off,ev,L,B,won)
            if flat(b[m]): add(295,f"{r} {st} FLAT",off,ev,L,B,won)
    print(lo,"rows",len(X),"markets",nm,"cands",len(rows),f"{time.time()-T0:.0f}s",flush=True); del X
con.close()
print("counts",dict(sorted(C.items())),flush=True)
T=pd.DataFrame(rows,columns=['item','lab','side','off','ev','v']).dropna(subset=['v'])
T['v']=T.v.astype(float)
T=T.drop_duplicates(['item','lab','side','off','ev'])
med=T.off.median(); T['h']=np.where(T.off<=med,1,2); print("halves split at",pd.Timestamp(med,unit='s',tz='UTC'),"games",T[['off','ev']].drop_duplicates().shape[0],flush=True)
for it in (294,295):
    o=[]
    for (l,s),x in T[T['item']==it].groupby(['lab','side']):
        if len(x)<2: continue
        d=line(x.v.values,x.h.values); v=x.v.values; xl=np.delete(v,v.argmax()).mean()
        o.append(dict(line=f"{l} {s}",n=d['n'],per10=round(d['per10'],3),t=round(d['t'],2),h1=round(d['h1'],3),h2=round(d['h2'],3),n1=d['n1'],n2=d['n2'],no_top=round(xl,3),PASS=d['PASS']))
    O=pd.DataFrame(o).sort_values('t',ascending=False)
    print(f"ITEM {it}: lines {len(O)}"); print(O.head(15).to_string(index=False)); print("worst"); print(O.tail(4).to_string(index=False))
    print(f"SURVIVORS {it}"); S=O[O.PASS]; print(S.to_string(index=False) if len(S) else "none",flush=True)
PY
