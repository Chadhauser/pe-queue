#!/bin/bash
set -o pipefail
# 499_oct24_lines (Finder 2026-11-05, queue items 147, 163, 164, Finder's own, sources c, d; from jobs/499_longtail_senior.sh, jobs/499_longtail_other_markets.sh): do the long-tail lines of 5 Nov repeat on Oct 2024, a month that chose nothing? Rules pushed in the queue (commit e987e9e) before any Oct 2024 price was read. Read only.
# ENTRY last non-in-play print T-20 to T-2 min, worse of it and the next within 120 s, one tick adverse, 2%, £10 risk, hold to the official result. Over 50 not traded, counted. Lowest id per event per market type. A market without exactly one WINNER is dropped, counted.
# GROUPS (163) WOMEN, YOUTH by event name; other games S_THIN <=8, S_MID <=18, else S_DEEP on MO prints T-60 to T-20, item 144's cuts from its log, fixed. Item 157 ran with 6 and 14, so fit-window lines here differ a little from that report.
# WINDOWS fit: off from 1 May 2026. Test: Oct 2024. Scored: the 10 lines with the highest fit t (fit n >= 100) per item, on the test window only, plus 147's one line. Halves by date inside the window. One bet per game per line, but lines share games, so read them as correlated. Prints only: a pass is an upper bound and only earns a real-touch check.
# KNOWN GAP as run: load_results keeps markets with exactly one WINNER, so every DOUBLE_CHANCE market was lost here (two WINNERs) and item 164's 38 lines are HT/FT and HTS only. jobs/499_oct24_dc.sh reads double chance under the same rule.
# COVERAGE up to about 100 Oct 2024 games had loaded when items 157, 158 ran; they cannot be told apart now, and they are under 4% of the month.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(3_500_000_000,3_500_000_000))  # this job only: MemoryError rather than the box's OOM killer at a daemon
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
from scipy.stats import spearmanr
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,norm,jac
from lib_official import group,bk,ly,fill,last_in,secs,load_results,checks
import lib_cand; lib_cand._checks(); checks()
C1,C2=8,18
T_LO,T_HI=pd.Timestamp('2024-10-01',tz='UTC').timestamp(),pd.Timestamp('2024-11-01',tz='UTC').timestamp(); F_LO=pd.Timestamp('2026-05-01',tz='UTC').timestamp()
def mo_pair(home,away,runners):
    """As jobs/499_longtail_senior.sh."""
    r=[x for x in runners if str(x).strip().lower()!='the draw']
    if len(r)!=2: return None
    H,A,a,b=norm(home),norm(away),norm(r[0]),norm(r[1])
    s1,s2=jac(a,H)+jac(b,A),jac(a,A)+jac(b,H)
    if s1==s2: return None
    x,y=(r[0],r[1]) if s1>s2 else (r[1],r[0])
    if not (norm(x)&H and norm(y)&A): return None
    return x,y
def grp_of(x,liqv): return x if isinstance(x,str) else ('S_THIN' if liqv<=C1 else 'S_MID' if liqv<=C2 else 'S_DEEP')
def window(off): return 'T' if T_LO<=off<T_HI else 'F' if off>=F_LO else None
def htft(sel,fav,dog):
    """'Fav/Dog' -> 'FAV/DOG' by exact team name, the Draw as DRAW; None if a part is not one of the three. Split on the first '/' that gives two known parts, as a team name may hold one."""
    m={fav:'FAV',dog:'DOG','Draw':'DRAW'}; s=str(sel).strip()
    for i,c in enumerate(s):
        if c=='/' and s[:i] in m and s[i+1:] in m: return m[s[:i]]+'/'+m[s[i+1:]]
    return None
def dc(sel,home_fav):
    s=str(sel).strip().lower()
    if s=='home or away': return 'FAV_DOG'
    if s=='home or draw': return 'FAV_DRAW' if home_fav else 'DOG_DRAW'
    if s=='draw or away': return 'DOG_DRAW' if home_fav else 'FAV_DRAW'
    return None
