#!/bin/bash
set -o pipefail
# 478 (Finder 2026-11-03, queue item 24): CSM CORRECT SCORE RULES on the recorder. liq_sample CS (29 Oct onwards) joined to goal_timeline by the name matcher of job 457. PILOT: about 6 days of data.
# QUALIFIER: favourite (shorter of MO HOME/AWAY) back_px 1.40-1.80 and OU25 OVER back_px <= 1.80, at the first sample in minutes 0..2. The recorder starts at minute 0, so this is just after kick-off, not pre-match.
# ENTRY: same sample window. Dutch 1-0/2-0/2-1 (home favourite) or 0-1/0-2/1-2 (away). All three legs need a real two-sided touch, each at most 50 with lay_px < 1000. Back fills at back_px minus one tick (real touch, one tick adverse).
# STAKING: the course's staking is NOT on this box. Stated assumption: equal-return dutch, total stake £10 = the liability cap. No first goal known before the entry print.
# VARIANTS: SETTLE. GREEN_G2 / GREEN_G5: at the first real print at/after first goal +2 / +5 close each leg at lay_px plus one tick; a leg with no usable print settles at the result (a dead score is a loss, never dropped). No goal = settled at the result.
#   GREEN_G2_REC: GREEN_G2 plus, if still 0-0 at the first real 0-0 print at/after 60', lay 0-0 at lay_px plus one tick with £5 liability, held to settle. Total risk £15, P&L scaled to per £10. The recovery size is an assumption as well.
# LEGS: each leg alone, £10 back to settle, so the leg that carries the result is visible.
# RESULT: FT = CS selection with back_px <= 1.05 in the market's last 10 min (ANYOTHER* = score unknown but every leg lost), else the timeline's last score if it reached 85'. Reported TL (that) and WORST (still unknown = the open stake is lost). Only WORST can pass.
# PHANTOM GOALS: item 0g found about 2% of feed goals revert. A goal the feed later takes back is removed from the goal list.
# COST: 2% commission on the net of the whole trade (one market). £10 risk. Halves: date median. One entry per game.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,re,unicodedata,warnings,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
from functools import lru_cache
warnings.filterwarnings('ignore')
pd.set_option('display.width',230); pd.set_option('display.max_rows',100); pd.set_option('display.max_columns',30)
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
LAD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    x=lo
    while x<hi-1e-9: LAD.append(round(x,2)); x+=st
LAD.append(1000.0); LADA=np.array(LAD)
@lru_cache(maxsize=None)
def dn(p): return float(LADA[max(int(np.searchsorted(LADA,round(p,2)-1e-9))-1,0)])
@lru_cache(maxsize=None)
def up(p): return float(LADA[min(int(np.searchsorted(LADA,round(p,2)-1e-9))+1,len(LADA)-1)])
def stakes(fills,total=10.0):
    inv=[1/p for p in fills]; s=sum(inv)
    return [total*i/s for i in inv]
def net(x): return x*0.98 if x>0 else x
def leg_settle(stake,fill,won): return stake*(fill-1) if won else -stake
def leg_close(stake,fill,lay_touch): return stake*(fill/up(lay_touch)-1)
def lay_settle(liab,lay_touch,won):
    a=up(lay_touch); return -liab if won else liab/(a-1)
def score_key(s):
    m=re.match(r'^\s*(\d+)\s*-\s*(\d+)\s*$',str(s))
    return (int(m.group(1)),int(m.group(2))) if m else None
def goals_from_timeline(rows):
    """rows: (minute,h,a) in time order. Reversal removes the latest goal for that side."""
    gl=[]; prev=(0,0)
    for m,h,a in rows:
        if (h,a)==prev or m is None: continue
        for side,now,was in (('h',h,prev[0]),('a',a,prev[1])):
            for _ in range(max(0,now-was)): gl.append((int(m),side))
            for _ in range(max(0,was-now)):
                for i in range(len(gl)-1,-1,-1):
                    if gl[i][1]==side: gl.pop(i); break
        prev=(h,a)
    return sorted(gl),prev
