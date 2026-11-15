import re
p='watchman/FINDER_QUEUE.md'
out=[];done=[]
want={'265','269','342','352','283','362','395'}
for l in open(p):
    m=re.match(r'(\d+)\. TODO',l)
    if m and m.group(1) in want and 'recurring' not in l[:40]:
        l=l.replace(' TODO',' RUNNING 2026-11-07',1); done.append(m.group(1))
    out.append(l)
open(p,'w').writelines(out)
print('claimed',sorted(done))
