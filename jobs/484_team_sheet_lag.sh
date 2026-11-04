#!/bin/bash
set -o pipefail
# 484 (Finder 2026-11-04, queue item 0d): TEAM-SHEET LAG. Does the favourite's price move late when a key scorer is left out?
# DATA: af_lineups (already loaded by 329/332: 0 API calls here), af_events + af_fixtures (season of the fixture, goals strictly BEFORE its kick-off), stream_ticks football MO_PRE (the only pre-match touch on the box: liq_sample has no minute<0 rows, feed starts about T-2h, table rolls at about 4 days).
# PROXY: publication time cannot be recovered, so T-60 is the publication proxy, as the item says. T-45 and T-30 entries are the safer test of "already public"; a T-60 entry assumes you read the sheet the moment it appears.
# KEY PLAYERS: the team's top 3 scorers this season (own goals and missed penalties excluded, ties by name), with >= 2 goals, team with >= 5 prior league games.
# IDENTITY: af_lineups.player_id. af_events has names only, and one man has several spellings across fixtures, so a scorer resolves to the unique id at the club whose spellings match (exact, else same surname + compatible initial); goals are summed by id. Any key scorer not resolved -> team status UNKNOWN, excluded from BOTH missing and full, counted. This also drops long-term absentees who left no line-up rows since 13 Oct; they would be priced in anyway.
# FIRST RUN VOID: it compared one spelling with the XI, so Haaland was "absent" from a game he scored in (35 absent-but-scored, jobs/486). Job 486 is the label test; with ids it reads 0.
# GROUPS: MISSING = a resolved key scorer not in the XI. SURPRISE = MISSING and that player started the team's previous fixture (the real news). TOP1 = the top scorer himself is out. FULL = all key scorers start.
# FAVOURITE: shorter of home/away by back_px at T-90, before any sheet is public. No look-ahead in the choice.
# PRICES: mid of a real two-sided book. An anchor at T-X is the last tick at or before T-X, no older than 300 s, else no reading (counted), never carried further.
# TRADES (one per game): favourite out -> LAY the favourite at lay_px +1 tick (£10 liability); opponent out -> BACK the favourite at back_px -1 tick (£10 stake). Exit at the last pre-off tick at the opposite touch, 1 tick adverse. 2% commission on profit. Entry book must exist at T-X; if there is no later tick the trade exits at its own entry book. Pre-off positions do not settle, so the settled-market rule has nothing to act on.
# PASS: standard filter, n>=300, n>=150 per half, both halves > 0, t>=3.5, mean>=+£0.15. Halves split at the kick-off date of the median game.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,re,time,unicodedata,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
warnings.filterwarnings('ignore')
pd.set_option('display.width',230); pd.set_option('display.max_rows',80); pd.set_option('display.max_columns',30)
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
LAD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    x=lo
    while x<hi-1e-9: LAD.append(round(x,2)); x+=st
LAD.append(1000.0); LAD=np.array(LAD)
def dn(p): return float(LAD[max(int(np.searchsorted(LAD,round(p,2)-1e-9))-1,0)])
def up(p): return float(LAD[min(int(np.searchsorted(LAD,round(p,2)-1e-9))+1,len(LAD)-1)])
def comm(x): return x*0.98 if x>0 else x
def back_trade(bp0,lp1):
    if bp0<=1.01: return None
    return comm(10*(dn(bp0)/up(lp1)-1))
def lay_trade(lp0,bp1):
    a=up(lp0); c=max(1.01,dn(bp1)); return comm(10/(a-1)*(1-a/c))
