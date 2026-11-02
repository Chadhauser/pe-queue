#!/bin/bash
set -o pipefail
# 454 (Finder 2026-11-02, queue item 0): INDEPENDENT AUDIT of job 321's survivor "MOMO" (pressure scalp). Own code, own fixture matcher.
# Rule audited: at a goal_live_predictions row (time t, minute 1-80), if the Over 2.5 BACK price has shortened >= 4 ticks over the last
# 3 minutes (last recorder print strictly before t vs last print strictly before t-180s, both within 90s), back on Match Odds the side with
# more dangerous attacks over the last 5 minutes (stats row at t vs latest row <= t-300s; tie -> home, as in 321), exit +5 min, or at the
# first print >= goal+2 min if a goal (score change in goal_live_predictions) comes first; variants +10 min and 5%-target.
# HONEST FILLS (liq_recorder.py: back_px = availableToBack[0], lay_px = availableToLay[0]):
#   entry = BACK at back_px of the first print strictly after t (<= 90 s), one tick adverse (one tick LOWER);
#   exit  = LAY at lay_px of the first print at/after the exit time (ANY later time), one tick adverse (one tick HIGHER);
#   no later print with a lay price -> SETTLE AT RESULT (final score). Never skipped.
# 321 did: entry at lay_px, exit at back_px (wins the spread on both legs), and skipped exits with no print within 180 s.
# DATA FINDING (run 1): goal_live_predictions has no DA/SOT since 27 Oct, so the "side with more dangerous attacks" never existed;
# 321 always backed HOME. MO_PRESS below = HOME (what 321 traded), MO_OTHER = AWAY.
# The 321-style fill on this same sample is reported as REPLICA for reconciliation. £10 back stake, 2% commission on profits.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,re,unicodedata,psycopg2,pandas as pd,numpy as np,warnings
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor(); cur.execute("SET statement_timeout='2400s'")
S=pd.read_sql("""SELECT fixture_id, captured_at t, minute, score_home sh, score_away sa, home_da hda, away_da ada
 FROM goal_live_predictions WHERE captured_at>='2026-10-27' AND minute BETWEEN 0 AND 130 ORDER BY fixture_id, captured_at""",con)
GT=pd.read_sql("""SELECT DISTINCT ON (fixture_id) fixture_id, home_team, away_team, score_home fh, score_away fa, status, minute
 FROM goal_timeline WHERE captured_at>='2026-10-26' ORDER BY fixture_id, captured_at DESC""",con)
L=pd.read_sql("""SELECT ts, event_name ev, mkt, sel, back_px::float b, lay_px::float l FROM liq_sample
 WHERE ts>='2026-10-27' AND mkt IN ('MO','OU25') AND event_name LIKE '%% v %%' ORDER BY ts""",con)
