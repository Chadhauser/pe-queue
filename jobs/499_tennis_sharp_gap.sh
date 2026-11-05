#!/bin/bash
set -o pipefail
# 499_tennis_sharp_gap (Finder 2026-11-05, queue item 133, Finder's own, source b, Trademate-style, football was item 75): the exchange's last pre-off print against the de-vigged Pinnacle close, ATP. Rule written in the queue before any price was read. The number 499 is reused with a new slug: 450-499 are all taken.
# TAPE bf_hist_other Tennis singles MATCH_ODDS, local. RESULTS tennis_matches, Railway, the one history table not local, read-only, ATP only. Match on both players, surname and first initial, market date -1 to +3 days of the listed date, unique or dropped, counted.
# ENTRY last non-in-play print of that runner in the 60 minutes before the market's first in-play print; none = no trade, counted. Prints only, no book. One tick adverse, 2%, £10 risk, hold to result.
# VOID both sets columns 0 means no completed set is recorded: treated as void and excluded, counted. A retirement after a completed set stands, as Betfair's tennis rule was recalled, not checked here.
# LOOK-AHEAD the close is later than or equal to the print, which flatters the test: a pass here only earns a forward test. Halves by median date.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,re,time,unicodedata,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,back_settle,lay_settle,tstat,line
import lib_cand; lib_cand._checks()
pd.set_option('display.width',230); pd.set_option('display.max_rows',80); pd.set_option('display.max_columns',30)
T0=time.time()
def bk(x,won):
    a=step(x,-1); return None if a<=1.01 else back_settle(a,won)
def ly(x,won): return lay_settle(step(x,1),won)
def fold(s): return re.sub(r"[^a-z]","",unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower())
def key_td(s):
    """tennis-data form 'Davidovich Fokina A.' to ('davidovichfokina','a'). Hyphenated first initials use the first letter."""
    p=str(s).strip().split()
    return (fold(' '.join(p[:-1])),fold(p[-1])[:1]) if len(p)>=2 else (fold(s),'')
def key_bf(s):
    """Betfair form 'Alejandro Davidovich Fokina' to ('davidovichfokina','a')."""
    p=str(s).strip().split()
    return (fold(' '.join(p[1:])),fold(p[0])[:1]) if len(p)>=2 else (fold(s),'')
def fair_px(pa,pb):
    """De-vigged fair price of runner a from closes pa, pb, by proportion."""
    return ((1/pa)+(1/pb))/(1/pa)
assert key_td('Davidovich Fokina A.')==('davidovichfokina','a') and key_td('Machac T.')==('machac','t') and key_td('Auger-Aliassime F.')==('augeraliassime','f')
assert key_bf('Alejandro Davidovich Fokina')==('davidovichfokina','a') and key_bf('Tomas Machac')==('machac','t') and key_bf('Felix Auger-Aliassime')==('augeraliassime','f')
assert abs(fair_px(2.0,2.0)-2.0)<1e-9 and abs(fair_px(1.5,3.0)-1.5)<1e-9 and abs(fair_px(1.55,2.63)-(1/1.55+1/2.63)/(1/1.55))<1e-9
assert abs(bk(2.04,True)-9.996)<1e-9 and bk(2.04,False)==-10.0 and ly(2.0,True)==-10.0 and abs(ly(2.0,False)-10/1.02*.98)<1e-9
print("checks: OK",flush=True)
rc=psycopg2.connect(creds.pg_railway(),sslmode='require')
TM=pd.read_sql("SELECT date,tournament,round,winner,loser,psw::float8 psw,psl::float8 psl,wsets,lsets FROM tennis_matches WHERE psw>1 AND psl>1 AND date>='2024-08-25' AND date<='2026-04-05'",rc); rc.close()
TM['d']=pd.to_datetime(TM.date); SK=Counter(); ix=defaultdict(list)
for r in TM.itertuples():
    ix[frozenset((key_td(r.winner),key_td(r.loser)))].append(r)