def hts(sel,home_fav):
    s=str(sel).strip().lower()
    if s=='any unquoted': return 'AnyUnq'
    a,x,b=s.partition(' - ')
    if not x or not a.isdigit() or not b.isdigit(): return None
    return f"{a}-{b}" if home_fav else f"{b}-{a}"
# known answers, worked by hand
assert htft('Sarpsborg/Draw','Sarpsborg','Valerenga')=='FAV/DRAW' and htft('Draw/Valerenga','Sarpsborg','Valerenga')=='DRAW/DOG' and htft('Valerenga/Sarpsborg','Sarpsborg','Valerenga')=='DOG/FAV'
assert htft('A/B/Draw','A/B','C')=='FAV/DRAW' and htft('Leeds/Draw','Hull','Stoke') is None
assert dc('Home or Draw',True)=='FAV_DRAW' and dc('Home or Draw',False)=='DOG_DRAW' and dc('Draw or Away',True)=='DOG_DRAW' and dc('Draw or Away',False)=='FAV_DRAW' and dc('Home or Away',False)=='FAV_DOG' and dc('x',True) is None
assert hts('2 - 1',True)=='2-1' and hts('2 - 1',False)=='1-2' and hts('Any Unquoted ',True)=='AnyUnq' and hts('Any unquoted',False)=='AnyUnq' and hts('foo',True) is None
assert grp_of(None,8)=='S_THIN' and grp_of(float('nan'),9)=='S_MID' and grp_of(None,18)=='S_MID' and grp_of(None,19)=='S_DEEP' and grp_of('YOUTH',1)=='YOUTH'
assert window(T_LO)=='T' and window(T_HI) is None and window(F_LO)=='F' and window(T_LO-1) is None
print("checks: OK",flush=True)
pd.set_option('display.width',250); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',40)
T0=time.time()
LINES={'OVER_UNDER_05':'OU05','OVER_UNDER_15':'OU15','OVER_UNDER_25':'OU25','OVER_UNDER_35':'OU35','OVER_UNDER_45':'OU45','FIRST_HALF_GOALS_05':'FH05','FIRST_HALF_GOALS_15':'FH15','FIRST_HALF_GOALS_25':'FH25'}
OWN={'HALF_TIME_FULL_TIME':'HTFT','DOUBLE_CHANCE':'DC','HALF_TIME_SCORE':'HTS'}
TYPES=dict(MATCH_ODDS='MO',BOTH_TEAMS_TO_SCORE='BTTS',HALF_TIME='HT',DRAW_NO_BET='DNB',**LINES,**OWN)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
RS,bad=load_results(con,list(TYPES)); print(f"markets with one WINNER {len(RS)}, dropped {bad}, {time.time()-T0:.0f}s",flush=True)
cur.execute("SELECT DISTINCT market_id,event_id,event_name,market_type,market_time FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s)",(list(RS),))
MK=pd.DataFrame(cur.fetchall(),columns='market_id event_id ev mty mt'.split()); MK['off']=secs(MK.mt)
n0=len(MK); MK=MK.sort_values('market_id').drop_duplicates(['event_id','mty']); MK['w']=[window(o) for o in MK.off]
print(f"markets on the tape {n0}, second ids dropped {n0-len(MK)}, outside both windows {int(MK.w.isna().sum())}",flush=True); MK=MK[MK.w.notna()]
E1=MK.drop_duplicates('event_id'); print("events by window:",E1.groupby('w').size().to_dict(),"by month:",E1.groupby(pd.to_datetime(E1.mt,utc=True).dt.strftime('%Y-%m')).size().to_dict(),f"{time.time()-T0:.0f}s",flush=True)
print("markets by type and window:",MK.groupby(['mty','w']).size().to_dict(),flush=True)
SK=Counter(); rows=[]; evs=list(MK.event_id.unique()); MKE={e:g for e,g in MK.groupby('event_id')}
def ent_of(x,r,k):
    o=float(r.off); ent={}
    for s,y in x.groupby('sel',sort=False):
        if s not in RS[r.market_id]: SK['print on a runner with no result']+=1; continue
        ts,px=y.tt.values,y.ltp.values; i=last_in(ts,o-1200,o-120)
        if i is None: SK[k+' no print in window']+=1; continue
        ent[s]=(ts,px,i,bool(RS[r.market_id][s]))
    return ent
