def sub(t, a, b):
    assert a in t, a[:60]
    return t.replace(a, b)
p = 'jobs/499_fh3_lay_older.sh.wip'
t = open(p).read()
t = sub(t, "#!/bin/bash\nset -o pipefail\n", "#!/bin/bash\nset -o pipefail\n# FIX 2026-11-07: the +2 in clean_at, carried from jobs/499_fh3_aug24.sh, dropped goals up to 2 minutes AFTER the print, look-ahead that hurts a back and flatters a lay. CUSH keeps it, as item 212's rule; NOW drops only goals at or before the print, and is the read that counts. First run, void: n 5,206 +0.166 t 2.92.\n")
t = sub(t, "def clean_at(t,off,goals): return not any(g<=(t-off)/60+2 for g in goals)\n", "def clean_at(t,off,goals,c=0): return not any(g<=(t-off)/60+c for g in goals)\n")
t = sub(t, "assert clean_at(1000.,100.,[18]) and not clean_at(1000.,100.,[17])\n", "assert clean_at(1000.,100.,[18],2) and not clean_at(1000.,100.,[17],2) and clean_at(1000.,100.,[16]) and not clean_at(1000.,100.,[15])\n")
t = sub(t, "ALL.append((A[:7],r.fx,off,a,won,pnl('L',a,won)))", "ALL.append((A[:7],r.fx,off,a,won,pnl('L',a,won),clean_at(x[0][i],off,GL.get(r.fx,[]),2)))")
t = sub(t, "columns='mo g off a won v'.split())", "columns='mo g off a won v cush'.split())")
t = sub(t, "rd('ALL 15 months',R,True);", "rd('ALL 15 months NOW',R,True); rd('ALL 15 months CUSH',R[R.cush],False);")
open(p, 'w').write(t)
print('patched')
