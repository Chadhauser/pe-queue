#!/bin/bash
set -o pipefail
# 499_tennis_home (Finder 2026-11-06, queue item 223, Finder's own, source c): home player at the last pre-off print. Rule pushed before any price was read. Read only. The number 499 is reused: 450-499 are all taken.
# TAPE, ENTRY, MATCH, RETIREMENTS as jobs/499_tennis_format.sh: T-20 to T-2, worse of the print and the next within 120 s, one tick, <= 50, 2%, £10 risk, to the result, last-traded prints so an upper bound; unique match on both names, tournament start -2 to +21 days; a line must also clear +£0.15 with retirements removed.
# RULE: HOME = runner whose ioc is the tournament country, opponent's is not. Bands <1.5, 1.5-2, 2-3, 3-6. Back and lay. ALL, ATP, WTA, CHALLENGER. Control = either runner where neither is local, same band, cannot pass. Team events and season finals out.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_800_000_000,1_800_000_000))  # this job only
import sys,re,time,unicodedata,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,line,back_settle,lay_settle
pd.set_option('display.width',240); pd.set_option('display.max_rows',150); pd.set_option('display.max_columns',30)
T0=time.time(); BUDGET=2100
COUNTRY={
 'USA':"US Open;Miami Masters;Indian Wells Masters;Cincinnati Masters;Winston-Salem;Winston Salem;Dallas;Delray Beach;Washington;Houston;Miami;Indian Wells;Cincinnati;Charleston;Austin;Cleveland;Champaign;San Diego;Columbus;Sioux Falls;Cary;Las Vegas;Tiburon;Charlottesville;Phoenix;Knoxville;Chicago;Lincoln;Tyler;Newport;Savannah;Bloomfield Hills;Tallahassee;Baton Rouge;Lexington;Sarasota;Little Rock;Sumter;Fairfield",
 'AUS':"Australian Open;Brisbane;Adelaide;Hobart;Canberra;Playford;Sydney",'NZL':"Auckland",
 'GBR':"Wimbledon;Queen's Club;Eastbourne;Nottingham;Glasgow;Birmingham;Ilkley",
 'FRA':"Roland Garros;Paris Masters;Montpellier;Metz;Marseille;Rouen;Strasbourg;Quimper;Pau;Cherbourg;Lille;Mouilleron le Captif;Brest;Saint-Tropez;Thionville;Orleans;Cassis;Roanne;Rennes;St. Brieuc;Saint-Brieuc;Troyes;Lyon;Royan;Bordeaux;Aix-en-Provence;Noumea",
 'ITA':"Rome Masters;Rome;Todi;Genoa;Naples;Olbia;Como;Rovereto;Milan;Vicenza;Perugia;Trieste;Biella;Modena;Monza;Barletta;Sassuolo;Bergamo;Cordenons;Francavilla al Mare;Cesenatico;Turin",
 'ESP':"Madrid Masters;Madrid;Barcelona;Mallorca;Villena;Tenerife;Valencia;Murcia;Seville;Montemar;Alicante;Girona;Segovia;Menorca;Pozoblanco;Manacor",
 'GER':"Hamburg;Halle;Munich;Stuttgart;Bad Homburg;Berlin;Koblenz;Braunschweig;Augsburg;Heilbronn - Bad Rappenau;Bonn;Hagen",
 'AUT':"Vienna;Kitzbuhel;Linz;Tulln;Bad Waltersdorf;Mauthausen",'SUI':"Basel;Geneva;Gstaad;Lugano;Zug",'MON':"Monte Carlo Masters",
 'NED':"Rotterdam;'s-Hertogenbosch;Rosmalen;Bunschoten",'BEL':"Antwerp;Brussels",'SWE':"Stockholm;Bastad",'FIN':"Helsinki;Tampere",
 'POL':"Szczecin;Grodzisk Mazowiecki;Poznan",'CZE':"Prague Open;Prague;Ostrava;Liberec;Prostejov",'SVK':"Bratislava",
 'ROU':"Bucharest;Iasi;Cluj-Napoca;Targu Mures;Brasov;Sibiu",'BUL':"Dobrich;Sofia",'CRO':"Umag;Zadar;Zagreb;Split",'SRB':"Belgrade",'GRE':"Athens;Hersonissos;Crete",'TUR':"Istanbul",
 'POR':"Lisbon;Braga;Oeiras;Maia;Porto;Estoril",'SMR':"San Marino",'MDA':"Chisinau",'MKD':"Skopje",'GEO':"Tbilisi",'KAZ':"Almaty;Astana",
 'CAN':"Canada Masters;Montreal;Drummondville;Granby;Calgary;Winnipeg",
 'MEX':"Acapulco;Los Cabos;Merida;Guadalajara;Monterrey;San Luis Potosi;Morelia;Puerto Vallarta;Manzanillo;Morelos;Metepec;Cancun;Mexico City",
 'BRA':"Rio de Janeiro;Sao Paulo;Curitiba;Piracicaba;Brasilia;Itajai;Sao Leopoldo;Florianopolis;Costa do Sauipe;Porto Alegre;Santos",
 'ARG':"Buenos Aires;Villa Maria;Rosario;Tigre;Santa Fe;San Miguel de Tucuman",'CHI':"Santiago;Concepcion;Temuco;Antofagasta",'PAR':"Asuncion",'URU':"Montevideo;Punta del Este",'BOL':"Santa Cruz de la Sierra",'PER':"Lima;Lima - Los Inkas",'ECU':"Guayaquil",'COL':"Bogota;Cali;Barranquilla;Bucaramanga",'DOM':"Cap Cana;Santo Domingo",
 'CHN':"Shanghai Masters;Shanghai;Beijing;Chengdu;Hangzhou;Wuhan;Jiujiang;Ningbo;Guangzhou;Jinan;Zhangjiagang;Suzhou;Shenzhen;Wuxi",'HKG':"Hong Kong",'TPE':"Taipei",'JPN':"Tokyo;Osaka;Yokohama;Yokkaichi;Matsuyama;Kobe;Miyazaki",'KOR':"Seoul;Busan",
 'IND':"Chennai;New Delhi;Bengaluru;Pune",'THA':"Hua Hin;Nonthaburi",'VIE':"Phan Thiet",'SGP':"Singapore",'PAK':"Islamabad",
 'QAT':"Doha",'UAE':"Dubai;Abu Dhabi",'BRN':"Manama",'EGY':"Soma Bay",'MAR':"Marrakech;Rabat",'TUN':"Monastir;Tunis",'RWA':"Kigali",'CGO':"Brazzaville",'CIV':"Abidjan",
}
NAME2C={n:c for c,v in COUNTRY.items() for n in v.split(';')}
assert len(NAME2C)==sum(len(v.split(';')) for v in COUNTRY.values()),"a tournament name sits under two countries"
TEAM=re.compile(r"^(Davis Cup|Billie Jean King|BJK Cup|United Cup|Laver Cup|ATP Finals|ATP Tour Finals|Next Gen|WTA Finals|Riyadh Finals)")
def clean(n): return re.sub(r"\s+\d+$","",re.sub(r"\s*\(.*?\)","",str(n))).strip()
def country(n):
    if TEAM.match(str(n)): return 'TEAM'
    return NAME2C.get(clean(n))