print(f"results with Pinnacle closes {len(TM)}, {TM.d.min():%Y-%m-%d} to {TM.d.max():%Y-%m-%d}, {time.time()-T0:.0f}s",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
# event names are abbreviated on this tape ('Et Quinn v Spizzirri'), so the match is read from the two runner names
cur.execute("SELECT market_id,min(event_name),min(market_time),array_agg(DISTINCT sel) FROM bf_hist_other WHERE sport='Tennis' AND market_type='MATCH_ODDS' AND event_name LIKE '%% v %%' AND event_name NOT LIKE '%%/%%' AND market_time>='2024-08-31' AND market_time<'2026-04-01' GROUP BY 1")
ALLM=cur.fetchall(); print(f"singles MATCH_ODDS markets {len(ALLM)}",flush=True)
HIT={}
for mid,en,mt,sels in ALLM:
    if len(sels)!=2: SK['not two runners on the tape']+=1; continue
    c=ix.get(frozenset((key_bf(sels[0]),key_bf(sels[1]))))
    if not c: SK['no result, mostly WTA, Challenger or name form']+=1; continue
    t=pd.Timestamp(mt).tz_localize(None) if pd.Timestamp(mt).tzinfo is None else pd.Timestamp(mt).tz_convert(None)
    near=[r for r in c if -1<=(t.normalize()-r.d).days<=3]
    if len(near)!=1: SK['no unique result in the date window']+=1; continue
    HIT[mid]=(near[0],en,t)
print(f"matched {len(HIT)}; {dict(SK)}",flush=True); SK=Counter(); rows=[]; ids=list(HIT)
for i in range(0,len(ids),1000):
    P=pd.read_sql("SELECT market_id,sel,ts,inplay,ltp::float ltp FROM bf_hist_other WHERE sport='Tennis' AND market_type='MATCH_ODDS' AND market_id=ANY(%s) AND ltp>=1.01 AND ltp<1000",con,params=(ids[i:i+1000],))
    for mid,x in P.groupby('market_id'):
        ip=x[x.inplay==True]
        if ip.empty: SK['no in-play print']+=1; continue
        t0=ip.ts.min(); pre=x[(x.inplay==False)&(x.ts<t0)&(x.ts>=t0-pd.Timedelta(minutes=60))]
        r,en,t=HIT[mid]
        if r.wsets==0 and r.lsets==0: SK['void, no completed set']+=1; continue
        if pre.empty: SK['no print in the 60 min']+=1; continue
        wk,lk=key_td(r.winner),key_td(r.loser)
        last=pre.sort_values('ts').groupby('sel').ltp.last()
        for sel,px in last.items():
            k=key_bf(sel)
            if k==wk: won,pm,po=True,r.psw,r.psl
            elif k==lk: won,pm,po=False,r.psl,r.psw
            else: SK['runner name differs']+=1; continue
            fp=fair_px(pm,po); pos='FAV' if pm<po else 'DOG' if pm>po else None; h=t
            for cut in (1.03,1.05,1.08):
                if px>=fp*cut:
                    v=bk(px,won)
                    if v is not None:
                        for ps in ['ALL']+([pos] if pos else []): rows.append(('BACK',cut,ps,mid,t,px,won,1/fp,v))
                if px<=fp/cut:
                    for ps in ['ALL']+([pos] if pos else []): rows.append(('LAY',cut,ps,mid,t,px,won,1/fp,ly(px,won)))
            for ps in ['ALL']+([pos] if pos else []):
                v=bk(px,won)
                if v is not None: rows.append(('BACK',0,ps,mid,t,px,won,1/fp,v))
                rows.append(('LAY',0,ps,mid,t,px,won,1/fp,ly(px,won)))
    print(f"  {i+1000} of {len(ids)}, {time.time()-T0:.0f}s",flush=True)
con.close(); print("counts:",dict(SK),flush=True)
R=pd.DataFrame(rows,columns=['side','cut','pos','mid','t','x','won','fair','v'])
md=R[R.cut==0].t.median(); R['h']=np.where(R.t<md,1,2); out=[]
for k,x in R.groupby(['side','cut','pos']):
    l=line(x.v.values,x.h.values); out.append(dict(side=k[0],cut=k[1],pos=k[2],n=l['n'],games=x.mid.nunique(),per10=l['per10'],t=l['t'],t_game=tstat(x.groupby('mid').v.sum().values),n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],won=x.won.mean(),imp=(1/x.x).mean(),fair=x.fair.mean(),PASS=l['PASS']))
O=pd.DataFrame(out); C=O[O.cut==0]; L=O[O.cut>0].sort_values('t',ascending=False)
print("\n== control, every runner, not counted as a line"); print(C.drop(columns=['n1','n2','PASS']).round(3).to_string(index=False))
print(f"\n== lines {len(L)}, n>=300 {int((L.n>=300).sum())}. All by t"); print(L.drop(columns=['n1','n2']).round(3).to_string(index=False))
S=L[L.PASS]; print(f"\n== SURVIVORS: {len(S)} of {len(L)}. The close is later than the print, so a pass only earns a forward test\n",S.round(3).to_string(index=False) if len(S) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
