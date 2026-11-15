src = open('/root/pe-queue/jobs/499_ht_state_lines.sh').read()
def rep(a, b):
    global src
    assert src.count(a) == 1, a[:60]
    src = src.replace(a, b)
rep("# 499_ht_state_lines (Finder 2026-11-08, queue item 446, Finder's own, source a/c): at the half-time break",
    "# 499_ht_state_thin (Finder 2026-11-08, queue item 447, from item 446; built from jobs/499_ht_state_lines.sh, rule pushed in ca5a47f before any price). Changes only: entry window 55-62 min after the first in-play print, a no-second-half-goal guard, scored on the games item 446 dropped as half-time not clear (UNSEEN). Item 446's text follows: at the half-time break")
rep('''def guard_ok(G,seen_ts,entry_ts):''', '''def window2(ip0):
    """Item 447: 55 to 62 min after the first in-play print, which is at or after the kick-off."""
    return (ip0+55*60,ip0+62*60)
def no_new_goal(seen_next,entry_ts):
    """Item 447: the Over (G+0.5) must not have printed at 1.05 or under before entry."""
    return seen_next is None or seen_next>=entry_ts
def guard_ok(G,seen_ts,entry_ts):''')
rep("assert band(1.6)=='HIGH'", "assert window2(0)==(3300,3720) and no_new_goal(None,10) and no_new_goal(10,10) and not no_new_goal(9,10)\nassert band(1.6)=='HIGH'")
rep("params=(list(OU.values())[:4],lo,hi))", "params=(list(OU.values()),lo,hi))")
rep('''        ip0s=float(secs(pd.Series([ip0])).iloc[0]); thts=float(secs(pd.Series([tht])).iloc[0])
        wnd=window(ip0s,thts)
        if wnd is None: C['half-time not clear']+=1; continue''',
'''        if ip0 is None or ip0!=ip0: C['no in-play prints']+=1; continue
        ip0s=float(secs(pd.Series([ip0])).iloc[0])
        thts=float(secs(pd.Series([tht])).iloc[0]) if tht is not None and tht==tht else None
        unseen=(thts is None) or (window(ip0s,thts) is None)
        C['UNSEEN' if unseen else 'seen by 446']+=1
        wnd=window2(ip0s)''')
rep("        if ip0 is None or ip0!=ip0 or tht is None or tht!=tht: C['no in-play prints']+=1; continue\n", "")
rep("            sel=f'Under {L} Goals'", "            if not no_new_goal(SEEN.get((e,OU[G+0.5])),float(tt[i])): C[f'N{N} second-half goal before entry']+=1; continue\n            sel=f'Under {L} Goals'")
rep("s60=float(tt[i])>=ip0s+3600,ent=float(tt[i])-ip0s,brk=float(tt[i])-thts))", "s60=float(tt[i])>=ip0s+3600,ent=float(tt[i])-ip0s,brk=0.0,unseen=unseen))")
rep("T=pd.DataFrame(rows); med=T.ip0.median()", "TA=pd.DataFrame(rows); T=TA[TA.unseen].copy(); med=T.ip0.median(); TA['h']=np.where(TA.ip0<=med,1,2)")
rep('''min after first in-play print, {T.brk.median()/60:.1f} min after half-time")''', '''min after first in-play print; UNSEEN only, audit on all games below")''')
rep("print(f\"\\n== ITEM 446, {len(O)} scored lines, top 25 by t\")", "print(f\"\\n== ITEM 447 (UNSEEN games), {len(O)} scored lines, top 25 by t\")")
rep('''top=O.sort_values('t',ascending=False).head(3)''', '''for N in (1,2):
    for col,sd in (('vb','back U'),('vl','lay U')): c.append(row(f'AUDIT all games N{N} all G {sd}',TA[TA.N==N],col))
print("\\n-- audit, all games incl. those item 446 read, not scored\\n",pd.DataFrame(c[-4:]).to_string(index=False))
top=O.sort_values('t',ascending=False).head(3)''')
open('/root/pe-queue/jobs/499_ht_state_thin.sh.wip', 'w').write(src)
print('written')
