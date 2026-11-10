#!/bin/bash
# 547 (Tue 10 Nov 2026). READY BEFORE THE PURCHASE: the Betfair ADVANCED history loader and the resting-order replay on it, so the hour
# Peter's Advanced months appear on his account they load and replay by themselves — nothing designed after the download.
# Advanced files = the same per-market stream files as Basic, but every second with the top 3 of the ladder (atb/atl price+size deltas)
# and traded volume. The loader keeps each runner's ladder state, writes one book row per runner every 5 s in the last 60 min before the
# off and every 15 s in play (Soccer: MATCH_ODDS, OVER_UNDER_25 and every type with a passed cell), plus the official runner result from
# the final market definition into bf_hist_result (same table the map uses). Table: bf_hist_book. Hourly cron; it exits in a second when
# no Advanced month is owned, so it costs nothing until the purchase. Months load newest-first, football first, one at a time; each month
# is replayed as soon as it lands (replay_fills_hist.py) and the table fair_price_replay_hist + reports/replay_hist_<date>.md say per cell:
# quotes, fills, fill rate, settled n, £ per £100, adverse move 10 min after fill — on YEARS of real books, not three weeks.
set -o pipefail
export PYTHONDONTWRITEBYTECODE=1
mkdir -p /root/pe-hist && cd /root/pe-hist
cat > loader_adv.py <<'PYFILE'
import os, sys, bz2, json, time, calendar, datetime, shutil, requests, psycopg2, psycopg2.extras, fcntl
sys.path.insert(0,'/root/pe-queue/runner'); import creds
LOCK=open('/root/pe-hist/.adv.lock','w')
try: fcntl.flock(LOCK,fcntl.LOCK_EX|fcntl.LOCK_NB)
except OSError: print("another Advanced load is running"); sys.exit(0)
APP,U,P=creds.betfair()
r=requests.post("https://identitysso.betfair.com/api/login",data={"username":U,"password":P},headers={"X-Application":APP,"Accept":"application/json"},timeout=20).json()
tok=r.get('token'); H={"ssoid":tok,"Content-Type":"application/json"}
md=requests.get("https://historicdata.betfair.com/api/GetMyData",headers=H,timeout=30).json()
if md: print("GetMyData item keys:",sorted(md[0].keys()))
adv=set()
for d in md:
    plan=str(d.get('plan') or d.get('planName') or '')
    if 'advanced' in plan.lower() or 'pro' in plan.lower():
        fd=str(d.get('forDate'))[:7]; adv.add((d.get('sport'),int(fd[:4]),int(fd[5:7]),plan))
if not adv: print("no Advanced/Pro months owned yet — nothing to do"); sys.exit(0)
con=psycopg2.connect(creds.pg_local(),sslmode='disable'); con.autocommit=True; cur=con.cursor()
cur.execute("""CREATE TABLE IF NOT EXISTS bf_hist_book (sport TEXT, market_id TEXT, market_type TEXT, event_name TEXT, market_time TIMESTAMPTZ, country TEXT, n_winners INT,
  sel TEXT, sel_id BIGINT, ts TIMESTAMPTZ, inplay BOOLEAN, bb1 NUMERIC, bs1 NUMERIC, bb2 NUMERIC, bs2 NUMERIC, bb3 NUMERIC, bs3 NUMERIC, bl1 NUMERIC, ls1 NUMERIC, bl2 NUMERIC, ls2 NUMERIC, bl3 NUMERIC, ls3 NUMERIC, ltp NUMERIC, tv NUMERIC);
  CREATE INDEX IF NOT EXISTS bfb_mkt ON bf_hist_book (market_id, ts); CREATE INDEX IF NOT EXISTS bfb_type ON bf_hist_book (sport, market_type, market_time);
  CREATE TABLE IF NOT EXISTS bf_hist_adv_files (path TEXT PRIMARY KEY, loaded_at TIMESTAMPTZ);
  CREATE TABLE IF NOT EXISTS bf_hist_adv_months (sport TEXT, y INT, m INT, status TEXT, files INT, loaded INT, updated TIMESTAMPTZ, PRIMARY KEY (sport,y,m))""")
