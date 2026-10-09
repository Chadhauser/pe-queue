#!/bin/bash
# 018: second pass of the Historic Data pull. 010's first pass hit HTTP 429 (rate limit) on the month LISTING for some months
# (2024-12, 2025-01 seen) and skipped them. The pull skips files already on disk, so re-running only fetches what is missing.
# Up to 3 attempts, 10 min apart, then reload all ext markets (010's loader) so 019 can rescan on the complete set.
for i in 1 2 3; do
  echo "=== attempt $i $(date -u) ==="
  (cd /root/pe-logger && python3 bf_hist_pull_ext.py) 2>&1 | tee /tmp/pull_$i.log | grep -E 'LIST FAILED|files,|TOTAL|done' | tail -40
  if ! grep -q 'LIST FAILED' /tmp/pull_$i.log; then echo "no listing failures on attempt $i"; break; fi
  [ $i -lt 3 ] && sleep 600
done
echo "ext files on disk: $(find /root/bfdata/ext -name '*.bz2' | wc -l)"
cd /root/pe-scan && python3 load_ext.py
