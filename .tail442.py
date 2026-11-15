p='jobs/499_cs_longshot_minor.sh'
s=open(p).read()
i=s.index('print("counts:",dict(sorted(SK.items())),flush=True)')
j=s.index('\nPY\n')
new='''print("counts:",dict(sorted(SK.items())),flush=True)
na=agree['agree']+agree['disagree']; share=agree['agree']/na if na else 0.0
print(f"MAJOR check, official winner v af/fd final score: agree {agree['agree']}, disagree {agree['disagree']}, share {share:.4f}",flush=True)
if na<300 or share<0.99: sys.exit("official winner and af/fd disagree on over 1% of MAJOR games (or too few to check): stopped before any table, as the rule says")
R=pd.DataFrame(rows,columns=['var','win','band','side','ev','when','p','won','v','sel','grp'])
w1=R[(R['var']=='ALL')&(R.side=='L')].groupby(['ev','win']).won.sum(); print("winning runners per game-window among traded (must be 0 or 1):",dict(Counter(w1.values)),flush=True); assert w1.max()<=1
R=pd.concat([R,R.assign(grp='BOTH')],ignore_index=True)
out=[]
for (grp,var,wn,bn,side),d in R.groupby(['grp','var','win','band','side']):
    r=gate(d.v.values.astype(float),d.when.values,ev=d.ev.values if var=='ALL' else None)
    fp=d.p.map(lambda q:step(q,-1)) if side=='B' else d.p.map(lambda q:step(q,1))
    out.append(dict(grp=grp,var=var,win=wn,band=bn,side=side,**r,games=d.ev.nunique(),won=d.won.mean(),imp=(1/fp).mean(),med_p=d.p.median()))
S=pd.DataFrame(out)
B=R[R.grp=='BOTH']
print(f"\\ndates {pd.Timestamp(B.when.min(),unit='s'):%Y-%m-%d} to {pd.Timestamp(B.when.max(),unit='s'):%Y-%m-%d}; games {B.ev.nunique()} (MINOR {R[R.grp=='MINOR'].ev.nunique()}, MAJOR {R[R.grp=='MAJOR'].ev.nunique()}); lines {len(S)}")
for g in ['MINOR','MAJOR','BOTH']:
    print(f"\\n== {g}, LAY lines\\n",S[(S.grp==g)&(S.side=='L')].sort_values(['var','win','band']).drop(columns=['n1','n2']).round(3).to_string(index=False))
    print(f"\\n== {g}, BACK lines\\n",S[(S.grp==g)&(S.side=='B')].sort_values(['var','win','band']).drop(columns=['n1','n2','PASS']).round(3).to_string(index=False))
print("\\n== TOP 15 by t, all groups\\n",S.sort_values('t',ascending=False).head(15).drop(columns=['n1','n2']).round(3).to_string(index=False))
Y=S[S.PASS]; print(f"\\n== SURVIVORS: {len(Y)} of {len(S)}\\n",Y.round(3).to_string(index=False) if len(Y) else "none")
print(f"total {time.time()-T0:.0f}s")'''
s=s[:i]+new+s[j:]
open(p,'w').write(s); print('ok')
