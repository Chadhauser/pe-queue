#!/bin/bash
set -o pipefail
# 499_home_atp_close (Finder 2026-11-06, queue item 226, Finder's own, source c, from jobs/499_tennis_home.sh, jobs/499_young_fav_old.sh): ATP home runner at Pinnacle closes, on dates outside the tape window. Rule pushed before any odds were read. Read only. The number 499 is reused: 450-499 are all taken.
# TABLES tennis_matches (Railway, results with Pinnacle closes), tennis_results_2026 (Railway, ioc and tournament name). Join as jobs/499_young_fav_old.sh: tour, both players (folded surname + first initial), tournament start -21 to +2 days from the match; a unique match only.
# READ THE LAYS WITH CARE: a lay at a Pinnacle close collects Pinnacle's margin, which no exchange fill would (as item 74), so the lay lines flatter; ATP 1.5-2 favourites lay about +0.15 to +0.25 even in years when the error is near zero. Use the error and z, not the lay P&L.
# TEST, fixed first: HOME won minus de-vigged fair, close under 6.0, sits below the control's (either runner, neither local, under 6.0) by z <= -2. Control holds both runners of a match, so its error is near zero by construction. Back and lay at the close shown, one tick, 2%, £10. Closes are a proxy, so no line here can pass the bar: support only earns a forward test.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_500_000_000,1_500_000_000))  # this job only
import sys,re,time,unicodedata,warnings,psycopg2,pandas as pd,numpy as np
from collections import defaultdict,Counter
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,back_settle,lay_settle,line
pd.set_option('display.width',220); pd.set_option('display.max_rows',60); pd.set_option('display.max_columns',30)
T0=time.time()
# ATP names only: item 223's map, plus the names on dates before the tape. Cordoba on the ATP is the Argentine event.
COUNTRY={
 'USA':"US Open;Miami Masters;Indian Wells Masters;Cincinnati Masters;Winston-Salem;Dallas;Delray Beach;Washington;Houston;Atlanta;Newport;San Diego",
 'AUS':"Australian Open;Brisbane;Adelaide;Adelaide-1;Adelaide-2;Murray River Open;Great Ocean Road Open;Melbourne;Sydney",'NZL':"Auckland",
 'GBR':"Wimbledon;Queen's Club;Eastbourne",
 'FRA':"Roland Garros;Paris Masters;Montpellier;Metz;Marseille;Lyon",
 'ITA':"Rome Masters;Cagliari;Parma;Florence;Naples",
 'ESP':"Madrid Masters;Barcelona;Mallorca;Gijon;Marbella",
 'GER':"Hamburg;Halle;Munich;Stuttgart",
 'AUT':"Vienna;Kitzbuhel",'SUI':"Basel;Geneva;Gstaad",'MON':"Monte Carlo Masters",
 'NED':"Rotterdam;'s-Hertogenbosch",'BEL':"Antwerp;Brussels",'SWE':"Stockholm;Bastad",
 'ROU':"Bucharest",'BUL':"Sofia",'CRO':"Umag",'SRB':"Belgrade;Serbia",'BIH':"Banja Luka",'GRE':"Athens",'TUR':"Antalya",'ISR':"Tel Aviv",'RUS':"Moscow;St. Petersburg",
 'POR':"Estoril",'KAZ':"Almaty;Astana;Nur-Sultan",
 'CAN':"Canada Masters",
 'MEX':"Acapulco;Los Cabos",
 'BRA':"Rio de Janeiro;Rio De Janeiro",
 'ARG':"Buenos Aires;Cordoba",'CHI':"Santiago",
 'CHN':"Shanghai Masters;Shanghai;Beijing;Chengdu;Hangzhou;Zhuhai",'HKG':"Hong Kong",'JPN':"Tokyo",'KOR':"Seoul",
 'IND':"Pune",'SGP':"Singapore",
 'QAT':"Doha",'UAE':"Dubai",'MAR':"Marrakech",
}
NAME2C={n:c for c,v in COUNTRY.items() for n in v.split(';')}
assert len(NAME2C)==sum(len(v.split(';')) for v in COUNTRY.values()),"a tournament name sits under two countries"
TEAM=re.compile(r"^(Davis Cup|United Cup|ATP Cup|Laver Cup|ATP Finals|ATP Tour Finals|Tour Finals|Next ?Gen|Paris Olympics|Tokyo Olympics)")
def country(n):
    if TEAM.match(str(n)): return 'TEAM'
    return NAME2C.get(str(n).strip())
