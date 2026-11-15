s = open('/root/pe-queue/jobs/499_equaliser_unseen.sh').read()
def rep(a, b):
    global s
    assert s.count(a) == 1, a
    s = s.replace(a, b)
rep("# 499_equaliser_unseen (Finder 2026-11-07, queue item 431, Finder's own, source a, from item 430; rule from jobs/499_equaliser_stress.sh, match from jobs/lib_afmatch.py as jobs/499_var_off_unseen.sh): LAY THE SIDE THAT SCORED FIRST ONCE A SECOND-HALF EQUALISER IS PRICED IN, games not in af_price_map.",
    "# 499_equaliser_draw_unseen (Finder 2026-11-07, queue item 432, Finder's own, source a, from item 430; copied from jobs/499_equaliser_unseen.sh): BACK THE DRAW AFTER A LATE EQUALISER TO 1-1, games not in af_price_map.")
rep("the second (1-1) at af minute E 46-80 (ITEM) or 10-40 (CONTROL, cannot pass)", "the second (1-1) at af minute E 66-80 (ITEM), 46-65 (CONTROL_H2) or 10-40 (CONTROL_H1); controls cannot pass")
rep("# ENTRY: first in-play MATCH_ODDS print of the first scorer in match minutes", "# ENTRY: back 'The Draw' at its first in-play MATCH_ODDS print in match minutes")
rep("PRICED: that raw print >= 1.25 x the first scorer's last print in match minutes E-6..E-1. Raw print 2-50 only.", "PRICED: that raw print <= 0.8 x the Draw's last print in match minutes E-6..E-1. Raw print 1.01-50.")
rep("# EXIT: held to the af FT score, never dropped. £10 liability,", "# EXIT: held to the af FT score, never dropped. £10 stake,")
rep("    grp='ITEM' if 46<=s[0]<=80 else ('CONTROL' if 10<=s[0]<=40 else None)", "    grp='ITEM' if 66<=s[0]<=80 else ('CONTROL_H2' if 46<=s[0]<=65 else ('CONTROL_H1' if 10<=s[0]<=40 else None))")
rep("    won=bool(f.hg>f.ag) if fh else bool(f.ag>f.hg)\n    x=PX.get((r.market_id,nm[fh]))", "    won=bool(f.hg==f.ag)\n    x=PX.get((r.market_id,'The Draw'))")
rep("clock_min(E+7),'L')", "clock_min(E+7),'B')")
rep("    if not 2<=p<=50: SK[f'{grp} print outside 2-50']+=1; continue", "    if not 1.01<=p<=50: SK[f'{grp} print outside 1.01-50']+=1; continue")
rep("priced=(pre is not None and p>=1.25*pre),won=won,v=pnl('L',e[1],won)", "priced=(pre is not None and p<=0.8*pre),won=won,v=pnl('B',e[1],won)")
rep("    o.append(L(x[x.priced],f'{grp} FIRST LAY PRICED',grp=='ITEM'))\n    o.append(L(x,f'{grp} FIRST LAY all prints'))\n    o.append(L(x[~x.priced&x.pre.notna()],f'{grp} FIRST LAY NOT_PRICED'))",
    "    o.append(L(x[x.priced],f'{grp} DRAW BACK PRICED',grp=='ITEM'))\n    o.append(L(x,f'{grp} DRAW BACK all prints'))\n    o.append(L(x[~x.priced&x.pre.notna()],f'{grp} DRAW BACK NOT_PRICED'))")
rep("Z['pb']=pd.cut(Z.p,[2,3,4,6,10,50],include_lowest=True)", "Z['pb']=pd.cut(Z.p,[1,1.5,1.8,2.2,3,50])")
rep("assert abs(pnl('L',3.05,False)-10/2.05*.98)<1e-6 and pnl('L',3.05,True)==-10", "assert abs(pnl('B',1.69,True)-6.9*.98)<1e-6 and pnl('B',1.69,False)==-10")
open('/root/pe-queue/jobs/499_equaliser_draw_unseen.sh', 'w').write(s)
print('written')
