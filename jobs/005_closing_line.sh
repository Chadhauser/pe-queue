#!/bin/bash
# 005: PRE-MATCH CLOSING-LINE VALUE. Our 7am Betfair price (fts_advanced_results) vs Pinnacle CLOSING price (football-data.co.uk, free).
# Edge hypothesis (documented, retail-reachable): where the 7am Betfair price is longer than where sharp money closes, backing at 7am
# beats the market. Measured on 5.5 seasons, found on <Jul 2025, tested on >=Jul 2025. 2pct comm. Also the reverse (lay when 7am is short).
cd /root/pe-scan && mkdir -p fd && cat > closing_line.py <<'PYFILE'
import re, io, sys, datetime, urllib.request, psycopg2, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
def norm(s): return re.sub(r'[^a-z]','',(s or '').lower().split(' ')[0])
# football-data main leagues: code -> our competition name
MAIN={'E0':'English Premier League','E1':'English Championship','E2':'English League One','SP1':'Spanish Primera Division','SP2':'Spanish Segunda Division',
      'I1':'Italian Serie A','D1':'German Bundesliga','D2':'German Bundesliga 2','F1':'French Ligue 1','F2':'French Ligue 2','N1':'Dutch Eredivisie',
      'P1':'Portuguese Primeira Liga','T1':'Turkish Super Lig','B1':'Belgian Premier League','SC0':'Scottish Premiership'}
seasons=['2021','2122','2223','2324','2425','2526']
frames=[]
for code,comp in MAIN.items():
    for s in seasons:
        url=f"https://www.football-data.co.uk/mmz4281/{s}/{code}.csv"
        try:
            raw=urllib.request.urlopen(url,timeout=60).read().decode('latin-1')
            df=pd.read_csv(io.StringIO(raw)); df['comp']=comp; frames.append(df)
        except Exception as e: print("miss",code,s,str(e)[:60],flush=True)
FD=pd.concat(frames,ignore_index=True)
FD['d']=pd.to_datetime(FD.Date,dayfirst=True,errors='coerce').dt.date
for c in ['PSCH','PSCD','PSCA','PSH','PSD','PSA','PC>2.5','PC<2.5','FTHG','FTAG']:
    if c in FD: FD[c]=pd.to_numeric(FD[c],errors='coerce')
FD=FD[FD.PSCH.notna()&FD.d.notna()].copy()
FD['k']=FD.d.astype(str)+'|'+FD.HomeTeam.map(norm)+'|'+FD.AwayTeam.map(norm)
print(f"football-data rows with Pinnacle closing: {len(FD)} across {FD.comp.nunique()} leagues",flush=True)
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor()
cur.execute("SELECT match_date, competition, home_team, away_team, mo_home_back, mo_draw_back, mo_away_back, mo_home_lay, mo_draw_lay, mo_away_lay, o25_back, u25_back, ft_home, ft_away, hf_pts, af_pts, home_colour, away_colour FROM fts_advanced_results")
F=pd.DataFrame(cur.fetchall(),columns=['d','comp','h','a','bh','bd','ba','lh','ld','la','bo','bu','fh','fa','hpts','apts','hcol','acol'])
for c in ['bh','bd','ba','lh','ld','la','bo','bu','fh','fa','hpts','apts']: F[c]=pd.to_numeric(F[c],errors='coerce')
F['d']=pd.to_datetime(F.d).dt.date
F['k']=F.d.astype(str)+'|'+F.h.map(norm)+'|'+F.a.map(norm)
FDi=FD.set_index('k')
# join on exact date, then +-1 day
def lk(k,d,h,a):
    for off in (0,1,-1):
        kk=f"{d+datetime.timedelta(days=off)}|{h}|{a}"
        if kk in FDi.index: return kk
    return None
F['fk']=[lk(k,d,norm(h),norm(a)) for k,d,h,a in zip(F.k,F.d,F.h,F.a)]
J=F[F.fk.notna()].join(FDi[['PSCH','PSCD','PSCA','PSH','PSD','PSA','PC>2.5','PC<2.5','comp']].rename(columns={'comp':'fdcomp'}),on='fk')
J=J[~J.index.duplicated()]
print(f"joined 7am Betfair to Pinnacle closing: {len(J)} of {len(F)} FTS matches; by league:\n{J.groupby('comp').size().to_string()}",flush=True)
J['hold']=J.d>=datetime.date(2025,7,1)
J['res']=np.where(J.fh>J.fa,'H',np.where(J.fh<J.fa,'A','D'))
# closing implied probs (de-margined) and our 7am implied
for s,bf,pc in (('H','bh','PSCH'),('D','bd','PSCD'),('A','ba','PSCA')):
    J['pin_'+s]=1/J[pc]; J['bf_'+s]=1/J[bf]
