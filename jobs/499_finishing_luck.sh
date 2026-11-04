#!/bin/bash
set -o pipefail
# 499_finishing_luck (Finder 2026-11-04, queue item 76, Finder's own, source d): is recent finishing luck priced? Rule written in the queue before any price was read. The number 499 is reused with a new slug: 450-499 are all taken.
# DATA fd_matches 2019-20 to 2026-27: goals, shots on target, closing odds. Price: BFEC if the file has it, else Pinnacle close, else Bet365 close, as jobs/499_season_goal_persist.sh.
# SIGNAL, known before kick-off: over a team's last N (5, 10) league games that season, with dates strictly before the game: F = goals for - c x SOT for, A = goals against - c x SOT against, per game; c = goals per SOT in that division-season on dates strictly before the game, at least 50 games. Luck L = F - A; goal-line G = F + A.
# MATCH ODDS: S = L home - L away. |S| >= 0.4/0.7/1.0: BACK the unlucky team, LAY the lucky team; FADE lines back the lucky team, as a control.
# GOAL LINE: both teams' G < 0 and mean <= -cut: goals are due, BACK Over, LAY Under; both > 0 and mean >= cut: BACK Under, LAY Over. Cuts 0.3/0.5/0.8.
# FILL close +/- 1 tick, 2% commission, £10 risk, held to FT, one bet per game per line. Halves 2019-22 v 2022-25; 2025-26 and 2026-27 shown alone as the later read. Close is a proxy and a Pinnacle price cannot be laid, so A PASS IS AN UPPER BOUND ON A PROXY; the exchange-close seasons are also shown alone.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import defaultdict,deque
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import *
import lib_cand; lib_cand._checks()
pd.set_option('display.width',260); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',40)
T0=time.time()
def num(x):
    try: v=float(x)
    except (TypeError,ValueError): return np.nan
    return v if 1<v<=1000 else np.nan
def signals(games,N,min_c=50):
    """games: dicts date,home,away,hg,ag,hst,ast of ONE division-season. Returns {index: (Lh,La,Gh,Ga)} using only dates strictly before each game's date."""
    order=sorted(range(len(games)),key=lambda i:games[i]['date']); hist=defaultdict(lambda:deque(maxlen=N)); tg=ts=np.int64(0); nc=0; out={}; i=0
    while i<len(order):
        j=i; d=games[order[i]]['date']
        while j<len(order) and games[order[j]]['date']==d: j+=1
        day=order[i:j]
        if nc>=min_c and ts>0:
            c=tg/ts
            for k in day:
                x=games[k]; h,a=hist[x['home']],hist[x['away']]
                if len(h)==N and len(a)==N:
                    fh=np.mean([q[0]-c*q[1] for q in h]); ah=np.mean([q[2]-c*q[3] for q in h]); fa=np.mean([q[0]-c*q[1] for q in a]); aa=np.mean([q[2]-c*q[3] for q in a])
                    out[k]=(fh-ah,fa-aa,fh+ah,fa+aa)
        for k in day:
            x=games[k]
            if x['hst'] is None or x['ast'] is None or x['hst']!=x['hst'] or x['ast']!=x['ast']: continue
            hist[x['home']].append((x['hg'],x['hst'],x['ag'],x['ast'])); hist[x['away']].append((x['ag'],x['ast'],x['hg'],x['hst']))
            tg+=x['hg']+x['ag']; ts+=x['hst']+x['ast']; nc+=1
        i=j
    return out
def mo_side(Lh,La,cut):
    S=Lh-La
    if abs(S)<cut: return None
    return ('H','A') if S<0 else ('A','H')   # (unlucky, lucky)
def ou_side(Gh,Ga,cut):
    m=(Gh+Ga)/2
    if Gh<0 and Ga<0 and m<=-cut: return 'OVER'
    if Gh>0 and Ga>0 and m>=cut: return 'UNDER'
    return None
def bk(x,won):
    a=step(x,-1); return None if a<=1.01 else back_settle(a,won)
