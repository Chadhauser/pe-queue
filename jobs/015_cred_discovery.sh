#!/bin/bash
# 015: find how the existing bots authenticate to Betfair (variable names and where they come from) so 010/013 can reuse
# them. Prints NAMES and sources only — every value is masked.
python3 - <<'PY'
import re, glob, os
pat=re.compile(r'(?i)\b([A-Z_]*(USER|PASS|PWD|APP_KEY|APPKEY|SSOID|TOKEN|CERT|KEY)[A-Z_]*)\s*=\s*(.+)')
for d in ('/root/pe-bot','/root/pe-prematch','/root/pe-logger','/root/pe-liq'):
    for f in sorted(glob.glob(d+'/*.py'))+sorted(glob.glob(d+'/.env*'))+sorted(glob.glob(d+'/*.json')):
        try: lines=open(f,errors='ignore').read().split('\n')
        except Exception: continue
        hits=[]
        for i,ln in enumerate(lines):
            m=pat.search(ln)
            if m:
                val=m.group(3).strip()
                src='env' if 'environ' in val or 'getenv' in val or 'dotenv' in val else 'file' if 'open(' in val else 'literal' if val[:1] in '\'"' else 'expr'
                hits.append(f"  L{i+1} {m.group(1)} <- {src}: {re.sub(r'[A-Za-z0-9]{6,}','***',val)[:80]}")
            if re.search(r'identitysso|certlogin|X-Authentication|X-Application',ln): hits.append(f"  L{i+1} AUTH: {re.sub(r'[A-Za-z0-9]{12,}','***',ln.strip())[:120]}")
        if hits: print(f,*hits,sep='\n')
print("\nENV KEY NAMES:")
for f in glob.glob('/root/pe-*/.env*'):
    print(f, [ln.split('=')[0] for ln in open(f) if '=' in ln and not ln.startswith('#')])
print("\nCRONTAB (masked):")
print(re.sub(r'[A-Za-z0-9]{20,}','***',os.popen('crontab -l').read()))
PY
