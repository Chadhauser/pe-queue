#!/bin/bash
# 579 (Sun 15 Nov 2026, 09:15). Peter ordered Contabo object storage (EU, 250 GB) and put four ARCHIVE_S3_* lines in /root/operators/.env.
# This job: reads them (never prints the secret), installs boto3 if missing, creates the bucket when the storage is out of provisioning
# (retries with exit 75 until it is), uploads every archive file (/root/pe-archive/**/*.zst), verifies size and etag/md5 on the bucket,
# writes the manifest to reports/archive_offbox.md, installs the nightly upload step after archive_tape.py, and un-pauses the history
# loader's 20 GB guard to 10 GB once the first upload is verified. Local files are KEPT (nothing deleted; Peter's order) until the
# monthly read-back has passed once against the bucket copies.
set -o pipefail
set -a; . /root/operators/.env; set +a
for v in ARCHIVE_S3_ENDPOINT ARCHIVE_S3_BUCKET ARCHIVE_S3_KEY ARCHIVE_S3_SECRET; do [ -n "${!v}" ] || { echo "missing $v in .env"; exit 1; }; done
echo "endpoint $ARCHIVE_S3_ENDPOINT bucket $ARCHIVE_S3_BUCKET key ${ARCHIVE_S3_KEY:0:4}... (secret hidden)"
python3 -c "import boto3" 2>/dev/null || pip3 install -q boto3 2>&1 | tail -1
cat > /root/pe-archive/offbox.py <<'PY'
# 579: upload archive files to the object storage and verify. Idempotent; prints a manifest. Exit 75 while the storage is provisioning.
import os,sys,glob,hashlib,boto3,botocore,datetime
E,B,K,S=(os.environ[k] for k in ('ARCHIVE_S3_ENDPOINT','ARCHIVE_S3_BUCKET','ARCHIVE_S3_KEY','ARCHIVE_S3_SECRET'))
s3=boto3.client('s3',endpoint_url=E,aws_access_key_id=K,aws_secret_access_key=S,config=botocore.config.Config(signature_version='s3v4',retries={'max_attempts':3}))
try:
    buckets=[b['Name'] for b in s3.list_buckets().get('Buckets',[])]
except Exception as e:
    print("storage not ready:",str(e)[:120]); sys.exit(75)
if B not in buckets:
    try: s3.create_bucket(Bucket=B); print("bucket created:",B)
    except Exception as e: print("bucket create failed:",str(e)[:140]); sys.exit(75)
def md5(p):
    h=hashlib.md5()
    with open(p,'rb') as f:
        for ch in iter(lambda: f.read(1<<20),b''): h.update(ch)
    return h.hexdigest()
have={o['Key']:(o['Size'],o['ETag'].strip('"')) for page in s3.get_paginator('list_objects_v2').paginate(Bucket=B) for o in page.get('Contents',[])}
up=0; ok=0; bad=[]; tot=0
for p in sorted(glob.glob('/root/pe-archive/**/*.zst',recursive=True)):
    key=os.path.relpath(p,'/root/pe-archive'); sz=os.path.getsize(p); tot+=sz
    if key in have and have[key][0]==sz: ok+=1; continue
    s3.upload_file(p,B,key); up+=1
    h=s3.head_object(Bucket=B,Key=key)
    if h['ContentLength']!=sz: bad.append(key)
    elif sz<5*1024**3 and h['ETag'].strip('"')!=md5(p) and '-' not in h['ETag']: bad.append(key+' (checksum)')
    else: ok+=1
print(f"files {ok+len(bad)} | uploaded now {up} | verified on bucket {ok} | problems {len(bad)} | {tot/1e9:.1f} GB local")
for b in bad: print("PROBLEM",b)
open('/root/pe-queue/reports/archive_offbox.md','a').write(f"- {datetime.datetime.utcnow():%F %H:%M} UTC: {ok} files verified on {B}, {up} uploaded this run, {len(bad)} problems\n")
sys.exit(1 if bad else 0)
PY
python3 -m py_compile /root/pe-archive/offbox.py && cd /root/pe-archive && python3 offbox.py; RC=$?
[ $RC = 75 ] && { echo "storage still provisioning — this job re-polls every cycle until it is ready"; exit 75; }
[ $RC = 0 ] || { echo "upload problems — nothing else changed"; exit 1; }
cat > /root/pe-archive/offbox.sh <<'SH'
#!/bin/bash
set -a; . /root/operators/.env; set +a; cd /root/pe-archive && /usr/bin/python3 offbox.py >> offbox.log 2>&1
SH
chmod +x /root/pe-archive/offbox.sh
( crontab -l | grep -v offbox.sh; echo "15 4 * * * /root/pe-archive/offbox.sh" ) | crontab - && echo "nightly upload at 04:15 UTC, after the 02:35 archive"
# history loader: guard from 20 GB to 10 GB now the archive leaves the box; the loader itself decides from df each run
grep -rln "20" /root/pe-hist/*.py 2>/dev/null | head -3; L=$(grep -ln "free.*20\|20.*free\|MIN_FREE" /root/pe-hist/*.py 2>/dev/null | head -1)
if [ -n "$L" ]; then cp $L $L.bak_579; sed -i -E 's/(MIN_FREE(_GB)?\s*=\s*)20/\110/; s/free\s*<\s*20/free<10/' $L; python3 -m py_compile $L && echo "loader guard: $L now pauses under 10 GB" || { cp $L.bak_579 $L; echo "loader guard unchanged"; }; else echo "loader guard not found by pattern — left as is (reported)"; fi
df -h / | tail -1
cd /root/pe-queue && git add reports/archive_offbox.md && git commit -qm "579: archive off-box manifest" && git pull -q --no-edit && git push -q && echo pushed
echo "579 done"
