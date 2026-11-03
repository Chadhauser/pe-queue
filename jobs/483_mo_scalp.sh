#!/bin/bash
set -o pipefail
# 483 (Finder 2026-11-04, queue item 29): MATCH ODDS IN-PLAY SCALP on liq_sample (real touch, about one sample a minute), favourite only, 29 Oct onwards. Compared with the -£0.52/£10 round trip quoted in the item.
# TRIGGER, per minute: favourite (shorter of HOME/AWAY at the first sample in minutes 0..2); spread exactly 1 tick (lay_px is one ladder step above back_px); back_px range over the previous 10 samples >= 3 ticks; no goal in the previous 10 minutes on goal_timeline (reversed goals removed). Trigger uses only earlier samples plus the current one.
# BACK: entry at back_px less one tick. Target +1 tick: 1 ladder step below entry, filled AT target only when a later sample's ltp is strictly below it (trades through). Stop -2 ticks measured from the touch: lay_px at least 3 steps above the filled entry, exits at lay_px plus one tick. Time: third later sample, at lay_px plus one tick.
#   First run measured the stop from the filled entry: an unchanged 1-tick book is already 2 steps away after the adverse fill, so the stop fired on no move at all (83% of backs). Corrected.
# LAY mirror: entry at lay_px plus one tick. Target: ltp strictly above 1 step over entry. Stop: back_px at least 3 steps below the filled entry, exits at back_px less one tick. Time: third later sample, back_px less one tick.
# SAMPLING LIMIT: a minute sample cannot show the path inside the minute. If stop and target are both true on a sample, the STOP is taken (conservative). A real bot would see more; this may understate fills and overstate them too.
# No later sample = settled at the result (FT from the MO tape <= 1.05 or timeline if it reached 85'); unknown = -£10. Never dropped.
# SETS: ALLNO = every non-overlapping entry, correlated within a game. FIRST = first entry per game per side. Only FIRST can pass. COST: 2% commission on profit, £10 stake / £10 liability. Halves: date median.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,re,unicodedata,time,warnings,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
warnings.filterwarnings('ignore')
pd.set_option('display.width',230); pd.set_option('display.max_rows',60); pd.set_option('display.max_columns',30)
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
LAD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    x=lo
    while x<hi-1e-9: LAD.append(round(x,2)); x+=st
LAD.append(1000.0); LADA=np.array(LAD)
def ix(p): return int(np.searchsorted(LADA,round(float(p),2)-1e-9))
def step(p,k): return float(LADA[min(max(ix(p)+k,0),len(LADA)-1)])
def trade_back(e,q):  # stake 10 at e, closed at lay price q
    r=10*(e/q-1); return r*0.98 if r>0 else r
def trade_lay(e,q):   # liability 10 at e (stake 10/(e-1)), closed at back price q
    r=10/(e-1)*(1-e/q); return r*0.98 if r>0 else r
def simulate(side,e,later):
    """later: list of (back_px,lay_px,ltp) for following samples. Returns (exit_price, reason, samples_used) or (None,'none',0)."""
    t=step(e,-1) if side=='B' else step(e,1)
    for i,(b,l,lt) in enumerate(later[:3],1):
        if side=='B':
            if ix(l)-ix(e)>=3: return step(l,1),'stop',i
            if lt is not None and lt<t-1e-9: return t,'target',i
            if i==3: return step(l,1),'time',i
        else:
            if ix(e)-ix(b)>=3: return step(b,-1),'stop',i
            if lt is not None and lt>t+1e-9: return t,'target',i
            if i==3: return step(b,-1),'time',i
    return None,'none',0