# known answers, worked by hand
assert dn(7.0)==6.8 and up(7.0)==7.2 and dn(2.0)==1.99 and up(9.8)==10.0
s=stakes([7.0,9.0,9.0]); assert abs(sum(s)-10)<1e-9 and abs(s[0]*7-s[1]*9)<1e-9 and abs(s[0]-3.913043)<1e-5   # 10*(1/7)/(1/7+2/9)
assert abs(s[0]*7-27.391304)<1e-5                                                                            # the equal return
assert abs(leg_settle(s[0],7.0,True)+leg_settle(s[1],9.0,False)+leg_settle(s[2],9.0,False)-17.391304)<1e-5   # return less the £10 stake
assert net(10.0)==9.8 and net(-10.0)==-10.0 and net(0.0)==0.0
assert abs(leg_close(5.0,6.8,3.0)-5*(6.8/3.05-1))<1e-9
assert abs(lay_settle(5,10.0,False)-5/9.5)<1e-9 and lay_settle(5,10.0,True)==-5                              # 10 fills 10.5, stake 5/9.5
assert score_key('2-1')==(2,1) and score_key('2 - 1')==(2,1) and score_key('ANYOTHERHOMEWIN') is None
assert goals_from_timeline([(10,1,0),(30,1,1)])==([(10,'h'),(30,'a')],(1,1))
assert goals_from_timeline([(10,1,0),(12,0,0)])==([],(0,0))                                                  # phantom removed
assert goals_from_timeline([(10,1,0),(12,0,0),(40,1,0)])==([(40,'h')],(1,0))                                 # phantom then real goal
assert goals_from_timeline([(50,2,0)])==([(50,'h'),(50,'h')],(2,0))                                          # two at one sample
print("known-answer checks: OK",flush=True)

con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
Q=pd.read_sql("""SELECT DISTINCT ON (event_name,mkt,sel) event_name,mkt,sel,minute,back_px::float bp,ts FROM liq_sample
  WHERE event_name LIKE '%% v %%' AND ((mkt='MO' AND sel IN ('HOME','AWAY')) OR (mkt='OU25' AND sel='OVER')) AND minute BETWEEN 0 AND 2 AND back_px>1 AND lay_px>1 AND ts>='2026-10-29'
  ORDER BY event_name,mkt,sel,ts""",con)
