#!/bin/bash
set -o pipefail
# 499_title_close (Finder 2026-11-06, queue item 320, from jobs/499_tennis_load_close.sh): first match after a title, close under 1.5, ATP, dates outside the tape. Rule pushed before any close was read. Read only. Closes are a proxy, so no line can pass the bar.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_500_000_000,1_500_000_000))  # this job only
import sys,re,time,unicodedata,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,line,back_settle,lay_settle
pd.set_option('display.width',240); pd.set_option('display.max_columns',30)
T0=time.time()
RANK={'1':0,'R128':5,'R64':6,'R32':7,'R16':8,'QF':9,'SF':10,'BR':10.5,'F':11,'RR':4,'Quarterfinals':9}
TEAM=re.compile(r"davis cup|atp cup|united cup|laver cup|billie jean|bjk|fed cup|hopman|olympic|finals",re.I)
def fold(s): return re.sub(r"[^a-z]","",unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower())
def key_short(s):
    w=str(s).strip().split()
    if len(w)<2: return None
    return fold(' '.join(w[:-1])),fold(w[-1])[:1]
def key_full(s):
    w=str(s).strip().split()
    if len(w)<2: return None
    return fold(' '.join(w[1:])),fold(w[0])[:1]
def fair(pa,pb): return (1/pa)/(1/pa+1/pb)
def bk(x,won):
    a=step(x,-1); return np.nan if a<=1.01 else back_settle(a,won)
def ly(x,won): return lay_settle(step(x,1),won)
def zdiff(a,b):
    a=np.asarray(a,float); b=np.asarray(b,float)
    return (a.mean()-b.mean())/np.sqrt(a.var(ddof=1)/len(a)+b.var(ddof=1)/len(b))
def band(p): return '<1.5' if p<1.5 else '1.5-2' if p<2 else '2-3' if p<3 else None
def prev_rank(ranks,cur):
    if cur==RANK['RR'] or cur==99: return None
    e=[r for r in ranks if r<cur]
    if not e: return None
    m=max(e)
    if m==RANK['RR'] or e.count(m)>1 or m==99: return None
    return m
def good_min(m): return m is not None and m==m and 20<=m<=400
def gap_state(a,b,big,even):
    d=a-b
    return 'a' if d>=big else 'b' if -d>=big else 'even' if abs(d)<=even else None
def is_first(ranks,cur): return cur!=99 and cur!=RANK['RR'] and RANK['RR'] not in ranks and 99 not in ranks and min(ranks)==cur and ranks.count(cur)==1
def unseen(d): return d<pd.Timestamp('2024-08-31') or d>pd.Timestamp('2026-03-31')
# known answers, worked by hand
assert prev_rank([7,8],9)==8 and prev_rank([8],8) is None and prev_rank([4],9) is None
assert gap_state(150,100,45,15)=='a' and gap_state(100,145,45,15)=='b' and gap_state(115,100,45,15)=='even' and gap_state(116,100,45,15) is None and gap_state(300,211,90,20) is None
assert is_first([7,8],7) and not is_first([7,8],8) and not is_first([4,7],7)
assert key_short('De Minaur A.')==key_full('Alex De Minaur')==('deminaur','a') and key_short('Nadal') is None
assert abs(fair(1.5,3.0)-2/3)<1e-9 and band(1.49)=='<1.5' and band(1.99)=='1.5-2' and band(2.99)=='2-3' and band(3.0) is None
assert unseen(pd.Timestamp('2024-08-30')) and unseen(pd.Timestamp('2026-04-01')) and not unseen(pd.Timestamp('2024-08-31')) and not unseen(pd.Timestamp('2026-03-31'))
assert abs(bk(2.0,True)-10*.99*.98)<1e-9 and bk(2.0,False)==-10.0 and np.isnan(bk(1.02,True)) and ly(2.0,True)==-10.0 and abs(ly(2.0,False)-10/1.02*.98)<1e-9
assert zdiff([0,1]*50,[0,0,0,1]*50)>2 and abs(zdiff([0,1]*50,[0,1]*50))<1e-9
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
c=psycopg2.connect(creds.pg_railway(),sslmode='require')
M=pd.read_sql("SELECT tour,date,winner,loser,psw::float8 psw,psl::float8 psl,score FROM tennis_matches",c)
T=pd.read_sql("SELECT tour,tourney_name,tourney_date,surface,minutes::float8 minutes,winner_name,loser_name,round,score FROM tennis_results_2026",c); c.close()
M['d']=pd.to_datetime(M.date,errors='coerce'); M['tour']=M.tour.astype(str).str.upper(); T['tour']=T.tour.astype(str).str.upper()
T=T[~T.score.astype(str).str.upper().str.contains(r"W/O|WO|WALK")&~T.tourney_name.str.contains(TEAM)&(T.tour=='ATP')]
print(f"tennis_matches rows {len(M)}, {M.d.min()} to {M.d.max()}; ATP result rows {len(T)}",flush=True)
played=defaultdict(list); MIN={}; ix=defaultdict(list); trn=defaultdict(dict)
for r in T.itertuples():
    a,b=key_full(r.winner_name),key_full(r.loser_name)
    if not (a and b): continue
    q=RANK.get(r.round,99); key=(r.tour,r.tourney_name,r.tourney_date)
    for x in (a,b):
        played[key+(x,)].append(q); MIN[key+(x,q)]=r.minutes if good_min(r.minutes) else None; trn[x][key]=trn[x].get(key,dict(date=pd.Timestamp(r.tourney_date),title=False,won=0,lost=0))
    if q==RANK['F']: trn[a][key]['title']=True
    trn[a][key]['won']+=1; trn[b][key]['lost']+=1
    ix[(r.tour,frozenset((a,b)))].append(dict(key=key,q=q,date=pd.Timestamp(r.tourney_date),w=a,l=b,surface=r.surface))
