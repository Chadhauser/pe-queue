#!/bin/bash
# 069: 063's LTD "traded" result (+18/£100, t=6 both seasons) mixed units: the hold leg was per £1 LIABILITY but the cash-out leg
# (tp 'lay') was per £1 STAKE — a 5x+ inflation at draw prices 5.6-7.6. Rerun with everything per £1 liability, and print the
# traded P&L split by path (favourite led first / underdog led first / no goal) so no single path can hide a bug.
cd /root/pe-scan && python3 - <<'PY'
s=open('vendor_football.py').read()
old=s[s.index("    # ---- A. LTD 5.6-7.6"):s.index("    # ---- B. Early goal glitch")]
new='''    # ---- A. LTD 5.6-7.6 (all per £1 LIABILITY on the draw lay)
    if 5.6<=ko_d<=7.6:
        L=ko_d*(1+SPREAD)-1                      # liability per £1 stake laid at ko_d (with spread)
        hold=lay_liab(ko_d, fh==fa)
        pnl=None; path='no goal'; sh=sa=0
        for g,s,_ in goals:
            if s=='H': sh+=1
            else: sa+=1
            lead=('H' if sh>sa else 'A' if sa>sh else None)
            if lead==fav:
                x=px_at(px,'MO','DRAW',g+3,3)
                if x: pnl=tp('lay',ko_d,x)/L     # per £1 stake -> per £1 liability
                else: pnl=hold
                path='fav led first'; break
            if lead==dog and sh+sa==1:
                xu=px_at(px,'MO',('HOME' if dog=='H' else 'AWAY'),g+3,3)
                if xu:
                    green=(1/L)*(1-COMM)            # profit per £1 liability if no draw
                    dog_won=(fh>fa) if dog=='H' else (fa>fh)
                    # draw lay settles at FT; dog lay placed with liability = green at price xu
                    pnl=(-1.0 if fh==fa else green)+(-green if dog_won else (green/(xu*(1+SPREAD)-1))*(1-COMM))
                    path='dog led first'; break
        if pnl is None: pnl=hold
        A.append((season,lg,ko_d,'hold',hold,path)); A.append((season,lg,ko_d,'traded',pnl,path))
'''
s=s.replace(old,new)
s=s.replace("A=pd.DataFrame(A,columns=['season','lg','draw_ko','mode','pnl'])","A=pd.DataFrame(A,columns=['season','lg','draw_ko','mode','pnl','path'])")
s=s.replace("show(A,['lg','mode','season'],'pnl','A3. by league (traded)')","show(A,['mode','path','season'],'pnl','A2b. hold vs traded BY PATH (per £100 liability)')\nprint(A.groupby(['path','season']).size().unstack('season').to_string())\nshow(A[A['mode']=='traded'],['lg','season'],'pnl','A3. traded by league')")
open('vendor_football.py','w').write(s)
PY
python3 -m py_compile vendor_football.py && python3 vendor_football.py 2>&1 | sed -n '1,80p'
