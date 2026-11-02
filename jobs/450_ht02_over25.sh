#!/bin/bash
set -o pipefail
# 450 (Finder 2026-11-02, queue item 2): HT 0-2 -> BACK Over 2.5 at the first REAL second-half print, hold to settle. Two seasons.
# Games: af_price_map -> af_fixtures (FT, HT score from ht_hg/ht_ag). States: 0-2 (the watch-list line), 2-0 (comparison), 1-1 (control,
# same total). Entry: first real OU25 OVER print at match minute 46..48 on bf_hist_price (second-half minutes are Betfair clock minus the
# per-event half-time offset; ltp is the LAST trade in that minute). No forward-fill. If a second-half goal (af_events) happened at or
# before the entry minute the entry price is post-goal: the game is SKIPPED and counted (skips are all winners, so skipping biases
# AGAINST the line — reported). One tick adverse, £10 stake, 2% commission on profit, settle at the FT result (no early exit, so no
# settled-market drop is possible). Halves = season 2024 vs 2025. One entry per game (no correlation inflation).
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
def tick(p): return 0.01 if p<2 else 0.02 if p<3 else 0.05 if p<4 else 0.1 if p<6 else 0.2 if p<10 else 0.5 if p<20 else 1 if p<30 else 2 if p<50 else 5 if p<100 else 10
def back_pnl(p,won):
    p=p-tick(p)
    if p<=1.01: return None
    r=10*(p-1) if won else -10.0
    return r*0.98 if r>0 else r
# known answers (tick = increment AT p, as in 315 — conservative at band edges): 2.00 -> 1.98, win 9.8*0.98=9.604;
# 3.00 -> 2.95, win 19.5*0.98=19.11; 1.80 loss -10; 1.02 -> 1.01 unfillable
assert abs(back_pnl(2.00,True)-9.604)<1e-9 and abs(back_pnl(3.00,True)-19.11)<1e-9 and back_pnl(1.8,False)==-10.0 and back_pnl(1.02,True) is None
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor(); cur.execute("SET statement_timeout='2400s'")
G=pd.read_sql("""SELECT m.event_id, f.fixture_id, f.season, f.league, f.hg, f.ag, f.ht_hg, f.ht_ag FROM af_price_map m
 JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint
 WHERE f.status='FT' AND f.hg IS NOT NULL AND f.ht_hg IS NOT NULL""",con)
G['state']=G.ht_hg.astype(int).astype(str)+'-'+G.ht_ag.astype(int).astype(str)
print("mapped FT games with HT score:",len(G),"| seasons:",G.season.value_counts().to_dict())
G=G[G.state.isin(['0-2','2-0','1-1'])].copy()
print("HT states:",G.groupby(['state','season']).size().to_dict(),flush=True)
EV=pd.read_sql("""SELECT fixture_id, minute, coalesce(extra,0) extra FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal'
 AND detail IN ('Normal Goal','Penalty','Own Goal')""",con,params=(list(map(int,G.fixture_id)),))
first2h=EV[EV.minute>45].groupby('fixture_id').minute.min().to_dict()   # minute>45 = second half (45+x stoppage stays 45)
P=pd.read_sql("""SELECT event_id, minute, mkt, sel, ltp::float ltp, bool_or(calibrated) OVER (PARTITION BY event_id) cal FROM bf_hist_price
 WHERE event_id=ANY(%s) AND ((mkt='OU25' AND sel='OVER' AND minute BETWEEN 46 AND 48) OR (mkt='MO' AND sel IN ('HOME','AWAY') AND minute BETWEEN 0 AND 1))
 AND ltp>1.01 AND ltp<1000""",con,params=(list(G.event_id),))
P=P.sort_values(['event_id','mkt','sel','minute'])
ent=P[P.mkt=='OU25'].groupby('event_id').first()[['minute','ltp','cal']].rename(columns={'minute':'emin','ltp':'px'})
mo=P[P.mkt=='MO'].groupby(['event_id','sel']).ltp.first().unstack()
G=G.join(ent,on='event_id').join(mo,on='event_id')
n0=len(G); G=G[G.px.notna()].copy(); print(f"with a real OU25 OVER print at 46-48: {len(G)} of {n0}")
G['g2']=G.fixture_id.map(first2h)
G['won']=(G.hg+G.ag)>2
def fb(r):
    if pd.isna(r.HOME) or pd.isna(r.AWAY): return 'n/a'
    f=min(r.HOME,r.AWAY); return '<1.5' if f<1.5 else '1.5-2' if f<2 else '2-3' if f<3 else '3+'
