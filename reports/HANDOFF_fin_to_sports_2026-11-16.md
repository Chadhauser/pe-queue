# HANDOFF from the financial-trading chat to the SPORTS chat — 16 Nov 2026 14:40 UK
Peter: "pass this over to the sports, we will come back to this later in the week."

## 1. Financial work is STOPPED on this box (Peter's order, 14:33)
- Peter's SSH line killed every fin process (MT5/Wine, team loop, duka, paper bots) and removed every cron line containing /root/pe-fin/ or mt5. Backup: /root/crontab_backup.txt.
- Job 541 (queued) repeats the stop, flattens the Alpaca PAPER account, apt clean. Harmless if it runs after the stop.
- Nothing financial restarts until Peter says "restart fin segregated" (own runner, lowest priority, stops itself under 25 GB free, no MT5 on this box).
- What fin did to sports today: MT5 job 527 held the shared runner ~3 h this morning (runner not cycling 76/136 min); ~8 orphan terminal64.exe processes; fin data + Wine 4.1 GB on disk.
- Fin footprint: /root/.mt5wine 2.2 GB (delete line given to Peter, may or may not have been run), /root/pe-data 1.8 GB (kept), /root/pe-fin 0.1 GB.

## 2. DISK — the sports chat's to fix
- /dev/sda1 145 GB, 9.8 GB free (94%) at 14:37. sda is 150 GB in total: no unallocated space. The 250 GB Peter bought is Contabo OBJECT STORAGE, not disk.
- Job 413 (archive off-box) still failing SignatureDoesNotMatch.
- Peter's check of /root/operators/.env at 14:39: ARCHIVE_S3_ENDPOINT=https://eu2.contabostorage.com, ARCHIVE_S3_BUCKET=pe-archive, ARCHIVE_S3_KEY=cf06... (masked), ARCHIVE_S3_SECRET length 32 (no stray characters).
- So the format is right; the likely cause is a mismatched pair (secret not the one belonging to access key cf06..., e.g. regenerated in the panel, or key and secret swapped), or the storage's region is not eu2. Next step: Peter re-copies BOTH values from Contabo panel -> Object Storage -> S3 credentials, and checks the region shown there against eu2.
- 408 (liq_sample 60-day retention) is also waiting; with 9.8 GB free it is urgent.