def state(ca,cb,c):
    """For runners a, b in country c: which is HOME, or CTRL when neither is local, or None when both are or the country is unknown."""
    if c is None or c=='TEAM' or not ca or not cb: return None
    if ca==c and cb==c: return None
    if ca==c: return 'a'
    if cb==c: return 'b'
    return 'CTRL'
def fold(s): return re.sub(r"[^a-z]","",unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower())
def walkover(score): return bool(re.search(r"W/O|WO|WALK",str(score).upper()))
def retired(score): return bool(re.search(r"RET|ABD|ABN|DEF",str(score).upper()))
def entry(ts,p,mt):
    k=None
    for i in range(len(ts)):
        if mt-1200<=ts[i]<=mt-120: k=i
    if k is None: return None
    nx=float(p[k+1]) if k+1<len(ts) and ts[k+1]-ts[k]<=120 else None
    return float(p[k]),nx
def value(side,e,won):
    if e[0]>50: return None
    if side=='B':
        x=min(e[0],e[1]) if e[1] is not None else e[0]; a=step(x,-1)
        return None if a<=1.01 else back_settle(a,won)
    x=max(e[0],e[1]) if e[1] is not None else e[0]; a=step(x,1)
    return lay_settle(a,won)
def band(p): return '<1.5' if p<1.5 else '1.5-2' if p<2 else '2-3' if p<3 else '3-6' if p<6 else None
def zdiff(a,b):
    a=np.asarray(a,float); b=np.asarray(b,float)
    return (a.mean()-b.mean())/np.sqrt(a.var(ddof=1)/len(a)+b.var(ddof=1)/len(b))
