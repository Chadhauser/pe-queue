#!/bin/bash
# 580 (Sun 15 Nov 2026, 10:05). Contabo's S3 answered SignatureDoesNotMatch at 09:32 with 32-character keys. Besides provisioning, the
# usual cause on Contabo is addressing: it wants path-style requests and no AWS region in the signature. Patch offbox.py's client to
# path-style, region 'default', and print the exact error class on failure so the next report says which it is. Idempotent.
set -o pipefail
P=/root/pe-archive/offbox.py; cp $P $P.bak_580
python3 - <<'PY'
p='/root/pe-archive/offbox.py'; s=open(p).read()
if 'addressing_style' not in s:
    s=s.replace("config=botocore.config.Config(signature_version='s3v4',retries={'max_attempts':3}))","region_name='default',config=botocore.config.Config(signature_version='s3v4',retries={'max_attempts':3},s3={'addressing_style':'path'}))   # 580: Contabo wants path-style")
    open(p,'w').write(s); print("offbox.py: path-style + region default")
else: print("already path-style")
PY
python3 -m py_compile $P && echo compiles || { cp $P.bak_580 $P; echo RESTORED; exit 1; }
set -a; . /root/operators/.env; set +a; cd /root/pe-archive && timeout 600 python3 offbox.py 2>&1 | grep -v Deprecation | tail -5; echo "offbox exit ${PIPESTATUS[0]}"
echo "580 done"
