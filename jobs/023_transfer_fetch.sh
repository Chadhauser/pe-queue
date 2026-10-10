#!/bin/bash
# 023: TRANSFER MECHANISM. Big files go to the public repo Chadhauser/pe-transfer AES-256 encrypted; this server decrypts them with
# TRANSFER_KEY from /root/pe-logger/.env (one line Peter pastes ONCE; reused for every future transfer). No scp, no laptop terminal.
# Exits 75 (WAITING) until the key is there. Then fetches every *.enc in the repo listing below, verifies md5, drops the plaintext in place.
# take the TRANSFER_KEY line that is a full 32-hex key (a paste once lost 6 characters)
KEY=$(grep -E '^TRANSFER_KEY=' /root/pe-logger/.env 2>/dev/null | cut -d= -f2- | tr -d '"\047 \015' | grep -E '^[0-9a-f]{32}$' | tail -1)
[ -z "$KEY" ] && { echo "WAITING: no TRANSFER_KEY in /root/pe-logger/.env"; exit 75; }
echo "TRANSFER_KEY lines in .env: $(grep -c '^TRANSFER_KEY=' /root/pe-logger/.env) | using key of length ${#KEY} ending ...${KEY: -4} (expected length 32, ending ...384f)"
[ "${KEY: -4}" != "384f" ] && echo "KEY DOES NOT MATCH the one Claude issued — re-paste the echo line exactly"
RAW=https://raw.githubusercontent.com/Chadhauser/pe-transfer/main
mkdir -p /root/fts /root/transfer
# manifest: encrypted name -> destination
while read -r name dest; do
  [ -z "$name" ] && continue
  [ -f "$dest" ] && { echo "have $dest"; continue; }
  curl -fsSL "$RAW/$name" -o /root/transfer/$name || { echo "download failed $name"; exit 1; }
  curl -fsSL "$RAW/${name%.enc}.md5" -o /root/transfer/${name%.enc}.md5 || { echo "md5 missing $name"; exit 1; }
  openssl enc -d -aes-256-cbc -pbkdf2 -in /root/transfer/$name -out "$dest.tmp" -pass pass:"$KEY" || { echo "DECRYPT FAILED (wrong TRANSFER_KEY?)"; rm -f "$dest.tmp"; exit 75; }
  want=$(cat /root/transfer/${name%.enc}.md5); got=$(md5sum "$dest.tmp" | cut -d' ' -f1)
  [ "$want" = "$got" ] && mv "$dest.tmp" "$dest" && echo "OK $dest md5 $got" || { echo "MD5 MISMATCH $name"; rm -f "$dest.tmp"; exit 1; }
done <<'MANIFEST'
fts_newmodel.csv.gz.enc /root/fts/fts_newmodel.csv.gz
MANIFEST
ls -la /root/fts/
