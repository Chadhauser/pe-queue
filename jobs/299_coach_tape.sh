#!/bin/bash
set -o pipefail
# 299: THE COACH TAPE — for every football game the liquidity recorder saw today (real Betfair touch prices, live key, every
# market), reconstruct the day after the fact: score by minute (goal_timeline), the price path of every market at 0/15/30/45/
# 60/75/90, and every moment one of OUR lines would have fired, with the real price available at that moment, the exit price and
# the £10 result. No time pressure — this is what Peter studies instead of trading live. Lines marked:
#   BIAS_LAY_6_10  lay any Match Odds runner offered 6.0-10.0 between 3' and 70', hold to settle        (per £10 liability)
#   BACK_FAV_1.5_2 back any Match Odds runner offered 1.50-2.00 between 3' and 70', hold to settle      (per £10 stake)
#   LTD            0-0, 1'-10', lay the draw at 3.6-5.5; exit at the first goal (+2 min price) or 70'   (per £10 liability)
#   HOME_LAY_4PLUS pre-KO home 4.0-6.0 lay; exit the minute the home side scores, else settle           (per £10 liability)
#   HT_1_1_O25 / HT_2_0_O25 / HT_0_2_O25 / HT_0_0_U25 / HT_GOALFEST_O35 (3+ at HT) — the goal-signal lines at the REAL HT price
# Re-runnable for any date: COACH_DATE=YYYY-MM-DD (default today, Europe/London). Writes coach_tape + coach_path; log prints the
# day's summary (games, lines fired, £10 result per line) and nothing else.
mkdir -p /root/pe-coach
cat > /root/pe-coach/coach_tape.py <<'PY'
import sys,os,re,unicodedata,datetime,psycopg2,psycopg2.extras,pandas as pd,numpy as np
from zoneinfo import ZoneInfo
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET statement_timeout='2400s'")
D=os.environ.get('COACH_DATE') or datetime.datetime.now(ZoneInfo('Europe/London')).strftime('%Y-%m-%d')
d0=datetime.datetime.fromisoformat(D).replace(tzinfo=ZoneInfo('Europe/London')); d1=d0+datetime.timedelta(days=1)
cur.execute("""CREATE TABLE IF NOT EXISTS coach_tape (tape_date DATE, match TEXT, competition TEXT, line TEXT, minute INT, score TEXT, mkt TEXT, sel TEXT, side TEXT,
  price NUMERIC, exit_minute INT, exit_price NUMERIC, ft TEXT, pnl10 NUMERIC, note TEXT, PRIMARY KEY (tape_date, match, line, mkt, sel, minute));
CREATE TABLE IF NOT EXISTS coach_path (tape_date DATE, match TEXT, competition TEXT, mkt TEXT, sel TEXT, minute INT, score TEXT, back_px NUMERIC, lay_px NUMERIC, PRIMARY KEY (tape_date, match, mkt, sel, minute))""")
L=pd.read_sql("""SELECT ts, market_id, event_name, competition, mkt, sel, minute, ltp::float ltp, back_px::float back_px, lay_px::float lay_px
  FROM liq_sample WHERE ts>=%s AND ts<%s AND mkt IN ('MO','OU15','OU25','OU35','BTTS') AND event_name LIKE '%% v %%'""",con,params=(d0,d1))
