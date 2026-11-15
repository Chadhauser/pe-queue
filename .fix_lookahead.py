def sub(t, a, b):
    assert a in t, a[:60]
    return t.replace(a, b)

# item 184
p = 'jobs/499_ht_cards_unseen.sh.wip'
t = open(p).read()
t = sub(t, "plus a 3-minute cushion as the clock is an estimate. Held to the result",
        "no cushion. Held to the result")
t = sub(t, "# STATE as item 181.", "# FIX 2026-11-07, first run dropped goals AFTER the print through a 3-minute cushion, 242 games, look-ahead that flatters the lay: first read G0 Y23 lay n 783 +0.353 t 2.27 is void. Three reads now: RULE no cushion, scored; NODROP every game at its first print, none dropped; BREAK first print 54 to 60 min after kick-off, inside the break, where 0-0 is known with no goal check.\n# STATE as item 181.")
t = sub(t, '"""Any af goal after minute 45 at or before the print, el minutes after kick-off, with the 3-minute cushion."""\n    return any(45<m<=match_minute(el)+3 for m in goals)',
        '"""Any af goal after minute 45 at or before the print, el minutes after kick-off. Never a goal after the print."""\n    return any(45<m<=match_minute(el) for m in goals)')
t = sub(t, "assert h2_goal_by([47],63) is True      # el 63 reads 46, +3 = 49\n", "assert h2_goal_by([46],63) is True and h2_goal_by([47],63) is False     # el 63 reads 46\n")
t = sub(t, "assert h2_goal_by([50],63) is False and h2_goal_by([30],70) is False and h2_goal_by([53],70) is True and h2_goal_by([55],70) is False   # el 70 = 51, +3 = 54",
        "assert h2_goal_by([30],70) is False and h2_goal_by([51],70) is True and h2_goal_by([52],70) is False   # el 70 = 51")
t = sub(t, """    for side in 'BL':
        e=entry(x[0],x[1],ko,60,71,side)
        if e is None: SK[f'{side} no print or no bet']+=1; continue
        i,a=e
        if h2_goal_by(GO.get(r.fx,[]),(x[0][i]-ko)/60): SK[f'{side} second-half goal by entry']+=1; continue
        rows.append((Y,'BACK' if side=='B' else 'LAY',ko,int(f.season),r.fx,pnl(side,a,won),won,1/a,a))
""", """    for side in 'BL':
        for var,lo,hi,gc in (('RULE',60,71,True),('NODROP',60,71,False),('BREAK',54,60,False)):
            e=entry(x[0],x[1],ko,lo,hi,side)
            if e is None: SK[f'{var} {side} no print or no bet']+=1; continue
            i,a=e
            if gc and h2_goal_by(GO.get(r.fx,[]),(x[0][i]-ko)/60): SK[f'{var} {side} second-half goal by entry']+=1; continue
            rows.append((var,Y,'BACK' if side=='B' else 'LAY',ko,int(f.season),r.fx,pnl(side,a,won),won,1/a,a))
""")
t = sub(t, "columns='Y side off season g v won imp a'.split()); assert not T.duplicated(['Y','side','g']).any()",
        "columns='var Y side off season g v won imp a'.split()); assert not T.duplicated(['var','Y','side','g']).any()")
t = sub(t, "Nv={k:x.v.values for k,x in T[T.Y=='Y01'].groupby('side')}\nfor (Y,s),x in T.groupby(['Y','side']):",
        "Nv={k:x.v.values for k,x in T[T.Y=='Y01'].groupby(['var','side'])}\nfor (V,Y,s),x in T.groupby(['var','Y','side']):")
t = sub(t, "l=line(x.v.values,x.h.values); nv=Nv.get(s);", "l=line(x.v.values,half(x.off.values)); nv=Nv.get((V,s));")
t = sub(t, "T['h']=half(T.off); o=[]", "o=[]")
t = sub(t, "line=f'OU25 G0 {Y} {s}'", "line=f'{V} OU25 G0 {Y} {s}'")
t = sub(t, "PASS=l['PASS'] and Y=='Y23' and s=='LAY'", "PASS=l['PASS'] and V=='RULE' and Y=='Y23' and s=='LAY'")
t = sub(t, "Z=T[(T.Y=='Y23')&(T.side=='LAY')]", "Z=T[(T['var']=='RULE')&(T.Y=='Y23')&(T.side=='LAY')]")
t = sub(t, "S=L[L.PASS==True]", "G=T[T.side=='LAY'].groupby(['var','g']).agg(off=('off','first'),v=('v','first')).reset_index()\nprint('\\nAll G0 lay, every yellow bucket, for reading, not scored:')\nfor V,x in G.groupby('var'):\n    l=line(x.v.values,half(x.off.values)); print(' ',V,'n',l['n'],'per10',round(l['per10'],3),'t',round(l['t'],2),'h1',round(l['h1'],3),'h2',round(l['h2'],3))\nS=L[L.PASS==True]")
open(p, 'w').write(t)

