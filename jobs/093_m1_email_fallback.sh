#!/bin/bash
# 093: M1 EMAIL FALLBACK. The web push to Peter's iPhone is accepted by Apple but not arriving. Find the mail sender the daily
# report / health emails already use (SMTP/Resend/SendGrid/Gmail vars in /root/pe-*/.env or crontab) and add email delivery to
# every M1 push (same text, subject = title) to Peter's own address. Then send "M1 TEST" by email.
python3 - <<'PY'
import os, re, sys, glob, subprocess
sys.path.insert(0,'/root/pe-queue/runner'); import creds
E=creds.all_vars()
keys=[k for k in E if re.search(r'MAIL|SMTP|RESEND|SENDGRID|MAILGUN|POSTMARK|BREVO|GMAIL',k,re.I)]
print("mail-related var names:",keys)
print("crontab mail lines:"); print(subprocess.run("crontab -l | grep -i -E 'mail|report|health'",shell=True,capture_output=True,text=True).stdout)
print("mail senders on disk:"); print(subprocess.run("grep -l -i -E 'smtplib|resend|sendgrid|mailgun' /root/pe-*/*.py 2>/dev/null | head",shell=True,capture_output=True,text=True).stdout)
for f in subprocess.run("grep -l -i -E 'smtplib|resend\\.|sendgrid|mailgun' /root/pe-*/*.py 2>/dev/null | head -3",shell=True,capture_output=True,text=True).stdout.split():
    print("==",f); print(subprocess.run(f"grep -n -i -E 'smtp|resend|sendgrid|mailgun|from_addr|to_addr|EMAIL|def send' {f} | head -25",shell=True,capture_output=True,text=True).stdout)
PY
