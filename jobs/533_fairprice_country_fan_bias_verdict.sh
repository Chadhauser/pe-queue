#!/bin/bash
# 533 (Sun 8 Nov 2026). Two builds Peter asked for this morning.
#  A. FAIR-PRICE ENGINE, next door H1c (pre-registered in fairprice_v0.py and fairprice_inplay.py): the same calibration map by
#     (country, market type, implied-probability band). Same rules as H1: complete books only, official results, median-date IS/OOS,
#     one tick adverse, 2% commission, random-side control, cells n>=300. Writes fair_price_calib_country for the bot; registered in
#     hypotheses.json as H1c, daily. One market type at a time (memory-safe), countries inside.
#  B. FAN-BIAS VERDICT (the five, item 3; brief of 14 Oct, due Mon 10 Nov): English big-six games on the BASIC tape (bf_hist_other,
#     country GB, MATCH_ODDS). 7am price v kick-off price on the big club (drift), then LAY the big club at kick-off to full time, one tick
#     adverse, 2% commission, return per £100 stake and per £100 liability; splits home/away, big-six clash/rest, derby/rest; oldest
#     seasons in-sample, newest three out-of-sample. Televised/not is NOT held in any table we have — said in the output, not guessed.
#     Control: the same lay on the opponent. Writes fan_bias_verdict (local) and prints VERDICT in the owner-rule format.
set -o pipefail
export PYTHONDONTWRITEBYTECODE=1
echo "== A. H1c fair price by country =="
cd /root/pe-sports/team && cat > fairprice_country.py <<'PYFILE'
# H1c FAIR PRICE BY COUNTRY (pre-registered next door of H1/H1b; built 8 Nov 2026). Same map as fairprice_v0.py, one more key: country.
# Question the data answers: does the closing price miss by a different amount in different countries' books? Complete books only,
# official results (bf_hist_result), IS = older half by date, OOS = newer half, fair price per (country, type, band) = IS win rate.
# Trade toward the IS fair price at the closing price one tick ADVERSE, 2% commission; control = side at random. Cells n>=300 and >=50 each half.
import sys, math, json, datetime, gc, numpy as np, pandas as pd, psycopg2, psycopg2.extras
sys.path.insert(0,'/root/pe-queue/runner'); import creds
COMM=0.02; rng=np.random.default_rng(13)
LADDER=[(2,0.01),(3,0.02),(4,0.05),(6,0.1),(10,0.2),(20,0.5),(30,1),(50,2),(100,5),(1000,10)]
def vtick(p):
    inc=np.full(len(p),10.0)
    for lim,i in reversed(LADDER): inc=np.where(p<lim,i,inc)
    return inc