# items 139 and 405
for p in ('jobs/499_fh3_augs.sh.wip', 'jobs/499_fh3_lay_older.sh.wip'):
    t = open(p).read()
    t = sub(t, "#!/bin/bash\nset -o pipefail\n", "#!/bin/bash\nset -o pipefail\n# FIX 2026-11-07: the +2 in clean_at, carried from jobs/499_fh3_aug24.sh, dropped goals up to 2 minutes AFTER the print, look-ahead that hurts a back and flatters a lay. CUSH keeps it, as item 212's rule; NOW drops only goals at or before the print, and is the read that counts.\n")
    if 'augs' in p:
        t = sub(t, '''def clean_at(t,off,goals):
    """No goal with af minute at or before the print's clock minute + 2."""
    return not any(g<=(t-off)/60+2 for g in goals)
assert clean_at(1000.,100.,[]) and clean_at(1000.,100.,[18]) and not clean_at(1000.,100.,[17]) and not clean_at(1000.,100.,[5])
''', '''def clean_at(t,off,goals,c=0):
    """No goal with af minute at or before the print's clock minute + c."""
    return not any(g<=(t-off)/60+c for g in goals)
assert clean_at(1000.,100.,[]) and clean_at(1000.,100.,[18],2) and not clean_at(1000.,100.,[17],2) and not clean_at(1000.,100.,[5],2) and clean_at(1000.,100.,[16]) and not clean_at(1000.,100.,[15])
''')
        t = sub(t, """        if not clean_at(x[0][i],off,GL.get(r.fx,[])): SK['not 0-0 at the print']+=1; continue
        ALL.append((r.mt.strftime('%Y-%m'),r.fx,r.fx in MAPPED,off,a,won,pnl('B',a,won)))
""", """        if not clean_at(x[0][i],off,GL.get(r.fx,[])): SK['not 0-0 at the print']+=1; continue
        ALL.append((r.mt.strftime('%Y-%m'),r.fx,r.fx in MAPPED,off,a,won,pnl('B',a,won),clean_at(x[0][i],off,GL.get(r.fx,[]),2)))
""")
        t = sub(t, "columns='mo g mapped off a won v'.split())", "columns='mo g mapped off a won v cush'.split())")
        t = sub(t, "rd('ALL AUGUSTS',Aug,True); rd('ALL SEPTEMBERS control',Sep,False)",
                "rd('ALL AUGUSTS NOW',Aug,True); rd('ALL SEPTEMBERS NOW control',Sep,False); rd('ALL AUGUSTS CUSH',Aug[Aug.cush],False); rd('ALL SEPTEMBERS CUSH',Sep[Sep.cush],False)")
    else:
        t = sub(t, "def clean_at(t,off,goals): return not any(g<=(t-off)/60+2 for g in goals)\nassert clean_at(1000.,100.,[18]) and not clean_at(1000.,100.,[17])\n",
                "def clean_at(t,off,goals,c=0): return not any(g<=(t-off)/60+c for g in goals)\nassert clean_at(1000.,100.,[18],2) and not clean_at(1000.,100.,[17],2) and clean_at(1000.,100.,[16]) and not clean_at(1000.,100.,[15])\n")
        t = sub(t, "ALL.append((A[:7],r.fx,off,a,won,pnl('L',a,won)))", "ALL.append((A[:7],r.fx,off,a,won,pnl('L',a,won),clean_at(x[0][i],off,GL.get(r.fx,[]),2)))")
        t = sub(t, "columns='mo g off a won v'.split())", "columns='mo g off a won v cush'.split())")
        t = sub(t, "rd('ALL 15 months',R,True);", "rd('ALL 15 months NOW',R,True); rd('ALL 15 months CUSH',R[R.cush],False);")
    open(p, 'w').write(t)
print('patched')
