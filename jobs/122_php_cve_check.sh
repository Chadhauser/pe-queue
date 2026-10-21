#!/bin/bash
# 122: Contabo notice 21 Oct — PHP RCE CVE-2026-109618/109619. Our server runs Python daemons, not PHP, but check and patch
# anyway: is PHP installed, is anything serving web on 80/443, are security updates automatic. Patch PHP if present.
echo "== PHP present?"; which php php-fpm 2>/dev/null; php -v 2>/dev/null | head -1 || echo "no php binary"
dpkg -l 2>/dev/null | grep -iE '^ii +(php|libapache2-mod-php|apache2|nginx|lighttpd|litespeed)' || echo "no php/apache/nginx packages installed"
echo "== listening web ports"; ss -ltnp 2>/dev/null | grep -E ':(80|443|8080|8443) ' || echo "nothing listening on 80/443/8080/8443"
echo "== unattended security updates"; dpkg -l unattended-upgrades 2>/dev/null | grep -q '^ii' && echo "unattended-upgrades installed" || echo "unattended-upgrades NOT installed"
cat /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null || echo "no 20auto-upgrades config"
if dpkg -l 2>/dev/null | grep -qE '^ii +php'; then
  echo "== PHP found: patching"; export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq && apt-get install -y -qq --only-upgrade 'php*' && (systemctl restart 'php*-fpm' 2>/dev/null; systemctl restart apache2 2>/dev/null; systemctl restart nginx 2>/dev/null; true)
  php -v | head -1
else
  echo "== no PHP on this server: CVE does not apply. Enabling automatic security updates so future notices need no action."
  export DEBIAN_FRONTEND=noninteractive; apt-get update -qq; apt-get install -y -qq unattended-upgrades >/dev/null 2>&1
  printf 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\n' > /etc/apt/apt.conf.d/20auto-upgrades
  grep -q 'Automatic-Reboot "false"' /etc/apt/apt.conf.d/50unattended-upgrades 2>/dev/null || echo 'Unattended-Upgrade::Automatic-Reboot "false";' >> /etc/apt/apt.conf.d/50unattended-upgrades
  systemctl enable --now unattended-upgrades 2>/dev/null; echo "unattended security upgrades ON, auto-reboot OFF (recorders keep running)"
fi
echo "== pending security updates now"; apt list --upgradable 2>/dev/null | grep -i security | head -20 || true