T=pd.read_sql("SELECT fixture_id, captured_at, league_name, home_team, away_team, minute, score_home, score_away, status FROM goal_timeline WHERE captured_at>=%s AND captured_at<%s",con,params=(d0-datetime.timedelta(hours=2),d1+datetime.timedelta(hours=3)))
print(f"{D}: recorder rows {len(L)} | games on recorder {L.event_name.nunique()} | timeline fixtures {T.fixture_id.nunique()}",flush=True)
def norm(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
    s=re.sub(r"\b(fc|cf|afc|sc|ac|as|ss|us|sv|vfb|vfl|tsg|fk|club|de|the|athletic|atletico|sporting|real|cd|ud|sd|rcd|calcio|women|w|u21|u23|ii|b|if|bk|ff|aif|is|kv|sk|fsv|sv)\b"," ",s)
    return set(w for w in re.sub(r"[^a-z0-9 ]"," ",s).split() if len(w)>2)
def sim(a,b): A,B=norm(a),norm(b); return len(A&B)/max(1,len(A|B))
fx=T.groupby('fixture_id').agg(home=('home_team','first'),away=('away_team','first'),league=('league_name','first')).reset_index()
def match_fixture(ev):
    h,a=ev.split(' v ',1); best=None; bs=0; b2=0
    for f in fx.itertuples():
        sc=sim(h,f.home)+sim(a,f.away)
        if sc>bs: b2=bs; bs=sc; best=f.fixture_id
        elif sc>b2: b2=sc
    return best if bs>=1.0 and bs-b2>=0.3 else None
def tick(p): return 0.01 if p<2 else 0.02 if p<3 else 0.05 if p<4 else 0.1 if p<6 else 0.2 if p<10 else 0.5 if p<20 else 1 if p<30 else 2 if p<50 else 5 if p<100 else 10
def pnl(side,p,q,won):
    if side=='BACK':
        if q is None: r=10*(p-1) if won else -10.0
        else: r=10*(p/q-1)
    else:
        s=10/(p-1)
        if q is None: r=s if not won else -10.0
        else: r=s*(1-p/q)
    return round(r*0.98 if r>0 else r,2)
tape=[]; path=[]; games=0; matched=0
for ev,g in L.groupby('event_name'):
    games+=1; fid=match_fixture(ev)
    comp=g.competition.iloc[0]
    tl=T[T.fixture_id==fid].sort_values('captured_at') if fid else T.iloc[0:0]
    if len(tl)==0: continue
    matched+=1
    def score_at(m):
        s=tl[tl.minute<=m]
        if len(s)==0: return (0,0)
        r=s.iloc[-1]; return (int(r.score_home),int(r.score_away))
    ft=tl[tl.status.isin(['FT','AET','PEN'])]
    FT=(int(ft.iloc[-1].score_home),int(ft.iloc[-1].score_away)) if len(ft) else None
    ftxt=f"{FT[0]}-{FT[1]}" if FT else None
    # goals: first minute each score change seen
    gl=[]; prev=(0,0)
    for r in tl.itertuples():
        cur_s=(int(r.score_home),int(r.score_away))
        if cur_s!=prev and pd.notna(r.minute):
            if cur_s[0]>prev[0]: gl.append((int(r.minute),'h'))
            if cur_s[1]>prev[1]: gl.append((int(r.minute),'a'))
            prev=cur_s
    # price grid by (mkt,sel,minute) -> (back,lay); minute from recorder; pre-KO = earliest sample (minute null or 0)
    g=g.copy(); g['minute']=g.minute.fillna(0).astype(int)
    px={}
    for (mkt,sel),s in g.groupby(['mkt','sel']):
        s=s.sort_values('ts'); arr={}
        for r in s.itertuples():
            if r.back_px and r.lay_px and r.back_px>1 and r.lay_px>1: arr.setdefault(int(r.minute),(r.back_px,r.lay_px))
        px[(mkt,sel)]=arr
    def at(mkt,sel,m,tol=3):
        arr=px.get((mkt,sel),{})
        for mm in range(m,m+tol+1):
            if mm in arr: return arr[mm]
        return None
    def won(mkt,sel):
        if FT is None: return None
        hg,ag=FT; tot=hg+ag
        if mkt=='MO': return (hg>ag) if sel.upper().startswith('HOME') or sel==ev.split(' v ')[0] else (hg<ag) if sel.upper().startswith('AWAY') or sel==ev.split(' v ')[1] else hg==ag
        if mkt=='BTTS': return (hg>0 and ag>0)==(sel.upper().startswith('Y'))
        line=float(mkt[2]+'.'+mkt[3]); return (tot>line)==(sel.upper().startswith('O'))
    for (mkt,sel),arr in px.items():
        for m in (0,15,30,45,60,75,90):
            v=at(mkt,sel,m,4)
            if v: sh,sa=score_at(m); path.append((D,ev,comp,mkt,sel,m,f"{sh}-{sa}",v[0],v[1]))
    home,away=ev.split(' v ',1)
    fired=set()
    def add(line,m,mkt,sel,side,p,xm,q,note=''):
        key=(line,mkt,sel)
        if key in fired: return
        fired.add(key); w=won(mkt,sel); sh,sa=score_at(m)
        r=pnl(side,p,q,w) if (w is not None or q is not None) else None
        tape.append((D,ev,comp,line,m,f"{sh}-{sa}",mkt,sel,side,p,xm,q,ftxt,r,note))
    # BIAS lay 6-10 / BACK fav 1.5-2 : first minute between 3 and 70 the touch sits in band
    for (mkt,sel),arr in px.items():
        if mkt!='MO': continue
        for m in range(3,71):
            v=arr.get(m)
            if not v: continue
            if 6.0<=v[1]<=10.0: add('BIAS_LAY_6_10',m,mkt,sel,'LAY',v[1],None,None,'hold to settle')
            if 1.5<=v[0]<=2.0: add('BACK_FAV_1.5_2',m,mkt,sel,'BACK',v[0],None,None,'hold to settle')
    # LTD
    dr=px.get(('MO','The Draw'),{})
    for m in range(1,11):
        v=dr.get(m)
        if v and 3.6<=v[1]<=5.5 and score_at(m)==(0,0):
            nxt=next((gm for gm,s in gl if gm>m),None)
            if nxt and nxt<=70:
                q=at('MO','The Draw',nxt+2); add('LTD',m,'MO','The Draw','LAY',v[1],nxt+2,q[0] if q else None,f'goal {nxt}\'' )
            else:
                q=at('MO','The Draw',70); add('LTD',m,'MO','The Draw','LAY',v[1],70,q[0] if q else None,'no goal by 70 — stop')
            break
    # HOME lay 4+ pre-KO
    hv=px.get(('MO',home),{}).get(0)
    if hv and 4.0<=hv[1]<=6.0:
        hgm=next((gm for gm,s in gl if s=='h'),None)
        if hgm: q=at('MO',home,hgm+1); add('HOME_LAY_4PLUS',0,'MO',home,'LAY',hv[1],hgm+1,q[0] if q else None,f'home scored {hgm}\' — exit')
        else: add('HOME_LAY_4PLUS',0,'MO',home,'LAY',hv[1],None,None,'home never scored — settle')
    # HT lines at real HT price (minute 45-48 sample)
    hs=score_at(45); ht=f"{hs[0]}-{hs[1]}"
    def htline(name,mkt,selpref):
        sel=next((s for (mk,s) in px if mk==mkt and s.upper().startswith(selpref)),None)
        if not sel: return
        v=at(mkt,sel,45,4)
        if v: add(name,45,mkt,sel,'BACK',v[0],None,None,f'HT {ht}')
    if ht=='1-1': htline('HT_1_1_O25','OU25','O')
    if ht=='2-0': htline('HT_2_0_O25','OU25','O')
    if ht=='0-2': htline('HT_0_2_O25','OU25','O')
    if ht=='0-0': htline('HT_0_0_U25','OU25','U')
    if hs[0]+hs[1]>=3: htline('HT_GOALFEST_O35','OU35','O')
if path: psycopg2.extras.execute_values(cur,"INSERT INTO coach_path VALUES %s ON CONFLICT DO NOTHING",path,page_size=2000)
if tape: psycopg2.extras.execute_values(cur,"INSERT INTO coach_tape VALUES %s ON CONFLICT (tape_date,match,line,mkt,sel,minute) DO UPDATE SET exit_price=EXCLUDED.exit_price, ft=EXCLUDED.ft, pnl10=EXCLUDED.pnl10, note=EXCLUDED.note",tape,page_size=2000)
tp=pd.DataFrame(tape,columns=['d','match','comp','line','minute','score','mkt','sel','side','price','xm','xp','ft','pnl10','note'])
print(f"games on recorder {games} | matched to a live score feed {matched} | path points {len(path)} | lines fired {len(tp)}")
if len(tp):
    s=tp.groupby('line').agg(fired=('pnl10','size'),settled=('pnl10','count'),pnl10=('pnl10','sum'),per_trade=('pnl10','mean')).round(2)
    print(s.to_string())
PY
python3 -m py_compile /root/pe-coach/coach_tape.py || exit 1
# nightly at 23:35 London (server clock assumed UTC/London — both fine for a post-midnight-safe run), idempotent
( crontab -l 2>/dev/null | grep -v coach_tape.py; echo "35 23 * * * cd /root/pe-coach && python3 coach_tape.py >> /root/pe-coach/coach.log 2>&1" ) | crontab -
# back-fill the live-key days and run today so far
for d in 2026-10-27 2026-10-28 2026-10-29 2026-10-30 $(date +%F); do COACH_DATE=$d python3 /root/pe-coach/coach_tape.py 2>&1 | grep -v -E "UserWarning|pd.read_sql"; done
echo "cron:"; crontab -l | grep coach_tape
