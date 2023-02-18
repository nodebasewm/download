#!/usr/bin/env bash

aya_home=/opt/aya

echo -e "-- Configuring your node to start on server startup\n"
sudo ln -s $aya_home/cosmovisor/current/bin/ayad /usr/local/bin/ayad >/dev/null 2>&1
sudo ln -s $aya_home/cosmovisor/cosmovisor /usr/local/bin/cosmovisor >/dev/null 2>&1

sudo tee /etc/systemd/system/cosmovisor.service > /dev/null <<EOF
[Unit]
Description=Aya Node
After=network-online.target

[Service]
User=$USER
ExecStart=$(which cosmovisor) run start --home "$aya_home" &>>"$aya_home"/logs/aya.log
Restart=always
RestartSec=3
LimitNOFILE=4096

Environment="/opt/aya"
Environment="DAEMON_NAME=ayad"
Environment="DAEMON_DATA_BACKUP_DIR=/opt/aya/backup"
Environment="DAEMON_ALLOW_DOWNLOAD_BINARIES=true"
Environment="DAEMON_RESTART_AFTER_UPGRADE=true"
Environment="DAEMON_HOME=/opt/aya"
[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable cosmovisor

