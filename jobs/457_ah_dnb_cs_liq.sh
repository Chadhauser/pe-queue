#!/bin/bash
set -o pipefail
# 457 (Finder 2026-11-03, queue item 8): ASIAN HANDICAP, DNB and CORRECT SCORE on liq_sample (real touch, since 27 Oct; ~1 sample per
# selection per minute). Score by minute = goal_timeline joined by team-name similarity (same matcher as 300). FINAL SCORE = the CS
# selection whose back_px <= 1.05 on the last 10 minutes of that market's tape (cross-checked against the timeline's last score);
# no such selection -> result unknown: counted; settle lines shown three ways: "known" (unknowns dropped - DIAGNOSTIC ONLY, never eligible
# to PASS), "worst" (unknown = full loss) and "tlfill" (unknown filled from the timeline's last score if it reached 85'; else dropped).
# The first run (v1) passed CS 80 back on "known" only; the DROP-BIAS CHECK line tests whether unknown results hide late goals.
# BACK fills at back_px minus one tick, LAY at lay_px plus one tick (real touch + 1 tick adverse); exits the other way round.
# Back stake £10 / lay liability £10; 2% commission on net profit per trade.
# CS  : at 60/70/80 (first real print in m..m+3), the CURRENT scoreline selection, back and lay, held to settle. By scoreline.
# DNB : HOME/AWAY (mapped by name). AH: lines -1,-0.5,0,+0.5,+1 for each team, settled on the FULL-MATCH score (Betfair rule; checked
#       below by comparing AH -0.5 with MO at 1-0), quarter lines not used. DNB draw = void (0). AH whole-line push = void.
# Entry minutes 0,15,30,46,60,75; states: score diff from the selection's side (-2..+2), minute band, pre-KO favourite band of that team.
# Exits: SETTLE, NEXTGOAL (first real print at/after goal+2, ANY later minute; none -> settle at result; never skipped).
# Halves = event date before/after the median date. One entry per game per selection per entry minute (correlated within a game: said so).
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,re,unicodedata,time,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
def tick(p): return 0.01 if p<2 else 0.02 if p<3 else 0.05 if p<4 else 0.1 if p<6 else 0.2 if p<10 else 0.5 if p<20 else 1 if p<30 else 2 if p<50 else 5 if p<100 else 10
def pnl(side,p,q,res):
    # res: 1 win / 0 void / -1 lose for the BACKER (q None -> settle). p,q = raw touch (back side: p=back_px, q=lay_px; lay: p=lay_px, q=back_px)
    if side=='B':
        p=p-tick(p)
        if p<=1.01: return None
        if q is None: r=10*(p-1) if res==1 else 0.0 if res==0 else -10.0
        else: q=q+tick(q); r=10*(p/q-1)
    else:
        p=p+tick(p); s=10/(p-1)
        if q is None: r=s if res==-1 else 0.0 if res==0 else -10.0
        else: q=max(1.01,q-tick(q)); r=s*(1-p/q)
    return r*0.98 if r>0 else r