def tick_down(p): return np.round(np.maximum(1.01,p-vtick(p-1e-9)),2)
def tick_up(p): return np.round(np.minimum(1000,p+vtick(p)),2)
def tstat(a): a=np.asarray(a,float); return float(a.mean()/(a.std(ddof=1)/math.sqrt(len(a)))) if len(a)>5 and a.std()>0 else 0.0
edges=[0,0.03,0.06,0.10,0.15,0.20,0.25,0.30,0.35,0.40,0.45,0.50,0.55,0.60,0.65,0.70,0.80,0.90,1.0001]
con=psycopg2.connect(creds.pg_local(),sslmode='prefer'); cur=con.cursor(); cur.execute("SET statement_timeout=0; SET work_mem='512MB'")
cur.execute("SELECT market_type, count(DISTINCT market_id) FROM bf_hist_other WHERE sport='Soccer' GROUP BY 1 ORDER BY 2 DESC"); types=cur.fetchall(); print("types:",len(types),flush=True)
cur.execute("DROP TABLE IF EXISTS fair_price_calib_country; CREATE TABLE fair_price_calib_country (country TEXT, market_type TEXT, band INT, band_lo NUMERIC, band_hi NUMERIC, n_is INT, rate_is NUMERIC, p_mean_is NUMERIC, n_oos INT, rate_oos NUMERIC, p_mean_oos NUMERIC, fair_factor NUMERIC, built_at TIMESTAMPTZ DEFAULT now())"); con.commit()
T0=datetime.datetime.now(datetime.UTC); out=0; tot_rows=0
MULTI_LINE={'ASIAN_HANDICAP','GOAL_LINE','ASIAN_HANDICAP_HT','HANDICAP','CORNER_HANDICAP','ALT_TOTAL_GOALS','ALT_CORNERS','ALT_BOOKINGS','CORRECT_SCORE2'}
for mt,nmk in types:
    if mt in MULTI_LINE: continue
    cur.execute("""
    WITH pre AS (SELECT DISTINCT ON (market_id, sel) market_id, sel, market_time, coalesce(country,'??') AS country, ltp AS close_ltp
                 FROM bf_hist_other WHERE sport='Soccer' AND market_type=%s AND NOT inplay AND ltp>1 AND ltp<1000 ORDER BY market_id, sel, ts DESC),
         res AS (SELECT market_id, sel, (status='WINNER')::int AS won, count(*) OVER (PARTITION BY market_id) AS n_res FROM bf_hist_result WHERE market_type=%s AND status IN ('WINNER','LOSER')),
         j AS (SELECT pre.market_id, pre.market_time, pre.country, pre.close_ltp::float8 AS close_ltp, res.won, res.n_res, count(*) OVER (PARTITION BY pre.market_id) AS n_pre,
                      sum(1/pre.close_ltp::float8) OVER (PARTITION BY pre.market_id) AS book FROM pre JOIN res USING (market_id, sel))
    SELECT market_id, market_time, country, close_ltp, won FROM j WHERE n_pre=n_res AND n_res>=2 AND book BETWEEN 0.95 AND 1.25""",(mt,mt))
    df=pd.DataFrame(cur.fetchall(),columns=['market_id','market_time','country','close_ltp','won']); con.commit()
    if len(df)<1000: continue
    df['market_id']=df.market_id.astype('category').cat.codes
    nw=df.groupby('market_id',sort=False).won.transform('sum'); df=df[nw==1].copy()
    df['won']=df.won.astype(np.int8); df['p_raw']=1/df.close_ltp; df['p']=df.p_raw/df.groupby('market_id',sort=False).p_raw.transform('sum')
    mtime=pd.to_datetime(df.market_time,utc=True); SPLIT=mtime.quantile(0.5); df['band']=pd.cut(df.p,edges,right=False,labels=False).astype(int); df['oos']=(mtime>=SPLIT).values
    cells=0; rows=[]
    for ctry,cdf in df.groupby('country'):
        if len(cdf)<600: continue
        cal=cdf.groupby(['band','oos']).agg(n=('won','size'),rate=('won','mean'),p_mean=('p','mean')).reset_index()
        IS=cal[~cal.oos].set_index('band'); OOS=cal[cal.oos].set_index('band')
        for b,r in IS.iterrows():
            o=OOS.loc[b] if b in OOS.index else None
            rows.append((ctry,mt,int(b),edges[b],edges[b+1],int(r.n),float(r.rate),float(r.p_mean),int(o.n) if o is not None else 0,float(o.rate) if o is not None else None,float(o.p_mean) if o is not None else None,float(r.rate/r.p_mean) if r.p_mean>0 else None))
        g=cdf.merge(IS[['rate','p_mean']].rename(columns={'rate':'fair_rate','p_mean':'p_is'}),left_on='band',right_index=True,how='inner').reset_index(drop=True)
        back=(g.fair_rate>g.p_is).values; cl=g.close_ltp.values; won=g.won.values; bk=tick_down(cl); ly=tick_up(cl)
        g['pnl']=np.where(back,np.where(won==1,(bk-1)*10*(1-COMM),-10.0),np.where(won==1,-(ly-1)*10,10.0*(1-COMM))); g['side']=np.where(back,'BACK','LAY')
        for b,gdf in g.groupby('band'):
            n=len(gdf)
            if n<300 or gdf.oos.sum()<50 or (~gdf.oos).sum()<50: continue
            idx=gdf.index.values; w=won[idx]; rside=rng.random(len(idx))<0.5
            ctrl=np.where(rside,np.where(w==1,(bk[idx]-1)*10*(1-COMM),-10.0),np.where(w==1,-(ly[idx]-1)*10,10.0*(1-COMM)))
            isx=gdf.loc[~gdf.oos,'pnl'].values; oox=gdf.loc[gdf.oos,'pnl'].values
            name=f"H1c {ctry} {mt} p{edges[b]:.2f}-{edges[b+1]:.2f} {gdf.side.iloc[0]} at close (IS rate {gdf.fair_rate.iloc[0]:.3f} vs implied {gdf.p_is.iloc[0]:.3f})"
            print("RESULT "+json.dumps(dict(name=name,n=int(n),mean_per10=round(float(gdf.pnl.mean()),3),t=round(tstat(gdf.pnl.values),2),is_mean=round(float(isx.mean()),3),is_t=round(tstat(isx),2),oos_mean=round(float(oox.mean()),3),oos_t=round(tstat(oox),2),control_t=round(tstat(ctrl),2),n_oos=int(gdf.oos.sum()),is_rate=round(float(gdf.fair_rate.iloc[0]),4),implied=round(float(gdf.p_is.iloc[0]),4))),flush=True); cells+=1; out+=1
    if rows: psycopg2.extras.execute_values(cur,"INSERT INTO fair_price_calib_country (country,market_type,band,band_lo,band_hi,n_is,rate_is,p_mean_is,n_oos,rate_oos,p_mean_oos,fair_factor) VALUES %s",rows); con.commit()
    tot_rows+=len(df); print(f"  {mt}: {len(df)} runner-rows, {df.country.nunique()} countries, cells {cells}, {(datetime.datetime.now(datetime.UTC)-T0).seconds}s",flush=True)
    del df,rows; gc.collect()
