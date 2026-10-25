#!/bin/bash
# 228: PETER'S ORIGINAL PLAYBOOK RULES THROUGH THE HONEST ENGINE (never done until now). True Understat goal minutes (3,440 games), our
# own in-play prices (MO, OU25, OU15, OU35, FH15), 2% spread + 2% comm, by-minute cells + halves. Families added to stats_sweep:
#   S13: HT 0-2 with pre-match home favourite (home KO price <= 1.80) -> back Over 3.5 at 46'
#   S14: HT 1-1 with pre-match home favourite -> back Over 2.5 at 46'
#   S13b/S14b: same without the favourite condition (so the condition's value is visible)
#   S5 : favourite (KO <= 1.50) trailing 0-1 before 65' -> lay the leader (the "shock lead" rule), exit next goal / FT
# Pre-match rules S8 (lay draw at KO when draw >= 5.5), S9 (lay home at KO when home >= 4.0, Serie A and all leagues), S16 (home 4.0+
# lower leagues), S18 (PL first half Over 1.5 when home KO price >= 3.15) are settled from event_results on ALL 12,683 games with results
# in a separate pass below (KO price = minute-0 LTP). Everything prints by league group and by season half.
cd /root/pe-factory/v4 && python3 - <<'PY'
p='stats_sweep.py'; s=open(p).read(); n=0
if 'S13' not in s:
    anchor="                if hg==0 and ag==0: emit(f'LEVEL00@{m}','MO','DRAW','lay',m)\n"
    add="""                if m==55:
                    k0,h0=px_at(Pm['HOME'],0,3); hfav=(h0 is not None and h0<=1.80); hg45,ag45=state(46)
                    if hg45==0 and ag45==2:
                        emit('S13b@46','OU35','OVER','back',46)
                        if hfav: emit('S13@46','OU35','OVER','back',46)
                    if hg45==1 and ag45==1:
                        emit('S14b@46','OU25','OVER','back',46)
                        if hfav: emit('S14@46','OU25','OVER','back',46)
                if m<65 and m>=20:
                    k0,h0=px_at(Pm['HOME'],0,3); k0,a0=px_at(Pm['AWAY'],0,3)
                    if h0 is not None and h0<=1.50 and hg==0 and ag==1: emit(f'S5@{m}','MO','AWAY','lay',m)
                    if a0 is not None and a0<=1.50 and hg==1 and ag==0: emit(f'S5@{m}','MO','HOME','lay',m)
"""
    assert anchor in s; s=s.replace(anchor,anchor+add,1); n+=1
# OU35 prices must be loaded: extend the price query and the Po-style dict
if "'OU35'" not in s:
    s=s.replace("WHERE mkt IN ('MO','OU25','OU15') AND event_id = ANY(%s)","WHERE mkt IN ('MO','OU25','OU15','OU35') AND event_id = ANY(%s)",1)
    s=s.replace("P15={s_:series(g,'OU15',s_) for s_ in ('OVER','UNDER')}","P15={s_:series(g,'OU15',s_) for s_ in ('OVER','UNDER')}; P35={s_:series(g,'OU35',s_) for s_ in ('OVER','UNDER')}",1)
    s=s.replace("def win_ou15(sel): return (tot>1.5) if sel=='OVER' else (tot<1.5)","def win_ou15(sel): return (tot>1.5) if sel=='OVER' else (tot<1.5)\n            def win_ou35(sel): return (tot>3.5) if sel=='OVER' else (tot<3.5)",1)
    s=s.replace("prices=Pm[sel] if mkt=='MO' else (Po[sel] if mkt=='OU25' else P15[sel]); winf=win_mo if mkt=='MO' else (win_ou25 if mkt=='OU25' else win_ou15)",
                "prices=Pm[sel] if mkt=='MO' else (Po[sel] if mkt=='OU25' else (P35[sel] if mkt=='OU35' else P15[sel])); winf=win_mo if mkt=='MO' else (win_ou25 if mkt=='OU25' else (win_ou35 if mkt=='OU35' else win_ou15))",1)
    n+=1