# known answers, worked by hand
assert country('Nonthaburi 2')=='THA' and country('Bogota (Los Lagartos)')=='COL' and country('Guangzhou (Huangpu)')=='CHN' and country('Lima - Los Inkas')=='PER' and country("Queen's Club")=='GBR' and country('Tenerife 1')=='ESP' and country('Hua Hin 2')=='THA'
assert country('Davis Cup QLS R1: FRA vs BRA')=='TEAM' and country('BJK Cup Finals')=='TEAM' and country('Billie Jean King Cup Play-offs - Group B')=='TEAM' and country('Next Gen ATP Finals')=='TEAM' and country('Riyadh Finals')=='TEAM' and country('Cordoba') is None
assert state('FRA','ESP','FRA')=='a' and state('ESP','FRA','FRA')=='b' and state('FRA','FRA','FRA') is None and state('ESP','GER','FRA')=='CTRL' and state('FRA','ESP',None) is None and state('FRA','ESP','TEAM') is None and state('',"ESP",'FRA') is None
assert band(1.49)=='<1.5' and band(1.5)=='1.5-2' and band(2.0)=='2-3' and band(3.0)=='3-6' and band(5.9)=='3-6' and band(6.0) is None
assert entry([100.,1170.,1250.],[2.,3.,4.],1300.)==(3.0,4.0) and entry([1250.],[2.],1300.) is None
assert abs(value('B',(2.0,1.9),True)-8.722)<1e-9 and value('B',(2.0,1.9),False)==-10.0 and abs(value('L',(2.0,2.2),False)-10/1.22*0.98)<1e-9 and value('L',(2.0,2.2),True)==-10.0 and value('B',(51.0,None),True) is None
assert walkover('W/O') and retired('6-1 3-2 RET') and not retired('6-1 6-2')
assert abs(zdiff([0,1]*50,[0,1]*50))<1e-9 and zdiff([0,1]*50,[0,0,0,1]*50)>2
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
rc=psycopg2.connect(creds.pg_railway(),sslmode='require')
TR=pd.read_sql("""SELECT tourney_name,tourney_date,winner_norm,loser_norm,winner_ioc,loser_ioc,score,tour FROM tennis_results_2026""",rc); rc.close()
TR['tour']=TR.tour.astype(str).str.upper(); TR['c']=TR.tourney_name.map(country)
W=TR[(TR.tourney_date>=pd.Timestamp('2024-08-15').date())&(TR.tourney_date<=pd.Timestamp('2026-04-01').date())]
print(f"results {len(TR)}; window rows {len(W)}; team or finals {(W.c=='TEAM').sum()}; no country {W.c.isna().sum()}; unmapped names {sorted(W[W.c.isna()].tourney_name.unique())[:30]}",flush=True)
# map check, before prices: a wrongly mapped tournament shows few local players
M=W[W.c.notna()&(W.c!='TEAM')].copy(); M['loc']=(M.winner_ioc==M.c)|(M.loser_ioc==M.c)
ms=M.groupby(['tour','tourney_name','c']).agg(n=('loc','size'),loc=('loc','mean')).reset_index()
print("map check, share of rows with a local player, by tour:",M.groupby('tour')['loc'].mean().round(3).to_dict(),flush=True)
print("tournaments of 25+ rows with no local player at all:",ms[(ms.n>=25)&(ms['loc']==0)][['tour','tourney_name','c','n']].values.tolist(),flush=True)
ix=defaultdict(list); nw=0
for r in TR.itertuples():
    if walkover(r.score): nw+=1; continue
    w,l=fold(r.winner_norm),fold(r.loser_norm)
    ix[frozenset((w,l))].append(dict(date=r.tourney_date,w=w,l=l,score=r.score,tour=r.tour,cw=r.winner_ioc,cl=r.loser_ioc,c=r.c))