def goals_from_timeline(rows):
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
def band(p): return '<1.5' if p<1.5 else '1.5-2' if p<2 else '2-3' if p<3 else '3+'
# known answers, worked by hand
assert step(2.0,-1)==1.99 and step(2.0,1)==2.02 and step(1.99,1)==2.0 and step(1.01,-1)==1.01
assert abs(trade_back(2.0,1.98)-10*(2.0/1.98-1)*0.98)<1e-9 and abs(trade_back(2.0,2.04)-10*(2.0/2.04-1))<1e-9
assert abs(trade_lay(2.0,2.02)-10*(1-2.0/2.02)*0.98)<1e-9 and abs(trade_lay(2.0,1.98)-10*(1-2.0/1.98))<1e-9
assert simulate('B',2.0,[(1.98,1.99,1.98)])==(1.99,'target',1)            # 1.98 trades through 1.99
assert simulate('B',2.0,[(1.98,1.99,1.99)])[1]!='target'                  # touching the target is not through it
assert simulate('B',2.0,[(2.04,2.06,1.5)])==(2.08,'stop',1)               # lay 2.06 is 3 steps up: stop beats target; exit 2.08
assert simulate('B',1.99,[(1.99,2.0,1.99),(1.99,2.0,1.99),(1.99,2.0,1.99)])==(2.02,'time',3)   # the book that gave this fill (back 2.0, lay 2.02 less a move) does not stop out
assert simulate('B',1.99,[(2.0,2.02,2.0),(2.0,2.02,2.0),(2.0,2.02,2.0)])==(2.04,'time',3)      # unchanged book after fill 1.99 from back_px 2.0: 2 steps away, NOT a stop
assert simulate('B',2.0,[(2.0,2.02,2.0),(2.0,2.02,2.0),(2.0,2.02,2.0)])==(2.04,'time',3)
assert simulate('L',2.0,[(2.02,2.04,2.04)])==(2.02,'target',1)
assert simulate('L',2.0,[(1.97,1.98,2.5)])==(1.96,'stop',1)                # back 1.97 is 3 steps down: stop beats target; exit 1.96
assert simulate('L',2.02,[(2.0,2.02,2.0)]*3)==(1.99,'time',3)              # unchanged book after fill 2.02 from lay_px 2.0: NOT a stop
assert simulate('L',2.0,[(2.0,2.02,2.0)]*3)==(1.99,'time',3)
assert simulate('B',2.0,[])==(None,'none',0)
assert goals_from_timeline([(10,1,0),(12,0,0)])==([],(0,0)) and goals_from_timeline([(10,1,0),(30,1,1)])[0]==[(10,'h'),(30,'a')]
assert band(1.49)=='<1.5' and band(1.5)=='1.5-2' and band(3.0)=='3+'
print("known-answer checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
t0=time.time(); fr=[]; day=pd.Timestamp('2026-10-20',tz='UTC'); end=pd.Timestamp.now(tz='UTC')+pd.Timedelta(days=1)
while day<end:
    d=pd.read_sql("""SELECT event_name,sel,minute,ts,back_px::float bp,lay_px::float lp,ltp::float ltp FROM liq_sample
      WHERE ts>=%s AND ts<%s AND mkt='MO' AND sel IN ('HOME','AWAY') AND minute BETWEEN 0 AND 100 AND event_name LIKE '%% v %%'""",con,params=(day,day+pd.Timedelta(days=1)))
    if len(d): fr.append(d)
    print(f"  {day.date()} rows {len(d)} | {int(time.time()-t0)}s",flush=True); day+=pd.Timedelta(days=1)
if not fr: print("ERROR: no liq_sample rows pulled, so no verdict"); sys.exit(1)
L=pd.concat(fr,ignore_index=True).sort_values(['event_name','sel','ts'])
print(f"rows {len(L)} | games {L.event_name.nunique()} | {L.ts.min()} .. {L.ts.max()}",flush=True)
T=pd.read_sql("SELECT fixture_id,captured_at,home_team,away_team,minute,score_home,score_away FROM goal_timeline WHERE captured_at>=%s",con,params=(L.ts.min()-pd.Timedelta(hours=3),))
def norm(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
    s=re.sub(r"\b(fc|cf|afc|sc|ac|as|ss|us|sv|vfb|vfl|tsg|fk|club|de|the|athletic|atletico|sporting|real|cd|ud|sd|rcd|calcio|women|w|u21|u23|ii|b|if|bk|ff|aif|is|kv|sk|fsv)\b"," ",s)
    return set(w for w in re.sub(r"[^a-z0-9 ]"," ",s).split() if len(w)>2)
def sim(a,b): A,B=norm(a),norm(b); return len(A&B)/max(1,len(A|B))
fx=T.groupby('fixture_id').agg(home=('home_team','first'),away=('away_team','first'),t=('captured_at','min')).reset_index()
SK=defaultdict(int); rows=[]
for ev,g in L.groupby('event_name',sort=False):
    h,a=ev.split(' v ',1); d0=g.ts.min()
    cand=fx[(fx.t>d0-pd.Timedelta(hours=6))&(fx.t<d0+pd.Timedelta(hours=6))]
    sc=sorted(((sim(h,f.home)+sim(a,f.away),f.fixture_id) for f in cand.itertuples()),reverse=True)
    if not sc or sc[0][0]<1.0 or (len(sc)>1 and sc[0][0]-sc[1][0]<0.3): SK['no timeline match']+=1; continue
    tl=T[T.fixture_id==sc[0][1]].sort_values('captured_at')
    gl,last=goals_from_timeline([(None if pd.isna(r.minute) else int(r.minute),int(r.score_home),int(r.score_away)) for r in tl.itertuples() if pd.notna(r.score_home) and pd.notna(r.score_away)])
    tlend=tl.minute.max()
    two=g[(g.bp>1)&(g.lp>1)&(g.lp<1000)]
    e0=two[two.minute<=2].sort_values('ts').drop_duplicates('sel').set_index('sel').bp
    if len(e0)<2 or e0.get('HOME') is None or e0.get('AWAY') is None: SK['no early MO on both sides (incl. the recorder label defect)']+=1; continue
    fav='HOME' if e0['HOME']<=e0['AWAY'] else 'AWAY'
    s=two[two.sel==fav].sort_values('ts').drop_duplicates('minute')
    if len(s)<15: SK['under 15 samples']+=1; continue
    m=s.minute.values; b=s.bp.values; l=s.lp.values; lt=s.ltp.values
    tail=g[(g.sel==fav)&(g.ts>=g.ts.max()-pd.Timedelta(minutes=10))]; res=None
    if (tail.bp<=1.05).any(): res=True
    elif (tail.lp>=20).any() or (tail.bp>=20).any(): res=False
    elif pd.notna(tlend) and tlend>=85: res=(last[0]>last[1]) if fav=='HOME' else (last[1]>last[0])
    if res is None: SK['result unknown']+=1
    day_=g.ts.min().date()
    for side in ('B','L'):
        i=10; nth=0
        while i<len(s):
            recent=[x for x,_ in gl if m[i]-10<=x<=m[i]]
            ok=ix(l[i])-ix(b[i])==1 and ix(b[i-10:i+1].max())-ix(b[i-10:i+1].min())>=3 and not recent and 1<=m[i]<=90
            if not ok: i+=1; continue
            e=step(b[i],-1) if side=='B' else step(l[i],1)
            if side=='B' and e<=1.01: i+=1; continue
            q,why,used=simulate(side,e,[(b[j],l[j],None if pd.isna(lt[j]) else lt[j]) for j in range(i+1,min(i+4,len(s)))])
            if q is None:
                x=-10.0 if res is None else ((10*(e-1)*0.98 if res else -10.0) if side=='B' else (-10.0 if res else 10/(e-1)*0.98)); why='result'; used=len(s)-i
            else: x=trade_back(e,q) if side=='B' else trade_lay(e,q)
            rows.append(dict(side=side,ev=ev,day=day_,px=b[i],band=band(b[i]),minute=int(m[i]),why=why,x=x,first=nth==0))
            nth+=1; i=i+max(used,1)+1
print("counts (not hidden):",dict(SK),flush=True)
R=pd.DataFrame(rows)
if R.empty: print("ERROR: no entries, so no verdict"); sys.exit(1)
days=sorted(R.day.unique()); md=days[len(days)//2]; print(f"entries {len(R)} | games {R.ev.nunique()} | days {days[0]}..{days[-1]} | halves split at {md}",flush=True)
print("exit reasons:",R.groupby('side').why.value_counts(normalize=True).round(3).to_dict())
def tstat(v): return v.mean()/(v.std(ddof=1)/np.sqrt(len(v))) if len(v)>1 and v.std(ddof=1)>0 else 0.0
def line(d,first=False,**k):
    a=d[d.day<md].x; c=d[d.day>=md].x
    return dict(**k,n=len(d),games=d.ev.nunique(),per10=d.x.mean(),t=tstat(d.x),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(c),h2=c.mean() if len(c) else np.nan,target=(d.why=='target').mean(),PASS=first and len(d)>=300 and len(a)>=150 and len(c)>=150 and tstat(d.x)>=3.5 and a.mean()>0 and c.mean()>0 and d.x.mean()>=0.15)
out=[]
for side,d in R.groupby('side'):
    out.append(line(d,side=side,set='ALLNO',band='all')); f=d[d['first']]; out.append(line(f,first=True,side=side,set='FIRST',band='all'))
    for b_,dd in d.groupby('band'): out.append(line(dd,side=side,set='ALLNO',band=b_))
    for b_,dd in f.groupby('band'): out.append(line(dd,first=True,side=side,set='FIRST',band=b_))
S=pd.DataFrame(out); print("\n== RESULTS per £10\n",S.round(3).to_string(index=False))
print("\nbeats -£0.52 round trip (ALLNO, n>=100):",S[(S.set=='ALLNO')&(S.n>=100)&(S.per10>-0.52)][['side','band','n','per10']].round(3).values.tolist())
W=S[S.PASS==True]; print(f"\n== SURVIVORS: {len(W)} of {len(S)} lines"); print(W.round(3).to_string(index=False) if len(W) else "none")
PY