SK=Counter(); DAY={}; G=[]
# Dates of earlier rounds come from every tennis_matches row, tape window included: only the scored match must be outside it
for r in M[M.d.notna()&(M.tour=='ATP')].itertuples():
    if re.search(r"W/O|WO|WALK",str(r.score).upper()): SK['walkover']+=1; continue
    w,l=key_short(r.winner),key_short(r.loser)
    if not (w and l): SK['bad name']+=1; continue
    hits=[h for h in ix.get((r.tour,frozenset((w,l))),[]) if -21<=(h['date']-r.d).days<=2]
    if len(hits)!=1: SK['no unique match, or a team event or finals']+=1; continue
    h=hits[0]
    if h['w']!=w: SK['winner disagrees between tables']+=1; continue
    DAY[h['key']+(w,h['q'])]=r.d; DAY[h['key']+(l,h['q'])]=r.d
    if not unseen(r.d): SK['inside the tape window, not scored']+=1; continue
    if not (r.psw>1 and r.psl>1): SK['no close']+=1; continue
    SK['matched']+=1; G.append((h,r))
print("counts:",dict(SK),f"| {time.time()-T0:.0f}s",flush=True)
def tot_min(h,x):
    r=[q for q in played[h['key']+(x,)] if q<h['q']]
    if RANK['RR'] in r or 99 in r or h['q']==RANK['RR'] or len(r)!=len(set(r)): return None
    mm=[MIN.get(h['key']+(x,q)) for q in r]
    if any(m is None for m in mm): return None
    return len(r),sum(mm)
def prev(h,x):
    q=prev_rank(played[h['key']+(x,)],h['q'])
    if q is None: return None,None
    return MIN.get(h['key']+(x,q)),DAY.get(h['key']+(x,q))
def prior_t(h,x):
    """Most recent other tournament of x starting 5 to 16 days before this one, as item 306."""
    best=None
    for k,t_ in trn[x].items():
        g=(h['date']-t_['date']).days
        if k!=h['key'] and 5<=g<=16 and (best is None or t_['date']>best['date']): best=t_
    return best
rows=[]; LB=Counter()
for h,r in G:
    w,l=h['w'],h['l']; fw=fair(r.psw,r.psl); lab=defaultdict(list)
    fw_,fl_=is_first(played[h['key']+(w,)],h['q']),is_first(played[h['key']+(l,)],h['q'])
    pw=prior_t(h,w) if fw_ else None; pl=prior_t(h,l) if fl_ else None
    tw_,tl_=bool(pw and pw['title']),bool(pl and pl['title'])
    for who,p_,me,op in ((w,pw,tw_,tl_),(l,pl,tl_,tw_)):
        if not p_: continue
        if me and not op: lab[who].append('TITLE')
        elif p_['won']==0 and p_['lost']>0: lab[who].append('CTRL')
    for who,ls in lab.items():
        won=who==w; p=r.psw if won else r.psl; fr=fw if won else 1-fw
        for st in ls:
            LB[st]+=1; rows.append((st,band(p),r.d,p,won,float(won)-fr,bk(p,won),ly(p,won)))
print("labels, any price:",dict(sorted(LB.items())),flush=True)
A=pd.DataFrame(rows,columns='st band d px won err vb vl'.split()); A['won']=A.won.astype(bool)
print(f"dates {A.d.min()} to {A.d.max()}; by year {A.d.dt.year.value_counts().sort_index().to_dict()}",flush=True)
print("\n== TEST, close under 1.5, z >= 2 downward against the control")
o=A[(A.st=='TITLE')&(A.band=='<1.5')]; c_=A[(A.st=='CTRL')&(A.band=='<1.5')]; z=-zdiff(o.err,c_.err); x=o.copy(); x['vl']=[ly(p,w_) for p,w_ in zip(x.px,x.won)]; ll=line(x.vl.values,np.where(x.d<x.d.median(),1,2))
print(f"  TITLE <1.5: n {len(o)} won {o.won.mean():.3f} implied {(1/o.px).mean():.3f} err {o.err.mean():+.4f} v control n {len(c_)} err {c_.err.mean():+.4f}; z downward {z:.2f}: {'SUPPORTED' if z>=2 else 'NOT SUPPORTED'}; lay at the close, one tick, 2%: n {ll['n']} {ll['per10']:+.3f} t {ll['t']:.2f} h1 {ll['h1']:+.3f} h2 {ll['h2']:+.3f}",flush=True)
print("\n== context, by band, err v control, not tests")
for b in ('<1.5','1.5-2','2-3'):
    o=A[(A.st=='TITLE')&(A.band==b)]; c_=A[(A.st=='CTRL')&(A.band==b)]
    if len(o)>1 and len(c_)>1: print(f"  TITLE {b}: n {len(o)} err {o.err.mean():+.4f} v n {len(c_)} err {c_.err.mean():+.4f}; z {zdiff(o.err,c_.err):.2f}")
print("\n== SURVIVORS: none can pass at closes; item 321 only if the z test is supported")
print(f"total {time.time()-T0:.0f}s")
PY