assert abs(pnl('B',2.02,None,1)-10*1.0*0.98)<1e-9 and pnl('B',2.0,None,0)==0.0 and pnl('L',3.0,None,1)==-10.0
assert abs(pnl('L',4.9,None,-1)-10/4.0*0.98)<1e-9 and abs(pnl('B',2.5,2.0,1)-10*(2.48/2.02-1)*0.98)<1e-9
print("P&L unit checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor(); cur.execute("SET statement_timeout='2400s'")
t0=time.time()
L=pd.read_sql("""SELECT ts, market_id, event_name, mkt, sel, minute, back_px::float bp, lay_px::float lp FROM liq_sample
 WHERE event_name LIKE '%% v %%' AND back_px>1 AND lay_px>1 AND (mkt IN ('MO','DNB','CS') OR (mkt='AH' AND sel ~ ' [+-]?(0|0\\.5|1)$'))""",con)
print(f"liq rows {len(L)} | events {L.event_name.nunique()} | {L.ts.min()} .. {L.ts.max()} | {int(time.time()-t0)}s",flush=True)
print("CS selections:",sorted(L[L.mkt=='CS'].sel.unique())[:25])
T=pd.read_sql("SELECT fixture_id, captured_at, home_team, away_team, minute, score_home, score_away, status FROM goal_timeline WHERE captured_at>=%s",con,params=(L.ts.min()-pd.Timedelta(hours=3),))
def norm(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
    s=re.sub(r"\b(fc|cf|afc|sc|ac|as|ss|us|sv|vfb|vfl|tsg|fk|club|de|the|athletic|atletico|sporting|real|cd|ud|sd|rcd|calcio|women|w|u21|u23|ii|b|if|bk|ff|aif|is|kv|sk|fsv)\b"," ",s)
    return set(w for w in re.sub(r"[^a-z0-9 ]"," ",s).split() if len(w)>2)
def sim(a,b): A,B=norm(a),norm(b); return len(A&B)/max(1,len(A|B))
fx=T.groupby('fixture_id').agg(home=('home_team','first'),away=('away_team','first'),t=('captured_at','min')).reset_index()
SK=defaultdict(int); rows=[]; ahchk=[]; ftchk=[0,0]
for ev,g in L.groupby('event_name',sort=False):
    h,a=ev.split(' v ',1); d0=g.ts.min()
    cand=fx[(fx.t>d0-pd.Timedelta(hours=6))&(fx.t<d0+pd.Timedelta(hours=6))]
    sc=[(sim(h,f.home)+sim(a,f.away),f.fixture_id) for f in cand.itertuples()]; sc.sort(reverse=True)
    if not sc or sc[0][0]<1.0 or (len(sc)>1 and sc[0][0]-sc[1][0]<0.3): SK['no timeline match']+=1; continue
    tl=T[T.fixture_id==sc[0][1]].sort_values('captured_at')
    gl=[]; prev=(0,0)
    for r in tl.itertuples():
        c=(int(r.score_home),int(r.score_away))
        if c!=prev and pd.notna(r.minute):
            for _ in range(max(0,c[0]-prev[0])): gl.append((int(r.minute),'h'))
            for _ in range(max(0,c[1]-prev[1])): gl.append((int(r.minute),'a'))
            prev=c
    gl.sort()
    def score(m): return (sum(1 for x,s in gl if x<=m and s=='h'),sum(1 for x,s in gl if x<=m and s=='a'))
    cs=g[g.mkt=='CS']; FT=None
    if len(cs):
        tail=cs[cs.ts>=cs.ts.max()-pd.Timedelta(minutes=10)]; w=tail[tail.bp<=1.05]
        if len(w):
            mm=re.match(r'^(\d+)\s*-\s*(\d+)$',w.sel.iloc[-1].strip())
            if mm: FT=(int(mm.group(1)),int(mm.group(2)))
    if FT is None: SK['FT unknown (no CS sel <=1.05 at the end)']+=1
    else: ftchk[0]+=1; ftchk[1]+=int(FT==prev)
    tl_end=tl.minute.max() if len(tl) else 0
    FTT=FT if FT else (prev if tl_end>=85 else None)   # 'tlfill': CS-tape result, else the timeline's last score if it reached 85'
    late80=any(x>80 for x,_ in gl)
    g=g.assign(minute=g.minute.fillna(-1).astype(int)); g=g.sort_values('ts')
    px={}
    for (mkt,sel),s in g.groupby(['mkt','sel']):
        s=s.drop_duplicates('minute'); px[(mkt,sel)]=dict(zip(s.minute,zip(s.bp,s.lp)))
    def at(mkt,sel,m,span=3):
        d=px.get((mkt,sel),{})
        for x in range(m,m+span+1):
            if x in d: return x,d[x]
        return None
    def later(mkt,sel,m):
        d=px.get((mkt,sel),{}); ks=[k for k in d if k>=m]
        return (min(ks),d[min(ks)]) if ks else None
    mo={s:at('MO',s,-1,1) or at('MO',s,0,2) for s in ('HOME','AWAY')}
    if not all(mo.values()): SK['no pre-KO MO']+=1; continue
    fb={('h' if k=='HOME' else 'a'):('<1.5' if v[1][0]<1.5 else '1.5-2' if v[1][0]<2 else '2-3' if v[1][0]<3 else '3-5' if v[1][0]<5 else '5+') for k,v in mo.items()}
    day=g.ts.min().date()
    def side_of(sel):
        base=re.sub(r'\s[+-]?\d+(\.\d+)?$','',sel); sh,sa=sim(base,h),sim(base,a)
        return 'h' if sh>sa else 'a' if sa>sh else None
    def emit(mkt,sel,line,team,t,diff,res_fn,cs_score=None):
        e=at(mkt,sel,t)
        if e is None: SK[mkt+': no entry print']+=1; return
        em,(bp,lp)=e
        if bp>50: return
        nxt=next((x for x,_ in gl if x>em),None)
        for ex in ('SETTLE','NEXTGOAL') if mkt!='CS' else ('SETTLE',):
            for side in ('B','L'):
                q=None
                if ex=='NEXTGOAL' and nxt is not None:
                    lp2=later(mkt,sel,nxt+2)
                    if lp2 is None: SK[mkt+' NEXTGOAL: no later print -> result']+=1
                    else: q=lp2[1][1] if side=='B' else lp2[1][0]
                for rv in ('known','worst','tlfill'):
                    ftv=FTT if rv=='tlfill' else FT
                    res=res_fn(ftv) if ftv else None
                    if q is None and res is None:
                        if rv!='worst': continue
                        r=-10.0
                    else:
                        r=pnl(side,bp if side=='B' else lp,q,res)
                    if r is None: continue
                    rows.append(dict(mkt=mkt,line=line,side=side,exit=ex,rv=rv,t=t,diff=diff,fav=fb.get(team,'-'),cs=cs_score,ev=ev,day=day,px=bp,pnl=r,res=res,
                                     ftknown=FT is not None,late80=late80))
    hs={s:side_of(s) for (mk,s) in px if mk in ('DNB','AH')}
    for t in (0,15,30,46,60,75):
        sh,sa=score(t)
        for (mkt,sel) in list(px):
            if mkt not in ('DNB','AH'): continue
            team=hs.get(sel)
            if team is None: SK['team not mapped']+=1; continue
            diff=max(-2,min(2,(sh-sa) if team=='h' else (sa-sh)))
            hc=0.0 if mkt=='DNB' else float(sel.rsplit(' ',1)[1])
            def res_fn(F,team=team,hc=hc):
                m=(F[0]-F[1] if team=='h' else F[1]-F[0])+hc
                return 1 if m>0 else 0 if m==0 else -1
            emit(mkt,sel,('DNB' if mkt=='DNB' else f'AH {hc:+g}'),team,t,diff,res_fn)
            if mkt=='AH' and hc==-0.5 and team=='h' and (sh,sa)==(1,0) and t>=46:
                e1=at('AH',sel,t); e2=at('MO','HOME',t)
                if e1 and e2: ahchk.append((e1[1][0],e2[1][0]))
    for t in (60,70,80):
        sh,sa=score(t); sel=next((s for (mk,s) in px if mk=='CS' and re.match(rf'^{sh}\s*-\s*{sa}$',s.strip())),None)
        if sel is None: SK['CS current score not on the board']+=1; continue
        emit('CS',sel,f'CS {t}',None,t,0,lambda F,sh=sh,sa=sa:1 if F==(sh,sa) else -1,f'{sh}-{sa}')
R=pd.DataFrame(rows); print("counts (not hidden):",dict(SK),flush=True)
print(f"FT from CS tape: {ftchk[0]} games; agrees with timeline last score in {ftchk[1]} ({ftchk[1]/max(1,ftchk[0]):.0%})")
if ahchk:
    A=np.array(ahchk); print(f"AH rule check (home -0.5 vs MO HOME back at 1-0, 2H): median ratio {np.median(A[:,0]/A[:,1]):.3f} over {len(A)} (≈1 => full-match settlement)")
if R.empty: print("\n== SURVIVORS: 0\nnone"); sys.exit()
md=sorted(R.day.unique())[len(R.day.unique())//2]; R['half']=np.where(R.day<md,'H1','H2')
c80=R[(R.line=='CS 80')&(R.side=='B')&(R.rv=='worst')].drop_duplicates('ev')
print("DROP-BIAS CHECK, CS 80 games: timeline shows a goal after 80' in",
      f"{c80[c80.ftknown].late80.mean():.0%} of FT-known games (n {c80.ftknown.sum()}) vs {c80[~c80.ftknown].late80.mean():.0%} of FT-unknown games (n {(~c80.ftknown).sum()})")
print(f"games traded {R.ev.nunique()} | days {R.day.min()}..{R.day.max()} | halves split at {md}")
def tstat(x): return x.mean()/(x.std(ddof=1)/len(x)**0.5) if len(x)>1 and x.std(ddof=1)>0 else 0.0
out=[]
R['tband']=R.t.map(lambda t:'0' if t==0 else '15-30' if t<46 else '46-75')
for dims in (['mkt','line','side','exit','rv'],['mkt','line','side','exit','rv','tband'],['mkt','line','side','exit','rv','tband','diff'],
             ['mkt','line','side','exit','rv','tband','diff','fav'],['mkt','line','side','exit','rv','cs']):
    for k,gg in R.groupby(dims):
        a=gg[gg.half=='H1'].pnl; b=gg[gg.half=='H2'].pnl
        out.append(dict(level='+'.join(dims[5:]) or 'base',cell=' / '.join(map(str,k)),n=len(gg),games=gg.ev.nunique(),per10=gg.pnl.mean(),t=tstat(gg.pnl),
                        n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,avg_px=gg.px.mean()))
S=pd.DataFrame(out).round(3)
S['PASS']=(~S.cell.str.contains(' / known'))&(S.n>=300)&(S.n1>=150)&(S.n2>=150)&(S.t>=3.5)&(S.h1>0)&(S.h2>0)&(S.per10>=0.15)
pd.set_option('display.width',230); pd.set_option('display.max_rows',400)
print("\n== base cells"); print(S[S.level=='base'].to_string(index=False))
print("\n== CS by current scoreline (n>=30)"); print(S[(S.level=='cs')&(S.n>=30)].to_string(index=False))
print(f"\n== cells tested: {len(S)}, at n>=300: {(S.n>=300).sum()}")
print("\n== top 15 by t (n>=100)"); print(S[S.n>=100].sort_values('t',ascending=False).head(15).to_string(index=False))
print("\n== top 15 by t (worst-case results only, n>=100)"); print(S[(S.n>=100)&S.cell.str.contains('worst')].sort_values('t',ascending=False).head(15).to_string(index=False))
W=S[S.PASS].sort_values('t',ascending=False)
print(f"\n== SURVIVORS: {len(W)}"); print(W.head(40).to_string(index=False) if len(W) else "none")
PY