tot=J.pin_H+J.pin_D+J.pin_A
for s in 'HDA': J['pin_'+s]/=tot
# CLV = closing prob minus 7am Betfair prob; positive => 7am price was too long (value to BACK at 7am)
rows=[]
for s,bf,ly in (('H','bh','lh'),('D','bd','ld'),('A','ba','la')):
    clv=J['pin_'+s]-J['bf_'+s]; won=J.res==s
    back=np.where(won,(J[bf]-1)*0.98,-1.0); lay=np.where(won,-(J[ly]-1),0.98)
    for lo,hi in [(-1,-0.06),(-0.06,-0.03),(-0.03,-0.01),(-0.01,0.01),(0.01,0.03),(0.03,0.06),(0.06,1)]:
        m=(clv>=lo)&(clv<hi)&J[bf].notna()&J[ly].notna()
        for per,mm in (('train',m&~J.hold),('hold',m&J.hold)):
            if mm.sum()<30: continue
            rows.append((s,f"{lo:+.2f}..{hi:+.2f}",per,int(mm.sum()),100*back[mm].mean(),100*lay[mm].mean(),100*won[mm].mean(),100*J['bf_'+s][mm].mean(),100*J['pin_'+s][mm].mean()))
R=pd.DataFrame(rows,columns=['sel','clv_band','period','n','back_roi','lay_roi','actual%','bf7am%','pin_close%'])
pd.set_option('display.width',220)
print("\nCLOSING-LINE VALUE: 7am Betfair vs Pinnacle close. clv>0 = Betfair longer than close at 7am. ROI of BACKING at the 7am price / LAYING at 7am lay price, 2pct comm.")
print(R.round(1).to_string(index=False))
print("\nHEADLINE RULES (found on train, checked on hold):")
for s in 'HDA':
    for lo,lab in ((0.03,'clv>=+3pts'),(0.06,'clv>=+6pts')):
        clv=J['pin_'+s]-J['bf_'+s]; won=J.res==s; back=np.where(won,(J['bh' if s=='H' else 'bd' if s=='D' else 'ba']-1)*0.98,-1.0)
        m=(clv>=lo)
        a=m&~J.hold; b=m&J.hold
        print(f"  BACK {s} at 7am when {lab}: train n={a.sum()} ROI={100*back[a].mean():+.1f}% | hold n={b.sum()} ROI={100*back[b].mean():+.1f}%")
    for lo,lab in ((-0.03,'clv<=-3pts'),(-0.06,'clv<=-6pts')):
        clv=J['pin_'+s]-J['bf_'+s]; won=J.res==s; lay=np.where(won,-(J['lh' if s=='H' else 'ld' if s=='D' else 'la']-1),0.98)
        m=(clv<=lo); a=m&~J.hold; b=m&J.hold
        print(f"  LAY  {s} at 7am when {lab}: train n={a.sum()} ROI={100*lay[a].mean():+.1f}% | hold n={b.sum()} ROI={100*lay[b].mean():+.1f}%")
# Overs: 7am Betfair O2.5 vs Pinnacle closing O2.5
if 'PC>2.5' in J:
    o=J[J['PC>2.5'].notna()&J.bo.notna()&J.bu.notna()].copy()
    o['pin_o']=(1/o['PC>2.5'])/((1/o['PC>2.5'])+(1/o['PC<2.5'])); o['bf_o']=(1/o.bo)/((1/o.bo)+(1/o.bu)); o['clv']=o.pin_o-o.bf_o
    won=(o.fh+o.fa)>2.5; back=np.where(won,(o.bo-1)*0.98,-1.0)
    print("\nOVER 2.5 — back at 7am when clv>=+3pts:")
    for per,mm in (('train',(o.clv>=0.03)&~o.hold),('hold',(o.clv>=0.03)&o.hold)): print(f"  {per}: n={mm.sum()} ROI={100*back[mm].mean():+.1f}%")
print("\nHOW OFTEN does the 7am Betfair price move toward Pinnacle's close? (sign agreement between 7am->close Betfair move and 7am Betfair->Pinnacle gap): needs closing Betfair prices — available in fts_live going forward, not in the history. UNVERIFIED until a month of fts_live closes.")
J[['d','comp','h','a','bh','bd','ba','PSCH','PSCD','PSCA','res','hold']].to_csv('/root/pe-scan/closing_line_joined.csv',index=False)
PYFILE
python3 closing_line.py
