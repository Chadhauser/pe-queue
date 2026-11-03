#!/bin/bash
set -o pipefail
# 478 (Finder 2026-11-03, queue item 23): MOMENTUM AND PRESSURE. goal_stats_live (minute, SOT, shots in box "home_da", corners; about one row per 3 min per fixture) x liq_sample (real touch) by fixture name via goal_timeline, jobs/468 style. Both clocks are real timestamps, so the tape clock issue of jobs/471 does not apply.
# TRIGGER at a stats row, per side: rise over the last W minutes (W = 5, 10), against the latest earlier row of that fixture at or before t-W (at most 3 min older): SOT >= 2, shots in box >= 3, corners >= 2. Look-back only. One entry per fixture/side/trigger/W per 15 min.
# CONTROL: rows where that side's three stats did not rise over 10 min, same spacing, both sides, so friction is not mistaken for signal.
# ENTRY: first liq_sample at or after the stats row, within 90 s, else no entry (counted). Back at back_px -1 tick (exact ladder), £10 stake, 2% commission.
# TRADES: MO = back the pressing side. OVER = back the next goal line (total 0: OU05 if recorded, 1: OU15, 2: OU25, 3: OU35; else not traded, counted).
# EXITS: NG2 = first real sample at/after next feed goal +2 min, no goal = settle. P10, P15 = first real sample at/after +10/+15 min. Exit at lay_px +1 tick. An Over line passed before the exit is settled at the RESULT. No later sample = settled at the result.
# RESULT from the last feed row. A fixture whose feed does not reach minute 88 or FT is unknown: known-only per10 is shown beside unknown = loss, and PASS uses unknown = loss. Games with a mislabelled MO (two rows of one label in a sample) are dropped (counted; recorder defect, jobs/466).
# Halves by median entry time. tc = t on per-fixture means.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,re,time,unicodedata,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
LAD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    x=lo
    while x<hi-1e-9: LAD.append(round(x,2)); x+=st
LAD.append(1000.0); LADA=np.array(LAD)
def ti(p): return int(np.searchsorted(LADA,round(p,2)-1e-9))
def dn(p): return float(LADA[max(ti(p)-1,0)])
def up(p): return float(LADA[min(ti(p)+1,len(LADA)-1)])
def back(p,q,won):
    a=dn(p)
    if a<=1.01: return None
    r=(10*(a-1) if won else -10.0) if q is None else 10*(a/up(q)-1)
    return r*0.98 if r>0 else r
