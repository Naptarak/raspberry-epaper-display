#!/bin/bash

# Rendszerfrissítés és alapvető csomagok telepítése
echo "Rendszer frissítése..."
sudo apt update && sudo apt upgrade -y

# Szükséges rendszerszintű csomagok telepítése
echo "Szükséges csomagok telepítése..."
sudo apt install -y \
    git \
    nodejs \
    npm \
    python3-pip \
    python3-pil \
    python3-numpy \
    libatlas-base-dev \
    wiringpi \
    chromium-browser

# SPI interfész engedélyezése
echo "SPI interfész engedélyezése..."
if ! grep -q "dtparam=spi=on" /boot/config.txt; then
    echo "dtparam=spi=on" | sudo tee -a /boot/config.txt
fi

# Node.js projekt inicializálása és függőségek telepítése
echo "Node.js függőségek telepítése..."
npm install

# Python függőségek telepítése
echo "Python függőségek telepítése..."
sudo pip3 install RPi.GPIO spidev pillow

# Systemd service létrehozása
echo "Systemd service létrehozása..."
sudo tee /etc/systemd/system/weather-display.service << EOF
[Unit]
Description=Weather Display Service
After=network.target

[Service]
ExecStart=/usr/bin/node /home/pi/weather-display/index.js
WorkingDirectory=/home/pi/weather-display
User=pi
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Service engedélyezése és indítása
echo "Service engedélyezése és indítása..."
sudo systemctl enable weather-display
sudo systemctl start weather-display

echo "Telepítés befejezve!"
echo "A rendszer automatikusan frissíti az időjárás kijelzést 5 percenként."
echo "Az alkalmazás logjai megtekinthetők: journalctl -u weather-display -f"