#!/bin/bash
# 234: iOS truncates a long push body, so the digest goes out as one short push per line (<=150 chars each, numbered), ~12 pushes,
# 2 s apart. Same content as 233. The daily 06:45 cron now uses this format.
python3 - <<'PY'
p='/root/pe-push/digest.py'; s=open(p).read()
old='''for i,(t,b) in enumerate([("PE morning 1/2 — live books",part1),("PE morning 2/2 — overnight verdicts",part2)],1):
    cur.execute("INSERT INTO digest_log (part, body) VALUES (%s,%s)",(i,b)); n=push(t,b,f"digest{i}"); print(f"pushed part {i} to {n} devices\\n{b}\\n")'''
new='''import time
lines=[l for l in (part1+"\\n"+part2).splitlines() if l.strip()]
cur.execute("INSERT INTO digest_log (part, body) VALUES (%s,%s)",(0,part1+"\\n"+part2))
for i,l in enumerate(lines,1):
    n=push(f"PE {i}/{len(lines)}",l[:150],f"d{i}"); print(f"[{i}/{len(lines)}] -> {n} devices: {l[:150]}"); time.sleep(2)'''
assert old in s, "anchor"; s=s.replace(old,new,1); open(p,'w').write(s); print("digest now one line per push")
PY
python3 -m py_compile /root/pe-push/digest.py && python3 /root/pe-push/digest.py