print(f"cells reported {out} | runner-rows {tot_rows}")
print("NEXT DOOR (pre-registered): H1d multi-line markets (AH, goal line) with line-aware settlement; H1e the same map on the LIVE tape's closing prices (liq_sample archive) to check the BASIC map transfers.")
PYFILE
python3 -m py_compile fairprice_country.py && echo "fairprice_country compiles"
python3 - <<'PY'
import json; p='/root/pe-sports/team/hypotheses.json'; r=json.load(open(p))
if not any(h['id'].startswith('H1c') for h in r['hypotheses']):
    r['hypotheses'].append({"id":"H1c fair price by country (country x market type x probability band, official results)","script":"/root/pe-sports/team/fairprice_country.py","status":"proposed","kind":"sweep","pre_registered_sign":"trade toward the IS fair price of that country's book","next_door":"H1d multi-line markets; H1e map on the live tape closes","timeout":14400,"repeat_hours":24})
json.dump(r,open(p,'w'),indent=1); print([(h['id'][:30],h['status']) for h in r['hypotheses']])
PY
echo; echo "== B. fan-bias verdict =="
mkdir -p /root/pe-sports/verdicts && cd /root/pe-sports/verdicts && cat > fan_bias_verdict.py <<'PYFILE'
# FAN-BIAS VERDICT (Peter's brief, 14 Oct 2026; built 8 Nov for Mon 10 Nov). Big-six games in England on the BASIC tape.
import sys, re, math, json, datetime, numpy as np, pandas as pd, psycopg2, psycopg2.extras
sys.path.insert(0,'/root/pe-queue/runner'); import creds
COMM=0.02
LADDER=[(2,0.01),(3,0.02),(4,0.05),(6,0.1),(10,0.2),(20,0.5),(30,1),(50,2),(100,5),(1000,10)]
def tick_up(p):
    for lim,inc in LADDER:
        if p<lim: return round(p+inc,2)
    return p+10
