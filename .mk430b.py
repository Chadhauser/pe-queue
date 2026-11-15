p = '/root/pe-queue/jobs/499_equaliser_side.sh'
s = open(p).read()
s = s.replace("# 499_equaliser_side (Finder 2026-11-07", "# 499_equaliser_stress (Finder 2026-11-07, item 430 stress of the one numeric pass in jobs/499_equaliser_side.sh: FIRST LAY ALL n 1,683 +0.664 t 3.52; its largest win 98 is a lay near 1.11, which a post-equaliser price cannot be, so the clock is suspect). Copied from 499_equaliser_side", 1)
s = s.replace("# HALVES:", "# STRESS: L (t=E+L) 3, 6, 10; PRICED = FIRST's entry print at least 1.25 x its last print in af minutes E-6..E-1 (the leader must have drifted on the goal); 3 ticks adverse; without the 1% largest wins; by price band; CLOCK = median FIRST price by tape minute minus E.\n# HALVES:", 1)
# signal loop: several L, priced flag, 3 ticks
old_start = "        t=E+3\n"
i = s.index(old_start); j = s.index("    print(f\"  {min(i+1000", i)
new = '''        favside='h' if arr['HOME'][h0]<=arr['AWAY'][a0] else 'a'
        res='h' if hg>ag else ('a' if ag>hg else 'd')
        fa=arr[SEL[first]]
        if grp=='ITEM' and (len(gl)==2 or gl[2][0]>E+12):
            for o in range(-6,13):
                if 0<=E+o<131 and not np.isnan(fa[E+o]): clock[o].append(fa[E+o])
        pre=[fa[m] for m in range(max(E-6,0),E) if not np.isnan(fa[m])]
        for L in (3,6,10):
            t=E+L
            if len(gl)>2 and gl[2][0]<=t: cnt[f'{grp} L{L} third goal by t']+=1; continue
            cnt[f'{grp} L{L} signals']+=1
            sel=SEL[first]; ent=first_print(fa,t+1,t+4)
            if ent is None: cnt[f'{grp} L{L} no print']+=1; continue
            p=float(fa[ent])
            if p>50: continue
            won=(res==first); priced=bool(pre) and p>=1.25*pre[-1]
            rows.append(dict(grp=grp,L=L,event_id=g.event_id,season=int(g.season),E=E,p=p,won=won,v=lay_settle(up(p),won),v3=lay_settle(up(p,3),won),priced=priced,haspre=bool(pre),eqfav=('FAV' if eq==favside else 'DOG')))
'''
s = s[:i] + new + s[j:]
s = s.replace("rows=[]; cnt=defaultdict(int)", "rows=[]; cnt=defaultdict(int); clock=defaultdict(list)", 1)
# replace analysis
k = s.index("R=pd.DataFrame(rows)"); e = s.index("PY\n", k)
ana = '''R=pd.DataFrame(rows); assert not R.duplicated(['grp','L','event_id']).any()
print("\\ncounts:",dict(cnt))
print("\\n== CLOCK: median price of the side that scored first, by tape minute minus af minute of the equaliser (E 46-80, no third goal within 12 min)")
print(" ".join(f"{o:+d}:{np.median(clock[o]):.2f}(n{len(clock[o])})" for o in sorted(clock)))
def line(d,c='v'):
    a=d[d.season==2024][c]; b=d[d.season==2025][c]; v=d[c]
    r=dict(n=len(v),px=d.p.median(),won=d.won.mean(),imp=(1/d.p).mean(),per10=v.mean(),t=tstat(v),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,max_win=v.max() if len(v) else np.nan)
    r['PASS']=bool(r['n']>=300 and r['n1']>=150 and r['n2']>=150 and r['t']>=3.5 and r['h1']>0 and r['h2']>0 and r['per10']>=0.15); return r
o=[]
for (grp,L),d in R.groupby(['grp','L']):
    o.append(dict(grp=grp,L=L,cut='ALL',ex='1 tick',**line(d)))
    o.append(dict(grp=grp,L=L,cut='ALL',ex='3 ticks',**line(d,'v3')))
    o.append(dict(grp=grp,L=L,cut='PRICED',ex='1 tick',**line(d[d.priced])))
    o.append(dict(grp=grp,L=L,cut='PRICED',ex='3 ticks',**line(d[d.priced],'v3')))
    o.append(dict(grp=grp,L=L,cut='NOT_PRICED',ex='1 tick',**line(d[d.haspre&~d.priced])))
    o.append(dict(grp=grp,L=L,cut='p>=2',ex='1 tick',**line(d[d.p>=2])))
    q=d.v.quantile(0.99); o.append(dict(grp=grp,L=L,cut='less top 1%',ex='1 tick',**line(d[d.v<q])))
T=pd.DataFrame(o)
print("\\n== FIRST LAY stress lines\\n",T.round(3).to_string(index=False))
B=R[(R.grp=='ITEM')&(R.L==3)].copy(); B['pb']=pd.cut(B.p,[1,1.5,2,3,4,6,10,50])
u=[]
for kk,d in B.groupby('pb',observed=True): u.append(dict(band=str(kk),**line(d)))
print("\\n-- ITEM L3 by entry price\\n",pd.DataFrame(u).drop(columns=['PASS']).round(3).to_string(index=False))
W=T[T.PASS&(T.grp=='ITEM')]
print(f"\\n== SURVIVORS: {len(W)} of {int((T.grp=='ITEM').sum())} ITEM stress lines (one bet a game per line; lines share games)")
print(W.round(3).to_string(index=False) if len(W) else "none")
print(f"total {time.time()-T0:.0f}s")
'''
s = s[:k] + ana + s[e:]
open('/root/pe-queue/jobs/499_equaliser_stress.sh', 'w').write(s)
print('written')
