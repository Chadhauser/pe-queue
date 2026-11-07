#!/bin/bash
set -o pipefail
# 499_dnb_resting_pooled (Finder 2026-11-07, queue item 265): jobs/499_derivative_gap.sh unchanged except the date window, every month 263 did not read, Sep 2023 to Feb 2024, as one read, and a pooled line added at the end: DNB G2 CHEAP back and DEAR lay as one line, halves by date, also without the largest win. Scored now the pooled n is over 300.
python3 - /root/pe-queue/jobs/499_derivative_gap.sh <<'PY' | bash || echo "ERROR: derivative_gap failed"
import sys
t=open(sys.argv[1]).read()
a="market_time>='2024-03-01' AND market_time<'2026-10-01'"
assert t.count(a)>=1
t=t.replace(a,"market_time>='2023-09-01' AND market_time<'2024-03-01'")
b='S=O[O.PASS]; print(f"\\n== SURVIVORS: {len(S)} of {len(O)}")'
assert t.count(b)==1
add=r'''x1=A[(A.mk=='DNB')&(A.bd=='G2')&(A.kind=='CHEAP')]; x2=A[(A.mk=='DNB')&(A.bd=='G2')&(A.kind=='DEAR')]
pv=np.concatenate([x1.vb.values.astype(float),x2.vl.values.astype(float)]); po=np.concatenate([x1.off.values,x2.off.values]); ph=np.where(po<MD,1,2); pl=line(pv,ph)
print(f"\n== ITEM 265 POOLED, DNB G2 CHEAP back + DEAR lay, Sep 2023 to Feb 2024: n {pl['n']} per10 {pl['per10']:.3f} t {pl['t']:.2f} n1 {pl['n1']} h1 {pl['h1']:.3f} n2 {pl['n2']} h2 {pl['h2']:.3f} maxwin {pl['maxwin']:.2f} games {pd.concat([x1.e,x2.e]).nunique()} PASS {pl['PASS']}; CHEAP n {len(x1)} per10 {x1.vb.astype(float).mean():.3f}; DEAR n {len(x2)} per10 {x2.vl.astype(float).mean():.3f}")
k=int(np.argmax(pv)); pz=line(np.delete(pv,k),np.delete(ph,k)); print(f"   without the largest win: n {pz['n']} per10 {pz['per10']:.3f} t {pz['t']:.2f} h1 {pz['h1']:.3f} h2 {pz['h2']:.3f}",flush=True)
'''
print(t.replace(b,add+b))
PY