for c0 in range(0,len(evs),1500):
    ch=evs[c0:c0+1500]; ms=[r for e in ch for r in MKE[e].market_id]
    P=pd.read_sql("SELECT market_id,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s) AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND ts>=market_time-interval '60 minutes'",con,params=(ms,))
    P['tt']=secs(P.ts); P=P.drop_duplicates(['market_id','sel','tt']).sort_values('tt',kind='stable'); PX={k:g for k,g in P.groupby('market_id')}; del P
    for e in ch:
        g=MKE[e]; ev=g.ev.iloc[0]; off=float(g.off.iloc[0]); w=g.w.iloc[0]; home,_x,away=ev.partition(' v '); mo_=g[g.mty=='MATCH_ODDS']
        if not len(mo_): SK['no MO market, game dropped']+=1; continue
        x0=PX.get(mo_.market_id.iloc[0]); o0=float(mo_.off.iloc[0])
        liqv=int(((x0.tt>=o0-3600)&(x0.tt<o0-1200)).sum()) if x0 is not None else 0
        grp=grp_of(group(ev),liqv)
        fav=dog=hf=None
        if x0 is not None:
            em=ent_of(x0,next(mo_.itertuples()),'MO'); pr=mo_pair(home,away,list(em))
            if pr:
                hf=float(em[pr[0]][1][em[pr[0]][2]])<=float(em[pr[1]][1][em[pr[1]][2]]); fav,dog=(pr[0],pr[1]) if hf else (pr[1],pr[0])
        def add(item,g_,nm,en):
            ts,px,i,won=en
            for side in 'BL':
                p=fill(ts,px,i,side)
                if p>50: SK['over 50, not traded']+=1; continue
                v=bk(p,won) if side=='B' else ly(p,won)
                if v is None: SK['bottom of ladder, no back']+=1; continue
                rows.append((item,e,w,g_,off,nm,side,p,won,v))
        for r in g.itertuples():
            k=TYPES[r.mty]; x=PX.get(r.market_id)
            if x is None: SK[k+' no pre-off print']+=1; continue
            ent=ent_of(x,r,k)
            if k=='MO':
                if fav is not None:
                    if fav in ent: add(163,grp,'MO FAV',ent[fav])
                    if dog in ent: add(163,grp,'MO DOG',ent[dog])
                if 'The Draw' in ent: add(163,grp,'MO DRAW',ent['The Draw'])
            elif k=='BTTS':
                for s in ent:
                    if str(s).strip().lower() in ('yes','no'): add(163,grp,'BTTS '+str(s).strip().title(),ent[s])
            elif r.mty in LINES:
                for s in ent:
                    sl=str(s).strip().lower()
                    if sl.startswith(('over','under')): add(163,grp,f"{k} {sl.split()[0].title()}",ent[s])
            elif k in ('HT','DNB'):
                pair=mo_pair(home,away,list(ent))
                if pair:
                    fh=float(ent[pair[0]][1][ent[pair[0]][2]])<=float(ent[pair[1]][1][ent[pair[1]][2]]); add(163,grp,k+' FAV',ent[pair[0] if fh else pair[1]]); add(163,grp,k+' DOG',ent[pair[1] if fh else pair[0]])
                else: SK[k+' teams not both priced or matched']+=1
                if 'The Draw' in ent: add(163,grp,k+' DRAW',ent['The Draw'])
            else:
                if fav is None: SK[k+' no MO favourite at entry']+=1; continue
                for s in ent:
                    lab=htft(s,fav,dog) if k=='HTFT' else dc(s,hf) if k=='DC' else hts(s,hf)
                    if lab is None: SK[k+' runner not mapped']+=1; continue
                    add(164,'ALL',f"{k} {lab}",ent[s])
    del PX
    print(f"  events {min(c0+1500,len(evs))} of {len(evs)}, rows {len(rows):,}, {time.time()-T0:.0f}s",flush=True)