W=Q.pivot_table(index='event_name',columns=['mkt','sel'],values='bp',aggfunc='first'); W.columns=[f"{a}_{b}" for a,b in W.columns]
print("games with an early sample:",len(W),"| dates",Q.ts.min(),"..",Q.ts.max(),flush=True)
W=W.dropna(subset=['MO_HOME','MO_AWAY','OU25_OVER'])
W['fav']=np.where(W.MO_HOME<=W.MO_AWAY,'h','a'); W['fp']=W[['MO_HOME','MO_AWAY']].min(axis=1)
C=W[W.fp.between(1.40,1.80)&(W.OU25_OVER<=1.80)]
print(f"with MO and OU25: {len(W)} | fav 1.40-1.80: {int(W.fp.between(1.40,1.80).sum())} | qualifiers: {len(C)} (home fav {int((C.fav=='h').sum())}, away fav {int((C.fav=='a').sum())})",flush=True)
names=list(C.index)
CS=pd.read_sql("SELECT event_name,sel,minute,ts,back_px::float bp,lay_px::float lp FROM liq_sample WHERE mkt='CS' AND event_name=ANY(%s) AND ts>='2026-10-29'",con,params=(names,))
print("CS rows for qualifiers:",len(CS),"events",CS.event_name.nunique(),flush=True)
t0=Q.ts.min()-pd.Timedelta(hours=3)
T=pd.read_sql("SELECT fixture_id,captured_at,home_team,away_team,minute,score_home,score_away FROM goal_timeline WHERE captured_at>=%s",con,params=(t0,))
def norm(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
    s=re.sub(r"\b(fc|cf|afc|sc|ac|as|ss|us|sv|vfb|vfl|tsg|fk|club|de|the|athletic|atletico|sporting|real|cd|ud|sd|rcd|calcio|women|w|u21|u23|ii|b|if|bk|ff|aif|is|kv|sk|fsv)\b"," ",s)
    return set(w for w in re.sub(r"[^a-z0-9 ]"," ",s).split() if len(w)>2)
def sim(a,b): A,B=norm(a),norm(b); return len(A&B)/max(1,len(A|B))
fx=T.groupby('fixture_id').agg(home=('home_team','first'),away=('away_team','first'),t=('captured_at','min')).reset_index()
SK=defaultdict(int); rows=[]; legrows=[]; ftchk=[0,0]
for ev,g in CS.groupby('event_name',sort=False):
    h,a=ev.split(' v ',1); d0=g.ts.min(); fav=C.loc[ev,'fav']
    cand=fx[(fx.t>d0-pd.Timedelta(hours=6))&(fx.t<d0+pd.Timedelta(hours=6))]
    sc=sorted(((sim(h,f.home)+sim(a,f.away),f.fixture_id) for f in cand.itertuples()),reverse=True)
    if not sc or sc[0][0]<1.0 or (len(sc)>1 and sc[0][0]-sc[1][0]<0.3): SK['no timeline match']+=1; continue
    tl=T[T.fixture_id==sc[0][1]].sort_values('captured_at')
    gl,last=goals_from_timeline([(None if pd.isna(r.minute) else int(r.minute),int(r.score_home),int(r.score_away)) for r in tl.itertuples() if pd.notna(r.score_home) and pd.notna(r.score_away)])
    tail=g[(g.ts>=g.ts.max()-pd.Timedelta(minutes=10))&(g.bp>1)&(g.bp<=1.05)].sort_values('ts')
    FT=None; other=False
    if len(tail):
        lastsel=tail.sel.iloc[-1]; FT=score_key(lastsel); other=str(lastsel).startswith('ANYOTHER')
    if FT is not None: ftchk[0]+=1; ftchk[1]+=int(FT==last)
    if FT is None and not other and pd.notna(tl.minute.max()) and tl.minute.max()>=85: FT=last; SK['FT from timeline']+=1
    known=FT is not None or other
    if not known: SK['FT unknown']+=1
    if fav=='h': labels=('1-0','2-0','2-1')
    else: labels=('0-1','0-2','1-2')
    g=g.sort_values('ts').dropna(subset=['minute'])
    px={}
    for sel,s in g.groupby('sel'):
        s=s[(s.bp>1)&(s.lp>1)&(s.lp<1000)].drop_duplicates('minute'); px[sel]=dict(zip(s.minute.astype(int),zip(s.bp,s.lp)))
    entry={}
    for sel in labels:
        ms=[m for m in px.get(sel,{}) if m<=2]
        if ms: entry[sel]=(min(ms),)+px[sel][min(ms)]
    if len(entry)<3: SK['a leg has no two-sided touch in minutes 0..2']+=1; continue
    if max(v[1] for v in entry.values())>50: SK['a leg over 50']+=1; continue
    em=max(v[0] for v in entry.values())
    if gl and gl[0][0]<em: SK['goal before entry']+=1; continue
    fills=[dn(entry[s][1]) for s in labels]
    if min(fills)<=1.01: SK['fill at 1.01']+=1; continue
    st=stakes(fills)
    won={s:(score_key(s)==FT) for s in labels}
    first=next((m for m,_ in gl if m>=em),None)
    def lose_unknown(s,f):
        return leg_settle(s,f,False)
    def settle_all(idx=(0,1,2)):
        return sum(leg_settle(st[i],fills[i],won[labels[i]]) for i in idx)
    # SETTLE. WORST and TL differ only where the result is unknown, and then every open leg counts as lost
    pl={'SETTLE':settle_all()}
    closes={}
    for k in (2,5):
        if first is None: closes[k]=None; continue
        tot=0.0; closed=0
        for i,s in enumerate(labels):
            d=px.get(s,{}); ks=[m for m in d if m>=first+k]
            if ks:
                q=d[min(ks)][1]; tot+=leg_close(st[i],fills[i],q); closed+=1
            else: tot+=leg_settle(st[i],fills[i],won[s])
        closes[k]=(tot,closed)
        pl[f'GREEN_G{k}']=tot
    if first is None:
        pl['GREEN_G2']=settle_all(); pl['GREEN_G5']=settle_all()
    # recovery lay of 0-0
    rec=0.0; rec_on=False
    if first is None or first>=60:
        d=px.get('0-0',{}); ks=sorted(m for m in d if m>=60 and (first is None or m<first))
        if ks:
            rec_on=True; rec=lay_settle(5.0,d[ks[0]][1],FT==(0,0))
    base2=pl['GREEN_G2']
    day=g.ts.min().date()
    all_closed=closes.get(2) is not None and closes[2][1]==3
    def row(vr,x,res): rows.append(dict(variant=vr,res=res,ev=ev,day=day,fav=fav,fp=C.loc[ev,'fp'],pnl=x))
    for vr,x in pl.items():
        needs=not (vr.startswith('GREEN') and first is not None and closes[int(vr[-1])][1]==3)
        if known or not needs:
            row(vr,net(x),'TL'); row(vr,net(x),'WORST')
        else:
            row(vr,-10.0,'WORST'); SK[f'{vr} unknown result']+=1
    if known or (first is not None and all_closed):
        y=net(base2+rec)*(10/15); row('GREEN_G2_REC',y,'TL'); row('GREEN_G2_REC',y,'WORST')
    else: row('GREEN_G2_REC',-15.0*(10/15),'WORST')
    SK['recovery lay used']+=int(rec_on)
    for i,(s,nm) in enumerate(zip(labels,('fav 1-0','fav 2-0','fav 2-1'))):
        if known:
            x=net(leg_settle(10.0,fills[i],won[s])); legrows.append(dict(leg=nm,ev=ev,day=day,pnl=x,won=won[s],px=fills[i]))
print("counts (not hidden):",dict(SK),flush=True)
print(f"FT from CS tape: {ftchk[0]} games; agrees with the timeline's last score in {ftchk[1]}",flush=True)
R=pd.DataFrame(rows)
if R.empty: print("\n== SURVIVORS: 0\nnone"); sys.exit()
days=sorted(R.day.unique()); md=days[len(days)//2]; print(f"games traded {R.ev.nunique()} | days {days[0]}..{days[-1]} | halves split at {md}",flush=True)
def tstat(x): return x.mean()/(x.std(ddof=1)/np.sqrt(len(x))) if len(x)>1 and x.std(ddof=1)>0 else 0.0
out=[]
for (vr,res),d in R.groupby(['variant','res']):
    a=d[d.day<md].pnl; b=d[d.day>=md].pnl
    out.append(dict(variant=vr,res=res,n=len(d),per10=d.pnl.mean(),t=tstat(d.pnl),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,PASS=(res=='WORST') and len(d)>=300 and len(a)>=150 and len(b)>=150 and tstat(d.pnl)>=3.5 and a.mean()>0 and b.mean()>0 and d.pnl.mean()>=0.15))
S=pd.DataFrame(out); print("\n== VARIANTS\n",S.round(3).to_string(index=False))
Lg=pd.DataFrame(legrows)
if len(Lg):
    LO=[]
    for lg,d in Lg.groupby('leg'):
        a=d[d.day<md].pnl; b=d[d.day>=md].pnl
        LO.append(dict(leg=lg,n=len(d),hit=d.won.mean(),avg_fill=d.px.mean(),per10=d.pnl.mean(),t=tstat(d.pnl),h1=a.mean() if len(a) else np.nan,h2=b.mean() if len(b) else np.nan))
    print("\n== LEGS, £10 back to settle, known results only (diagnostic: unknowns dropped)\n",pd.DataFrame(LO).round(3).to_string(index=False))
n=R[(R.variant=='SETTLE')&(R.res=='WORST')].ev.nunique(); rate=n/max(1,len(days))
print(f"\nqualifying games traded per day {rate:.1f}: n 300 needs about {300/max(rate,0.01):.0f} days of recorder data from 29 Oct, IF the table keeps that long")
W_=S[S.PASS]; print(f"\n== SURVIVORS: {len(W_)}"); print(W_.round(3).to_string(index=False) if len(W_) else "none")
PY
