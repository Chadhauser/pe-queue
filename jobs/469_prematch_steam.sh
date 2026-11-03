#!/bin/bash
set -o pipefail
# 469 (Finder 2026-11-03, queue item 0h): PRE-MATCH STEAM CONTINUATION. stream_ticks football MO_PRE, pre-off (inplay=false, OPEN), whole table
# (rolling ~3.8 days; range printed). The feed starts ~T-2h (secs_to_off max ~7200), so a 15-min look-back can fire from T-105 min at the earliest.
# Signal at tick i: back_px has moved >= 3% (and >= 5%) against the standing book 15 min earlier (latest tick at or before t-900, at most 300 s older).
#   VOL = runner's traded volume in the last 15 min > its volume in the 15 min before that (needs a book at t-1800, so from T-90 min).
# Trades, entry at the real touch with one tick adverse (exact ladder):
#   STEAM back: back at back_px -1 tick, lay out at lay_px +1 tick.  DRIFT lay (mirror): lay at lay_px +1 tick (£10 liability), back out at back_px -1 tick.
#   CTRL back/lay: same trade at the first tick in the band with |move| < 3% (what friction alone costs).
# Exits: KO = the runner's last pre-off tick; P15 = first tick at or after t+900, else the last pre-off tick. Nothing is ever dropped: a runner with no
#   later tick exits at its own entry book (full spread + 2 ticks), counted as "no_later". KO exit age is reported; KOf re-tests with the exit book <= 300 s before the off.
# One entry per runner per signal per time-to-KO band (5-30, 30-60, 60-105 min); ONE = first STEAM per market only (one per game). 2% commission on profit.
# Halves by median entry time. Correlated: three runners and three bands per game, so tc (t on per-market means) is printed next to t.
# Pre-off positions do not settle, so the settled-market rule has nothing to act on here.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
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
    a=dn(bp0)
    if bp0<=1.01: return None
    return comm(10*(a/up(lp1)-1))
def lay_trade(lp0,bp1):
    a=up(lp0); c=max(1.01,dn(bp1)); return comm(10/(a-1)*(1-a/c))
# known answers, worked by hand:
# ladder edges: below 2.00 the step is 0.01, above it 0.02; 3.00 steps to 2.98 below and 3.05 above
assert dn(2.0)==1.99 and up(2.0)==2.02 and up(1.99)==2.0 and dn(3.0)==2.98 and up(3.0)==3.05 and dn(1.02)==1.01
# back 5.0 -> 4.9, lay out 4.0 -> 4.1: 10*(4.9/4.1-1)=1.951220, less 2% = 1.912195
assert abs(back_trade(5.0,4.0)-1.912195)<1e-6
# no price move, 1-tick spread: back 2.0 -> 1.99, lay out 2.02 -> 2.04: 10*(1.99/2.04-1) = -0.245098, a loss so no commission
assert abs(back_trade(2.0,2.02)+0.245098)<1e-6
# lay 5.0 -> 5.1 (stake 10/4.1), back out 6.0 -> 5.9 (step below 6.0 is 0.1): 2.439024*(1-5.1/5.9)=0.330715, less 2% = 0.324101
assert abs(lay_trade(5.0,6.0)-0.324101)<1e-6
# lay losing: 2.0 -> 2.02 (stake 9.803922), back out 1.5 -> 1.49: 9.803922*(1-2.02/1.49) = -3.487...; unfillable back price
assert abs(lay_trade(2.0,1.5)-(10/1.02*(1-2.02/1.49)))<1e-9 and back_trade(1.01,1.5) is None
print("ladder + P&L unit checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s';")
cur.execute("SELECT min(ts_recv), max(ts_recv) FROM stream_ticks"); r=cur.fetchone(); print("stream_ticks range:",r[0],"..",r[1],flush=True)
t0=time.time(); parts=[]
for a in pd.date_range(pd.Timestamp(r[0]).floor('6h'),pd.Timestamp(r[1]),freq='6h'):
    cur.execute("""SELECT market_id, sel_id, extract(epoch from ts_recv)::float8, secs_to_off, back_px::float8, back_sz::float8, lay_px::float8, lay_sz::float8, tv::float8
      FROM stream_ticks WHERE ts_recv>=%s AND ts_recv<%s AND sport='football' AND mkt='MO_PRE' AND inplay=false AND status='OPEN'""",(a,a+pd.Timedelta(hours=6)))
    parts.append(pd.DataFrame(cur.fetchall(),columns=['mid','sid','ts','sto','bp','bs','lp','ls','tv']))
    print(f"  chunk {a}: {len(parts[-1])} ticks ({int(time.time()-t0)}s)",flush=True)