def ly(x,won): return lay_settle(step(x,1),won)
# known answers. Mini league A,B: 2 games then a third. N=2, min_c=2. Game 1 A 2-0 B, SOT 4,2. Game 2 B 0-1 A, SOT 2,4. Total goals 3, SOT 12, c=.25.
_g=[dict(date=1,home='A',away='B',hg=2,ag=0,hst=4,ast=2),dict(date=2,home='B',away='A',hg=0,ag=1,hst=2,ast=4),dict(date=3,home='A',away='B',hg=9,ag=9,hst=1,ast=1)]
_s=signals(_g,2,2)
# A: for (2-.25*4)=1, (1-.25*4)=0, mean F .5; against (0-.25*2)=-.5 twice, mean A -.5; L=1.0, G=0. B is the mirror: F -.5, A .5, L -1.0, G 0.
assert list(_s)==[2] and abs(_s[2][0]-1.0)<1e-9 and abs(_s[2][1]+1.0)<1e-9 and abs(_s[2][2])<1e-9 and abs(_s[2][3])<1e-9
# no look-ahead: changing the game's own result, or a same-date game, changes nothing
_g2=[dict(x) for x in _g]; _g2[2]['hg']=0; _g2[2]['hst']=30; assert signals(_g2,2,2)==_s
_g3=[dict(x) for x in _g]+[dict(date=3,home='A',away='B',hg=7,ag=0,hst=9,ast=0)]; assert signals(_g3,2,2)[2]==_s[2]
assert mo_side(1.0,-1.0,.7)==('A','H') and mo_side(-1.0,1.0,.7)==('H','A') and mo_side(.2,.0,.4) is None and mo_side(.4,0.,.4)==('A','H')
assert ou_side(-.5,-.5,.5)=='OVER' and ou_side(.5,.5,.5)=='UNDER' and ou_side(-1.,.2,.3) is None and ou_side(-.2,-.2,.3) is None
assert abs(bk(2.04,True)-9.996)<1e-9 and bk(2.04,False)==-10.0 and abs(ly(2.0,False)-10/1.02*.98)<1e-9 and ly(2.0,True)==-10.0 and bk(1.02,True) is None
print("checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='600s'")
D=pd.read_sql("SELECT div,season,date,home,away,fthg,ftag,hst,ast,raw FROM fd_matches WHERE fthg IS NOT NULL AND season>='1920' AND season<'9000'",con); con.close()
D['dt']=pd.to_datetime(D.date); print(f"games {len(D)}, shots present {D.hst.notna().mean():.3f}",flush=True)
def mo_px(r):
    for src,k in (('BFEC','BFEC'),('PSC','PSC'),('B365C','B365C')):
        v=[num(r.get(k+s)) for s in 'HDA']
        if not np.isnan(v).any(): return dict(H=v[0],D=v[1],A=v[2]),src
    return None,None
def ou_px(r):
    for src,a,b in (('BFEC','BFEC<2.5','BFEC>2.5'),('PC','PC<2.5','PC>2.5'),('B365C','B365C<2.5','B365C>2.5')):
        u,o=num(r.get(a)),num(r.get(b))
        if u==u and o==o: return dict(UNDER=u,OVER=o),src
    return None,None
rows=[]; ngames=0
for (dv,s),g in D.groupby(['div','season']):
    g=g.reset_index(drop=True); games=[dict(date=x.dt,home=x.home,away=x.away,hg=int(x.fthg),ag=int(x.ftag),hst=x.hst,ast=x.ast) for x in g.itertuples()]
    for N in (5,10):
        sig=signals(games,N)
        for k,(Lh,La,Gh,Ga) in sig.items():
            x=g.iloc[k]; res='H' if x.fthg>x.ftag else 'A' if x.ftag>x.fthg else 'D'; over=x.fthg+x.ftag>2.5; ngames+=1
            mp,ms=mo_px(x.raw); op,os_=ou_px(x.raw)
            if mp:
                for cut in (.4,.7,1.0):
                    sd=mo_side(Lh,La,cut)
                    if sd:
                        u,l=sd
                        for lab,v in (('BACK_UNLUCKY',bk(mp[u],res==u)),('LAY_LUCKY',ly(mp[l],res==l)),('FADE_BACK_LUCKY',bk(mp[l],res==l))):
                            if v is not None: rows.append(('MO',N,cut,lab,dv,s,ms,x['dt'],mp[u] if lab=='BACK_UNLUCKY' else mp[l],v))
            if op:
                for cut in (.3,.5,.8):
                    w=ou_side(Gh,Ga,cut)
                    if w:
                        wo=(w=='OVER')==over; other='UNDER' if w=='OVER' else 'OVER'
                        for lab,v in (('BACK_'+w,bk(op[w],wo)),('LAY_'+other,ly(op[other],not wo)),('FADE_BACK_'+other,bk(op[other],not wo))):
                            if v is not None: rows.append(('OU',N,cut,lab,dv,s,os_,x['dt'],op[w] if lab.startswith('BACK') else op[other],v))
print(f"signal rows {ngames}, trades {len(rows)} {time.time()-T0:.0f}s",flush=True)
R=pd.DataFrame(rows,columns=['mkt','N','cut','line','div','season','src','dt','x','v'])
H1={'1920','2021','2122'}; H2={'2223','2324','2425'}
o=[]
for k,x in R.groupby(['mkt','N','cut','line']):
    a=x[x.season.isin(H1|H2)]; h=np.where(a.season.isin(H1),1,2); l=line(a.v.values,h); y=x[x.season=='2526']; z=x[x.season=='2627']; b=x[x.src=='BFEC']
    ls=a.groupby(['div','season']).v.mean()
    o.append(dict(zip(['mkt','N','cut','line'],k),n=l['n'],per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],n2526=len(y),p2526=y.v.mean(),n2627=len(z),p2627=z.v.mean(),nBFEC=len(b),pBFEC=b.v.mean(),tBFEC=tstat(b.v.values),t_ls=tstat(ls.values),PASS=l['PASS']))
O=pd.DataFrame(o); print(f"\n== lines {len(O)}; every line"); print(O.drop(columns=['n1','n2']).sort_values(['mkt','line','N','cut']).round(3).to_string(index=False))
print("\n== TOP 15 by t"); print(O.sort_values('t',ascending=False).head(15).drop(columns=['n1','n2']).round(3).to_string(index=False))
print("\n== SURVIVORS (bar: n>=300, n>=150 per half, both halves > 0, t>=3.5, mean>=+0.15, proxy upper bound; read beside p2526, p2627, pBFEC)"); S=O[O.PASS]; print(S.drop(columns=['n1','n2']).round(3).to_string(index=False) if len(S) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
