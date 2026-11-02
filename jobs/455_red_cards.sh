#!/bin/bash
set -o pipefail
# 455 (Finder 2026-11-02, queue item 6): RED CARDS AS A STATE. bf_hist_price (1-min LTP) + af_events (type Card; 'Red Card' and
# 'Second Yellow card' both = sent off, split reported) via af_price_map. FIRST sending-off of each game only (one entry per game per trade).
# Decision at the first real print in card+2..card+4 for that selection; FILL at the worse of the decision print and the next real print
# within 2 minutes, one tick adverse (same pnl() as 452, asserted). Trades: BACK the 11-man side (MO), LAY the 10-man side (MO), BACK Over 2.5.
# Exits: +10 / +20 minutes after the decision (first real print at/after that minute, ANY later minute to 95) or SETTLE at the result.
# Over 2.5: if the 3rd goal comes before the exit print the market has SETTLED -> settled as a win, never dropped; a game already on
# 3+ goals at the card is not traded for Over. No print to 95 -> settled at result. Back stake £10 / lay liability £10, 2% commission.
# Splits: card minute (<30, 30-60, 60+), score state at the card from the 10-man side's view, league, card type. Halves = season 2024 vs 2025.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
def tick(p): return 0.01 if p<2 else 0.02 if p<3 else 0.05 if p<4 else 0.1 if p<6 else 0.2 if p<10 else 0.5 if p<20 else 1 if p<30 else 2 if p<50 else 5 if p<100 else 10
def pnl(side,p,q,won):
    if side=='B':
        p=p-tick(p)
        if p<=1.01: return None
        if q is None: r=10*(p-1) if won else -10.0
        else: q=q+tick(q); r=10*(p/q-1)
    else:
        p=p+tick(p); s=10/(p-1)
        if q is None: r=s if not won else -10.0
        else: q=max(1.01,q-tick(q)); r=s*(1-p/q)
    return r*0.98 if r>0 else r
