#!/bin/bash

# install.sh - Telepítő script Raspberry Pi Zero 2W-hez és Waveshare 4.01 HAT (F) e-paper kijelzőhöz

echo "Waveshare 4.01 HAT (F) E-paper kijelző telepítő script"
echo "======================================================"

# Ellenőrizzük, hogy root jogosultsággal fut-e a script
if [ "$(id -u)" -ne 0 ]; then
    echo "Hiba: A telepítőt root jogosultsággal kell futtatni!" >&2
    echo "Használja a 'sudo bash install.sh' parancsot." >&2
    exit 1
fi

# Telepítési könyvtár létrehozása
INSTALL_DIR="/opt/e-paper-display"
echo "Telepítési könyvtár létrehozása: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

# Rendszer frissítése
echo "Rendszer frissítése..."
apt-get update
apt-get upgrade -y

# Szükséges csomagok telepítése
echo "Szükséges csomagok telepítése..."
apt-get install -y python3 python3-pip python3-pil python3-numpy git libopenjp2-7 libatlas-base-dev wget chromium-browser xvfb

# SPI interfész engedélyezése
echo "SPI interfész engedélyezése..."
if ! grep -q "dtparam=spi=on" /boot/config.txt; then
    echo "dtparam=spi=on" >> /boot/config.txt
    echo "SPI interfész engedélyezve. Újraindítás szükséges a változtatások érvényesítéséhez."
else
    echo "SPI interfész már engedélyezve van."
fi

# Waveshare e-paper könyvtár letöltése
echo "Waveshare e-paper könyvtár letöltése..."
cd "$INSTALL_DIR"
git clone https://github.com/waveshare/e-Paper.git
cd e-Paper/RaspberryPi_JetsonNano/python
pip3 install RPi.GPIO spidev
pip3 install requests pillow

# E-paper display script létrehozása
echo "E-paper display script létrehozása..."
cat > "$INSTALL_DIR/e_paper_display.py" << 'EOL'
#!/usr/bin/env python3
# -*- coding:utf-8 -*-

import os
import sys
import time
import requests
from PIL import Image
import logging
from datetime import datetime
import subprocess

# Konfiguráljuk a naplózást
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler("/var/log/e-paper-display.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger("e-paper-display")

# Waveshare e-Paper könyvtárak importálása
waveshare_dir = os.path.join(os.path.dirname(os.path.realpath(__file__)), "e-Paper/RaspberryPi_JetsonNano/python/lib")
sys.path.append(waveshare_dir)

try:
    from waveshare_epd import epd4in01f
except ImportError:
    logger.error("Waveshare e-Paper könyvtár nem található!")
    sys.exit(1)

def capture_webpage_to_image():
    """Weboldal képernyőképének mentése"""
    try:
        logger.info("Weboldal képernyőképének készítése...")
        # Xvfb használata virtuális képernyőként
        cmd = "xvfb-run --server-args='-screen 0, 640x400x24' " \
              "chromium-browser --headless --disable-gpu " \
              "--screenshot=/tmp/screenshot.png " \
              "--window-size=640,400 " \
              "https://naptarak.com/e-paper.html"
        subprocess.run(cmd, shell=True, check=True)
        return Image.open('/tmp/screenshot.png')
    except Exception as e:
        logger.error(f"Hiba a weboldal képernyőképének készítésekor: {str(e)}")
        return None

def update_display():
    try:
        # Inicializáljuk a kijelzőt
        logger.info("E-paper kijelző inicializálása...")
        epd = epd4in01f.EPD()
        epd.init()
        
        # Weboldal képének készítése
        image = capture_webpage_to_image()
        
        if image is None:
            # Ha nem sikerült képernyőképet készíteni, próbáljuk meg letölteni a weboldalt
            try:
                logger.info("Alternatív tartalom letöltése...")
                response = requests.get("https://naptarak.com/e-paper.html")
                with open('/tmp/temp_page.html', 'wb') as f:
                    f.write(response.content)
                
                # Ha a weboldal képet ad vissza, azt használjuk
                if 'image' in response.headers.get('Content-Type', ''):
                    with open('/tmp/image.png', 'wb') as f:
                        f.write(response.content)
                    image = Image.open('/tmp/image.png')
                else:
                    # Ha minden más módszer sikertelen, hibaüzenetet jelenítünk meg
                    image = Image.new('RGB', (640, 400), (255, 255, 255))
                    
            except Exception as e:
                logger.error(f"Hiba a weboldal letöltésekor: {str(e)}")
                image = Image.new('RGB', (640, 400), (255, 255, 255))
                
        # Kijelző méreteihez igazítás ha szükséges
        if image.size != (epd.width, epd.height):
            image = image.resize((epd.width, epd.height))
        
        # Frissítjük a kijelzőt
        logger.info("Kijelző frissítése...")
        epd.display(epd.getbuffer(image))
        logger.info("Kijelző frissítve!")
        
        # Alvó módba helyezzük a kijelzőt az energiatakarékosság érdekében
        epd.sleep()
            
    except Exception as e:
        logger.error(f"Hiba a kijelző frissítése közben: {str(e)}")

def main():
    logger.info("E-paper kijelző alkalmazás elindult")
    
    # Végtelen ciklusban frissítjük a kijelzőt
    while True:
        update_display()
        # 5 percet várunk a következő frissítésig (300 másodperc)
        logger.info("Várakozás 5 percet a következő frissítésig...")
        time.sleep(300)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        logger.info("A program megszakítva a felhasználó által")
        sys.exit(0)
EOL

# Script futtathatóvá tétele
chmod +x "$INSTALL_DIR/e_paper_display.py"

# Systemd service létrehozása az automatikus indításhoz
echo "Systemd service létrehozása..."
cat > /etc/systemd/system/e-paper-display.service << EOL
[Unit]
Description=E-Paper Display Service
After=network.target

[Service]
ExecStart=/usr/bin/python3 $INSTALL_DIR/e_paper_display.py
WorkingDirectory=$INSTALL_DIR
StandardOutput=inherit
StandardError=inherit
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOL

# Service engedélyezése és indítása
echo "Systemd service engedélyezése és indítása..."
systemctl daemon-reload
systemctl enable e-paper-display.service
systemctl start e-paper-display.service

echo ""
echo "Telepítés befejezve!"
echo "Az e-paper kijelző alkalmazás telepítve lett és automatikusan elindul a rendszer indításakor."
echo "A kijelző 5 percenként frissül a https://naptarak.com/e-paper.html oldal tartalmával."
echo ""
echo "A naplófájlok itt találhatók: /var/log/e-paper-display.log"
echo ""
echo "A telepítő után újraindítás ajánlott:"
echo "sudo reboot"
echo ""
