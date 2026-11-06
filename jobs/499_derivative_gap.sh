#!/bin/bash
set -o pipefail
# 499_derivative_gap (Finder 2026-11-06, queue item 263, Finder's own, source c): Draw No Bet and Double Chance against the price Match Odds implies. Rule pushed in the queue before any price was read. Read only.
# ENTRY last non-in-play print T-20 to T-2 on all three MO runners and the derivative runner, each MO print within 600 s of the derivative print, MO book 0.98-1.08. Worse of the print and the next within 120 s, one tick adverse, 2%, £10 risk, to the official result. Never a forward fill: a print older than T-20 is no entry.
# VOID a drawn game voids DNB and leaves no result row (checked: all 18,889 result markets have one WINNER), so no row with MO's winner the Draw is a trade at £0. load_results keeps exactly one WINNER, so Double Chance (two winners) is read here directly.
# Prints only on thin books: a pass is an upper bound. Stale quotes have fooled this estate before (item 75), hence G10 kept apart and the taker's-fills diagnostic. A crossing back fills on a down-print, a crossing lay on an up-print.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_000_000_000,2_000_000_000))  # this job only
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,norm,jac,tstat
from lib_official import bk,ly,fill,last_in,secs,checks
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',240); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',200)
def mo_pair(home,away,runners):
    """As jobs/499_oct24_lines.sh: (home runner, away runner) by name, None if unsure."""
    r=[x for x in runners if str(x).strip().lower()!='the draw']
    if len(r)!=2: return None
    H,A,a,b=norm(home),norm(away),norm(r[0]),norm(r[1])
    s1,s2=jac(a,H)+jac(b,A),jac(a,A)+jac(b,H)
    if s1==s2: return None
    x,y=(r[0],r[1]) if s1>s2 else (r[1],r[0])
    if not (norm(x)&H and norm(y)&A): return None
    return x,y
def fair(h,d,a):
    """Normalised MO probabilities from prices -> dict of fair probabilities; None outside book 0.98-1.08."""
    b=1/h+1/d+1/a
    if not 0.98<=b<=1.08: return None
    H,D,A=(1/h)/b,(1/d)/b,(1/a)/b
    return dict(DNB_H=H/(H+A),DNB_A=A/(H+A),HD=H+D,DA=D+A,HA=H+A)
def band(g):
    x=abs(g)
    if x<0.01: return 'NEAR'
    if 0.02<=x<0.04: return 'G2'
    if 0.04<=x<0.10: return 'G4'
    if x>=0.10: return 'G10'
    return None
# known answers, worked by hand. H 2.0, D 4.0, A 4.0: book 1.0, 0.5/0.25/0.25. DNB home 2/3, HD 0.75, DA 0.5, HA 0.75. DNB home at 1.6: 0.6667-0.625=+0.0417, G4, cheap.
_f=fair(2.0,4.0,4.0); assert abs(_f['DNB_H']-2/3)<1e-9 and abs(_f['HD']-.75)<1e-9 and abs(_f['DA']-.5)<1e-9 and abs(_f['HA']-.75)<1e-9
assert fair(1.5,3.0,4.0) is None and fair(2.2,4.4,4.4) is None   # books 1.25 and 0.909
assert band(_f['DNB_H']-1/1.6)=='G4' and band(0.03)=='G2' and band(-0.03)=='G2' and band(0.015) is None and band(0.005)=='NEAR' and band(0.1)=='G10' and band(0.04)=='G4'
assert mo_pair('Leeds','Hull',['Hull','Leeds','The Draw'])==('Leeds','Hull') and mo_pair('Leeds','Hull',['Hull','The Draw']) is None
assert secs(pd.Series(pd.to_datetime(['2026-01-01 00:00:00+00:00']))).iloc[0]==1767225600.0
print("checks: OK",flush=True); T0=time.time()
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
TY={'MATCH_ODDS':'MO','DRAW_NO_BET':'DNB','DOUBLE_CHANCE':'DC'}
R=pd.read_sql("SELECT market_id,sel,status FROM bf_hist_result WHERE sport='Soccer' AND market_type=ANY(%s)",con,params=(list(TY),))
RS={m:dict(zip(g.sel,g.status)) for m,g in R.groupby('market_id')}; del R; print(f"result markets {len(RS):,}, {time.time()-T0:.0f}s",flush=True)
cur.execute("SELECT DISTINCT market_id,event_id,event_name,market_type,market_time FROM bf_hist_other WHERE sport='Soccer' AND market_type=ANY(%s) AND market_time>='2024-03-01' AND market_time<'2026-10-01'",(list(TY),))
MK=pd.DataFrame(cur.fetchall(),columns='market_id event_id ev mty mt'.split()); MK['off']=secs(MK.mt); MK=MK.sort_values('market_id').drop_duplicates(['event_id','mty']).drop_duplicates(['ev','mt','mty'])
MO=MK[(MK.mty=='MATCH_ODDS')&MK.market_id.isin(RS)]; evs=list(MO.event_id); MKE={e:g for e,g in MK[MK.event_id.isin(evs)].groupby('event_id')}
print(f"MO games with a result {len(evs):,}; by month {MO.groupby(pd.to_datetime(MO.mt,utc=True).dt.strftime('%Y-%m')).size().to_dict()}",flush=True)
SK=Counter(); rows=[]
def ent(x,o):
    out={}
    for s,y in x.groupby('sel',sort=False):
        ts,px=y.tt.values,y.ltp.values; i=last_in(ts,o-1200,o-120)
        if i is not None: out[s]=(ts,px,i)
    return out
