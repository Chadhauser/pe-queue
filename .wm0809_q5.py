import os
jobs = sorted(f[:-3] for f in os.listdir('/root/pe-queue/jobs') if f.endswith('.sh'))
done = set(os.listdir('/root/pe-queue-state/done'))
pend = [j for j in jobs if j not in done and j + '.sh' not in done]
print(len(pend), pend)