cur.execute("SELECT sport,y,m,status FROM bf_hist_adv_months"); st={(a,b,c):d for a,b,c,d in cur.fetchall()}
cur.execute("SELECT DISTINCT market_type FROM fair_price_passed WHERE sport='Soccer'"); TYPES=sorted({'MATCH_ODDS','OVER_UNDER_25'}|{t for (t,) in cur.fetchall()})
todo=sorted([a for a in adv if st.get(a[:3]) not in ('DONE','EMPTY')],key=lambda a:(a[0]!='Soccer',-a[1],-a[2]))
print("Advanced months owned:",len(adv),"to load:",len(todo),"types:",TYPES,flush=True)
def top3(ladder,reverse):
    items=sorted([(p,s) for p,s in ladder.items() if s>0],key=lambda x:x[0],reverse=reverse)[:3]
    out=[]
    for i in range(3): out+= [items[i][0],items[i][1]] if i<len(items) else [None,None]
    return out
def parse(local,sport):
    md_=None; runners={}; atb={}; atl={}; ltp={}; tv={}; last_emit={}; rows=[]; res=[]
    with bz2.open(local,'rt') as f:
        for ln in f:
            if not ln.strip(): continue
            try: o=json.loads(ln)
            except Exception: continue
            pt=o.get('pt')
            for mc in o.get('mc',[]):
                mid=mc.get('id')
                if 'marketDefinition' in mc:
                    md_=mc['marketDefinition']; runners.update({x['id']:x['name'] for x in md_.get('runners',[])})
                if not md_: continue
                inplay=bool(md_.get('inPlay')); mt=md_.get('marketType'); mtime=md_.get('marketTime')
                try: sto=(datetime.datetime.fromisoformat(mtime.replace('Z','+00:00'))-datetime.datetime.fromtimestamp(pt/1000,datetime.timezone.utc)).total_seconds()
                except Exception: sto=None
                for rc in mc.get('rc',[]):
                    sid=rc['id']; L=atb.setdefault(sid,{}); M=atl.setdefault(sid,{})
                    for p,s in rc.get('atb',[]): L[p]=s
                    for p,s in rc.get('atl',[]): M[p]=s
                    if 'ltp' in rc: ltp[sid]=rc['ltp']
                    if 'tv' in rc: tv[sid]=rc['tv']
                    if sto is None or (not inplay and sto>3600): continue
                    step=5 if not inplay else 15
                    if pt//1000-last_emit.get(sid,-99)<step: continue
                    last_emit[sid]=pt//1000
                    b=top3(L,True); l=top3(M,False)
                    rows.append((sport,mid,mt,md_.get('eventName'),mtime,md_.get('countryCode'),md_.get('numberOfWinners'),runners.get(sid,str(sid)),sid,datetime.datetime.fromtimestamp(pt/1000,datetime.timezone.utc),inplay,*b,*l,ltp.get(sid),tv.get(sid)))
    if md_:
        for x in md_.get('runners',[]):
            if x.get('status') in ('WINNER','LOSER'): res.append((sport,str(mid),str(md_.get('eventId')),md_.get('marketType'),runners.get(x['id'],str(x['id'])),x['status'],md_.get('settledTime'),md_.get('status')))
    return rows,res,md_
