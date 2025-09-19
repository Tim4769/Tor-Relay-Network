#!/bin/bash

echo "==== Tor Middle Relay Full Auto Setup ===="

# === System Update ===
apt update && apt upgrade -y

# === Prerequisite Packages ===
apt install -y apt-transport-https curl gnupg lsb-release wget nyx unattended-upgrades apt-listchanges firewalld fail2ban logrotate

# === Verify CPU Architecture ===
ARCH=$(dpkg --print-architecture)
echo "Detected architecture: $ARCH"

# === Detect Distribution Codename ===
DISTRO=$(lsb_release -sc)
echo "Detected distro codename: $DISTRO"

# === Add Tor Project Repo ===
cat <<EOF > /etc/apt/sources.list.d/tor.list
deb     [signed-by=/usr/share/keyrings/deb.torproject.org-keyring.gpg] https://deb.torproject.org/torproject.org $DISTRO main
deb-src [signed-by=/usr/share/keyrings/deb.torproject.org-keyring.gpg] https://deb.torproject.org/torproject.org $DISTRO main
EOF

# === Add Tor GPG Key ===
wget -qO- https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc \
  | gpg --dearmor | tee /usr/share/keyrings/deb.torproject.org-keyring.gpg >/dev/null

# === Install Tor ===
apt update
apt install -y tor deb.torproject.org-keyring

# === Setup Logging ===
mkdir -p /var/log/tor
touch /var/log/tor/notices.log
chown -R debian-tor:debian-tor /var/log/tor

# === Configure torrc ===
cat <<EOF > /etc/tor/torrc
ORPort 9001
Nickname MyRelayNickname
ContactInfo Tim <wt95377@gmail.com>
ExitRelay 0
SocksPort 0
Log notice file /var/log/tor/notices.log
AccountingStart month 1 00:00
AccountingMax 1 TB
EOF

# === Restart Tor ===
systemctl enable --now tor
systemctl restart tor

# === Configure Logrotate ===
cat <<EOF > /etc/logrotate.d/tor
/var/log/tor/notices.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 debian-tor adm
    sharedscripts
    postrotate
        /bin/systemctl reload tor.service > /dev/null 2>/dev/null || :
    endscript
}
EOF

# === Firewall Setup ===
systemctl enable --now firewalld
firewall-cmd --permanent --add-service=ssh
firewall-cmd --permanent --add-port=9001/tcp
firewall-cmd --reload

# === Fail2Ban Setup ===
cat <<EOF > /etc/fail2ban/jail.local
[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
backend = systemd
EOF

systemctl enable --now fail2ban
systemctl restart fail2ban

# === Unattended Upgrades Config ===
cat <<EOF > /etc/apt/apt.conf.d/50unattended-upgrades
Unattended-Upgrade::Origins-Pattern {
    "origin=Debian,codename=${DISTRO},label=Debian-Security";
    "origin=TorProject";
};
Unattended-Upgrade::Package-Blacklist {};
Unattended-Upgrade::Automatic-Reboot "true";
EOF

cat <<EOF > /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::AutocleanInterval "5";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Verbose "1";
EOF

# === Final Checks ===
systemctl status tor --no-pager
systemctl status firewalld --no-pager
systemctl status fail2ban --no-pager
systemctl status unattended-upgrades --no-pager
systemctl status tor@default


echo "✅ Tor relay setup complete. Monitor it with: nyx"
