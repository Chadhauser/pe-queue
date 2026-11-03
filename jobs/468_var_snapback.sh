#!/bin/bash
set -o pipefail
# 468 (Finder 2026-11-03, item 0g): VAR SNAP-BACK and goal OVERSHOOT on the live recorder.
# Data: goal_timeline (live score feed, captured_at real timestamps) joined to liq_sample (real Betfair touch, ~1 sample/min/market)
# by event-name token match (jobs/300 style), same London day. Clock: feed captured_at vs recorder ts — both real timestamps,
# no minute alignment needed. Entry and exit ONLY at a real recorder sample (back at back_px, lay at lay_px, exit at the opposite
# touch), never forward-filled: entry = first sample with ts >= signal time (<= 90 s later, else no entry); exit = first sample with
# ts >= entry + H (<= 120 s late, else held to the next real sample whenever it comes; never dropped). One tick adverse each way,
# 2% commission on profit, £10 risk (back stake / lay liability). OU25 legs settle at the RESULT if the line is passed before exit.
# Events per fixture (feed rows sorted by captured_at, null scores ignored):
#   UP     = a side's score rises.  REVERSAL = that side's score falls back by exactly 1 within 15 min of the UP and the next feed row
#   agrees (two rows) — a VAR/feed-corrected goal.  GLITCH = any other fall (e.g. to 0-0, both sides) — counted, not traded.
#   STANDING goal = UP not reversed within 15 min.
# Snap-back: wrongly-credited side's MO back price pre-UP (last sample <= 3 min before UP) vs samples after the revert; snap time =
#   first sample (after UP) where back_px is within 5% of pre; reported relative to the feed revert (negative = market knew first).
# Recipes at the REVERT sample: R_BACK_OTHER (back the side that was wrongly marked down), R_LAY_SCORER (lay the wrongly credited side),
#   R_LAY_O25 (lay OU25 OVER); exit +3 min. Overshoot on STANDING goals: G_LAY_SCORER / G_BACK_SCORER at the first sample after the
#   feed goal, exits +3/+5/+10 min; G_LAY_O_NEXT skipped (the next line is not always listed). Halves by date median.
# MO label defect (0e): games with two runners labelled the same are dropped.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,re,unicodedata,datetime,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
def tick(p): return 0.01 if p<2 else 0.02 if p<3 else 0.05 if p<4 else 0.1 if p<6 else 0.2 if p<10 else 0.5 if p<20 else 1 if p<30 else 2 if p<50 else 5 if p<100 else 10
def pnl(side,p,q,won=None):
    # side B: back at touch p (one tick worse), exit lay at touch q (one tick worse) or settle (q None, won given)
    if side=='B':
        p=p-tick(p)
        if p<=1.01: return None
        r=(10*(p-1) if won else -10.0) if q is None else 10*(p/(q+tick(q))-1)
    else:
        p=p+tick(p); s=10/(p-1)
        r=(s if not won else -10.0) if q is None else s*(1-p/max(1.01,q-tick(q)))
    return r*0.98 if r>0 else r