T0=time.time()
for sport,y,m,plan in todo:
    if shutil.disk_usage('/root').free<20e9: print("WAITING: box disk under 20 GB free"); break
    mts=TYPES if sport=='Soccer' else []
    body={"sport":sport,"plan":plan,"fromDay":1,"fromMonth":m,"fromYear":y,"toDay":calendar.monthrange(y,m)[1],"toMonth":m,"toYear":y,"marketTypesCollection":mts,"countriesCollection":[],"fileTypeCollection":["M"]}
    r=requests.post("https://historicdata.betfair.com/api/DownloadListOfFiles",headers=H,json=body,timeout=180)
    files=r.json() if r.status_code==200 else []
    print(f"{sport} {y}-{m:02d} ({plan}): {len(files)} files",flush=True)
    if not files: cur.execute("INSERT INTO bf_hist_adv_months VALUES (%s,%s,%s,'EMPTY',0,0,now()) ON CONFLICT (sport,y,m) DO UPDATE SET status='EMPTY', updated=now()",(sport,y,m)); continue
    cur.execute("INSERT INTO bf_hist_adv_months VALUES (%s,%s,%s,'LOADING',%s,0,now()) ON CONFLICT (sport,y,m) DO UPDATE SET status='LOADING', files=%s, updated=now()",(sport,y,m,len(files),len(files)))
    cur.execute("SELECT path FROM bf_hist_adv_files"); done={p for (p,) in cur.fetchall()}; n=0; buf=[]; rbuf=[]
    for fp in files:
        if fp in done: continue
        try:
            d=requests.get("https://historicdata.betfair.com/api/DownloadFile",params={"filePath":fp},headers={"ssoid":tok},timeout=120)
            local='/root/pe-hist/.adv.bz2'; open(local,'wb').write(d.content)
            rows,res,md_=parse(local,sport); buf+=rows; rbuf+=res
        except Exception as e: print("file failed",fp[-40:],repr(e)[:80],flush=True); continue
        cur.execute("INSERT INTO bf_hist_adv_files VALUES (%s,NOW()) ON CONFLICT DO NOTHING",(fp,)); n+=1
        if len(buf)>=50000:
            psycopg2.extras.execute_values(cur,"INSERT INTO bf_hist_book VALUES %s",buf,page_size=5000); buf=[]
            if rbuf: psycopg2.extras.execute_values(cur,"INSERT INTO bf_hist_result VALUES %s ON CONFLICT DO NOTHING",rbuf,page_size=5000); rbuf=[]
            cur.execute("UPDATE bf_hist_adv_months SET loaded=%s, updated=now() WHERE sport=%s AND y=%s AND m=%s",(n,sport,y,m))
    if buf: psycopg2.extras.execute_values(cur,"INSERT INTO bf_hist_book VALUES %s",buf,page_size=5000)
    if rbuf: psycopg2.extras.execute_values(cur,"INSERT INTO bf_hist_result VALUES %s ON CONFLICT DO NOTHING",rbuf,page_size=5000)
    cur.execute("UPDATE bf_hist_adv_months SET status='DONE', loaded=%s, updated=now() WHERE sport=%s AND y=%s AND m=%s",(n,sport,y,m))
    print(f"  loaded {n} files in {(time.time()-T0)/60:.0f} min — replaying this month now",flush=True)
    os.system(f"cd /root/pe-sports/team && timeout 7000 python3 replay_fills_hist.py {y} {m} >> replay_hist.log 2>&1")
print("Advanced loader pass complete")
PYFILE
python3 -m py_compile loader_adv.py && echo "loader_adv compiles"
cd /root/pe-sports/team && cat > replay_fills_hist.py <<'PYFILE'
# Resting-order replay on the ADVANCED history book (bf_hist_book), one month per run (argv: year month) or all loaded months.
# Same rules as replay_fills.py (546): per passed cell, every 5 min in the last hour pre-off, rest the bot's quote, fill one tick adverse
# within 10 min, settle on the OFFICIAL result (bf_hist_result), adverse move 10 min after fill; control = runners in no cell, random side.
import sys, json, datetime, numpy as np, pandas as pd, psycopg2, psycopg2.extras
sys.path.insert(0,'/root/pe-queue/runner'); import creds
COMM=0.02; STAKE=2.0; STEP=300; HOLD=600; MIN_SIZE=10.0; MAX_SPREAD=3; MAX_PRICE=20.0
LADDER=[(2,0.01),(3,0.02),(4,0.05),(6,0.1),(10,0.2),(20,0.5),(30,1),(50,2),(100,5),(1000,10)]
def tick(p):
    for lim,inc in LADDER:
        if p<lim: return inc
    return 10
def tick_down(p): return round(max(1.01,p-tick(p-1e-9)),2)
def tick_up(p): return round(min(1000,p+tick(p)),2)
def nticks(a,b):
    n=0; p=a
    while p<b-1e-9 and n<50: p=tick_up(p); n+=1
    return n