con.close()
print("counted:",dict(sorted(SK.items())),flush=True)
R=pd.DataFrame(rows,columns='item e w g off nm side p won v'.split()); del rows
assert not R.duplicated(['item','e','g','nm','side']).any()
def tab(x):
    md=np.median(x.off.values); l=line(x.v.values,np.where(x.off<md,1,2))
    return dict(n=l['n'],games=x.e.nunique(),per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],won=x.won.mean(),imp=(1/x.p).mean(),PASS=l['PASS'])
out=[]
for k,x in R.groupby(['item','w','g','nm','side']): out.append(dict(item=k[0],w=k[1],g=k[2],sel=k[3],side=k[4],**tab(x)))
O=pd.DataFrame(out); F=O[O.w=='F'].set_index(['item','g','sel','side']); T=O[O.w=='T'].set_index(['item','g','sel','side'])
J=F.join(T,lsuffix='_f',rsuffix='_t',how='outer')
SURV=[]
for it,x in J.reset_index().groupby('item'):
    b=x[(x.n_f>=50)&(x.n_t>=50)]; rho=spearmanr(b.per10_f,b.per10_t) if len(b)>2 else None
    print(f"\n== item {it}: lines {len(x)}; n>=50 in both windows {len(b)}; Spearman per10 fit v test {rho.statistic:.3f} (p {rho.pvalue:.3f}); fit positive {int((b.per10_f>0).sum())}, test positive {int((b.per10_t>0).sum())}, both {int(((b.per10_f>0)&(b.per10_t>0)).sum())}",flush=True)
    top=x[x.n_f>=100].sort_values('t_f',ascending=False).head(10)
    print("SCORED, the 10 best by fit t, read on Oct 2024:"); print(top[['g','sel','side','n_f','per10_f','t_f','n_t','games_t','per10_t','t_t','h1_t','h2_t','won_t','imp_t','PASS_t']].round(3).to_string(index=False))
    SURV.append(top[top.PASS_t==True])
    print("context, not scored: top 8 on Oct 2024 by t, n>=100"); print(x[x.n_t>=100].sort_values('t_t',ascending=False).head(8)[['g','sel','side','n_t','games_t','per10_t','t_t','h1_t','h2_t','won_t','imp_t','n_f','per10_f','t_f']].round(3).to_string(index=False))
    print("worst 3 on Oct 2024, n>=100"); print(x[x.n_t>=100].sort_values('t_t').head(3)[['g','sel','side','n_t','per10_t','t_t','n_f','per10_f','t_f']].round(3).to_string(index=False))
y=J.reset_index(); y=y[(y.item==163)&(y.g=='YOUTH')&(y.sel=='OU25 Over')&(y.side=='L')]
print("\n== item 147, the one scored line: YOUTH OU25 Over lay, Oct 2024"); print(y[['n_f','per10_f','t_f','n_t','games_t','per10_t','t_t','n1_t','h1_t','n2_t','h2_t','won_t','imp_t','PASS_t']].round(3).to_string(index=False))
S=pd.concat(SURV+[y[y.PASS_t==True]])
print(f"\n== SURVIVORS: {len(S)}\n",S[['item','g','sel','side','n_t','games_t','per10_t','t_t','h1_t','h2_t']].round(3).to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