BIG={'Man City':r'^(man(chester)? city)$','Man Utd':r'^(man(chester)? (utd|united))$','Liverpool':r'^liverpool$','Arsenal':r'^arsenal$','Chelsea':r'^chelsea$','Tottenham':r'^(tottenham( hotspur)?|spurs)$'}
DERBY={frozenset(a) for a in [('Man Utd','Man City'),('Liverpool','Everton'),('Arsenal','Tottenham'),('Chelsea','Tottenham'),('Chelsea','Arsenal'),('Man Utd','Liverpool'),('Man Utd','Leeds'),('Tottenham','West Ham'),('Chelsea','Fulham'),('Arsenal','West Ham'),('Chelsea','West Ham')]}
def club(name):
    n=str(name).strip().lower()
    for k,pat in BIG.items():
        if re.match(pat,n): return k
    return None
def canon(name):
    c=club(name)
    if c: return c
    n=str(name).strip()
    return {'Everton':'Everton','Leeds':'Leeds','Leeds Utd':'Leeds','Leeds United':'Leeds','West Ham':'West Ham','West Ham Utd':'West Ham','Fulham':'Fulham'}.get(n,n)
def tstat(a): a=np.asarray(a,float); return float(a.mean()/(a.std(ddof=1)/math.sqrt(len(a)))) if len(a)>5 and a.std()>0 else 0.0
con=psycopg2.connect(creds.pg_local(),sslmode='prefer'); cur=con.cursor(); cur.execute("SET statement_timeout=0; SET work_mem='512MB'")
cur.execute("""
WITH mk AS (SELECT DISTINCT market_id, event_name, market_time FROM bf_hist_other
            WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND country='GB'
              AND (event_name ~* '(^|\\s)(man(chester)? (city|utd|united)|liverpool|arsenal|chelsea|tottenham|spurs)(\\s|$)')
              AND event_name !~* '(\\(w\\)|women|u21|u23|u19|u18|reserves|ladies)'),
     ko AS (SELECT DISTINCT ON (o.market_id, o.sel) o.market_id, o.sel, o.ltp AS ko_ltp, o.ts AS ko_ts
            FROM bf_hist_other o JOIN mk USING (market_id) WHERE o.market_type='MATCH_ODDS' AND NOT o.inplay AND o.ltp>1 ORDER BY o.market_id, o.sel, o.ts DESC),
     am AS (SELECT DISTINCT ON (o.market_id, o.sel) o.market_id, o.sel, o.ltp AS am_ltp, o.ts AS am_ts
            FROM bf_hist_other o JOIN mk USING (market_id) WHERE o.market_type='MATCH_ODDS' AND NOT o.inplay AND o.ltp>1
              AND o.ts >= date_trunc('day', mk.market_time AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' + interval '7 hours' AND o.ts < mk.market_time ORDER BY o.market_id, o.sel, o.ts ASC)
SELECT mk.market_id, mk.event_name, mk.market_time, ko.sel, ko.ko_ltp, am.am_ltp, am.am_ts, r.status
FROM mk JOIN ko USING (market_id) LEFT JOIN am ON am.market_id=ko.market_id AND am.sel=ko.sel
JOIN bf_hist_result r ON r.market_id=ko.market_id AND r.sel=ko.sel AND r.market_type='MATCH_ODDS' AND r.status IN ('WINNER','LOSER')""")
D=pd.DataFrame(cur.fetchall(),columns=['market_id','event_name','market_time','sel','ko','am','am_ts','status']); con.commit()
print("rows (runner x market):",len(D),"markets:",D.market_id.nunique(),flush=True)
D['ko']=D.ko.astype(float); D['am']=pd.to_numeric(D.am,errors='coerce')
D['sides']=D.event_name.map(lambda e: re.split(r'\s+v(?:s\.?)?\s+|\s+-\s+',str(e),maxsplit=1))
D=D[D.sides.map(len)==2].copy(); D['home']=D.sides.map(lambda s:s[0].strip()); D['away']=D.sides.map(lambda s:s[1].strip())
D['club']=D.sel.map(club)
mt=pd.to_datetime(D.market_time,utc=True); D['season']=np.where(mt.dt.month>=8,mt.dt.year,mt.dt.year-1); D['season']=D.season.map(lambda y:f"{y}/{str(y+1)[2:]}")
# the big-club rows, with the opponent row of the same market as control
B=D[D.club.notna()].copy()
B['side']=np.where(B.apply(lambda r: club(r.home)==r.club,axis=1),'HOME','AWAY')
B['opp']=np.where(B.side=='HOME',B.away,B.home); B['opp_c']=B.opp.map(canon)
B['clash']=B.opp.map(club).notna(); B['derby']=[frozenset((c,o)) in DERBY for c,o in zip(B.club,B.opp_c)]
B['won']=(B.status=='WINNER').astype(int); B['lay_px']=B.ko.map(tick_up)
B['pnl100']=np.where(B.won==1,-(B.lay_px-1)*100,100*(1-COMM))                 # lay £100 stake
B['pnl100L']=np.where(B.won==1,-100.0,(100/(B.lay_px-1))*(1-COMM))            # lay to £100 liability
B['drift']=B.ko/B.am-1                                                         # + = drifted (longer) since 7am, - = shortened
B['implied']=1/B.ko
# control: the opponent laid the same way
O=D[D.market_id.isin(B.market_id)&(D.sel!='The Draw')&D.sel.map(club).isna()].copy()
O['won']=(O.status=='WINNER').astype(int); O['lay_px']=O.ko.map(tick_up); O['pnl100']=np.where(O.won==1,-(O.lay_px-1)*100,100*(1-COMM))
seasons=sorted(B.season.unique()); oos_seasons=set(seasons[-3:]) if len(seasons)>=6 else set(seasons[len(seasons)//2:])
B['oos']=B.season.isin(oos_seasons)
print("seasons present:",{s:int((B.season==s).sum()) for s in seasons},"| IS:",[s for s in seasons if s not in oos_seasons],"OOS:",sorted(oos_seasons),flush=True)
print("DATA HOLE STATED: the BASIC loader fills newest-first; seasons with few rows above are partly loaded. Televised/not: not held in any table — split not run.",flush=True)
rows=[]
def line(name,X,ctrl=None):
    if len(X)<30: return
    isx=X.loc[~X.oos,'pnl100']; oox=X.loc[X.oos,'pnl100']
    d=X.drift.dropna()
    rec=dict(split=name,n=int(len(X)),per100=round(float(X.pnl100.mean()),2),per100_liab=round(float(X.pnl100L.mean()),2),t=round(tstat(X.pnl100),2),
             is_n=int(len(isx)),is_per100=round(float(isx.mean()),2) if len(isx) else None,oos_n=int(len(oox)),oos_per100=round(float(oox.mean()),2) if len(oox) else None,
             won=round(float(X.won.mean()),3),implied=round(float(X.implied.mean()),3),drift_mean=round(float(d.mean()),4) if len(d) else None,shortened_share=round(float((d<0).mean()),3) if len(d) else None,
             control_t=round(tstat(ctrl.pnl100),2) if ctrl is not None and len(ctrl)>5 else None,control_per100=round(float(ctrl.pnl100.mean()),2) if ctrl is not None and len(ctrl)>5 else None)
    rows.append(rec); print("RESULT "+json.dumps(rec),flush=True)
line("ALL big six, lay at KO",B,O)
line("HOME",B[B.side=='HOME'],O[O.market_id.isin(B[B.side=='HOME'].market_id)])
line("AWAY",B[B.side=='AWAY'],O[O.market_id.isin(B[B.side=='AWAY'].market_id)])
line("big-six CLASH",B[B.clash]); line("not a clash",B[~B.clash]); line("DERBY",B[B.derby]); line("not a derby",B[~B.derby])
line("shortened since 7am",B[B.drift<0]); line("drifted since 7am",B[B.drift>0]); line("shortened 5%+ since 7am",B[B.drift<-0.05])
for lo,hi in [(1,1.5),(1.5,2),(2,3),(3,5),(5,50)]: line(f"KO price {lo}-{hi}",B[(B.ko>=lo)&(B.ko<hi)])
for c in BIG: line(f"club {c}",B[B.club==c])
cur.execute("CREATE TABLE IF NOT EXISTS fan_bias_verdict (run_at TIMESTAMPTZ DEFAULT now(), split TEXT, n INT, per100 NUMERIC, per100_liab NUMERIC, t NUMERIC, is_n INT, is_per100 NUMERIC, oos_n INT, oos_per100 NUMERIC, won NUMERIC, implied NUMERIC, drift_mean NUMERIC, shortened_share NUMERIC, control_t NUMERIC, control_per100 NUMERIC)")
psycopg2.extras.execute_values(cur,"INSERT INTO fan_bias_verdict (split,n,per100,per100_liab,t,is_n,is_per100,oos_n,oos_per100,won,implied,drift_mean,shortened_share,control_t,control_per100) VALUES %s",
    [(r['split'],r['n'],r['per100'],r['per100_liab'],r['t'],r['is_n'],r['is_per100'],r['oos_n'],r['oos_per100'],r['won'],r['implied'],r['drift_mean'],r['shortened_share'],r['control_t'],r['control_per100']) for r in rows]); con.commit()
a=next((r for r in rows if r['split'].startswith('ALL')),None)
if a:
    bar=a['n']>=300 and a['t']>=3.5 and a['per100']>=1.5 and (a['is_per100'] or 0)>0 and (a['oos_per100'] or 0)>0 and abs(a['control_t'] or 0)<=2
    pos=[r for r in rows if r['n']>=100 and r['per100']>0 and (r['is_per100'] or 0)>0 and (r['oos_per100'] or 0)>0]
    best=max(pos,key=lambda r:r['t']) if pos else None
    drift="big club SHORTENED from 7am to KO in %s%% of games, mean move %s%%"%(round(100*a['shortened_share']),round(100*a['drift_mean'],2)) if a['drift_mean'] is not None else "7am price not present"
    if bar: v=f"VERDICT: WORKS — lay the big six at kick-off: {a['per100']:+.2f} per £100 stake after 2% on n {a['n']}, t {a['t']}, IS {a['is_per100']:+.2f} / OOS {a['oos_per100']:+.2f}, control t {a['control_t']}. {drift}. Next: in-play comeback lay when a big club goes behind, on the live tape, job queued 10 Nov."
    else:
        sup=f"(a) what it DOES support: {best['split']} n {best['n']} {best['per100']:+.2f}/£100, t {best['t']}, IS {best['is_per100']:+.2f} / OOS {best['oos_per100']:+.2f}" if best else "(a) no split positive in both halves at n>=100"
        v=f"VERDICT: NOT YET — all big six laid at KO: {a['per100']:+.2f} per £100 stake after 2% on n {a['n']}, t {a['t']}, IS {a['is_per100']} / OOS {a['oos_per100']}, control (opponent laid) {a['control_per100']:+.2f} t {a['control_t']}; won {a['won']} v implied {a['implied']}. {drift}. {sup}. (b) next door: in-play lay of the big club's comeback price when it goes behind, on the live tape (liq_sample archive, 2025-26), scheduled 12 Nov; (c) third door: the same KO lay with the 7am->KO shortening as the entry filter once older seasons load (14 Nov)."
    print(v,flush=True)
else: print("VERDICT: NOT ENOUGH DATA — no big-six MATCH_ODDS markets with official results on the loaded months (data hole stated above)",flush=True)
PYFILE
python3 -m py_compile fan_bias_verdict.py && echo "fan_bias_verdict compiles"
timeout 3000 python3 fan_bias_verdict.py
echo "533 done"