con=psycopg2.connect(creds.pg_local(),sslmode='disable'); cur=con.cursor(); cur.execute("SET statement_timeout=0; SET work_mem='256MB'")
cur.execute("SELECT sport, market_type, band_lo, band_hi, side, fair_factor FROM fair_price_passed"); C={}
for sp,mt,lo,hi,side,f in cur.fetchall(): C.setdefault((sp,mt),[]).append((float(lo),float(hi),side,float(f)))
def cell_for(sp,mt,p):
    for lo,hi,side,f in C.get((sp,mt),[]):
        if lo<=p<hi: return side,f
    return None,None
where="" ; args=()
if len(sys.argv)>=3: where="AND date_trunc('month',market_time)=make_date(%s,%s,1)"; args=(int(sys.argv[1]),int(sys.argv[2]))
cur.execute(f"SELECT DISTINCT market_id, sport, market_type FROM bf_hist_book WHERE NOT inplay {where}",args); mk=cur.fetchall()
print("markets:",len(mk),flush=True)
res={}
cur.execute("SELECT market_id, sel, status FROM bf_hist_result WHERE market_id = ANY(%s)",([m for m,_,_ in mk],))
for m,s,stt in cur.fetchall(): res.setdefault(m,{})[s]=stt
quotes=[]
for i_m,(mid,sp,mt) in enumerate(mk):
    cur.execute("SELECT ts, sel, bb1, bs1, bl1, ls1 FROM bf_hist_book WHERE market_id=%s AND NOT inplay ORDER BY ts",(mid,))
    df=pd.DataFrame(cur.fetchall(),columns=['ts','sel','bb','bs','bl','ls'])
    if df.empty or df.sel.nunique()<2: continue
    for c in ('bb','bs','bl','ls'): df[c]=pd.to_numeric(df[c],errors='coerce')
    sels=df.sel.unique(); g=df.set_index('ts').groupby('sel').resample('60s').last().ffill().reset_index(); times=sorted(g.ts.unique())
    for i,t in enumerate(times):
        if i%(STEP//60): continue
        snap=g[g.ts==t].dropna(subset=['bb','bl'])
        if len(snap)<len(sels): continue
        mids_=(snap.bb+snap.bl)/2; tot=(1/mids_[mids_>1]).sum()
        if tot<=0: continue
        fut=g[(g.ts>t)&(g.ts<=t+pd.Timedelta(seconds=HOLD))]
        for _,r in snap.iterrows():
            bb,bl,bs,ls=float(r.bb),float(r.bl),float(r.bs or 0),float(r.ls or 0)
            if bl<=bb or bs<MIN_SIZE or ls<MIN_SIZE or bl>MAX_PRICE or nticks(bb,bl)>MAX_SPREAD: continue
            p=(1/((bb+bl)/2))/tot; side,f=cell_for(sp,mt,p); incell=side is not None
            if not incell: side='BACK' if (hash((mid,str(r.sel),i))%2) else 'LAY'; f=1.0
            fair=1/max(0.005,min(0.995,p*f)); nt=nticks(bb,bl)
            if side=='BACK':
                q=tick_up(bb) if nt>=2 else bb
                if incell and not (q>=fair and q<bl): continue
            else:
                q=tick_down(bl) if nt>=2 else bl
                if incell and not (q<=fair and q>bb): continue
            fr=fut[fut.sel==r.sel]; hit=fr[fr.bb>=tick_up(q)] if side=='BACK' else fr[fr.bl<=tick_down(q)]
            filled=len(hit)>0; adv=None; pnl=None
            if filled:
                tf=hit.ts.iloc[0]; after=fr[fr.ts>=tf+pd.Timedelta(seconds=HOLD)]
                if len(after): m2=float((after.bb.iloc[0]+after.bl.iloc[0])/2); adv=(q/m2-1) if side=='BACK' else (m2/q-1)
                stt=res.get(mid,{}).get(r.sel)
                if stt in ('WINNER','LOSER'):
                    won=stt=='WINNER'; gross=((q-1)*STAKE if won else -STAKE) if side=='BACK' else (-(q-1)*STAKE if won else STAKE); pnl=gross*(1-COMM) if gross>0 else gross
            quotes.append((mid,sp,mt,str(r.sel),incell,side,q,p,filled,adv,pnl))
    if i_m%300==0: print(f"  {i_m}/{len(mk)} quotes {len(quotes)}",flush=True)
Q=pd.DataFrame(quotes,columns=['mid','sport','mt','sel','incell','side','q','p','filled','adv','pnl'])
def band_of(sp,mt,p):
    for lo,hi,side,f in C.get((sp,mt),[]):
        if lo<=p<hi: return lo
Q['band']=[band_of(s,m,p) if ic else None for s,m,p,ic in zip(Q.sport,Q.mt,Q.p,Q.incell)]
cur.execute("CREATE TABLE IF NOT EXISTS fair_price_replay_hist (run_at TIMESTAMPTZ DEFAULT now(), month TEXT, sport TEXT, market_type TEXT, band_lo NUMERIC, side TEXT, quotes INT, fills INT, fill_rate NUMERIC, settled INT, pnl NUMERIC, per100 NUMERIC, adverse_10m NUMERIC)")
label=f"{sys.argv[1]}-{int(sys.argv[2]):02d}" if len(sys.argv)>=3 else 'all'
cur.execute("DELETE FROM fair_price_replay_hist WHERE month=%s",(label,))
lines=[f"# Resting-order replay on ADVANCED books — month {label} ({datetime.date.today()})","",f"markets {len(mk)} | quotes {len(Q)} | fills {int(Q.filled.sum())} | settled {int(Q.pnl.notna().sum())} | £2 a quote, one tick adverse, 2% commission, official results","","| cell | quotes | fills | fill rate | settled | £ | £ per £100 | adverse 10 min |","|---|---|---|---|---|---|---|---|"]
rows=[]
def line(name,g,key=None):
    fl=g[g.filled]; st=fl[fl.pnl.notna()]; per=(st.pnl.sum()/(len(st)*STAKE)*100) if len(st) else None; adv=fl.adv.dropna().mean() if fl.adv.notna().any() else None
    lines.append(f"| {name} | {len(g)} | {len(fl)} | {len(fl)/max(1,len(g)):.1%} | {len(st)} | {st.pnl.sum():+.2f} | {'n/a' if per is None else f'{per:+.2f}'} | {'n/a' if adv is None else f'{adv:+.2%}'} |")
    if key: rows.append((label,*key,len(g),len(fl),len(fl)/max(1,len(g)),len(st),round(float(st.pnl.sum()),2),round(per,2) if per is not None else None,round(float(adv),4) if adv is not None else None))
for (sp,mt,band,side),g in Q[Q.incell].groupby(['sport','mt','band','side']): line(f"{sp} {mt} p{band:.2f} {side}",g,(sp,mt,band,side))
line("CONTROL (no cell, random side)",Q[~Q.incell])
if rows: psycopg2.extras.execute_values(cur,"INSERT INTO fair_price_replay_hist (month,sport,market_type,band_lo,side,quotes,fills,fill_rate,settled,pnl,per100,adverse_10m) VALUES %s",rows)
con.commit()
open(f"/root/pe-queue/reports/replay_hist_{label}.md",'w').write("\n".join(lines)+"\n"); print("\n".join(lines))
import subprocess; subprocess.run("cd /root/pe-queue && git add reports && git commit -q -m 'replay on Advanced books "+label+"' && git pull -q --rebase && git push -q",shell=True)
PYFILE
python3 -m py_compile replay_fills_hist.py && echo "replay_hist compiles"
( crontab -l 2>/dev/null | grep -v 'loader_adv.py'; echo "15 * * * * cd /root/pe-hist && timeout 72000 /usr/bin/python3 loader_adv.py >> loader_adv.log 2>&1" ) | crontab -
cd /root/pe-hist && timeout 120 python3 loader_adv.py | head -5
echo "547 done — loader and replay armed; they start by themselves the hour Advanced months appear on the account"