for c0 in range(0,len(evs),2000):
    ch=evs[c0:c0+2000]; ms=[m for e in ch for m in MKE[e].market_id]
    P=pd.read_sql("SELECT market_id,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s) AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND ts>=market_time-interval '60 minutes'",con,params=(ms,))
    P['tt']=secs(P.ts); P=P.drop_duplicates(['market_id','sel','tt']).sort_values('tt',kind='stable'); PX={k:g for k,g in P.groupby('market_id')}; del P
    for e in ch:
        g=MKE[e]; a=g[g.mty=='MATCH_ODDS'].iloc[0]; o=float(a.off); xm=PX.get(a.market_id)
        if xm is None: SK['no MO print']+=1; continue
        em=ent(xm,o); home,_x,away=str(a.ev).partition(' v ')
        dr=[s for s in em if str(s).strip().lower()=='the draw']; pr=mo_pair(home,away,list(em))
        if len(em)!=3 or len(dr)!=1 or pr is None: SK['MO not three named prints']+=1; continue
        hn,an=pr; ph,pd_,pa=[float(em[s][1][em[s][2]]) for s in (hn,dr[0],an)]
        f=fair(ph,pd_,pa)
        if f is None: SK['MO book outside 0.98-1.08']+=1; continue
        tm=[em[s][0][em[s][2]] for s in (hn,dr[0],an)]; rm=RS[a.market_id]; drawn=rm.get(dr[0])=='WINNER'
        for mty,lab in (('DRAW_NO_BET','DNB'),('DOUBLE_CHANCE','DC')):
            b=g[g.mty==mty]
            if not len(b): SK[lab+' no market']+=1; continue
            b=b.iloc[0]; xd=PX.get(b.market_id)
            if xd is None: SK[lab+' no print']+=1; continue
            ed=ent(xd,o)
            if lab=='DNB': mp={hn:f['DNB_H'],an:f['DNB_A']}
            else: mp={'Home or Draw':f['HD'],'Draw or Away':f['DA'],'Home or Away':f['HA']}
            cand=[]
            for s,(ts,px,i) in ed.items():
                if s not in mp: SK[lab+' runner not mapped']+=1; continue
                if max(abs(ts[i]-t) for t in tm)>600: SK[lab+' MO print over 600 s away']+=1; continue
                gp=mp[s]-1/float(px[i]); cand.append((abs(gp),gp,s,ts,px,i))
            if not cand: continue
            for sign,kind in ((1,'CHEAP'),(-1,'DEAR')):
                c=[z for z in cand if z[1]*sign>0]
                if not c: continue
                _,gp,s,ts,px,i=max(c,key=lambda z:z[0]); bd=band(gp)
                if bd is None: continue
                st=RS.get(b.market_id,{}).get(s)
                if st is None:
                    if lab=='DNB' and drawn: won=None
                    else: SK[lab+' no result, game not drawn']+=1; continue
                elif st not in ('WINNER','LOSER'): SK[lab+' other status']+=1; continue
                else: won=st=='WINNER'
                pb,pl=fill(ts,px,i,'B'),fill(ts,px,i,'L')
                vb=0.0 if won is None else bk(pb,won); vl=0.0 if won is None else ly(pl,won)
                dn=bool(i>0 and px[i]<px[i-1]); up=bool(i>0 and px[i]>px[i-1])
                rows.append((lab,bd,kind,e,o,won,vb,vl,dn,up))
    del PX; print(f"  chunk {c0:,}/{len(evs):,} {time.time()-T0:.0f}s",flush=True)
con.close(); print("counted:",dict(sorted(SK.items())),flush=True)
A=pd.DataFrame(rows,columns='mk bd kind e off won vb vl dn up'.split()); assert len(A)
MD=A.drop_duplicates('e').off.median(); print(f"halves split at {pd.Timestamp(MD,unit='s',tz='UTC')}; voids at £0 {int(A.won.isna().sum())}")
def score(nm,x,side,taker=False):
    if taker: x=x[x.dn] if side=='B' else x[x.up]
    v=(x.vb if side=='B' else x.vl); x=x[v.notna()]; v=v.dropna().values.astype(float)
    if not len(v): return None
    l=line(v,np.where(x.off.values<MD,1,2)); ws=x.won.dropna().astype(float)
    return dict(line=nm,side=side,n=l['n'],games=x.e.nunique(),per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],won=ws.mean(),maxwin=l['maxwin'],PASS=l['PASS'])
sc,ctx=[],[]
for (m,b,k),x in A.groupby(['mk','bd','kind']):
    right='B' if k=='CHEAP' else 'L'; wrong='L' if k=='CHEAP' else 'B'
    if b in ('G2','G4'):
        sc.append(score(f"263 {m} {b} {k}",x,right)); ctx.append(score(f"swap {m} {b} {k}",x,wrong)); ctx.append(score(f"taker {m} {b} {k}",x,right,True))
    else:
        ctx.append(score(f"ctx {m} {b} {k}",x,right)); ctx.append(score(f"ctx {m} {b} {k}",x,wrong))
O=pd.DataFrame([z for z in sc if z]); Q=pd.DataFrame([z for z in ctx if z]).drop(columns='PASS')
print(f"\n== item 263, {len(O)} scored lines"); print(O.sort_values('t',ascending=False).round(3).to_string(index=False))
print("\ncontext, cannot pass"); print(Q.sort_values('line').round(3).to_string(index=False))
S=O[O.PASS]; print(f"\n== SURVIVORS: {len(S)} of {len(O)}"); print(S.round(3).to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