assert abs(pnl('B',3.0,None,True)-19.11)<1e-9 and pnl('L',3.0,None,True)==-10.0
assert abs(pnl('B',3.0,4.0)+2.804878)<1e-6
assert abs(pnl('L',1.5,1.5)-(10/0.51)*(1-1.51/1.49))<1e-9      # lay 1.5 fill 1.51, back out 1.5 fill 1.49: a small loss
# NB tick(2.0)=0.02 both ways, so at exactly 2.00 the down-tick is 0.02 not 0.01 (one tick conservative at that boundary only)
assert pnl('L',2.0,2.0)<0 and pnl('B',2.0,2.0)<0                 # flat price round trip always loses the two ticks
print("P&L unit checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor(); cur.execute("SET statement_timeout='2400s'")
cur.execute("SELECT min(ts),max(ts) FROM liq_sample"); L0,L1=cur.fetchone()
T=pd.read_sql("""SELECT fixture_id, captured_at, league_name, home_team, away_team, minute, score_home, score_away, status FROM goal_timeline
  WHERE captured_at>=%s AND captured_at<=%s AND score_home IS NOT NULL AND score_away IS NOT NULL ORDER BY fixture_id, captured_at""",con,params=(L0-datetime.timedelta(hours=3),L1))
L=pd.read_sql("""SELECT ts, event_name, mkt, sel, back_px::float back_px, lay_px::float lay_px FROM liq_sample
  WHERE mkt IN ('MO','OU25') AND event_name LIKE '%% v %%' AND back_px>1 AND lay_px>1""",con)
print(f"liq_sample {L0:%Y-%m-%d %H:%M} .. {L1:%Y-%m-%d %H:%M} | recorder games {L.event_name.nunique()} | timeline fixtures {T.fixture_id.nunique()} rows {len(T)}",flush=True)
gap=T.groupby('fixture_id').captured_at.diff().dt.total_seconds().dropna()
print(f"feed cadence: median {gap.median():.0f} s, p90 {gap.quantile(.9):.0f} s",flush=True)
def norm(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
    s=re.sub(r"\b(fc|cf|afc|sc|ac|as|ss|us|sv|vfb|vfl|tsg|fk|club|de|the|athletic|atletico|sporting|real|cd|ud|sd|rcd|calcio|women|w|u21|u23|ii|b|if|bk|ff|aif|is|kv|sk|fsv)\b"," ",s)
    return set(w for w in re.sub(r"[^a-z0-9 ]"," ",s).split() if len(w)>2)
def sim(a,b): A,B=norm(a),norm(b); return len(A&B)/max(1,len(A|B))
fx=T.groupby('fixture_id').agg(home=('home_team','first'),away=('away_team','first'),t0=('captured_at','min'),t1=('captured_at','max')).reset_index()
fx['hn']=fx.home.map(norm); fx['an']=fx.away.map(norm)
# --- events from the feed
EVS=[]; nglitch=0; nup=0
for fid,g in T.groupby('fixture_id'):
    rows=list(zip(g.captured_at,g.score_home.astype(int),g.score_away.astype(int)))
    for i in range(1,len(rows)):
        t,h,a=rows[i]; _,ph,pa=rows[i-1]
        if (h<ph or a<pa):
            # a fall: reversal of a single goal only if exactly one side falls by 1 and the next row agrees
            one=((ph-h==1 and a==pa) or (pa-a==1 and h==ph)); nxt_ok=(i+1<len(rows) and rows[i+1][1]==h and rows[i+1][2]==a) or i+1==len(rows)
            if not(one and nxt_ok): nglitch+=1
        for side,new,old in (('h',h,ph),('a',a,pa)):
            if new>old:
                nup+=1; rev=None
                for j in range(i+1,len(rows)):
                    tj,hj,aj=rows[j]
                    if (tj-t).total_seconds()>900: break
                    sj=hj if side=='h' else aj; oj=aj if side=='h' else hj
                    if sj==new-1 and oj==(a if side=='h' else h):
                        if (j+1<len(rows) and rows[j+1][1]==hj and rows[j+1][2]==aj) or j+1==len(rows): rev=tj
                        break
                    if sj<new-1 or sj>new: break
                cls=None
                if rev is not None:
                    # SWAP = feed credited the wrong team: the OTHER side's score rises within 180 s of the revert; else VAR (goal removed)
                    oth0=a if side=='h' else h; cls='VAR'
                    for tk,hk,ak in rows:
                        if rev<=tk<=rev+pd.Timedelta(seconds=180) and (ak if side=='h' else hk)>oth0: cls='SWAP'; break
                EVS.append(dict(fid=fid,side=side,t_up=t,t_rev=rev,cls=cls,score=(h,a)))
E=pd.DataFrame(EVS)
print(f"feed UP events {nup} | reversals {int(E.t_rev.notna().sum())} | glitches (other falls, not traded) {nglitch}",flush=True)
# final score per fixture = last feed row
FT={fid:(int(g.score_home.iloc[-1]),int(g.score_away.iloc[-1])) for fid,g in T.groupby('fixture_id')}
# --- map recorder games to fixtures
L['day']=L.ts.dt.tz_convert('Europe/London').dt.date
px={}; ev2fid={}; dropped_label=0
for (ev,day),g in L.groupby(['event_name','day']):
    mo=g[g.mkt=='MO']
    if mo.groupby(['ts']).sel.apply(lambda s: s.duplicated().any()).any(): dropped_label+=1; continue
    h,a=ev.split(' v ',1); H,A=norm(h),norm(a); best=None; bs=0; b2=0
    cand=fx[(fx.t0.dt.tz_convert('Europe/London').dt.date<=day)&(fx.t1.dt.tz_convert('Europe/London').dt.date>=day)]
    for f in cand.itertuples():
        sc=len(H&f.hn)/max(1,len(H|f.hn))+len(A&f.an)/max(1,len(A|f.an))
        if sc>bs: b2=bs; bs=sc; best=f.fixture_id
        elif sc>b2: b2=sc
    if best is None or bs<1.0 or bs-b2<0.3: continue
    ev2fid[(ev,day)]=best
    for (mkt,sel),s in g.groupby(['mkt','sel']):
        s=s.sort_values('ts'); px[(best,mkt,sel.upper())]=(s.ts.values.astype('datetime64[s]').astype('int64'),s.back_px.values,s.lay_px.values)
print(f"recorder games mapped to the feed: {len(ev2fid)} (dropped for MO label defect: {dropped_label})",flush=True)
def first_after(key,t,maxlag=None):
    v=px.get(key)
    if v is None: return None
    i=np.searchsorted(v[0],t)
    if i>=len(v[0]) or (maxlag is not None and v[0][i]-t>maxlag): return None
    return i
def last_before(key,t,maxlag):
    v=px.get(key)
    if v is None: return None
    i=np.searchsorted(v[0],t,side='right')-1
    if i<0 or t-v[0][i]>maxlag: return None
    return i
def tsec(x): return int(pd.Timestamp(x).timestamp())
rows=[]; snaps=[]; revn=0; revpriced=0
for e in E.itertuples():
    sc_sel='HOME' if e.side=='h' else 'AWAY'; ot_sel='AWAY' if e.side=='h' else 'HOME'
    kS=(e.fid,'MO',sc_sel); kO=(e.fid,'MO',ot_sel); kU=(e.fid,'OU25','OVER')
    if kS not in px: continue
    tu=tsec(e.t_up); day=pd.Timestamp(e.t_up).tz_convert('Europe/London').date()
    fth,fta=FT[e.fid]
    def trade(name,key,side,t_sig,H,settle_fn=None):
        i=first_after(key,t_sig,90)
        if i is None: return
        ts,bk,ly=px[key]; p=bk[i] if side=='B' else ly[i]
        j=first_after(key,ts[i]+H)
        if settle_fn is not None:
            done,won=settle_fn(ts[i], ts[j] if j is not None else None)
            if done or j is None:
                r=pnl(side,p,None,won)
                if r is not None: rows.append((name,H//60,e.fid,day,r,'settled')); return
        if j is None:   # no later print at all = market closed (FT): settle MO at the RESULT, never dropped
            won=(fth>fta) if key[2]=='HOME' else (fta>fth)
            r=pnl(side,p,None,won)
            if r is not None: rows.append((name,H//60,e.fid,day,r,'settled'))
            return
        q=ly[j] if side=='B' else bk[j]
        r=pnl(side,p,q)
        if r is not None: rows.append((name,H//60,e.fid,day,r,'print'))
    if e.t_rev is not None and not pd.isna(e.t_rev):
        revn+=1; tr=tsec(e.t_rev)
        ip=last_before(kS,tu,180); ts,bk,ly=px[kS]
        if ip is not None:
            pre=bk[ip]; revpriced+=1
            iu=first_after(kS,tu,120); ir=first_after(kS,tr,120)
            k=np.searchsorted(ts,tu-60); snap=None
            moved=False
            for m in range(k,len(ts)):
                if ts[m]>tr+900: break
                if abs(np.log(bk[m]/pre))>0.15: moved=True
                if moved and abs(np.log(bk[m]/pre))<=0.05: snap=ts[m]; break
            snaps.append(dict(cls=e.cls,pre=pre,flash=bk[iu] if iu is not None else np.nan,at_rev=bk[ir] if ir is not None else np.nan,
                              moved=moved,flash_s=tr-tu,snap_rel=(snap-tr) if snap is not None else np.nan))
        # goals per feed between entry and exit time for OU25 settlement
        def ou_settle(t_in,t_out):
            g=T[(T.fixture_id==e.fid)]; t_end=t_out if t_out is not None else 10**12
            tot=(g[g.captured_at.map(lambda x: x.timestamp())<=t_end].iloc[-1:][['score_home','score_away']].sum(axis=1))
            tot=int(tot.iloc[0]) if len(tot) else 0
            if tot>2: return True,True
            if t_out is None: return True,(fth+fta>2)
            return False,None
        for c in ('ALL',e.cls):
            trade(f'R_BACK_OTHER_{c}',kO,'B',tr,180); trade(f'R_LAY_SCORER_{c}',kS,'L',tr,180)
            if kU in px and c!='SWAP': trade(f'R_LAY_O25_{c}',kU,'L',tr,180,ou_settle)
    else:
        for H in (180,300,600):
            trade('G_LAY_SCORER',kS,'L',tu,H); trade('G_BACK_SCORER',kS,'B',tu,H)
print(f"reversals {revn} | with a pre-goal MO price {revpriced}",flush=True)
S=pd.DataFrame(snaps)
for cls,S in [('ALL',S)]+list(S.groupby('cls')):
    print(f"\n== feed reversals [{cls}]: wrongly-credited side MO back price")
    print(f"  n {len(S)} | market moved >15% at all: {int(S.moved.sum())} | median feed flash duration {S.flash_s.median():.0f} s")
    print(f"  median pre {S.pre.median():.2f} | at flash {S.flash.median():.2f} | at feed revert {S.at_rev.median():.2f}")
    sm=S[S.moved].snap_rel.dropna()
    print(f"  snap-back (within 5% of pre) relative to the feed revert: n {len(sm)}, median {sm.median() if len(sm) else float('nan'):.0f} s, share BEFORE the feed reverted {(sm<0).mean() if len(sm) else float('nan'):.2f}")
D=pd.DataFrame(rows,columns=['line','hold','fid','day','pnl','how'])
out=[]
if len(D):
    med=sorted(D.day.unique())[len(D.day.unique())//2]
    for (ln,h),x in D.groupby(['line','hold']):
        n=len(x); mu=x.pnl.mean(); sd=x.pnl.std(ddof=0) or 1e-9
        a=x[x.day<med].pnl; c=x[x.day>=med].pnl
        out.append(dict(line=ln,hold_min=h,n=n,games=x.fid.nunique(),mean=mu,t=mu/(sd/np.sqrt(n)),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(c),h2=c.mean() if len(c) else np.nan,settled=(x.how=='settled').sum()))
R=pd.DataFrame(out)
if len(R):
    R['PASS']=(R.n>=300)&(R.n1>=150)&(R.n2>=150)&(R.t>=3.5)&(R.h1>0)&(R.h2>0)&(R['mean']>=0.15)
    print(f"\n== trades (halves split at {med}); per £10")
    print(R.sort_values('t',ascending=False).round(3).to_string(index=False))
    S2=R[R.PASS]
    print(f"\n== SURVIVORS: {len(S2)}"); print(S2.round(3).to_string(index=False) if len(S2) else "none")
else:
    print("\n== SURVIVORS: none (no trades)")
PY
