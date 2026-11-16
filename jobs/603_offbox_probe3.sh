#!/bin/bash
# 603 (Mon 16 Nov 2026, 10:20). boto3 on the box is 1.34 (no checksum option): rerun without it.
# 602. Rerun of 600: boto3 import died on the box's broken pyOpenSSL (same clash 413 worked round); block it first.
# 600. Storage is Ready in the panel and the key prefix matches, yet ListBuckets says SignatureDoesNotMatch.
# Probe four client settings with the same credentials and report which works: v4 path-style with checksum trailers off (newer boto3
# sends CRC trailers that Ceph-based stores reject), v4 virtual-host, v2 signature, and v4 with region eu2. Then patch offbox.py with the
# first working one and run it. Secrets never printed.
set -o pipefail
cd /root/operators && set -a && . ./.env && set +a
export AWS_REQUEST_CHECKSUM_CALCULATION=when_required AWS_RESPONSE_CHECKSUM_VALIDATION=when_required
R=/root/pe-queue/reports/offbox_probe3.md
{ echo "# Off-box signature probe $(date -u '+%F %H:%M') UTC"; echo '```'
python3 - <<'PY'
import os, sys; sys.modules["OpenSSL"]=None; sys.modules["urllib3.contrib.pyopenssl"]=None
import boto3, botocore
from botocore.config import Config
E,K,S=os.environ['ARCHIVE_S3_ENDPOINT'],os.environ['ARCHIVE_S3_KEY'],os.environ['ARCHIVE_S3_SECRET']
print("boto3",boto3.__version__,"botocore",botocore.__version__,"endpoint",E)
tries=[("v4 path default region",dict(region_name='default',config=Config(signature_version='s3v4',s3={'addressing_style':'path'}))),
       ("v4 virtual-host",dict(region_name='default',config=Config(signature_version='s3v4',s3={'addressing_style':'virtual'}))),
       ("v2 signature path",dict(region_name='default',config=Config(signature_version='s3',s3={'addressing_style':'path'}))),
       ("v4 region eu2 path",dict(region_name='eu2',config=Config(signature_version='s3v4',s3={'addressing_style':'path'}))),
       ("v4 region us-east-1 path",dict(region_name='us-east-1',config=Config(signature_version='s3v4',s3={'addressing_style':'path'})))]
ok=None
for name,kw in tries:
    try:
        c=boto3.client('s3',endpoint_url=E,aws_access_key_id=K,aws_secret_access_key=S,**kw); r=c.list_buckets(); print(f"OK   {name}: buckets {[b['Name'] for b in r.get('Buckets',[])]}"); ok=ok or name
    except Exception as e: print(f"FAIL {name}: {str(e)[:110]}")
print("WORKING:",ok)
open('/root/pe-archive/.probe_ok','w').write(ok or '')
PY
echo '```'; } > $R 2>&1
OK=$(cat /root/pe-archive/.probe_ok)
if [ -n "$OK" ]; then
  python3 - <<'PY'
p='/root/pe-archive/offbox.py'; s=open(p).read(); ok=open('/root/pe-archive/.probe_ok').read()
import re
cfg={"v4 path default region":"region_name='default', config=Config(signature_version='s3v4', s3={'addressing_style':'path'})",
     "v4 virtual-host":"region_name='default', config=Config(signature_version='s3v4', s3={'addressing_style':'virtual'})",
     "v2 signature path":"region_name='default', config=Config(signature_version='s3', s3={'addressing_style':'path'})",
     "v4 region eu2 path":"region_name='eu2', config=Config(signature_version='s3v4', s3={'addressing_style':'path'})",
     "v4 region us-east-1 path":"region_name='us-east-1', config=Config(signature_version='s3v4', s3={'addressing_style':'path'})"}[ok]
s2=re.sub(r"region_name='default', config=Config\([^\n]*?\)\)", cfg+")", s, count=1) if "region_name='default', config=Config(" in s else s
if s2==s: print("offbox.py: could not find the client config line to patch"); 
else: open(p,'w').write(s2); print("offbox.py patched with:",ok)
PY
  grep -q 'sys.modules\["OpenSSL"\]' /root/pe-archive/offbox.py || sed -i '1i import sys; sys.modules["OpenSSL"]=None; sys.modules["urllib3.contrib.pyopenssl"]=None' /root/pe-archive/offbox.py
  python3 -m py_compile /root/pe-archive/offbox.py && echo compiles
  grep -n "offbox.sh\|offbox" /root/pe-archive/offbox.sh | head -3; grep -q "AWS_REQUEST_CHECKSUM_CALCULATION" /root/pe-archive/offbox.sh || sed -i '2i export AWS_REQUEST_CHECKSUM_CALCULATION=when_required AWS_RESPONSE_CHECKSUM_VALIDATION=when_required' /root/pe-archive/offbox.sh
  { echo; echo "## upload run"; echo '```'; timeout 2400 python3 /root/pe-archive/offbox.py 2>&1 | grep -vi secret | tail -25 | cut -c1-200; echo "offbox exit ${PIPESTATUS[0]}"; echo '```'; } >> $R
else echo "no client setting worked (see the five FAIL lines): if all five say SignatureDoesNotMatch the secret in .env differs from the panel" >> $R; fi
cd /root/pe-queue && env -u GITHUB_TOKEN git add reports/offbox_probe3.md && git commit -qm "offbox probe" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q && echo pushed
echo "603 done"
