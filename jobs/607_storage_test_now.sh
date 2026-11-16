#!/bin/bash
# 607 (Mon 16 Nov 2026, 14:45). Test the storage key pair as it stands in .env now; if it works and no upload is running, start one.
cd /root/operators && set -a && . ./.env && set +a; unset GITHUB_TOKEN
R=/root/pe-queue/reports/storage_test.md
{ echo "# Storage test $(date -u '+%F %H:%M') UTC"; echo '```'
echo ".env mtime $(stat -c %y .env | cut -c1-19); key lines $(grep -c ARCHIVE_S3_KEY .env), secret lines $(grep -c ARCHIVE_S3_SECRET .env), key ends ...${ARCHIVE_S3_KEY: -4}, lengths ${#ARCHIVE_S3_KEY} ${#ARCHIVE_S3_SECRET}"
python3 -c "
import sys,os; sys.modules['OpenSSL']=None; sys.modules['urllib3.contrib.pyopenssl']=None
import boto3; from botocore.config import Config
c=boto3.client('s3',endpoint_url=os.environ['ARCHIVE_S3_ENDPOINT'],aws_access_key_id=os.environ['ARCHIVE_S3_KEY'],aws_secret_access_key=os.environ['ARCHIVE_S3_SECRET'],region_name='default',config=Config(signature_version='s3v4',s3={'addressing_style':'path'}))
print('STORAGE OK', [b['Name'] for b in c.list_buckets()['Buckets']])" 2>&1 | tail -1 | cut -c1-200
pgrep -fa offbox.py | cut -c1-80 || echo "no upload running"
tail -5 /root/pe-archive/offbox_manual.log 2>/dev/null | grep -vi secret | cut -c1-200
echo '```'; } > $R
cd /root/pe-queue && git add reports/storage_test.md && git commit -qm "storage test" && git pull -q --no-rebase --no-edit && git push -q && echo pushed