def line_for(total): return {0:'OU05',1:'OU15',2:'OU25',3:'OU35'}.get(total)
def over_won(mkt,total): return total>{'OU05':0.5,'OU15':1.5,'OU25':2.5,'OU35':3.5}[mkt]
def norm(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
    s=re.sub(r"\b(fc|cf|afc|sc|ac|as|ss|us|sv|vfb|vfl|tsg|fk|club|de|the|athletic|atletico|sporting|real|cd|ud|sd|rcd|calcio|women|w|u21|u23|ii|b|if|bk|ff|aif|is|kv|sk|fsv)\b"," ",s)
    return set(w for w in re.sub(r"[^a-z0-9 ]"," ",s).split() if len(w)>2)
def sim(A,B): return len(A&B)/max(1,len(A|B))
# known answers, worked by hand: back 3.0 -> 2.98, wins 19.8 less 2% = 19.404; loses £10; lay out at 2.5 -> 2.52: 10*(2.98/2.52-1) = 1.825397, less 2% = 1.788889; a flat 2.00/2.02 book: 1.99/2.04 = -0.245098
assert abs(back(3.0,None,True)-19.404)<1e-9 and back(3.0,None,False)==-10.0 and abs(back(3.0,2.5,None)-1.788889)<1e-5 and abs(back(2.0,2.02,None)+0.245098)<1e-5 and back(1.02,None,True) is None
assert line_for(0)=='OU05' and line_for(3)=='OU35' and line_for(4) is None and over_won('OU25',3) and not over_won('OU25',2) and over_won('OU05',1) and not over_won('OU05',0)
assert sim(norm('Manchester United'),norm('Manchester United FC'))==1.0 and sim(norm('Arsenal'),norm('Chelsea'))==0.0
print("P&L + line + name unit checks: OK",flush=True)
def tstat(x):
    x=np.asarray(x,dtype=float); s=x.std(ddof=1) if len(x)>1 else 0
    return x.mean()/(s/len(x)**0.5) if s>0 else 0.0
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s';")
cur.execute("SELECT min(ts),max(ts) FROM liq_sample"); L0,L1=cur.fetchone(); print("liq_sample",L0,"..",L1,flush=True)
S=pd.read_sql("""SELECT fixture_id, captured_at, minute, score_home, score_away, home_sot, away_sot, home_da, away_da, home_corners, away_corners FROM goal_stats_live WHERE captured_at>=%s ORDER BY fixture_id, captured_at""",con,params=(L0,))
T=pd.read_sql("""SELECT fixture_id, captured_at, home_team, away_team, minute, score_home, score_away, status FROM goal_timeline WHERE captured_at>=%s AND score_home IS NOT NULL AND score_away IS NOT NULL ORDER BY fixture_id, captured_at""",con,params=(L0-pd.Timedelta(hours=3),))
print(f"stats rows {len(S)}, fixtures {S.fixture_id.nunique()}; timeline fixtures {T.fixture_id.nunique()}; rows with SOT {S.home_sot.notna().mean():.0%}, shots in box {S.home_da.notna().mean():.0%}, corners {S.home_corners.notna().mean():.0%}",flush=True)
parts=[]
for a in pd.date_range(pd.Timestamp(L0).floor('D'),pd.Timestamp(L1),freq='1D'):
    parts.append(pd.read_sql("""SELECT ts, event_name, mkt, sel, back_px::float bp, lay_px::float lp FROM liq_sample WHERE ts>=%s AND ts<%s AND mkt IN ('MO','OU05','OU15','OU25','OU35') AND event_name LIKE '%% v %%' AND back_px>1 AND lay_px>back_px""",con,params=(a,a+pd.Timedelta(days=1))))
L=pd.concat(parts,ignore_index=True); del parts; print(f"liq rows {len(L)}, games {L.event_name.nunique()}, markets {L.mkt.value_counts().to_dict()}",flush=True)
L['side']=L.sel.str.upper().str.split().str[0]
L['day']=L.ts.dt.tz_convert('Europe/London').dt.date
SK=defaultdict(int); books={}
gx=[]
for (ev,day),g in L.groupby(['event_name','day'],sort=False):
    mo=g[g.mkt=='MO']
    if len(mo) and mo.groupby(['ts','side']).size().max()>1: SK['MO label defect, game dropped']+=1; continue
    h_,_,a_=ev.partition(' v '); gx.append(dict(ev=ev,day=day,t0=g.ts.min(),t1=g.ts.max(),H=norm(h_),A=norm(a_),g=g))
fx={}
for fid,g in T.groupby('fixture_id'):
    fx[fid]=dict(H=norm(g.home_team.iloc[0]),A=norm(g.away_team.iloc[0]),t0=g.captured_at.iloc[0],t1=g.captured_at.iloc[-1],ts=g.captured_at.values,tot=(g.score_home.astype(int)+g.score_away.astype(int)).values,hg=int(g.score_home.iloc[-1]),ag=int(g.score_away.iloc[-1]),last_min=g.minute.iloc[-1],status=str(g.status.iloc[-1]))
want=set(S.fixture_id); mp={}
for e in gx:
    best=None; bs=0
    for fid,f in fx.items():
        if fid in want and f['t0']-pd.Timedelta(hours=1)<=e['t1'] and e['t0']<=f['t1']+pd.Timedelta(hours=1):
            s_=min(sim(e['H'],f['H']),sim(e['A'],f['A']))
            if s_>bs: bs,best=s_,fid
    if best is not None and bs>=0.3: mp[best]=e
print(f"fixtures in stats {len(want)}, with a timeline {len(want&set(fx))}, mapped to recorder games {len(mp)}",flush=True)
def get_book(fid):
    if fid in books: return books[fid]
    b={}
    for (mkt,side),x in mp[fid]['g'].groupby(['mkt','side']):
        x=x.sort_values('ts'); b[(mkt,side)]=(x.ts.values,x.bp.values,x.lp.values)
    books[fid]=b; return b
STATS=(('SOT','sot',2),('BOX','da',3),('CRN','corners',2))
rows=[]
def trade(fid,tsig,side_,mkt,sel,total,tag,trig,W):
    b=get_book(fid).get((mkt,sel))
    if b is None: SK[f'no book {mkt}']+=1; return
    ts,bp,lp=b; i=int(np.searchsorted(ts,tsig))
    if i>=len(ts) or (ts[i]-tsig)>np.timedelta64(90,'s'): SK['no sample within 90 s']+=1; return
    f=fx[fid]; hg,ag=f['hg'],f['ag']; ftt=hg+ag
    known=f['status'] in ('FT','AET','PEN','Match Finished','FINISHED') or (pd.notna(f['last_min']) and f['last_min']>=88)
    won=((hg>ag) if sel=='HOME' else (ag>hg)) if mkt=='MO' else over_won(mkt,ftt)
    entry_t=ts[i]; j=int(np.searchsorted(f['ts'],entry_t,side='right'))
    tot0=f['tot'][j-1] if j>0 else total
    later=np.flatnonzero(f['tot'][j:]>tot0); gt=f['ts'][j+int(later[0])] if len(later) else None
    rec=dict(fid=fid,ts=entry_t,tag=tag,trig=trig,W=W,mkt=mkt,known=known,px=bp[i],side_=side_)
    for ex,tgt in (('NG2',None if gt is None else gt+np.timedelta64(120,'s')),('P10',entry_t+np.timedelta64(600,'s')),('P15',entry_t+np.timedelta64(900,'s'))):
        q=None
        if tgt is not None:
            passed=False
            if mkt!='MO':
                jj=int(np.searchsorted(f['ts'],tgt,side='right'))
                if jj>0 and over_won(mkt,int(f['tot'][jj-1])): passed=True
            if not passed:
                k=int(np.searchsorted(ts,tgt))
                if k<len(ts) and k>i: q=float(lp[k])
        r=back(float(bp[i]),q,won)
        if r is None: SK['back at 1.01']+=1; return
        rec[ex]=r
    rows.append(rec)
t0=time.time()
for fid,g in S.groupby('fixture_id'):
    if fid not in mp or fid not in fx: SK['stats fixture not mapped']+=1; continue
    g=g.sort_values('captured_at'); ts=g.captured_at.values; n=len(g)
    tot=(g.score_home.fillna(0)+g.score_away.fillna(0)).astype(int).values
    last=defaultdict(lambda:np.datetime64('1970-01-01')); co=defaultdict(lambda:np.datetime64('1970-01-01'))
    for side_,pre in (('HOME','home'),('AWAY','away')):
        V={c:pd.to_numeric(g[f'{pre}_{c}'],errors='coerce').values for _,c,_ in STATS}
        for i in range(n):
            flag=False
            for W in (5,10):
                j=int(np.searchsorted(ts,ts[i]-np.timedelta64(W*60,'s'),side='right'))-1
                if j<0 or (ts[i]-np.timedelta64(W*60,'s')-ts[j])>np.timedelta64(180,'s'): continue
                for trig,c,th in STATS:
                    d=V[c][i]-V[c][j]
                    if np.isnan(d) or d<th: continue
                    flag=True; k=(side_,trig,W)
                    if ts[i]-last[k]<np.timedelta64(900,'s'): continue
                    last[k]=ts[i]
                    trade(fid,ts[i],side_,'MO',side_,tot[i],'TRIG',trig,W)
                    ml=line_for(tot[i])
                    if ml: trade(fid,ts[i],side_,ml,'OVER',tot[i],'TRIG',trig,W)
                    else: SK['total >= 4, no Over line']+=1
            j=int(np.searchsorted(ts,ts[i]-np.timedelta64(600,'s'),side='right'))-1
            if not flag and j>=0 and (ts[i]-np.timedelta64(600,'s')-ts[j])<=np.timedelta64(180,'s') and all((V[c][i]-V[c][j])==0 for _,c,_ in STATS) and ts[i]-co[side_]>=np.timedelta64(900,'s'):
                co[side_]=ts[i]
                trade(fid,ts[i],side_,'MO',side_,tot[i],'CTRL','none',10)
                ml=line_for(tot[i])
                if ml and side_=='HOME': trade(fid,ts[i],side_,ml,'OVER',tot[i],'CTRL','none',10)
print(f"entries built in {int(time.time()-t0)}s; counted skips: {dict(SK)}",flush=True)
R=pd.DataFrame(rows)
if R.empty: print("\n== SURVIVORS: 0\nnone (no entries)"); sys.exit()
R['kind']=np.where(R.mkt=='MO','MO','OVER'); R['ts_']=pd.to_datetime(R.ts); med=R.ts_.median(); R['h']=R.ts_>=med; days=(R.ts_.max()-R.ts_.min()).total_seconds()/86400
print(f"entries {len(R)}, fixtures {R.fid.nunique()}, span {days:.1f} days, half split {med}, known results {R.known.mean():.1%}",flush=True)
out=[]
for (tag,trig,W,kind),x in R.groupby(['tag','trig','W','kind']):
    for ex in ('NG2','P10','P15'):
        v=x[ex].where(x.known,-10.0); a=v[~x.h]; b=v[x.h]
        per=pd.DataFrame(dict(f=x.fid,v=v)).groupby('f').v.mean()
        out.append(dict(tag=tag,trig=trig,W=W,trade=kind,exit=ex,n=len(x),games=x.fid.nunique(),px=x.px.mean(),per10=v.mean(),known_only=x[x.known][ex].mean(),t=tstat(v),tc=tstat(per),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan))
O=pd.DataFrame(out); O['PASS']=(O.tag=='TRIG')&(O.n>=300)&(O.n1>=150)&(O.n2>=150)&(O.t>=3.5)&(O.h1>0)&(O.h2>0)&(O.per10>=0.15)
pd.set_option('display.width',240); pd.set_option('display.max_rows',100); pd.set_option('display.max_columns',30)
print("\n== all lines (per10 = unknown result as a loss; known_only beside it)"); print(O.sort_values(['tag','trade','trig','W','exit']).round(3).to_string(index=False))
print("\n== top 15 by t, triggers only"); print(O[O.tag=='TRIG'].sort_values('t',ascending=False).head(15).round(3).to_string(index=False))
out2=[]
for (tag,trig,W),x in R[(R.kind=='MO')&(R.px<=10)].groupby(['tag','trig','W']):
    for ex in ('NG2','P10','P15'):
        v=x[ex].where(x.known,-10.0); a=v[~x.h]; b=v[x.h]
        out2.append(dict(tag=tag,trig=trig,W=W,exit=ex,n=len(x),games=x.fid.nunique(),px=x.px.mean(),per10=v.mean(),t=tstat(v),tc=tstat(pd.DataFrame(dict(f=x.fid,v=v)).groupby('f').v.mean()),h1=a.mean() if len(a) else np.nan,h2=b.mean() if len(b) else np.nan))
print("\n== MO, entry price <= 10 only (the pressing side at a sensible price; the all-price lines above carry long shots)"); print(pd.DataFrame(out2).sort_values(['tag','trig','W','exit']).round(3).to_string(index=False))
Tr=R[R.tag=='TRIG']; print(f"\naccrual: {len(Tr)/max(days,0.01):.0f} trigger entries/day across {Tr.groupby(['trig','W','kind']).ngroups} lines; largest line n {int(O[O.tag=='TRIG'].n.max())}")
W_=O[O.PASS].sort_values('t',ascending=False)
print(f"\n== SURVIVORS: {len(W_)}"); print(W_.round(3).to_string(index=False) if len(W_) else "none")
PY