print("stats rows",len(S),"fixtures",S.fixture_id.nunique(),"| recorder rows",len(L),"events",L.ev.nunique(),"range",L.ts.min(),"->",L.ts.max(),flush=True)
print("goal_timeline final statuses:",GT.status.value_counts().head(8).to_dict())
# ---- own matcher: token overlap of both team names + kick-off window
STOP={'fc','cf','afc','sc','ac','club','the','de','cd','ud','sd','sv','fk','if','bk','sk','women','u21','u23','u19','res','reserves'}
def toks(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
    return {w for w in re.sub(r"[^a-z0-9 ]"," ",s).split() if len(w)>=3 and w not in STOP}
def score(a,b):
    A,B=toks(a),toks(b)
    if not A or not B: return 0
    exact=len(A&B); pref=sum(1 for x in A for y in B if x!=y and (x.startswith(y[:4]) or y.startswith(x[:4])) and min(len(x),len(y))>=4)
    return (exact+0.5*min(pref,1))/min(len(A),len(B))
EV=L.groupby('ev').ts.agg(['min','max']).reset_index(); EV['h']=EV.ev.str.split(' v ').str[0]; EV['a']=EV.ev.str.split(' v ').str[1]
k0=S[S.minute<=3].groupby('fixture_id').t.min().rename('k0'); F=GT.merge(k0,left_on='fixture_id',right_index=True)
M={}
for f in F.itertuples():
    c=EV[(EV['min']<f.k0+pd.Timedelta(minutes=30))&(EV['max']>f.k0+pd.Timedelta(minutes=20))]
    sc=sorted(((min(score(f.home_team,x.h),1)+min(score(f.away_team,x.a),1),x.ev) for x in c.itertuples()),reverse=True)
    if sc and sc[0][0]>=1.5 and (len(sc)==1 or sc[0][0]-sc[1][0]>=0.5): M[f.fixture_id]=sc[0][1]
print("fixtures with a kick-off row:",len(F),"matched to recorder:",len(M),"| events used twice:",pd.Series(list(M.values())).duplicated().sum(),flush=True)
# ---- books
BK={}
for (ev,mk,sl),g in L[L.ev.isin(set(M.values()))].groupby(['ev','mkt','sel']):
    BK[(ev,mk,sl)]=(g.ts.values.astype('datetime64[ns]'),g.b.values,g.l.values)
def tick(p): return 0.01 if p<2 else 0.02 if p<3 else 0.05 if p<4 else 0.1 if p<6 else 0.2 if p<10 else 0.5 if p<20 else 1.0 if p<30 else 2.0
def tdn(p): return tick(p-1e-9)
N64=lambda t: np.datetime64(pd.Timestamp(t).tz_convert(None) if pd.Timestamp(t).tzinfo else pd.Timestamp(t),'ns')
def last_before(key,t,tol=90):
    ts,b,l=BK[key]; i=np.searchsorted(ts,t,side='left')-1   # strictly before t
    while i>=0 and (t-ts[i])/np.timedelta64(1,'s')<=tol:
        if not np.isnan(b[i]): return b[i]
        i-=1
    return None
def first_after(key,t,tol=None,need='b',strict=True):
    ts,b,l=BK[key]; i=np.searchsorted(ts,t,side='right' if strict else 'left'); arr=b if need=='b' else l
    while i<len(ts):
        if tol is not None and (ts[i]-t)/np.timedelta64(1,'s')>tol: return None
        if not np.isnan(arr[i]): return i
        i+=1
    return None
def green(p,q):  # backed at p, laid out at q, greened up, per £10
    r=10*(p/q-1); return r*0.98 if r>0 else r
def settle(p,win): return 10*(p-1)*0.98 if win else -10.0
rows=[]; skipped={'no_da':0,'no_entry_print':0,'no_result':0}
S['t64']=S.t.dt.tz_convert(None).values.astype('datetime64[ns]')
for fid,g in S.groupby('fixture_id'):
    ev=M.get(fid)
    if not ev or (ev,'OU25','OVER') not in BK: continue
    okey=(ev,'OU25','OVER')
    gt=F[F.fixture_id==fid].iloc[0]; last=g.iloc[-1]
    # goal_timeline never stores FT (last status is 2H): result = last captured score if that row is >= 88'; ET games -> unresolved
    if str(gt.status)=='2H' and gt.minute>=88 and pd.notna(gt.fh): fh,fa=int(gt.fh),int(gt.fa)
    elif str(gt.status)!='ET' and last.minute>=88 and pd.notna(last.sh): fh,fa=int(last.sh),int(last.sa)
    else: fh,fa=None,None
    g=g.reset_index(drop=True); tot=(g.sh.fillna(0)+g.sa.fillna(0)).values; T=g.t64.values
    goals=[T[i] for i in range(1,len(g)) if tot[i]>tot[i-1]]
    for i,r in g.iterrows():
        if not (1<=r.minute<=80): continue
        t=T[i]
        o_now=last_before(okey,t); o_3=last_before(okey,t-np.timedelta64(180,'s'))
        if o_now is None or o_3 is None or (o_3-o_now)<4*tick(o_now)-1e-9: continue
        j=np.searchsorted(T,t-np.timedelta64(300,'s'),side='right')-1
        if j<0: continue
        w=g.iloc[j]
        # FIX after run 1: goal_live_predictions has NO dangerous-attack data since 27 Oct (home_da/away_da/sot/stats_json all NULL,
        # 0 of 174k rows). 321's (x or 0) made every DA delta 0 -> tie -> HOME. So "MOMO MO" was in fact "back HOME". We test that
        # (PRESS=HOME as 321 traded it; OTHER=AWAY) and count how often real DA existed.
        if any(pd.isna(x) for x in (r.hda,r.ada,w.hda,w.ada)): skipped['no_da']+=1; press='HOME'
        else: press='HOME' if (r.hda-w.hda)>=(r.ada-w.ada) else 'AWAY'
        other='AWAY' if press=='HOME' else 'HOME'
        k3=np.searchsorted(T,t-np.timedelta64(180,'s'),side='right')-1
        goal3=bool(k3>=0 and tot[i]>tot[k3])
        pj=bool(o_now<=0.75*o_3)
        ng=next((x for x in goals if x>t),None)
        for leg,key,winf in (('MO_PRESS',(ev,'MO',press),(fh is not None) and ((fh>fa) if press=='HOME' else (fa>fh))),
                             ('MO_OTHER',(ev,'MO',other),(fh is not None) and ((fh>fa) if other=='HOME' else (fa>fh))),
                             ('OU25_OVER',okey,(fh is not None) and fh+fa>=3)):
            if key not in BK: continue
            ts,b,l=BK[key]
            ie=first_after(key,t,tol=90,need='b')
            if ie is None: skipped['no_entry_print']+=1; continue
            bpx=b[ie]
            if bpx>20 or bpx<=1.01: continue
            p=bpx-tdn(bpx); te=ts[ie]
            rep_in=l[ie] if not np.isnan(l[ie]) else None
            for ex,secs in (('+5m',300),('+10m',600)):
                tx=t+np.timedelta64(secs,'s'); gflag=ng is not None and ng<tx
                if gflag: tx=ng+np.timedelta64(120,'s')
                ix=first_after(key,tx,need='l',strict=False)
                if ix is not None: q=l[ix]+tick(l[ix]); pnl=green(p,q); how='print'
                elif fh is None: skipped['no_result']+=1; pnl=-10.0; how='noresult_as_loss'
                else: pnl=settle(p,winf); how='settled'
                # 5% target inside the window: first print after entry with lay_px <= p*0.95
                tp=pnl; hit=False
                k=ie+1
                while k<len(ts) and ts[k]<=tx:
                    if not np.isnan(l[k]) and l[k]+tick(l[k])<=p*0.95: tp=green(p,l[k]+tick(l[k])); hit=True; break
                    k+=1
                # 321-style replica: in at lay_px, out at back_px within 180 s, both "one tick adverse" as 321 coded it; skip if no print
                rep=None
                if rep_in is not None:
                    ir=first_after(key,tx,tol=180,need='b',strict=False)
                    if ir is not None: rep=green(rep_in-tdn(rep_in),b[ir]+tick(b[ir]))
                rows.append((leg,ex,fid,pd.Timestamp(t),int(r.minute),bpx,round(pnl,3),round(tp,3),hit,how,goal3,pj,gflag,rep))
R=pd.DataFrame(rows,columns=['leg','exit','fid','t','minute','px','pnl','pnl_tgt','tgt_hit','how','goal_prev3','price_jump','goal_in_window','replica'])
print("entries (leg x exit rows):",len(R),"| fixtures with a trigger:",R.fid.nunique(),"| skipped:",skipped,flush=True)
if len(R)==0: sys.exit(0)
med=R.t.median(); R['h2']=R.t>med; print("half split at",med)
def tt(x): x=x.dropna(); return x.mean()/(x.std(ddof=1)/len(x)**0.5) if len(x)>2 and x.std(ddof=1)>0 else 0
def summ(D,col='pnl'):
    return pd.Series({'n':len(D),'games':D.fid.nunique(),'per10':D[col].mean(),'t':tt(D[col]),'h1':D[~D.h2][col].mean(),'h2':D[D.h2][col].mean(),
                      'n_h1':(~D.h2).sum(),'n_h2':D.h2.sum()})
def one_per_10(D):
    keep=[];
    for fid,g in D.sort_values('t').groupby('fid'):
        lastt=None
        for ix,x in g.iterrows():
            if lastt is None or (x.t-lastt).total_seconds()>=600: keep.append(ix); lastt=x.t
    return D.loc[keep]
pd.set_option('display.width',220); pd.set_option('display.max_rows',200)
print("\n== (0) RECONCILE: 321-style fills on THIS sample (in at lay_px, out at back_px, skip if no exit print <=180 s)")
for (leg,ex),D in R.groupby(['leg','exit']):
    d=D.dropna(subset=['replica']); print(f"  {leg:10s} {ex:5s} n {len(d):5d} per10 {d.replica.mean():+.3f} t {tt(d.replica):5.2f}   | honest fills same rows: {d.pnl.mean():+.3f}")
out=[]
for (leg,ex),D in R.groupby(['leg','exit']):
    for ver,DD in (('all',D),('1per10min',one_per_10(D))):
        for col in ('pnl','pnl_tgt'):
            s=summ(DD,col); s['cell']=f"{leg} {ex} {'fixed' if col=='pnl' else 'tgt5%'} {ver}"; out.append(s)
O=pd.DataFrame(out).set_index('cell').round(3)
print("\n== (3,4,5,7) HONEST: back at back_px -1 tick, lay out at lay_px +1 tick at the first print at/after exit (any time), else settle at result")
print(O.sort_values('t',ascending=False).to_string())
P=R[(R.leg=='MO_PRESS')&(R.exit=='+5m')]
print("\n== exit mechanics, MO_PRESS +5m:",P.how.value_counts().to_dict(),"| goal in window:",round(P.goal_in_window.mean(),3),"| 5% target hit:",round(P.tgt_hit.mean(),3))
print("\n== (2) goal in the previous 3 minutes (score change in goal_live_predictions), MO_PRESS +5m")
print(P.groupby('goal_prev3').apply(summ).round(3).to_string())
print("\n== (2b) OU25 Over back price fell >= 25% in the 3 min (a goal the price already knows, maybe before the stats feed), MO_PRESS +5m")
print(P.groupby('price_jump').apply(summ).round(3).to_string())
print("\n== (6) minute band, MO_PRESS +5m"); P=P.assign(mb=pd.cut(P.minute,[0,30,60,80]),pb=pd.cut(P.px,[1,2,3,5,10,20]))
print(P.groupby('mb').apply(summ).round(3).to_string())
print("\n== (6) entry price band, MO_PRESS +5m"); print(P.groupby('pb').apply(summ).round(3).to_string())
print("\n== same splits for OU25_OVER +5m (goal_prev3)"); print(R[(R.leg=='OU25_OVER')&(R.exit=='+5m')].groupby('goal_prev3').apply(summ).round(3).to_string())
O2=O.reset_index(); SV=O2[(O2.n>=300)&(O2.n_h1>=150)&(O2.n_h2>=150)&(O2.t>=3.5)&(O2.h1>0)&(O2.h2>0)&(O2.per10>=0.15)]
print(f"\n== SURVIVORS: {len(SV)}"); print(SV.to_string(index=False) if len(SV) else "none")
PY