print(f"walkovers out {nw} | {time.time()-T0:.0f}s",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
cur.execute("SELECT DISTINCT market_id FROM bf_hist_other WHERE sport='Tennis' AND market_type='MATCH_ODDS'")
MID=sorted(r[0] for r in cur.fetchall() if r[0].startswith('MATCH_ODDS|') and '/' not in r[0]); print(f"singles markets {len(MID)} | {time.time()-T0:.0f}s",flush=True)
SK=Counter(); rows=[]; seen=set()
for c_ in range(0,len(MID),800):
    if time.time()-T0>BUDGET: SK['chunks not pulled, budget']+=1; continue
    cur.execute("""SELECT market_id,extract(epoch from market_time)::float8,market_time,sel,extract(epoch from ts)::float8,ltp::float8 FROM bf_hist_other
                   WHERE sport='Tennis' AND market_id=ANY(%s) AND market_type='MATCH_ODDS' AND NOT inplay AND ltp>=1.01 AND ltp<=1000 AND ts>=market_time-interval '25 minutes'""",(MID[c_:c_+800],))
    d=pd.DataFrame(cur.fetchall(),columns='mid mts mt sel ts ltp'.split())
    if d.empty: continue
    d=d.drop_duplicates(['mid','sel','ts']).sort_values(['mid','ts'],kind='stable')
    for mk,g in d.groupby('mid',sort=False):
        SK['market']+=1; run={s:x for s,x in g.groupby('sel',sort=False)}
        if len(run)!=2: SK['not two runners with prints']+=1; continue
        names={fold(s):s for s in run}; day=pd.Timestamp(g.mt.iloc[0]).date(); mt=float(g.mts.iloc[0]); pair=frozenset(names)
        hits=[h for h in ix.get(pair,[]) if -2<=(day-h['date']).days<=21]
        if len(hits)!=1: SK['no unique results match or walkover']+=1; continue
        h=hits[0]
        if (pair,h['date']) in seen: SK['second market on one result row, skipped']+=1; continue
        seen.add((pair,h['date'])); SK['matched']+=1
        w,l=h['w'],h['l']; ew=entry(run[names[w]].ts.values,run[names[w]].ltp.values,mt); el=entry(run[names[l]].ts.values,run[names[l]].ltp.values,mt)
        if ew is None or el is None: SK['no entry print on both']+=1; continue
        SK['scored']+=1; ret=retired(h['score']); T=h['tour']; pw,pl=ew[0],el[0]
        st=state(h['cw'],h['cl'],h['c'])
        if st is None: SK['both local, team or finals, or no country']+=1; continue
        SK['state '+('CTRL' if st=='CTRL' else 'HOME')]+=1
        fair_w=(1/pw)/(1/pw+1/pl)
        for k,e,won,fr,flag in ((w,ew,True,fair_w,st in ('a','CTRL')),(l,el,False,1-fair_w,st in ('b','CTRL'))):
            if not flag: continue
            b=band(e[0])
            if not b: continue
            for side in 'BL':
                v=value(side,e,won)
                if v is None: SK['no bet at the ladder ends']+=1; continue
                rows.append(('CTRL' if st=='CTRL' else 'HOME',b,side,T,day,mk,ret,won,e[0],fr,k,v))
    print(f"  {min(c_+800,len(MID))}/{len(MID)}, rows {len(rows)} | {time.time()-T0:.0f}s",flush=True)
con.close(); print("counts:",dict(sorted(SK.items())),flush=True)
R=pd.DataFrame(rows,columns='st band side tour day m ret won px fair k v'.split())
if R.empty or not (R.st=='HOME').any(): print("ERROR: no HOME rows, no verdict"); sys.exit(1)
assert not R[R.st=='HOME'].duplicated(['band','side','m']).any(),"more than one HOME bet per match per line"
assert not R[R.st=='CTRL'].duplicated(['band','side','m','k']).any(),"a control runner twice in one line"
R['when']=pd.to_datetime(R.day).astype('int64'); print(f"dates {R.day.min()}..{R.day.max()}; markets {R.m.nunique()}; HOME by tour {R[(R.st=='HOME')&(R.side=='B')].tour.value_counts().to_dict()}",flush=True)
def tab(x,**k):
    md=np.median(x.when.values); hh=np.where(x.when.values<md,1,2); l=line(x.v.values,hh); xr=x[~x.ret].v
    return dict(**k,n=l['n'],per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2'],n1=l['n1'],n2=l['n2'],x_ret=xr.mean() if len(xr) else np.nan,won=x.won.mean(),implied=(1/x.px).mean(),games=x.m.nunique(),players=x.k.nunique(),PASS=bool(l['PASS'] and len(xr)>0 and xr.mean()>=0.15))
out=[]
for (st,b,side),x in R.groupby(['st','band','side']):
    for cut,xx in (('ALL',x),('ATP',x[x.tour=='ATP']),('WTA',x[x.tour=='WTA']),('CHALLENGER',x[x.tour=='CHALLENGER'])):
        if len(xx): out.append(tab(xx,st=st,band=b,side=side,cut=cut))
S=pd.DataFrame(out).sort_values('t',ascending=False)
A=S[S.st=='HOME']; C=S[S.st=='CTRL'].drop(columns='PASS')
print(f"\n== ITEM 223, {len(A)} lines of a possible 32, by t\n",A.round(3).to_string(index=False))
print("\n-- control, neither runner local, cannot pass\n",C.round(3).to_string(index=False))
print("\n== HOME v control, won minus overround-free print, back rows")
for cut in ('ALL','ATP','WTA','CHALLENGER'):
    x=R[(R.side=='B')&((R.tour==cut)|(cut=='ALL'))]
    for b in ('ALLB','<1.5','1.5-2','2-3','3-6'):
        y=x if b=='ALLB' else x[x.band==b]; o=y[y.st=='HOME']; c=y[y.st=='CTRL']
        if len(o)>1 and len(c)>1: print(f"  {cut} {b}: HOME n {len(o)} err {(o.won-o.fair).mean():+.4f} v CTRL n {len(c)} err {(c.won-c.fair).mean():+.4f}; z {zdiff(o.won-o.fair,c.won-c.fair):.2f}")
W_=A[A.PASS]; print(f"\n== SURVIVORS: {len(W_)} of {len(A)}\n",W_.round(3).to_string(index=False) if len(W_) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