T=pd.concat(parts,ignore_index=True); n_all=len(T)
T=T.dropna(subset=['bp','lp','sto'])
T=T[(T.bp>1)&(T.lp>T.bp)&(T.lp<1000)]
T=T.sort_values(['mid','sid','ts'],kind='stable')
print(f"ticks {n_all}, usable touch {len(T)}, markets {T.mid.nunique()}, runners {T.groupby(['mid','sid']).ngroups}, sto {T.sto.min()}..{T.sto.max()}",flush=True)
BANDS=((300,1800,'05-30'),(1800,3600,'30-60'),(3600,6300,'60-105'))
def pband(p): return '<2' if p<2 else '2-3' if p<3 else '3-5' if p<5 else '5-10' if p<10 else '10+'
rows=[]; nolater=0; unfill=0
for (mid,sid),g in T.groupby(['mid','sid'],sort=False):
    if len(g)<3: continue
    ts=g.ts.values; sto=g.sto.values.astype(float); bp=g.bp.values; lp=g.lp.values; bs=g.bs.values; ls=g.ls.values
    tv=pd.Series(g.tv.values).where(lambda s:s>0).ffill().values       # volume is a signal, never a fill price
    j=np.searchsorted(ts,ts-900,side='right')-1; k=np.searchsorted(ts,ts-1800,side='right')-1
    okj=(j>=0)&((ts-900-ts[np.maximum(j,0)])<=300); okk=(k>=0)&((ts-1800-ts[np.maximum(k,0)])<=300)
    mv=np.where(okj,bp/bp[np.maximum(j,0)]-1,np.nan)
    vr=np.where(okj&okk,(tv-tv[np.maximum(j,0)])>(tv[np.maximum(j,0)]-tv[np.maximum(k,0)]),False)&(tv-tv[np.maximum(j,0)]>0)
    for lo,hi,tb in BANDS:
        inb=(sto>=lo)&(sto<hi)&okj
        for sig,side,mask in (('STEAM3','B',mv<=-0.03),('STEAM5','B',mv<=-0.05),('STEAM3v','B',(mv<=-0.03)&vr),('STEAM5v','B',(mv<=-0.05)&vr),
                              ('DRIFT3','L',mv>=0.03),('DRIFT3v','L',(mv>=0.03)&vr),('CTRLb','B',np.abs(mv)<0.03),('CTRLl','L',np.abs(mv)<0.03)):
            c=np.where(inb&mask)[0]
            if not len(c): continue
            i=int(c[0]); last=len(ts)-1
            p15=int(np.searchsorted(ts,ts[i]+900,side='left')); p15=min(p15,last)
            if last==i: nolater+=1
            rec=dict(mid=mid,sid=sid,ts=ts[i],sig=sig,side=side,ttk=tb,band=pband(bp[i]),sprd=int(np.searchsorted(LAD,round(lp[i],2)-1e-9)-np.searchsorted(LAD,round(bp[i],2)-1e-9)),
                     fill=(bs[i]>=10 if side=='B' else ls[i]>=10),xage=float(sto[last]),lastflag=last==i)
            bad=False
            for ex,x in (('KO',last),('P15',p15)):
                r_=back_trade(bp[i],lp[x]) if side=='B' else lay_trade(lp[i],bp[x])
                if r_ is None: bad=True; break
                rec[ex]=r_
                rec['mv'+ex]=np.log(((bp[i]+lp[i])/2)/((bp[x]+lp[x])/2))    # >0 = mid shortened after entry
            if bad: unfill+=1; continue
            rows.append(rec)
