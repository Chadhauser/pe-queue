#!/bin/bash
set -o pipefail
# 499_player_corner_markets (Finder 2026-11-05, queue item 74): player, corner, card and HT/FT markets on the loaded months, Aug-Sep 2026, read-only. Rules fixed before any price was read.
# NOT the item's seven seasons: only Jul-Sep 2026 of these markets are loaded (Soccer back to 2019 is days away), so this is a SCREEN: halves by median market date, no fit/score split. Aug is still loading as this runs.
# PRINTS ONLY, these books are thin: a pass is an upper bound and would earn a real-touch check on player_liq (item 52), no more.
# ENTRY: PRE first non-in-play print T-30 min to the off; EARLY first print T-6 h to T-60 min (before team sheets, publication proxy). Worse of that print and the next within 120 s. One tick adverse, 2%, £10 risk, hold to result. Over 200 not traded, a back filling at 1.01 no bet, both counted.
# RESULTS: af_fixtures status FT only (AET has no 90-minute split here). Goals by player from af_player_stats, only where their sum plus own goals equals hg+ag. Cards, first goal: af_events. Corners: af_stats.
# ASSUMED, the market rules are NOT on this box, from memory: a player who does not take part is void. So minutes 0 = void; a runner not found in the squad = not traded, counted. Backs also shown with those charged at -10 ("back lost"), and a back line must survive that.
# FGS: own goals do not count; a game with only own goals is not traded. A player with too few minutes to have been on at the first goal is void, which removes lay winners, so it is the cautious side. Booking points 10 yellow, 25 red, cap 35 a player. Cards count Y+R. af_events can hold a card shown off the pitch.
# t is by entry, and many runners share a game: tg is t on per-game sums, read that one. Long-price lays have few losers, so their t is weak.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,re,unicodedata,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,back_settle,lay_settle,tstat,passes,norm,loose
import lib_cand; lib_cand._checks()
pd.set_option('display.width',230); pd.set_option('display.max_rows',200); pd.set_option('display.max_columns',30)
T0=time.time()
def pnl(side,p,won):
    if side=='B':
        a=step(p,-1)
        return np.nan if a<=1.01 else back_settle(a,won)
    return lay_settle(step(p,1),won)