def pname(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
    return [w for w in re.sub(r"[^a-z ]"," ",s).split() if w]
def same_player(a,b):
    A,B=pname(a),pname(b)
    if not A or not B: return False
    if A==B: return True
    if A[-1]!=B[-1]: return False
    if len(A)==1 or len(B)==1: return True          # mononym v full name, same last token
    return A[0][0]==B[0][0]
def resolve_id(scorer,idn):
    """idn: {player_id: set of spellings}. Unique id for a scorer, or None if absent or ambiguous."""
    ex=[i for i,ns in idn.items() if any(pname(n)==pname(scorer) for n in ns)]
    if len(ex)==1: return ex[0]
    if len(ex)>1: return None
    m=[i for i,ns in idn.items() if any(same_player(scorer,n) for n in ns)]
    return m[0] if len(m)==1 else None
def key_ids(names,idn,k=2):
    """names: one per goal. Top 3 by goals summed by id, ties by id; an unresolved name stays as ('?',name)."""
    c=Counter()
    for n,g in Counter(names).items():
        i=resolve_id(n,idn); c[i if i is not None else ('?',n)]+=g
    return [p for p,g in sorted(c.items(),key=lambda kv:(-kv[1],str(kv[0])))[:3] if g>=k]
def team_status(key,xi_ids,prev_ids):
    """key: ids in rank order. Returns (status, surprise, top1_out)"""
    if not key or any(isinstance(k,tuple) for k in key): return 'UNKNOWN',False,False
    out=[k for k in key if k not in xi_ids]
    if not out: return 'FULL',False,False
    return 'MISSING',bool(prev_ids) and any(k in prev_ids for k in out),key[0] in out
def anchor(sto,x,maxage=300):
    """index of the last tick at or before T-x (sto descending in time order), or None if none or older than maxage"""
    idx=np.where(sto>=x)[0]
    if len(idx)==0: return None
    i=idx[-1]
    return int(i) if sto[i]-x<=maxage else None
def mid(b,l): return (b+l)/2
def tstat(v):
    v=np.asarray(v,dtype=float)
    return float(v.mean()/(v.std(ddof=1)/np.sqrt(len(v)))) if len(v)>1 and v.std(ddof=1)>0 else 0.0
def welch(a,b):
    a,b=np.asarray(a,float),np.asarray(b,float)
    if len(a)<2 or len(b)<2: return 0.0
    s=np.sqrt(a.var(ddof=1)/len(a)+b.var(ddof=1)/len(b))
    return float((a.mean()-b.mean())/s) if s>0 else 0.0
# known answers, worked by hand
assert dn(2.0)==1.99 and up(2.0)==2.02 and up(1.99)==2.0 and dn(3.0)==2.98 and up(3.0)==3.05
assert abs(back_trade(5.0,4.0)-1.912195)<1e-6             # 10*(4.9/4.1-1)=1.951220, less 2%
assert abs(back_trade(2.0,2.02)+0.245098)<1e-6            # 10*(1.99/2.04-1), a loss so no commission
assert abs(lay_trade(5.0,6.0)-0.324101)<1e-6              # 2.439024*(1-5.1/5.9)=0.330715, less 2%
assert abs(lay_trade(2.0,1.5)-(10/1.02*(1-2.02/1.49)))<1e-9
assert back_trade(1.01,1.5) is None
assert same_player('M. Salah','Mohamed Salah') and not same_player('M. Salah','Luis Salah') and same_player('Vinícius Júnior','Vinicius Junior') and same_player('Rodri','Rodrigo Rodri')
_i={1:{'L. Vallejo','Luciano Vallejo'},2:{'J. Silva','Joao Silva'},3:{'J. Silva','Jose Silva'},4:{'E. Godoy','É. Godoy'}}
assert resolve_id('Luciano Vallejo',_i)==1 and resolve_id('L. Vallejo',_i)==1
assert resolve_id('Joao Silva',_i)==2 and resolve_id('J. Silva',_i) is None and resolve_id('Nobody Else',_i) is None   # ambiguous must not resolve
assert resolve_id('É. Godoy',_i)==4 and resolve_id('E. Godoy',_i)==4                # two spellings, one id: not ambiguous
assert key_ids(['L. Vallejo','Luciano Vallejo','Joao Silva'],_i)==[1]                 # spellings summed: id 1 has 2 goals, id 2 only 1
assert key_ids(['Nobody Else','Nobody Else'],_i)==[('?','Nobody Else')]
assert team_status([1,2],{1,2},{1})==('FULL',False,False)
assert team_status([1,2],{2},{1})==('MISSING',True,True)                              # started last game, out today, top scorer
assert team_status([1,2],{1},{3})==('MISSING',False,False)                            # second scorer out, did not start last game
assert team_status([1,2],{1},set())==('MISSING',False,False)                          # no previous sheet: surprise is not claimed
assert team_status([1,('?','Zed')],{5},set())==('UNKNOWN',False,False)                # unresolved never counts as missing
assert team_status([],{1},set())==('UNKNOWN',False,False)
_s=np.array([3700.,3650.,3500.,100.])
assert anchor(_s,3600)==1 and anchor(_s,3500)==2 and anchor(_s,50)==3 and anchor(_s,4000) is None
assert anchor(np.array([7000.,5000.]),3600) is None                                              # 1,400 s stale: no reading, not carried
assert abs(welch([1,2,3],[1,2,3]))<1e-12
print("known-answer checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
t0=time.time()
LU=pd.read_sql("SELECT fixture_id,team,is_home,player_id,player,starter FROM af_lineups",con)
print(f"null player_id rows {LU.player_id.isna().sum()} (their team-games fail the XI-of-11 check)",flush=True)
LU=LU[LU.player_id.notna()].drop_duplicates(['fixture_id','team','player_id']); LU['player_id']=LU.player_id.astype('int64')
print(f"af_lineups rows {len(LU)} fixtures {LU.fixture_id.nunique()} bench rows {(LU.starter==False).sum()} | API calls 0",flush=True)
F=pd.read_sql("""SELECT fixture_id,league,season,kickoff,home,away,status,events_done FROM af_fixtures WHERE kickoff>'2026-01-01' AND kickoff<now()+interval '1 day' AND status='FT'""",con)
G=pd.read_sql("""SELECT e.fixture_id,e.team,e.player,e.detail FROM af_events e JOIN af_fixtures f USING(fixture_id)
  WHERE f.kickoff>'2026-01-01' AND f.status='FT' AND e.type='Goal' AND e.detail IN ('Normal Goal','Penalty') AND e.player IS NOT NULL""",con)
G=G.merge(F[['fixture_id','kickoff','season']],on='fixture_id')
print(f"fixtures FT 2026 {len(F)} | goals {len(G)} | {int(time.time()-t0)}s",flush=True)
cur.execute("SELECT min(ts_recv),max(ts_recv) FROM stream_ticks"); r=cur.fetchone(); print("stream_ticks range:",r[0],"..",r[1],flush=True)
parts=[]
for a in pd.date_range(pd.Timestamp(r[0]).floor('6h'),pd.Timestamp(r[1]),freq='6h'):
    cur.execute("""SELECT market_id,sel,extract(epoch from ts_recv)::float8,secs_to_off::float4,back_px::float4,lay_px::float4,ltp::float4
      FROM stream_ticks WHERE ts_recv>=%s AND ts_recv<%s AND sport='football' AND mkt='MO_PRE' AND inplay=false AND status='OPEN' AND secs_to_off>=0""",(a,a+pd.Timedelta(hours=6)))
    d=pd.DataFrame(cur.fetchall(),columns=['mid','sel','ts','sto','bp','lp','ltp']); parts.append(d)
    print(f"  chunk {a}: {len(d)} ticks ({int(time.time()-t0)}s)",flush=True)
T=pd.concat(parts,ignore_index=True); n_all=len(T)
T=T.dropna(subset=['bp','lp','sto']); T=T[(T.bp>1)&(T.lp>T.bp)&(T.lp<1000)].sort_values(['mid','sel','ts'],kind='stable')
print(f"ticks {n_all}, usable touch {len(T)}, markets {T.mid.nunique()}",flush=True)
def norm(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
    s=re.sub(r"\b(fc|cf|afc|sc|ac|as|ss|us|sv|vfb|vfl|tsg|fk|club|de|the|athletic|atletico|sporting|real|cd|ud|sd|rcd|calcio|women|w|u21|u23|ii|b|if|bk|ff|aif|is|kv|sk|fsv)\b"," ",s)
    return set(w for w in re.sub(r"[^a-z0-9 ]"," ",s).split() if len(w)>2)
def sim(a,b):
    A,B=norm(a),norm(b); return len(A&B)/max(1,len(A|B))
SK=Counter()
Fx=F[F.fixture_id.isin(LU.fixture_id)].copy(); Fx['ko']=Fx.kickoff.map(lambda x:x.timestamp())
print(f"fixtures with line-ups and FT in 2026: {len(Fx)}",flush=True)
mk={}
for mid_,g in T.groupby('mid',sort=False):
    sels=[s for s in g.sel.unique()]
    teams=[s for s in sels if s.lower()!='the draw']
    if len(teams)!=2 or len(sels)!=3: SK['market not 3-way']+=1; continue
    st=float(np.median(g.ts+g.sto))
    cand=Fx[(Fx.ko-st).abs()<=900]
    best=[]
    for f in cand.itertuples():
        best.append((sim(teams[0],f.home)+sim(teams[1],f.away),f.fixture_id,teams[0],teams[1]))
        best.append((sim(teams[1],f.home)+sim(teams[0],f.away),f.fixture_id,teams[1],teams[0]))
    best.sort(key=lambda z:-z[0])
    if not best or best[0][0]<1.0: SK['market: no fixture match (other league or no line-up)']+=1; continue
    second=[b for b in best if b[1]!=best[0][1]]
    if second and best[0][0]-second[0][0]<0.3: SK['market: ambiguous fixture']+=1; continue
    mk[mid_]=dict(fixture_id=best[0][1],hsel=best[0][2],asel=best[0][3])
print(f"markets matched {len(mk)} | {dict(SK)}",flush=True)
dup=Counter(v['fixture_id'] for v in mk.values()); SK['fixtures with two markets, dropped']=sum(1 for c in dup.values() if c>1)
mk={k:v for k,v in mk.items() if dup[v['fixture_id']]==1}
# team structure
xi=defaultdict(set); idn=defaultdict(lambda:defaultdict(set)); team_games=defaultdict(list)
for r in LU.itertuples():
    idn[r.team][r.player_id].add(r.player)
    if r.starter: xi[(r.fixture_id,r.team)].add(r.player_id)
allF=F.sort_values('kickoff')
for f in allF.itertuples():
    team_games[f.home].append((f.kickoff,f.fixture_id,f.season)); team_games[f.away].append((f.kickoff,f.fixture_id,f.season))
def team_view(team,fid,ko,season):
    prior=[x for x in team_games[team] if x[0]<ko and x[2]==season]
    if len(prior)<5: return 'UNKNOWN',False,False,[],'under 5 prior games'
    if len(xi[(fid,team)])!=11: return 'UNKNOWN',False,False,[],'XI not 11'
    g=G[(G.team==team)&(G.season==season)&(G.kickoff<ko)]
    key=key_ids(list(g.player),idn[team])
    if not key: return 'UNKNOWN',False,False,[],'no scorer with 2+'
    prev=xi.get((prior[-1][1],team),set())
    s,sp,t1=team_status(key,xi[(fid,team)],prev)
    return s,sp,t1,key,('key scorer not resolved' if s=='UNKNOWN' else 'ok')
rows=[]; WIN=[(115,90),(90,60),(60,0),(45,0),(30,0),(90,0)]
for mid_,v in mk.items():
    f=Fx[Fx.fixture_id==v['fixture_id']].iloc[0]; g=T[T.mid==mid_]; R={}
    for name,s in g.groupby('sel'):
        s=s.sort_values('ts'); R[name]=(s.sto.values.astype(float),s.bp.values.astype(float),s.lp.values.astype(float))
    if v['hsel'] not in R or v['asel'] not in R: SK['runner missing']+=1; continue
    ih=anchor(R[v['hsel']][0],5400); ia=anchor(R[v['asel']][0],5400)
    if ih is None or ia is None: SK['no T-90 book on both sides']+=1; continue
    hb,ab=R[v['hsel']][1][ih],R[v['asel']][1][ia]
    if hb==ab: SK['no favourite at T-90']+=1; continue
    fav_home=hb<ab; fsel=v['hsel'] if fav_home else v['asel']; fteam=f.home if fav_home else f.away; oteam=f.away if fav_home else f.home
    fs=team_view(fteam,f.fixture_id,f.kickoff,f.season); os_=team_view(oteam,f.fixture_id,f.kickoff,f.season)
    SK['fav view: '+fs[4]]+=1; SK['opp view: '+os_[4]]+=1
    sto,bp,lp=R[fsel]; rec=dict(fid=f.fixture_id,league=f.league,day=f.kickoff.date(),fav=fteam,fav_px=float(min(hb,ab)),fav_status=fs[0],fav_surprise=fs[1],fav_top1=fs[2],opp_status=os_[0],opp_surprise=os_[1],opp_top1=os_[2],exit_age=float(sto[-1]))
    def at(x):
        i=anchor(sto,x) if x>0 else (len(sto)-1 if sto[-1]<=300 else None)
        return i
    for a,b in WIN:
        i,j=at(a*60),at(b*60)
        rec[f'd{a}_{b}']=np.nan if i is None or j is None or j<=i else 100*np.log(mid(bp[j],lp[j])/mid(bp[i],lp[i]))
    for x in (60,45,30):
        i=at(x*60)
        if i is None: rec[f'lay{x}']=np.nan; rec[f'back{x}']=np.nan; rec[f'spr{x}']=np.nan; continue
        j=len(sto)-1 if len(sto)-1>i else i   # no later tick: exit at the entry book
        rec[f'lay{x}']=lay_trade(lp[i],bp[j]); b_=back_trade(bp[i],lp[j]); rec[f'back{x}']=np.nan if b_ is None else b_
        rec[f'spr{x}']=100*(lp[i]/bp[i]-1)
    rows.append(rec)
print("counts (not hidden):",dict(SK),flush=True)
D=pd.DataFrame(rows)
if D.empty: print("ERROR: no games joined, so no verdict"); sys.exit(1)
days=sorted(D.day.unique()); md=sorted(D.day)[len(D)//2]   # median GAME, not median day: most games are at the weekend
print(f"\ngames joined {len(D)} | leagues {D.league.nunique()} | days {days[0]}..{days[-1]} | halves split at {md} | median exit age {D.exit_age.median():.0f}s | exit older than 300 s: {(D.exit_age>300).sum()}",flush=True)
GR={'FAV_MISSING':D.fav_status=='MISSING','FAV_SURPRISE':(D.fav_status=='MISSING')&D.fav_surprise,'FAV_TOP1':(D.fav_status=='MISSING')&D.fav_top1,'FAV_FULL':D.fav_status=='FULL',
    'OPP_MISSING':D.opp_status=='MISSING','OPP_SURPRISE':(D.opp_status=='MISSING')&D.opp_surprise,'OPP_TOP1':(D.opp_status=='MISSING')&D.opp_top1,'OPP_FULL':D.opp_status=='FULL',
    'FAVout_OPPfull':(D.fav_status=='MISSING')&(D.opp_status=='FULL'),'OPPout_FAVfull':(D.opp_status=='MISSING')&(D.fav_status=='FULL'),'BOTH_FULL':(D.fav_status=='FULL')&(D.opp_status=='FULL'),'ALL':pd.Series(True,index=D.index)}
print("\n== FAVOURITE PRICE DRIFT, % of mid (log), positive = favourite lengthens. Expected: FAV_* up, OPP_* down.")
out=[]
for k,m in GR.items():
    d=D[m]; row=dict(group=k,games=len(d))
    for a,b in WIN:
        c=f'd{a}_{b}'; v=d[c].dropna(); row[f'{a}>{b}']=v.mean() if len(v) else np.nan; row[f'n{a}>{b}']=len(v)
    out.append(row)
print(pd.DataFrame(out).round(2).to_string(index=False))
print("\n== LAG TEST: T-60 -> KO drift, group minus control (Welch t), and share moving >= 3% the expected way")
for k,ctl,sign in (('FAV_MISSING','FAV_FULL',1),('FAV_SURPRISE','FAV_FULL',1),('FAV_TOP1','FAV_FULL',1),('FAVout_OPPfull','BOTH_FULL',1),('OPP_MISSING','OPP_FULL',-1),('OPP_SURPRISE','OPP_FULL',-1),('OPP_TOP1','OPP_FULL',-1),('OPPout_FAVfull','BOTH_FULL',-1)):
    for w in ('d60_0','d45_0','d30_0'):
        a=D[GR[k]][w].dropna(); c=D[GR[ctl]][w].dropna()
        if len(a)<2 or len(c)<2: print(f"{k:16s} {w} n too small ({len(a)})"); continue
        print(f"{k:16s} {w:6s} n {len(a):4d} mean {a.mean():+6.2f}% v {ctl} {c.mean():+6.2f}% (n {len(c)}) diff {a.mean()-c.mean():+6.2f} t {welch(a,c):+5.2f} | moved>=3% expected way {100*(sign*a>=3).mean():4.1f}% v {100*(sign*c>=3).mean():4.1f}%")
def line(d,col,**k):
    d=d[d[col].notna()]; a=d[d.day<md][col]; c=d[d.day>=md][col]; v=d[col]
    if not len(v): return dict(**k,n=0,games=0,per10=np.nan,t=0.0,n1=0,h1=np.nan,n2=0,h2=np.nan,PASS=False)
    return dict(**k,n=len(v),games=d.fid.nunique(),per10=v.mean(),t=tstat(v),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(c),h2=c.mean() if len(c) else np.nan,PASS=len(v)>=300 and len(a)>=150 and len(c)>=150 and tstat(v)>=3.5 and a.mean()>0 and c.mean()>0 and v.mean()>=0.15)
res=[]
for k,tr in (('FAV_MISSING','lay'),('FAV_SURPRISE','lay'),('FAV_TOP1','lay'),('FAVout_OPPfull','lay'),('FAV_FULL','lay'),('BOTH_FULL','lay'),('OPP_MISSING','back'),('OPP_SURPRISE','back'),('OPP_TOP1','back'),('OPPout_FAVfull','back'),('OPP_FULL','back'),('BOTH_FULL','back'),('ALL','lay'),('ALL','back')):
    for x in (60,45,30): res.append(line(D[GR[k]],f'{tr}{x}',group=k,trade=f'{tr} fav',entry=f'T-{x}'))
R_=pd.DataFrame(res).sort_values('t',ascending=False)
print("\n== TRADES per £10 (one per game, entry at the real touch, exit at last pre-off touch)\n",R_.round(3).to_string(index=False))
print("\nentry spread %, median by entry:",{x:round(float(D[f'spr{x}'].median()),2) for x in (60,45,30)})
print("\nleagues in FAV_MISSING:",D[GR['FAV_MISSING']].league.value_counts().to_dict())
print("biggest favourite lengthening T-60 -> KO among FAV_MISSING:")
print(D[GR['FAV_MISSING']].sort_values('d60_0',ascending=False).head(8)[['day','league','fav','fav_px','fav_surprise','fav_top1','d90_60','d60_0']].round(2).to_string(index=False))
W=R_[R_.PASS==True]; print(f"\n== SURVIVORS: {len(W)} of {len(R_)} lines"); print(W.round(3).to_string(index=False) if len(W) else "none")
PY