G['fav']=G.apply(fb,axis=1)
def lf(r):
    if r.state=='1-1': return 'level'
    if pd.isna(r.HOME) or pd.isna(r.AWAY): return 'n/a'
    leader_home=r.state=='2-0'; return 'leader=fav' if (r.HOME<=r.AWAY)==leader_home else 'leader=dog'
G['lead']=G.apply(lf,axis=1); G['cal']=np.where(G.cal==True,'calibrated','default-offset')
G['pxband']=pd.cut(G.px,[1,1.5,1.8,2.1,2.5,100],labels=['<1.5','1.5-1.8','1.8-2.1','2.1-2.5','2.5+'])
# DIAGNOSTIC (found in the first run): bf_hist_price.calibrated is TRUE only for games that HAD a second-half goal (the offset was located
# from a goal), so it is look-ahead. The cal split is printed as a warning only and can never PASS. Pooled = all games, still fair.
def tstat(x): return x.mean()/(x.std(ddof=1)/len(x)**0.5) if len(x)>1 and x.std(ddof=1)>0 else 0.0
def table(D):
    rows=[]
    for dims in (['state'],['state','fav'],['state','lead'],['state','pxband'],['state','cal'],['state','league']):
        for k,g in D.groupby(dims,observed=True):
            k=k if isinstance(k,tuple) else (k,)
            a=g[g.season==2024].pnl; b=g[g.season==2025].pnl
            rows.append(dict(dim='+'.join(dims),line=' / '.join(map(str,k)),n=len(g),games=g.fixture_id.nunique(),per10=g.pnl.mean(),t=tstat(g.pnl),
                n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,hit=g.won.mean(),avg_px=g.px.mean()))
    R=pd.DataFrame(rows).round(3)
    R['PASS']=(R.n>=300)&(R.n1>=150)&(R.n2>=150)&(R.t>=3.5)&(R.h1>0)&(R.h2>0)&(R.per10>=0.15)&(R.dim!='state+cal')
    return R
# MAIN: skip if a 2H goal at/before the entry minute. CONSERVATIVE: skip if a 2H goal <= entry minute + 3 (guards a wrong default
# half-time offset putting a post-goal print at "46"), and entry price >= 1.15 (a post-goal Over price is ~1.01-1.10). Both skip only
# would-be winners, so CONS is biased AGAINST the line. A line PASSES only if it passes in BOTH.
out={}
for var,cond in (('MAIN',G.g2.notna()&(G.g2<=G.emin)),('CONS',(G.g2.notna()&(G.g2<=G.emin+3))|(G.px<1.15))):
    D=G[~cond].copy(); D['pnl']=[back_pnl(p,w) for p,w in zip(D.px,D.won)]; D=D[D.pnl.notna()]
    print(f"{var}: skipped {int(cond.sum())} (by state {G[cond].state.value_counts().to_dict()}), trades {len(D)}")
    out[var]=table(D)
R=out['MAIN'].merge(out['CONS'][['dim','line','n','per10','t','h1','h2','PASS']],on=['dim','line'],how='left',suffixes=('','_cons'))
R['PASS']=R.PASS&(R.PASS_cons==True)
show=['dim','line','n','games','per10','t','n1','h1','n2','h2','hit','avg_px','n_cons','per10_cons','t_cons','h1_cons','h2_cons','PASS']
print("\n== headline by HT state (back Over 2.5 at first real 2H print, hold to settle; per £10; _cons = conservative skip)")
print(R[R.dim=='state'][show].to_string(index=False))
print("\n== 0-2 and 2-0 splits (fav band, leader fav/dog, entry price band)")
print(R[R.dim.isin(['state+fav','state+lead','state+pxband'])&R.line.str.match(r'^(0-2|2-0) ')&(R.n>=20)].sort_values(['line'])[show].to_string(index=False))
print("\n== WARNING split (look-ahead, never passes): calibrated half-time offset")
print(R[R.dim=='state+cal'][show].to_string(index=False))
print("\n== top 15 by t (MAIN, n>=30, excluding the look-ahead cal split)")
print(R[(R.n>=30)&(R.dim!='state+cal')].sort_values('t',ascending=False).head(15)[show].to_string(index=False))
S=R[R.PASS].sort_values('t',ascending=False)
print(f"\n== SURVIVORS: {len(S)}"); print(S[show].to_string(index=False) if len(S) else "none")
PY
