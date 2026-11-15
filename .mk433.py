s = open('/root/pe-queue/jobs/499_goal_type.sh').read()
def rep(a, b):
    global s
    assert s.count(a) == 1, a
    s = s.replace(a, b)
rep("# 499_goal_type (Finder 2026-11-05, queue item 179, Finder's own, source a): first goal of the game by type, penalty or own goal v open play. Rule pushed to the queue before any price was read. Style from jobs/499_let_off.sh.",
    "# 499_goal_type_guard (Finder 2026-11-07, queue item 433, first part): jobs/499_goal_type.sh (item 179) unchanged except a PRICED-IN GUARD split. MOVED = the entry print has moved at least 20% from the leg's last print in af minutes c-6..c-1, the way the goal should move it (SCORER and OVER25 shorter, ratio <= 0.8; OTHER and DRAW longer, ratio >= 1.25); UNMOVED = it has not; no pre-goal print = neither. A lead whose profit sits only in UNMOVED is a clock artefact (items 430-432).")
rep("                d,fx=e\n", "                d,fx=e\n                pre=[arr[m] for m in range(max(r.c-6,0),r.c) if arr[m]==arr[m]]\n                mv=None if not pre else (arr[d]<=0.8*pre[-1] if leg in ('SCORER','OVER25') else arr[d]>=1.25*pre[-1])\n                sq=sp+([] if mv is None else ['MOVED' if mv else 'UNMOVED'])\n")
rep("                    for s in sp: rows.append(", "                    for s in sq: rows.append(")
# replace everything after the BOTH line with a focused print
a = s.index("print(f\"\\nlines {len(L)}")
b = s.index("\nPY\n")
new = '''print(f"\\nlines {len(L)}, at n>=300 {len(E)}, passing one entry {int(L.PASS.sum())}, passing both {int(L.BOTH.sum())}, {time.time()-T0:.0f}s")
C=['kind','leg','side','ent','exit','split','n','per10','t','h1','h2','maxwin','ex_top','PASS','BOTH']
print("\\n== ITEM 179's lead family: PEN OTHER BACK, all v MOVED v UNMOVED"); print(L[(L.kind=='PEN')&(L.leg=='OTHER')&(L.side=='BACK')&L.split.isin(['all','MOVED','UNMOVED'])].sort_values(['ent','exit','split'])[C].to_string(index=False))
print("\\n== item 179's top 10 'all' lines by t (n>=300), with the same line on MOVED and UNMOVED")
K=['kind','leg','side','ent','exit']; Lk=L.set_index(K+['split'])
for r in L[(L.split=='all')&(L.n>=300)].sort_values('t',ascending=False).head(10).itertuples():
    k=(r.kind,r.leg,r.side,r.ent,r.exit); m=Lk.loc[k+('MOVED',)] if k+('MOVED',) in Lk.index else None; u=Lk.loc[k+('UNMOVED',)] if k+('UNMOVED',) in Lk.index else None
    f=lambda z: 'none' if z is None else f"n {int(z.n)} {z.per10:+.3f} t {z.t:.2f} ex_top {z.ex_top:+.3f}"
    print(f"  {' '.join(map(str,k))}: all n {r.n} {r.per10:+.3f} t {r.t:.2f} | MOVED {f(m)} | UNMOVED {f(u)}")
U=L[L.split=='UNMOVED']; M=L[L.split=='MOVED']
print(f"\\nmean per10 over every line: MOVED {M.per10.mean():+.3f} (lines {len(M)}), UNMOVED {U.per10.mean():+.3f} (lines {len(U)})")
S=L[(L.split=='MOVED')&L.BOTH]; print(f"\\n== SURVIVORS (MOVED, passing on both E5 and E10): {len(S)}"); print(S[C].to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")'''
s = s[:a] + new + s[b:]
open('/root/pe-queue/jobs/499_goal_type_guard.sh', 'w').write(s)
print('written')