def toks(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
    return [w for w in re.sub(r"[^a-z ]"," ",s).split() if w]
def same(a,b):
    """2 same words; 1 same surname and first initial; 0 no. Betfair 'Erling Haaland' v API-Football 'E. Haaland'."""
    x,y=toks(a),toks(b)
    if not x or not y: return 0
    if set(x)==set(y): return 2
    if len(x)>=2 and len(y)>=2 and x[-1]==y[-1] and x[0][0]==y[0][0]: return 1
    return 0
def find(name,squad):
    """The one squad name that matches best; None if none or a tie."""
    sc=[(same(name,p),p) for p in squad]; top=max([s for s,_ in sc],default=0)
    if top==0: return None
    best=[p for s,p in sc if s==top]
    return best[0] if len(best)==1 else None
def band(p,edges):
    lo=None
    for hi in edges:
        if p<=hi: return (f"<={hi}" if lo is None else f"{lo}-{hi}")
        lo=hi
    return f"{lo}+"
def booking(cards):
    """cards: (player,'Y' or 'R'). 10 a yellow, 25 a red, cap 35 a player."""
    d=defaultdict(int)
    for p,c in cards: d[p]+=10 if c=='Y' else 25
    return sum(min(v,35) for v in d.values())
assert abs(pnl('B',2.0,True)-10*0.99*0.98)<1e-9 and pnl('L',6.0,True)==-10.0 and abs(pnl('L',6.0,False)-10/5.2*0.98)<1e-9
assert same('Erling Haaland','E. Haaland')==1 and same('Joao Pedro','João Pedro')==2 and same('Erling Haaland','Erik Haaland')==1 and same('Harry Kane','H. Maguire')==0 and same('Raphinha','Raphinha')==2
assert find('Erling Haaland',['E. Haaland','P. Foden'])=='E. Haaland' and find('J. Silva',['Joao Silva','Jose Silva']) is None and find('Nobody',['A. B']) is None
assert band(1.5,[2,3])=='<=2' and band(2.5,[2,3])=='2-3' and band(3.5,[2,3])=='3+' and band(2,[2,3])=='<=2'
assert booking([('a','Y')])==10 and booking([('a','Y'),('a','R')])==35 and booking([('a','R'),('b','Y'),('c','Y')])==45 and booking([('a','Y'),('a','Y'),('a','R')])==35
print("known-answer checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
FROM,TO='2026-08-01','2026-10-01'
FX=pd.read_sql(f"SELECT fixture_id,kickoff,home,away,hg,ag,ht_hg,ht_ag FROM af_fixtures WHERE kickoff>='{FROM}' AND kickoff<'{TO}' AND status='FT' AND hg IS NOT NULL",con)
FX['k']=pd.to_datetime(FX.kickoff,utc=True); FX=FX.sort_values('k').reset_index(drop=True); FX['H']=FX.home.map(norm); FX['A']=FX.away.map(norm); kt=FX.k.values.astype('datetime64[ns]')
ids=[int(x) for x in FX.fixture_id]
PS=pd.read_sql("SELECT fixture_id,team,player,COALESCE(minutes,0) minutes,COALESCE(goals,0) goals,position FROM af_player_stats WHERE fixture_id=ANY(%s)",con,params=(ids,))
EV=pd.read_sql("SELECT fixture_id,minute,COALESCE(extra,0) extra,type,detail,player FROM af_events WHERE fixture_id=ANY(%s) AND (type='Card' OR type='Goal')",con,params=(ids,))
ST=pd.read_sql("SELECT fixture_id,sum(corners) c,count(corners) k FROM af_stats WHERE fixture_id=ANY(%s) GROUP BY 1",con,params=(ids,))
COR={int(r.fixture_id):int(r.c) for r in ST.itertuples() if r.k==2}
SQ={k:x for k,x in PS.groupby('fixture_id')}; EVD={k:x for k,x in EV.groupby('fixture_id')}
SK=Counter(); Res={}
for r in FX.itertuples():
    fx=int(r.fixture_id); e=EVD.get(fx); s=SQ.get(fx)
    d=dict(fx=fx,hg=int(r.hg),ag=int(r.ag),ht=(r.ht_hg,r.ht_ag),corners=COR.get(fx),home=r.home)
    if s is None: SK['fixture: no player stats']+=1; d['squad']=None; Res[fx]=d; continue
    pl={}
    for p in s.itertuples():
        o=pl.get(p.player)
        if o is None: pl[p.player]=dict(min=int(p.minutes),g=int(p.goals),pos=p.position,home=(p.team==r.home))
        else: o['min']=max(o['min'],int(p.minutes)); o['g']=max(o['g'],int(p.goals))
    d['squad']=pl; names=list(pl)
    own=0 if e is None else int(((e.type=='Goal')&(e.detail=='Own Goal')).sum())
    d['goals_ok']=sum(v['g'] for v in pl.values())+own==r.hg+r.ag
    SK['fixture: player goals reconcile' if d['goals_ok'] else 'fixture: player goals do NOT reconcile, not traded']+=1
    d['first']=None; d['first_min']=None; d['fgs_ok']=False; d['cards']=[]; d['card_bad']=0
    if e is not None:
        g=e[(e.type=='Goal')&(e.detail.isin(['Normal Goal','Penalty']))].assign(tm=lambda x:x.minute.astype(float)+x.extra.astype(float)).sort_values('tm')
        if len(g):
            a=find(g.player.iloc[0],names)
            if a is not None and not (len(g)>1 and g.tm.iloc[0]==g.tm.iloc[1]): d['first']=a; d['first_min']=float(g.tm.iloc[0]); d['fgs_ok']=True
        else: d['fgs_ok']=(r.hg+r.ag==0)
        for c in e[e.type=='Card'].itertuples():
            a=find(c.player,names) if c.player is not None else None
            if a is None: d['card_bad']+=1; d['cards'].append((f'?{c.player}','Y' if 'Yellow' in str(c.detail) else 'R')); continue
            d['cards'].append((a,'Y' if 'Yellow' in str(c.detail) else 'R'))
    else: d['fgs_ok']=(r.hg+r.ag==0)
    Res[fx]=d
print(f"fixtures FT {len(FX)}, {dict(SK)}, corners {len(COR)}, {time.time()-T0:.0f}s",flush=True)
TY=['TO_SCORE','FIRST_GOAL_SCORER','TO_SCORE_2_OR_MORE','TO_SCORE_HATTRICK','SHOWN_A_CARD','CORNER_ODDS','BOOKING_ODDS','OVER_UNDER_25_CARDS','OVER_UNDER_35_CARDS','HALF_TIME_FULL_TIME']
P=pd.read_sql(f"SELECT market_id,market_type,event_name,market_time,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type=ANY(%s) AND market_time>='{FROM}' AND market_time<'{TO}' AND NOT inplay AND ltp>=1.01 AND ltp<1000",con,params=(TY,))
P['mt']=pd.to_datetime(P.market_time,utc=True); P['tt']=(pd.to_datetime(P.ts,utc=True)-pd.Timestamp('1970-01-01',tz='UTC'))/pd.Timedelta(seconds=1); P['off']=(P.mt-pd.Timestamp('1970-01-01',tz='UTC'))/pd.Timedelta(seconds=1)
P=P.sort_values(['market_id','sel','tt'],kind='stable')
print(f"prints {len(P):,}, markets {P.market_id.nunique():,}, {time.time()-T0:.0f}s",flush=True)
print(P.groupby('market_type').market_id.nunique().to_string(),flush=True)
def match(ev,mt):
    h,_,a=str(ev).partition(' v ')
    lo=np.searchsorted(kt,np.datetime64((mt-pd.Timedelta(minutes=20)).tz_convert(None))); hi=np.searchsorted(kt,np.datetime64((mt+pd.Timedelta(minutes=20)).tz_convert(None)),side='right')
    return loose(norm(h),norm(a),[(r.H,r.A,int(r.fixture_id)) for r in FX.iloc[lo:hi].itertuples()])
Mp={}
for (ev,mt),_ in P.groupby(['event_name','mt'],sort=False): Mp[(ev,mt)]=match(ev,mt)
print(f"events {len(Mp)}, matched {sum(v is not None for v in Mp.values())}",flush=True)
Bands={'TO_SCORE':[2,3,4,6,10,20],'FIRST_GOAL_SCORER':[6,10,15,25,50],'TO_SCORE_2_OR_MORE':[5,10,20,50],'TO_SCORE_HATTRICK':[20,50,100],'SHOWN_A_CARD':[2.5,3.5,5,8],'HALF_TIME_FULL_TIME':[5,10,20,50]}
HTFT_LAB={('H','H'),('H','D'),('H','A'),('D','H'),('D','D'),('D','A'),('A','H'),('A','D'),('A','A')}
def res1x2(h,a): return 'H' if h>a else 'A' if h<a else 'D'
rows=[]
def add(mty,tag,e,side,p,won,g,mtt,sel):
    """won: did the selection win."""
    if p>200: SK[mty+': over 200, not traded']+=1; return
    v=pnl(side,p,won)
    if np.isnan(v): SK[mty+': back fills at 1.01, no bet']+=1; return
    rows.append((mty,tag,e,side,g,mtt,p,bool(won),v,sel))
void=[]
for (mid,mty,ev,mt,sel),y in P.groupby(['market_id','market_type','event_name','mt','sel'],sort=False):
    fx=Mp.get((ev,mt))
    if fx is None: SK[mty+': event not matched, runner-markets']+=1; continue
    d=Res[fx]; off=y.off.iloc[0]; ts=y.tt.values; px=y.ltp.values
    ents={}
    i=np.where((ts>=off-1800)&(ts<=off))[0]
    if len(i): ents['PRE']=i[0]
    i=np.where((ts>=off-21600)&(ts<off-3600))[0]
    if len(i): ents['EARLY']=i[0]
    if not ents: SK[mty+': no print in either window']+=1; continue
    tags=[]; won=None; vd=False
    if mty in ('TO_SCORE','TO_SCORE_2_OR_MORE','TO_SCORE_HATTRICK','FIRST_GOAL_SCORER','SHOWN_A_CARD'):
        if d.get('squad') is None: SK[mty+': no squad']+=1; continue
        if mty=='FIRST_GOAL_SCORER' and sel=='No Goalscorer':
            if d['hg']+d['ag']>0 and d['first'] is None: SK[mty+': first goal unknown']+=1; continue
            won=d['hg']+d['ag']==0; tags=['No Goalscorer']
        else:
            a=find(sel,list(d['squad']))
            if a is None: SK[mty+': runner not in squad, not traded']+=1; continue
            u=d['squad'][a]
            if u['min']<=0: SK[mty+': minutes 0, void']+=1; vd=True
            if mty=='FIRST_GOAL_SCORER':
                if not d['fgs_ok']: SK[mty+': first goal unknown']+=1; continue
                won=(a==d['first'])
                if not vd and not won and d['first_min'] is not None and u['min']<90-d['first_min']-5: SK[mty+': came on after first goal, void']+=1; vd=True
            elif mty=='SHOWN_A_CARD':
                if d.get('card_bad',0)>0: SK[mty+': card not matched to a player, not traded']+=1; continue
                won=any(c[0]==a for c in d['cards'])
            else:
                if not d.get('goals_ok'): SK[mty+': goals not reconciled']+=1; continue
                need={'TO_SCORE':1,'TO_SCORE_2_OR_MORE':2,'TO_SCORE_HATTRICK':3}[mty]; won=u['g']>=need
            tags=['ALL',f"POS {u['pos']}",'HOME' if u['home'] else 'AWAY']
    elif mty=='CORNER_ODDS':
        if d['corners'] is None: SK[mty+': no corners']+=1; continue
        c=d['corners']; t=str(sel).strip()
        if t=='9 or less': won=c<=9
        elif t=='10 - 12': won=10<=c<=12
        elif t=='13 or more': won=c>=13
        else: SK[mty+': unknown runner']+=1; continue
        tags=[t]
    elif mty=='BOOKING_ODDS':
        if not d.get('squad') or d.get('card_bad',0)>0: SK[mty+': cards not usable']+=1; continue
        b=booking(d['cards']); t=str(sel).strip()
        if t=='25pts and Under': won=b<=25
        elif t=='30 - 40pts': won=30<=b<=40
        elif t=='45pts and Over': won=b>=45
        else: SK[mty+': unknown runner']+=1; continue
        tags=[t]
    elif mty in ('OVER_UNDER_25_CARDS','OVER_UNDER_35_CARDS'):
        if not d.get('squad') or d.get('card_bad',0)>0: SK[mty+': cards not usable']+=1; continue
        c=len(d['cards']); ln=2.5 if '25' in mty else 3.5; t=str(sel).lower()
        if t.startswith('over'): won=c>ln; tags=['OVER']
        elif t.startswith('under'): won=c<ln; tags=['UNDER']
        else: SK[mty+': unknown runner']+=1; continue
    else:
        hn,_,an=str(ev).partition(' v '); xs=str(sel).split('/')
        if len(xs)!=2 or d['ht'][0] is None or d['ht'][0]!=d['ht'][0]: SK[mty+': no HT or unknown runner']+=1; continue
        mp={hn.strip():'H',an.strip():'A','Draw':'D'}; a,b=mp.get(xs[0].strip()),mp.get(xs[1].strip())
        if a is None or b is None: SK[mty+': runner name unread']+=1; continue
        won=(a==res1x2(d['ht'][0],d['ht'][1]) and b==res1x2(d['hg'],d['ag'])); tags=[a+'/'+b]
    for e,i in ents.items():
        for side in 'BL':
            p=float(px[i])
            if i+1<len(ts) and ts[i+1]-ts[i]<=120: p=max(p,float(px[i+1])) if side=='L' else min(p,float(px[i+1]))
            bt=[]
            if mty in Bands and tags[0] not in ('No Goalscorer',): bt=['P '+band(p,Bands[mty])]
            tg=tags+bt if e=='PRE' else [tags[0]]+bt
            for tag in tg:
                if vd:
                    if side=='B' and p<=200: void.append((mty,tag,e,fx))   # void runner: no P&L, but charged -10 in the back check
                    continue
                add(mty,tag,e,side,p,won,fx,off,sel)
if not rows: sys.exit('no rows: a code fault')
R=pd.DataFrame(rows,columns='mty tag e side g mt p won v sel'.split())
print(f"rows {len(R):,}, games {R.g.nunique()}, {time.time()-T0:.0f}s",flush=True)
print('counted, not traded:',dict(sorted(SK.items())),flush=True)
# settle checks a reader can eyeball: implied v won on all-runner lines, backs
print("== entries by market month, as Aug is still loading"); print(R[(R.side=='B')&(R.tag.isin(['ALL','No Goalscorer','9 or less','10 - 12','13 or more','25pts and Under','30 - 40pts','45pts and Over','OVER','UNDER'])|R.tag.str.contains('/'))].assign(mo=lambda x:pd.to_datetime(x.mt,unit='s').dt.strftime('%Y-%m')).groupby(['mty','mo']).size().unstack(fill_value=0).to_string())
print("== hand check: scorers from af_events v runners the job settled as won, TO_SCORE PRE")
_c=R[(R.mty=='TO_SCORE')&(R.tag=='ALL')&(R.e=='PRE')&(R.side=='B')]
for g in sorted(_c[_c.won].g.unique())[:3]:
    _r=FX[FX.fixture_id==g].iloc[0]; _e=EVD[g]; _gl=_e[(_e.type=='Goal')&(_e.detail.isin(['Normal Goal','Penalty','Own Goal']))]
    print(f"  {_r.home} {_r.hg}-{_r.ag} {_r.away} | scorers {[f'{a} ({b})' for a,b in zip(_gl.player,_gl.detail)]} | won {sorted(_c[(_c.g==g)&_c.won].sel)} | lost {len(_c[(_c.g==g)&~_c.won])}")
_v=list(COR.values()); _t=[COR[g] for g in R[R.mty=='CORNER_ODDS'].g.unique() if g in COR]
print(f"== corners base rate: all FT games n {len(_v)} 9 or less {np.mean([c<=9 for c in _v]):.3f}, 10-12 {np.mean([10<=c<=12 for c in _v]):.3f}, 13+ {np.mean([c>=13 for c in _v]):.3f}; games with a corner market n {len(_t)} 9 or less {np.mean([c<=9 for c in _t]):.3f}")
print("== implied v won, PRE back fills (a book that sums over 100% should read implied a little over won)")
for k,x in R[(R.e=='PRE')&(R.side=='B')&(R.tag.isin(['ALL','No Goalscorer','9 or less','10 - 12','13 or more','25pts and Under','30 - 40pts','45pts and Over','OVER','UNDER','H/H','D/D','A/A']))].groupby(['mty','tag']):
    print(f"  {k[0]:22s} {k[1]:16s} n {len(x):6,d} games {x.g.nunique():5d} implied {(1/x.p).mean():.3f} won {x.won.mean():.3f}")
out=[]; med={}; VC=Counter(void)
VG=defaultdict(int)
for (a,b,c,_),k in VC.items(): VG[(a,b,c)]+=k
for (mty,tag,e,side),x in R.groupby(['mty','tag','e','side']):
    m=med.setdefault(mty,R[R.mty==mty].groupby('g').mt.first().median())
    a=x[x.mt<=m].v; b=x[x.mt>m].v
    gs=x.groupby('g').v.sum(); tg=tstat(gs.values)
    n,t=len(x),tstat(x.v.values)
    nv=VG[(mty,tag,e)] if side=='B' else 0; vl=(x.v.sum()-10*nv)/(n+nv)   # back check: void runners charged at -10
    out.append(dict(mkt=mty,line=tag,ent=e,side=side,vlost=round(vl,3),n=n,games=x.g.nunique(),per10=round(x.v.mean(),3),t=round(t,2),tg=round(tg,2),n1=len(a),h1=round(a.mean(),3) if len(a) else np.nan,n2=len(b),h2=round(b.mean(),3) if len(b) else np.nan,won=round(x.won.mean(),3),impl=round((1/x.p).mean(),3),PASS=passes(n,len(a),len(b),t,a.mean() if len(a) else -1,b.mean() if len(b) else -1,x.v.mean())))
O=pd.DataFrame(out).sort_values('t',ascending=False)
# CLEAN, on top of the standard PASS: t on per-game sums also >= 3.5, at least one losing trade so t means something, a back still >= +0.15 with voids charged.
O['CLEAN']=O.PASS&(O.tg>=3.5)&(np.where(O.side=='L',O.won,1-O.won)>0)&(O.vlost>=0.15)
O['noloser']=np.where(O.side=='L',O.won==0,O.won==1)
print("== lines with no losing trade: their t is void and not ranked",int(O.noloser.sum()))
print(f"== lines {len(O)}, at n>=300 {(O.n>=300).sum()}, numeric PASS {O.PASS.sum()}, CLEAN {O.CLEAN.sum()}, chance t>=1.65 about {0.05*len(O):.0f}")
print("== top 15 by t, lines with a loser"); print(O[~O.noloser].head(15).drop(columns='noloser').to_string(index=False),flush=True)
print("== top 3 by t, each market");
for k,x in O[~O.noloser].groupby('mkt'): print(x.head(3).drop(columns='noloser').to_string(index=False,header=False))
print("== biggest money lines n>=300 by per10"); print(O[O.n>=300].sort_values('per10',ascending=False).head(10).to_string(index=False))
print("== SURVIVORS (standard PASS; read CLEAN too)"); S=O[O.PASS]
print(S.to_string(index=False) if len(S) else "none",flush=True)
print(f"done {time.time()-T0:.0f}s")
PY