open(p,'w').write(s); print("patches:",n)
PY
python3 -m py_compile stats_sweep.py || exit 1
timeout 3300 python3 stats_sweep.py 2>&1 | grep -E "SWEEP:|stored" | head -3
python3 - <<'PY'
import sys,psycopg2,pandas as pd; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',230); pd.set_option('display.max_rows',200); c=psycopg2.connect(DB,sslmode='require')
d=pd.read_sql("SELECT fam, sel, dir, exit, band, n, round(mean,2) mean, round(t,2) t, round(h1,2) h1, round(h2,2) h2 FROM v4_stats_results WHERE run_date=current_date AND (fam LIKE 'S1%%' OR fam LIKE 'S5%%') ORDER BY fam, exit, band",c)
print("=== IN-PLAY PLAYBOOK RULES (true goals, top leagues) per £10 ===\n",d.to_string(index=False))
PY
echo "== PRE-MATCH PLAYBOOK RULES on all games with results (KO price = minute-0 LTP, settle FT, 2% spread + 2% comm)"
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,psycopg2,pandas as pd,numpy as np; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',230); c=psycopg2.connect(DB,sslmode='require'); SP=0.02; CM=0.02
ko=pd.read_sql("""SELECT p.event_id, p.m, p.mkt, p.sel, p.ltp::float ltp FROM bf_hist_price p WHERE p.minute=0 AND p.mkt IN ('MO','FH15') AND p.event_id IN (SELECT event_id FROM event_results)""",c)
res=pd.read_sql("SELECT event_id, fthg, ftag, hthg, htag FROM event_results WHERE fthg IS NOT NULL",c)
W=ko.pivot_table(index='event_id',columns=['mkt','sel'],values='ltp',aggfunc='first'); W.columns=[f"{a}_{b}" for a,b in W.columns]; W=W.join(res.set_index('event_id'),how='inner')
lg=pd.read_sql("SELECT DISTINCT event_id, competition FROM bf_hist_price WHERE minute=0 AND mkt='MO'",c).drop_duplicates('event_id').set_index('event_id') if 'competition' in [r[0] for r in c.cursor().execute("SELECT column_name FROM information_schema.columns WHERE table_name='bf_hist_price'") or []] else None
W['date']=pd.to_datetime(ko.drop_duplicates('event_id').set_index('event_id').m).reindex(W.index); med=W.date.median(); W['half']=np.where(W.date<med,'H1','H2')
def lay(px,won): return (-10*(px*(1+SP)-1)) if won else 10*(1-CM)
def back(px,won): return (10*(px*(1-SP)-1)*(1-CM)) if won else -10.0
rows=[]
S=W[W.MO_DRAW>=5.5]; rows.append(('S8 lay draw at KO, draw>=5.5',len(S),[lay(p,d) for p,d in zip(S.MO_DRAW,S.fthg==S.ftag)],S.half))
S=W[W.MO_HOME>=4.0]; rows.append(('S9/S16 lay home at KO, home>=4.0 (all leagues)',len(S),[lay(p,d) for p,d in zip(S.MO_HOME,S.fthg>S.ftag)],S.half))
S=W[(W.MO_HOME>=4.0)&(W.MO_HOME<4.5)]; rows.append(('S9 lay home 4.0-4.5',len(S),[lay(p,d) for p,d in zip(S.MO_HOME,S.fthg>S.ftag)],S.half))
if 'FH15_OVER' in W:
    S=W[(W.MO_HOME>=3.15)&W.FH15_OVER.notna()&(W.FH15_OVER<=3.30)]; rows.append(('S18 back FH Over 1.5 when home>=3.15 (all leagues)',len(S),[back(p,w) for p,w in zip(S.FH15_OVER,(S.hthg+S.htag)>1.5)],S.half))
for name,n,pl,half in rows:
    pl=np.array(pl,dtype=float); h=np.array(half)
    if n==0: print(f"{name}: no games"); continue
    t=pl.mean()/(pl.std(ddof=1)/np.sqrt(n)) if n>2 else 0
    print(f"{name}: n {n} | per £10 {pl.mean():+.2f} | t {t:.2f} | H1 {pl[h=='H1'].mean() if (h=='H1').any() else float('nan'):+.2f} H2 {pl[h=='H2'].mean() if (h=='H2').any() else float('nan'):+.2f} | win {(pl>0).mean():.0%}")
print("games with KO prices and results:",len(W),"| date range",W.date.min().date(),"->",W.date.max().date())
PY