assert abs(pnl('B',2.0,None,True)-9.604)<1e-9 and abs(pnl('L',6.0,None,False)-10/5.2*0.98)<1e-9
assert abs(pnl('L',6.0,3.0,False)-(10/5.2)*(1-6.2/2.95))<1e-9 and abs(pnl('B',1.5,1.3,False)-10*(1.49/1.31-1)*0.98)<1e-9 and pnl('L',2.0,None,True)==-10.0
assert pnl('B',1.01,None,True) is None and abs(pnl('B',3.0,None,False)+10)<1e-9
print("P&L unit checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor(); cur.execute("SET statement_timeout='3000s'")
G=pd.read_sql("""SELECT m.event_id, f.fixture_id, f.season, f.league, f.hg, f.ag FROM af_price_map m
 JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL""",con)
ids=list(map(int,G.fixture_id))
print("games:",len(G),"| seasons:",G.season.value_counts().to_dict(),flush=True)
C=pd.read_sql("SELECT detail, count(*) n FROM af_events WHERE fixture_id=ANY(%s) AND type='Card' GROUP BY 1",con,params=(ids,))
print("card details:",dict(zip(C.detail,C.n)))
RC=pd.read_sql("""SELECT fixture_id, coalesce(minute,0) AS minute, is_home, detail FROM af_events WHERE fixture_id=ANY(%s) AND type='Card'
 AND detail IN ('Red Card','Second Yellow card','Second Yellow Card')""",con,params=(ids,))
RC=RC.sort_values(['fixture_id','minute']); n_all=len(RC); RC=RC.groupby('fixture_id').head(1)
print("sendings-off:",n_all,"| games with one:",len(RC),flush=True)
EV=pd.read_sql("""SELECT fixture_id, coalesce(minute,0) AS minute, is_home, detail FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal'
 AND detail IN ('Normal Goal','Penalty','Own Goal')""",con,params=(list(map(int,RC.fixture_id)),))
goals=defaultdict(list)
for r in EV.itertuples():
    side=('h' if r.is_home else 'a') if r.detail!='Own Goal' else ('a' if r.is_home else 'h')
    goals[r.fixture_id].append((int(r.minute),side))
for k in goals: goals[k].sort()
def score(gl,m): return (sum(1 for g,s in gl if g<=m and s=='h'), sum(1 for g,s in gl if g<=m and s=='a'))
def rp(arr,a,b):
    for mm in range(max(0,a),min(b,96)+1):
        if not np.isnan(arr[mm]): return mm
    return None
G=G.merge(RC,on='fixture_id')
T=[]; SK=defaultdict(int); DESC=[]
P=pd.read_sql("SELECT event_id, minute, mkt, sel, ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND ((mkt='MO' AND sel IN ('HOME','AWAY')) OR (mkt='OU25' AND sel='OVER')) AND minute BETWEEN 0 AND 95 AND ltp>=1.01 AND ltp<1000",con,params=(list(G.event_id),))
px={}
for (eid,mkt,sel),gg in P.groupby(['event_id','mkt','sel'],sort=False):
    arr=np.full(97,np.nan); arr[gg.minute.values]=gg.ltp.values; px.setdefault(eid,{})[(mkt,sel)]=arr
for g in G.itertuples():
    b=px.get(g.event_id); c=int(g.minute)
    if not b or ('MO','HOME') not in b or ('MO','AWAY') not in b: SK['no MO prices']+=1; continue
    if c>85: SK['card after 85 (no room)']+=1; continue
    gl=goals.get(g.fixture_id,[]); hg,ag=int(g.hg),int(g.ag)
    ten='h' if g.is_home else 'a'
    sh,sa=score(gl,c); diff=(sh-sa) if ten=='h' else (sa-sh)
    state='10man level' if diff==0 else '10man ahead' if diff>0 else '10man behind'
    mb='<30' if c<30 else '30-60' if c<60 else '60+'
    H,A=b[('MO','HOME')],b[('MO','AWAY')]; TEN,ELE=(H,A) if ten=='h' else (A,H)
    ten_won=(hg>ag) if ten=='h' else (ag>hg); ele_won=(ag>hg) if ten=='h' else (hg>ag)
    O=b.get(('OU25','OVER'))
    legs=[('back 11-man','B',ELE,ele_won,False),('lay 10-man','L',TEN,ten_won,False)]
    if O is not None and sh+sa<3: legs.append(('back Over2.5','B',O,hg+ag>=3,True))
    for name,side,arr,won,isou in legs:
        d=rp(arr,c+2,c+4)
        if d is None: SK[name+': no print card+2..+4']+=1; continue
        n1=rp(arr,d+1,d+2)
        p=arr[d] if n1 is None else (min(arr[d],arr[n1]) if side=='B' else max(arr[d],arr[n1]))
        if isou and sum(score(gl,d))>=3: SK[name+': 3rd goal before fill']+=1; continue
        dd=dict(name=name,minute=c,p_d=arr[d])
        for ex in ('+10','+20','settle'):
            if ex=='settle': q=None
            else:
                tx=d+int(ex)
                if isou and sum(score(gl,tx))>=3: q=None; SK[name+' '+ex+': OU settled before exit -> result']+=1
                else:
                    e=rp(arr,tx,95); q=None if e is None else arr[e]
                    if e is None: SK[name+' '+ex+': no print to 95 -> result']+=1
                    dd['p'+ex]=q
            r=pnl(side,p,q,won)
            if r is None: SK[name+' unfillable']+=1; continue
            T.append(dict(trade=name,exit=ex,fixture_id=g.fixture_id,season=int(g.season),league=g.league,mband=mb,state=state,card=g.detail,px=p,pnl=r,won=bool(won)))
        DESC.append(dd)
R=pd.DataFrame(T); D=pd.DataFrame(DESC)
print("skips (counted, not hidden):",dict(SK))
print("\n== price paths (median LTP): decision print card+2..4, +10, +20; and hit rate at settle")
print(D.groupby('name')[['p_d','p+10','p+20']].median().round(2).to_string())
print(R[R.exit=='settle'].groupby('trade').won.mean().round(3).rename('selection_won').to_string())
def tstat(x): return x.mean()/(x.std(ddof=1)/len(x)**0.5) if len(x)>1 and x.std(ddof=1)>0 else 0.0
rows=[]
for dims in (['trade','exit'],['trade','exit','mband'],['trade','exit','state'],['trade','exit','mband','state'],['trade','exit','league'],['trade','exit','card']):
    for k,gg in R.groupby(dims):
        k=k if isinstance(k,tuple) else (k,)
        a=gg[gg.season==2024].pnl; c2=gg[gg.season==2025].pnl
        rows.append(dict(dim='+'.join(dims[2:]) or 'all',line=' / '.join(map(str,k)),n=len(gg),games=gg.fixture_id.nunique(),per10=gg.pnl.mean(),t=tstat(gg.pnl),
             n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(c2),h2=c2.mean() if len(c2) else np.nan,hit=gg.won.mean(),avg_px=gg.px.mean()))
S=pd.DataFrame(rows).round(3)
S['PASS']=(S.n>=300)&(S.n1>=150)&(S.n2>=150)&(S.t>=3.5)&(S.h1>0)&(S.h2>0)&(S.per10>=0.15)
pd.set_option('display.width',220); pd.set_option('display.max_rows',300)
print("\n== headline (per £10; h1 = 2024, h2 = 2025; hit = selection won)"); print(S[S.dim=='all'].to_string(index=False))
print("\n== by minute band"); print(S[S.dim=='mband'].to_string(index=False))
print("\n== by score state at the card"); print(S[S.dim=='state'].to_string(index=False))
print("\n== by card type"); print(S[S.dim=='card'].to_string(index=False))
print("\n== top 15 by t, all lines n>=30"); print(S[S.n>=30].sort_values('t',ascending=False).head(15).to_string(index=False))
W=S[S.PASS].sort_values('t',ascending=False)
print(f"\n== SURVIVORS: {len(W)}"); print(W.to_string(index=False) if len(W) else "none")
PY
