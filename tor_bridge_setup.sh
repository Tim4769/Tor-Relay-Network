
#!/bin/bash

# === Initial System Setup ===
apt update && apt upgrade -y
apt install apt-transport-https gnupg wget curl -y

# === Add Tor Project Repository ===
DISTRO_CODENAME=$(lsb_release -c -s)
echo "deb [signed-by=/usr/share/keyrings/deb.torproject.org-keyring.gpg] https://deb.torproject.org/torproject.org $DISTRO_CODENAME main" > /etc/apt/sources.list.d/tor.list
echo "deb-src [signed-by=/usr/share/keyrings/deb.torproject.org-keyring.gpg] https://deb.torproject.org/torproject.org $DISTRO_CODENAME main" >> /etc/apt/sources.list.d/tor.list

wget -qO- https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc | gpg --dearmor | tee /usr/share/keyrings/deb.torproject.org-keyring.gpg > /dev/null

# === Install Tor and obfs4proxy ===
apt update
apt install tor obfs4proxy deb.torproject.org-keyring nyx unattended-upgrades firewalld fail2ban logrotate -y

# === Enable and Start Services ===
systemctl enable --now tor
systemctl enable --now firewalld
systemctl enable --now fail2ban

# === Configure torrc for Bridge ===
cat <<EOF > /etc/tor/torrc
BridgeRelay 1
ORPort 443
ServerTransportPlugin obfs4 exec /usr/bin/obfs4proxy
ServerTransportListenAddr obfs4 0.0.0.0:5443
ExtORPort auto
ContactInfo Tim <wt95377@gmail.com>
Nickname TimBridgeRelay01
ExitRelay 0
SocksPort 0
Log notice file /var/log/tor/notices.log
EOF

# === Log Directory Setup ===
mkdir -p /var/log/tor
touch /var/log/tor/notices.log
chown -R debian-tor:debian-tor /var/log/tor

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

# === Firewall Configuration ===
firewall-cmd --permanent --add-service=ssh
firewall-cmd --permanent --add-port=443/tcp
firewall-cmd --permanent --add-port=5443/tcp
firewall-cmd --reload

# === Fail2Ban Configuration ===
echo "[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
backend = systemd" > /etc/fail2ban/jail.local

systemctl restart fail2ban
systemctl restart tor

# === Unattended Upgrades Configuration ===
echo 'Unattended-Upgrade::Origins-Pattern {
    "origin=Debian,codename=${distro_codename},label=Debian-Security";
    "origin=TorProject";
};
Unattended-Upgrade::Package-Blacklist {};
' > /etc/apt/apt.conf.d/50unattended-upgrades

echo 'APT::Periodic::Update-Package-Lists "1";
APT::Periodic::AutocleanInterval "5";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Verbose "1";' > /etc/apt/apt.conf.d/20auto-upgrades

# === Final Status Check ===
systemctl status tor
