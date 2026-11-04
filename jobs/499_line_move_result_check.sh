#!/bin/bash
set -o pipefail
# 499_line_move_result_check (Finder 2026-11-04, queue item 64): jobs/499_prematch_line_move.sh infers results as "the one runner whose final in-play print is <= 1.05", known on only 64.4% of markets, and its Over/Under table is impossible (priced 3-5, implied 0.285, won 0.634). So: test that rule against real final scores from goal_timeline, by exact name match on a sample of 2,500 markets of each type. Read only.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,re,unicodedata,time,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
T0=time.time()
def norm(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
    s=re.sub(r"\b(fc|cf|afc|sc|ac|as|ss|us|sv|vfb|vfl|tsg|fk|club|de|the|cd|ud|sd|rcd|calcio|ii|b|if|bk|ff|aif|sk|fsv)\b"," ",s)
    return frozenset(w for w in re.sub(r"[^a-z0-9 ]"," ",s).split() if len(w)>2)
def true_winner(mk,ev,hs,as_):
    h,_,a=ev.partition(' v ')
    if mk=='OU25': return 'Over 2.5 Goals' if hs+as_>=3 else 'Under 2.5 Goals'
    return 'The Draw' if hs==as_ else (h.strip() if hs>as_ else a.strip())
# known answers
assert true_winner('OU25','A v B',2,1)=='Over 2.5 Goals' and true_winner('OU25','A v B',1,1)=='Under 2.5 Goals' and true_winner('OU25','A v B',0,0)=='Under 2.5 Goals'
assert true_winner('MO','Leeds v Hull',1,1)=='The Draw' and true_winner('MO','Leeds v Hull',2,0)=='Leeds' and true_winner('MO','Leeds v Hull',0,1)=='Hull'
assert norm('FC Porto')==norm('Porto') and norm('Leeds')!=norm('Hull')
print("checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'"); cur.execute("SET statement_timeout='2400s'")
GT=pd.read_sql("""SELECT DISTINCT ON (fixture_id) fixture_id,home_team,away_team,captured_at,minute,score_home,score_away,status FROM goal_timeline WHERE captured_at>='2026-07-01' AND captured_at<'2026-10-02' AND score_home IS NOT NULL ORDER BY fixture_id,captured_at DESC""",con)
GT['t']=pd.to_datetime(GT.captured_at,utc=True); GT['mn']=pd.to_numeric(GT.minute,errors='coerce')
GT=GT[GT.status.isin(['FT','AET','PEN','Match Finished','FINISHED'])|(GT.mn>=88)].copy()
print(f"goal_timeline finished fixtures {len(GT)}, {GT.t.min()} .. {GT.t.max()}, {time.time()-T0:.0f}s",flush=True)
GT['H']=GT.home_team.map(norm); GT['A']=GT.away_team.map(norm)
idx={}
for r in GT.itertuples(): idx.setdefault((r.H,r.A),[]).append(r)
def find(ev,mt):
    h,_,a=ev.partition(' v '); hits=[r for r in idx.get((norm(h),norm(a)),[]) if 0<=(r.t-mt).total_seconds()/60<=240]
    return hits[0] if len(hits)==1 else None
rng=np.random.default_rng(3)
for MK,lo,hi in (('MO','MATCH_ODDS','MATCH_ODDT'),('OU25','OVER_UNDER_25','OVER_UNDER_26')):
    cur.execute("""WITH RECURSIVE t AS ((SELECT market_id FROM bf_hist_other WHERE sport='Soccer' AND market_id>=%s AND market_id<%s ORDER BY market_id LIMIT 1)
     UNION ALL SELECT (SELECT market_id FROM bf_hist_other WHERE sport='Soccer' AND market_id>t.market_id AND market_id<%s ORDER BY market_id LIMIT 1) FROM t WHERE t.market_id IS NOT NULL) SELECT market_id FROM t WHERE market_id IS NOT NULL""",(lo,hi,hi))
    ids=[r[0] for r in cur.fetchall() if '|' in r[0]]
    s=[str(x) for x in rng.choice(ids,2500,replace=False)]
    P=pd.read_sql("SELECT market_id,event_name,market_time,sel,ts,ltp::float ltp FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s) AND inplay AND ltp>=1.01",con,params=(s,))
    P['t']=pd.to_datetime(P.ts,utc=True); P['mt']=pd.to_datetime(P.market_time,utc=True); P['after']=(P.t-P.mt).dt.total_seconds()/60
    L=P.sort_values('t').groupby(['market_id','sel']).agg(last=('ltp','last'),after=('after','last'),ev=('event_name','first'),mt=('mt','first')).reset_index()
    rows=[]
    for mid,g in L.groupby('market_id'):
        hit=find(g.ev.iloc[0],g.mt.iloc[0]); rule=g[g['last']<=1.05].sel.tolist()
        d=dict(mid=mid,matched=hit is not None,n_rule=len(rule),runners=len(g),max_after=g.after.max(),maxlast=g['last'].max())
        if hit is not None:
            tw=true_winner(MK,g.ev.iloc[0],int(hit.score_home),int(hit.score_away)); x=g[g.sel==tw]; y=g[g.sel!=tw]
            d.update(true=tw,rule=rule[0] if len(rule)==1 else None,seen=len(x)>0,true_last=x['last'].iloc[0] if len(x) else np.nan,true_after=x.after.iloc[0] if len(x) else np.nan,loser_max=y['last'].min() if len(y) else np.nan)
            d['draw']=tw=='The Draw'; d['over']=tw=='Over 2.5 Goals'
        rows.append(d)
    D=pd.DataFrame(rows); M=D[D.matched].copy(); M['fires']=M.rule.notna(); F=M[M.fires]
    print(f"\n== {MK}: sampled {len(s)}, with in-play prints {len(D)}, exactly one rule winner {(D.n_rule==1).mean():.3f}, matched to a score {len(M)}, runners seen {D.runners.value_counts().to_dict()}")
    print(f"rule fires on {M.fires.mean():.3f} of matched; agrees with the score when it fires {(F.rule==F.true).mean():.3f} (n {len(F)}); true winner's runner has in-play prints {M.seen.mean():.3f}")
    print(f"true winner's last print quantiles {M.true_last.quantile([.1,.25,.5,.75,.9]).round(3).to_dict()}; minutes after the scheduled off {M.true_after.quantile([.1,.5,.9]).round(0).to_dict()}")
    print(f"losers' lowest last print quantiles {M.loser_max.quantile([.01,.1,.5]).round(2).to_dict()}")
    if MK=='OU25': print(f"rule fires: Over won {M[M.over==True].fires.mean():.3f} (n {int((M.over==True).sum())}), Under won {M[M.over==False].fires.mean():.3f} (n {int((M.over==False).sum())}); Over share of matched {(M.over==True).mean():.3f}, of rule-known {(F.rule=='Over 2.5 Goals').mean():.3f}")
    else: print(f"rule fires: draw {M[M.draw==True].fires.mean():.3f} (n {int((M.draw==True).sum())}), not draw {M[M.draw==False].fires.mean():.3f} (n {int((M.draw==False).sum())}); draw share of matched {(M.draw==True).mean():.3f}, of rule-known {(F.rule=='The Draw').mean():.3f}")
    # would a wider rule be safe? winner = lowest last print if at most this and every other runner's last print is at least 5
    for cap in (1.05,1.2,1.5,2.0):
        ok=[];cov=0
        for mid,g in L[L.market_id.isin(M.mid)].groupby('market_id'):
            g=g.sort_values('last')
            if g['last'].iloc[0]<=cap and (len(g)==1 or g['last'].iloc[1]>=5):
                cov+=1; ok.append(g.sel.iloc[0]==M.loc[M.mid==mid,'true'].iloc[0])
        print(f"  wider rule cap {cap}: covers {cov/max(1,len(M)):.3f}, agrees {np.mean(ok) if ok else float('nan'):.3f}")
    print(f"{time.time()-T0:.0f}s",flush=True)
con.close()
PY