def state(ca,cb,c):
    if c is None or c=='TEAM' or not ca or not cb: return None
    if ca==c and cb==c: return None
    if ca==c: return 'a'
    if cb==c: return 'b'
    return 'CTRL'
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
def band(p): return '<1.5' if p<1.5 else '1.5-2' if p<2 else '2-3' if p<3 else '3-6' if p<6 else None
# known answers, worked by hand
assert country('Adelaide-1')=='AUS' and country('Cordoba')=='ARG' and country('Nur-Sultan')=='KAZ' and country('Tour Finals')=='TEAM' and country('NextGen Finals')=='TEAM' and country('Next Gen ATP Finals')=='TEAM' and country('Paris Olympics')=='TEAM' and country('ATP Cup')=='TEAM' and country('Davis Cup QLS R1: FRA vs BRA')=='TEAM' and country('Nowhere') is None
assert state('FRA','ESP','FRA')=='a' and state('ESP','FRA','FRA')=='b' and state('FRA','FRA','FRA') is None and state('ESP','GER','FRA')=='CTRL' and state('FRA','ESP','TEAM') is None and state('FRA','ESP',None) is None
assert key_short('De Minaur A.')==key_full('Alex De Minaur')==('deminaur','a') and key_short('Nadal') is None and key_full('Nadal') is None
assert abs(fair(1.5,3.0)-2/3)<1e-9 and abs(fair(1.9,1.9)-0.5)<1e-9 and band(1.49)=='<1.5' and band(5.9)=='3-6' and band(6.0) is None
assert abs(bk(2.0,True)-10*.99*.98)<1e-9 and bk(2.0,False)==-10.0 and np.isnan(bk(1.02,True)) and abs(ly(2.0,False)-10/1.02*.98)<1e-9 and ly(2.0,True)==-10.0
assert zdiff([0,0,0,1]*50,[0,1]*50)<-2 and abs(zdiff([0,1]*50,[0,1]*50))<1e-9
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
c=psycopg2.connect(creds.pg_railway(),sslmode='require')
M=pd.read_sql("SELECT tour,date,winner,loser,psw::float8 psw,psl::float8 psl,score FROM tennis_matches",c)
A=pd.read_sql("SELECT tour,tourney_name,tourney_date,winner_name,loser_name,winner_ioc,loser_ioc FROM tennis_results_2026 WHERE tour='ATP'",c); c.close()
M['d']=pd.to_datetime(M.date,errors='coerce'); M['tour']=M.tour.astype(str).str.upper(); A['tour']=A.tour.astype(str).str.upper(); A['c']=A.tourney_name.map(country)
print(f"tennis_matches rows {len(M)}, {M.d.min()} to {M.d.max()}, tours {M.tour.value_counts().to_dict()}; ATP result rows {len(A)}",flush=True)
ix=defaultdict(list)
for r in A.itertuples():
    a,b=key_full(r.winner_name),key_full(r.loser_name)
    if a and b: ix[(r.tour,frozenset((a,b)))].append((pd.Timestamp(r.tourney_date),a,r.winner_ioc,b,r.loser_ioc,r.c,r.tourney_name))
SK=Counter(); rows=[]; noc=Counter()
U=M[(M.d<'2024-08-31')|(M.d>'2026-03-31')]; SK['rows on unseen dates']=len(U)
for r in U.itertuples():
    if re.search(r"W/O|WO|WALK",str(r.score).upper()): SK['walkover']+=1; continue
    if not (r.psw>1 and r.psl>1): SK['no close']+=1; continue
    w,l=key_short(r.winner),key_short(r.loser)
    if not (w and l): SK['bad name']+=1; continue
    hits=[h for h in ix.get((r.tour,frozenset((w,l))),[]) if -21<=(h[0]-r.d).days<=2]
    if len(hits)!=1: SK['no unique match']+=1; continue
    h=hits[0]; ioc={h[1]:h[2],h[3]:h[4]}; cw,cl=ioc.get(w),ioc.get(l); co=h[5]
    if co is None: noc[h[6]]+=1
    st=state(cw,cl,co)
    if st is None: SK['both local, team, or no country']+=1; continue
    SK['scored '+('CTRL' if st=='CTRL' else 'HOME')]+=1
    fw=fair(r.psw,r.psl)
    for flag,p,won,fr in ((st in('a','CTRL'),r.psw,True,fw),(st in('b','CTRL'),r.psl,False,1-fw)):
        if flag and band(p): rows.append(('CTRL' if st=='CTRL' else 'HOME',band(p),r.d,p,won,float(won)-fr,bk(p,won),ly(p,won)))
print("counts:",dict(SK),"; no country:",dict(noc.most_common(15)),flush=True)
R=pd.DataFrame(rows,columns='st band d px won err vb vl'.split())
if R.empty or not (R.st=='HOME').any(): print("ERROR: no HOME rows, no verdict"); sys.exit(1)
print(f"dates {R.d.min()} to {R.d.max()}",flush=True)
H=R[R.st=='HOME']; C=R[R.st=='CTRL']; z=zdiff(H.err,C.err)
print(f"\n== TEST: HOME n {len(H)} won {H.won.mean():.3f} err {H.err.mean():+.4f} v CTRL n {len(C)} err {C.err.mean():+.4f}; z {z:.2f}; bar z <= -2: {'SUPPORTED' if z<=-2 else 'NOT SUPPORTED'}",flush=True)
out=[]
for (st,b),x in R.groupby(['st','band']):
    print(f"  {st} {b}: n {len(x)} err {x.err.mean():+.4f}"+("" if st=='CTRL' else f"; z v CTRL {zdiff(x.err,C[C.band==b].err):.2f}"))
    md=x.d.median(); hh=np.where(x.d<md,1,2)
    for side,col in (('back','vb'),('lay','vl')):
        k=x[col].notna().values; l=line(x[col].values[k],hh[k]); out.append(dict(st=st,band=b,side=side,n=l['n'],per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],won=x.won.mean(),implied=(1/x.px).mean()))
print("\n== closes, a proxy, by t\n",pd.DataFrame(out).sort_values('t',ascending=False).round(3).to_string(index=False))
print("\n== SURVIVORS: none can pass at closes; forward test only if the z test is supported")
print(f"total {time.time()-T0:.0f}s")
PY