R=pd.DataFrame(rows); print(f"entries {len(R)} | exit at own entry book, no later tick (kept): {nolater} | back at 1.01, unfillable (counted): {unfill}",flush=True)
if R.empty: print("\n== SURVIVORS: 0\nnone (no triggers)"); sys.exit()
med=R.ts.median(); R['h']=R.ts>=med; print("half split at",pd.Timestamp(med,unit='s',tz='UTC'))
print(f"KO exit book age: median {R.xage.median():.0f} s before the off; older than 300 s on {(R.xage>300).mean():.1%}; off-time ticks after schedule on {(R.xage<0).mean():.1%}")
span=(R.ts.max()-R.ts.min())/86400; print(f"entries span {span:.2f} days")
def tstat(x):
    x=np.asarray(x,dtype=float); s=x.std(ddof=1) if len(x)>1 else 0
    return x.mean()/(s/len(x)**0.5) if s>0 else 0.0
def cell(name,x,ex):
    a=x[~x.h][ex]; b=x[x.h][ex]
    return dict(cell=name,exit=ex,n=len(x),games=x.mid.nunique(),per10=x[ex].mean(),t=tstat(x[ex]),tc=tstat(x.groupby('mid')[ex].mean()),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,
                short=(x['mv'+ex]>0).mean(),long=(x['mv'+ex]<0).mean(),logmv=x['mv'+ex].mean())
out=[]
for sig,x in R.groupby('sig'):
    views=[(sig,x),(sig+' sz>=10',x[x.fill]),(sig+' spread<=2t',x[x.sprd<=2])]
    if sig.startswith('STEAM') or sig.startswith('DRIFT'):
        views.append((sig+' ONE',x.sort_values('ts').drop_duplicates('mid')))
    for b,y in x.groupby('band'): views.append((f'{sig} px {b}',y))
    for b,y in x.groupby('ttk'): views.append((f'{sig} ttk {b}',y))
    for (b,c),y in x.groupby(['band','ttk']): views.append((f'{sig} px {b} ttk {c}',y))
    for nm,y in views:
        if len(y)==0: continue
        for ex in ('KO','P15'): out.append(cell(nm,y,ex))
        f=y[y.xage<=300]
        if len(f) and nm==sig: out.append({**cell(nm+' KOf',f,'KO'),'exit':'KOf'})
S=pd.DataFrame(out).round(3)
S['PASS']=(S.n>=300)&(S.n1>=150)&(S.n2>=150)&(S.t>=3.5)&(S.h1>0)&(S.h2>0)&(S.per10>=0.15)
pd.set_option('display.width',260); pd.set_option('display.max_rows',200); pd.set_option('display.max_columns',40)
print(f"\ncells {len(S)}, with n>=300: {(S.n>=300).sum()}")
print("\n== headline: every signal, all bands (short/long = share of entries whose mid shortened/lengthened by the exit; logmv + = shortened)")
print(S[S.cell.isin(R.sig.unique())|S.cell.str.endswith(' KOf')|S.cell.str.endswith(' ONE')|S.cell.str.endswith('sz>=10')|S.cell.str.endswith('spread<=2t')].sort_values(['cell','exit']).to_string(index=False))
print("\n== top 15 by t, excluding CTRL"); print(S[~S.cell.str.startswith('CTRL')].sort_values('t',ascending=False).head(15).to_string(index=False))
print("\n== top 15 by t with n>=300, excluding CTRL"); print(S[(~S.cell.str.startswith('CTRL'))&(S.n>=300)].sort_values('t',ascending=False).head(15).to_string(index=False))
st=R[R.sig=='STEAM3v']
if span>0 and len(st): print(f"\nSTEAM3v accrual: {len(st)} entries, {st.mid.nunique()} games in {span:.2f} days = {len(st)/span:.0f} entries/day")
W=S[S.PASS].sort_values('t',ascending=False)
print(f"\n== SURVIVORS: {len(W)}"); print(W.to_string(index=False) if len(W) else "none")
PY
