s=open('/root/pe-queue/jobs/499_off_unseen.sh').read()
def rep(a,b):
    global s
    assert s.count(a)==1,a
    s=s.replace(a,b)
L=s.split('\n')
assert L[2].startswith('# 499_off_unseen')
L[2]="# 499_yel_over_unseen (Finder 2026-11-07, queue item 358, Finder's own, source d; port of jobs/499_off_unseen.sh with Yellow Cards for Offsides, Over only): YEL HIGH Over 2.5 back on games item 355 did not read. Rule pushed in the queue before this read. Read only, no tables written. LTP only, so a pass is an upper bound."
s='\n'.join(L)
rep("HI,LO=4.2,2.8   # item 346's printed season 2023 cuts","HI,LO=5.1,3.5   # item 355's printed season 2023 cuts")
rep("(s.raw->>'Offsides')::float","(s.raw->>'Yellow Cards')::float")
rep("""OFF 20th, 80th",round(B3.quantile(.2),3),round(B3.quantile(.8),3),flush=True); assert abs(B3.quantile(.8)-HI)<1e-6 and abs(B3.quantile(.2)-LO)<1e-6""","""YEL 20th, 80th",round(B3.quantile(.2),3),round(B3.quantile(.8),3),flush=True); assert abs(B3.quantile(.8)-HI)<1e-6 and abs(B3.quantile(.2)-LO)<1e-6""")
rep(""",('MATCH_ODDS','The Draw','DRAW',lambda f:f.hg==f.ag,'LOW')):""","""):""")
assert "for mt_type,sel,tag,wfn,scored_state in (('OVER_UNDER_25','Over 2.5 Goals','OVER',lambda f:f.hg+f.ag>2.5,'HIGH')):" in s
s=s.replace("lambda f:f.hg+f.ag>2.5,'HIGH')):","lambda f:f.hg+f.ag>2.5,'HIGH'),):")
open('/root/pe-queue/jobs/499_yel_over_unseen.sh.wip','w').write(s)
p='/root/pe-queue/watchman/FINDER_QUEUE.md'
q=open(p).read()
assert '\n358. ' not in q
if not q.endswith('\n'): q+='\n'
q+="358. RUNNING 2026-11-07 (Finder's own, source d, from item 355; tables af_stats, af_fixtures, bf_hist_other; port of jobs/499_off_unseen.sh, job 499_yel_over_unseen) **Back Over 2.5 between two high-yellow sides, unseen games.** Rationale: item 355's best line, YEL HIGH Over back n 1,503 +0.451 t 1.67 h1 +0.581 h2 +0.293, won 0.519 v implied 0.490, control -0.049; it is the best of 36, so chance would give about this. Rule fixed before this read, no new cuts: YEL at or over 5.1, the season 2023 cut, Over 2.5 back, entry and costs as item 349, games item 355 did not read, Nov 2023 to Jul 2024 and Jul to Sep 2026, name match. One scored line; MID and LOW read as control. Standard bar, halves by date.\n"
open(p,'w').write(q); print('ok')
