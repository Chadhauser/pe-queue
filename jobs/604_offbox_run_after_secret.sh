#!/bin/bash
# 604 (Mon 16 Nov 2026, 10:10). Peter re-pasted the S3 secret. Test ListBuckets, then run the off-box copy; report to reports/offbox_run.md.
set -o pipefail
cd /root/operators && set -a && . ./.env && set +a; unset GITHUB_TOKEN
R=/root/pe-queue/reports/offbox_run.md
{ echo "# Off-box copy $(date -u '+%F %H:%M') UTC"; echo '```'
python3 - <<'PY'
import os, sys; sys.modules["OpenSSL"]=None; sys.modules["urllib3.contrib.pyopenssl"]=None
import boto3; from botocore.config import Config
E,K,S=os.environ['ARCHIVE_S3_ENDPOINT'],os.environ['ARCHIVE_S3_KEY'],os.environ['ARCHIVE_S3_SECRET']
c=boto3.client('s3',endpoint_url=E,aws_access_key_id=K,aws_secret_access_key=S,region_name='default',config=Config(signature_version='s3v4',s3={'addressing_style':'path'}))
try: print("ListBuckets OK:",[b['Name'] for b in c.list_buckets().get('Buckets',[])])
except Exception as e: print("ListBuckets FAIL:",str(e)[:120])
PY
timeout 3000 python3 /root/pe-archive/offbox.py 2>&1 | grep -vi secret | tail -30 | cut -c1-200; echo "offbox exit ${PIPESTATUS[0]}"; echo '```'; } > $R
cd /root/pe-queue && git add reports/offbox_run.md reports/archive_offbox.md 2>/dev/null; git commit -qm "offbox run" ; git pull -q --no-rebase --no-edit; git push -q && echo pushed
echo "604 done"
