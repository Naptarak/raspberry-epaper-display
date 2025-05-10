#!/bin/bash

# E-Paper kijelző telepítő szkript Raspberry Pi Zero 2W-hez
# Waveshare 4.01 HAT (F) e-paper kijelzőhöz
# Frissítési gyakoriság: 5 perc

echo "===================================================="
echo "E-Paper kijelző alkalmazás telepítése Raspberry Pi Zero 2W-re"
echo "Kijelző: Waveshare 4.01 inch HAT (F) e-paper"
echo "Tartalom forrás: https://naptarak.com/e-paper.html"
echo "Frissítési gyakoriság: 5 perc"
echo "===================================================="

# Kilépés hiba esetén
set -e

# Ellenőrizzük, hogy root-ként fut-e
if [ "$EUID" -ne 0 ]; then
  echo "Kérlek root-ként futtasd (használj sudo-t)"
  exit 1
fi

# Rendszer frissítése
echo "Rendszercsomag frissítése..."
apt-get update
apt-get upgrade -y

# libtiff csomag ellenőrzése (különböző verziók támogatása)
TIFF_PACKAGE="libtiff5"
if ! apt-cache show libtiff5 &>/dev/null; then
  echo "libtiff5 csomag nem található, alternatív csomagok keresése..."
  if apt-cache show libtiff6 &>/dev/null; then
    TIFF_PACKAGE="libtiff6"
  elif apt-cache show libtiff &>/dev/null; then
    TIFF_PACKAGE="libtiff"
  else
    echo "Nem található kompatibilis libtiff csomag. Telepítés libtiff nélkül folytatódik."
    TIFF_PACKAGE=""
  fi
fi

# Szükséges rendszer csomagok telepítése
echo "Szükséges rendszer csomagok telepítése..."
PACKAGES="python3-pip python3-pil python3-numpy libopenjp2-7 libatlas-base-dev git wget imagemagick"

if [ -n "$TIFF_PACKAGE" ]; then
  PACKAGES="$PACKAGES $TIFF_PACKAGE"
fi

apt-get install -y $PACKAGES

# Python csomagok telepítése apt-get használatával pip helyett
echo "Python csomagok telepítése apt segítségével..."
apt-get install -y python3-rpi.gpio python3-spidev python3-requests python3-pil python3-venv

# Alkalmazás könyvtár létrehozása
echo "Alkalmazás könyvtár létrehozása..."
APP_DIR="/opt/e-paper-display"
mkdir -p "$APP_DIR"

# Waveshare e-Paper könyvtár klónozása
echo "Waveshare e-Paper könyvtár letöltése..."
git clone https://github.com/waveshare/e-Paper.git /tmp/e-Paper
cp -r /tmp/e-Paper/RaspberryPi_JetsonNano/python/lib/waveshare_epd "$APP_DIR/"
rm -rf /tmp/e-Paper

# Fő Python script létrehozása
echo "Kijelző script létrehozása..."
cat > "$APP_DIR/display.py" << 'EOF'
#!/usr/bin/env python3
# -*- coding:utf-8 -*-

import os
import time
import logging
import requests
from PIL import Image
from io import BytesIO
import sys
import signal

# Waveshare e-paper kijelző könyvtár importálása
sys.path.append(os.path.join(os.path.dirname(os.path.realpath(__file__)), 'waveshare_epd'))
from waveshare_epd import epd4in01f

# Naplózás beállítása
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(os.path.join(os.path.dirname(os.path.realpath(__file__)), "display.log")),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Megjelenítendő URL
URL = "https://naptarak.com/e-paper.html"

# Globális változó a kijelző objektumnak
epd = None

def signal_handler(sig, frame):
    """Kezelő a tiszta kilépéshez"""
    logger.info("Kilépés...")
    global epd
    if epd is not None:
        try:
            epd.sleep()
        except:
            pass
    sys.exit(0)

def fetch_image():
    """
    Kép letöltése közvetlenül a weboldalról.
    A weboldal várhatóan egy, az e-paper kijelzőre optimalizált képet szolgáltat.
    """
    logger.info("Kép letöltése a weboldalról...")
    
    try:
        headers = {
            'User-Agent': 'RaspberryPiZero/1.0 EPaperDisplay/1.0',
        }
        
        # Próbáljuk meg közvetlenül a képet kérni
        response = requests.get(URL + "?direct=1", headers=headers, timeout=30)
        
        if response.status_code == 200:
            content_type = response.headers.get('Content-Type', '')
            if 'image' in content_type:
                try:
                    # Próbáljuk megnyitni a választ képként
                    img = Image.open(BytesIO(response.content))
                    return img
                except Exception as e:
                    logger.error(f"Nem sikerült megnyitni a képet: {e}")
            else:
                logger.info("A válasz nem kép, kép keresése a HTML-ben...")
        
        # Ha a közvetlen kép nem érhető el, letöltjük a weboldalt és keresünk egy meta tag-et
        response = requests.get(URL, headers=headers, timeout=30)
        if response.status_code == 200:
            # Meta tag keresése, amely tartalmazza a közvetlen kép linkjét
            html = response.text
            image_url = None
            
            # Egyszerű elemzés az e-paper kép meta tag megtalálásához
            for line in html.split('\n'):
                if 'meta' in line and 'e-paper-image' in line:
                    parts = line.split('content="')
                    if len(parts) > 1:
                        image_url = parts[1].split('"')[0]
                        break
            
            if image_url:
                logger.info(f"Kép URL megtalálva a meta tag-ben: {image_url}")
                img_response = requests.get(image_url, headers=headers, timeout=30)
                if img_response.status_code == 200:
                    img = Image.open(BytesIO(img_response.content))
                    return img
            
            logger.error("Nem található megfelelő kép a weboldalon")
            return None
        
        logger.error(f"Nem sikerült letölteni a weboldalt: HTTP {response.status_code}")
        return None
    
    except Exception as e:
        logger.error(f"Hiba a kép letöltésekor: {e}")
        return None

def update_display():
    """Az e-paper kijelző frissítése a legújabb képpel."""
    global epd
    
    try:
        # Kijelző inicializálása
        logger.info("Kijelző inicializálása...")
        epd = epd4in01f.EPD()
        epd.init()
        
        # Kép letöltése a weboldalról
        img = fetch_image()
        if img is None:
            logger.error("Nem sikerült letölteni a képet")
            return
        
        # Kép mód és átméretezés kezelése ha szükséges
        if img.mode != 'RGB':
            img = img.convert('RGB')
        
        # Kép átméretezése, ha szükséges
        display_width = 640  # Waveshare 4.01" HAT szélesség
        display_height = 400  # Waveshare 4.01" HAT magasság
        
        if img.size != (display_width, display_height):
            logger.info(f"Kép átméretezése {img.size}-ről {(display_width, display_height)}-re")
            img = img.resize((display_width, display_height))
        
        # Kép megjelenítése
        logger.info("Kijelző frissítése...")
        epd.display(epd.getbuffer(img))
        
        # Kijelző alvó módba helyezése az energiatakarékosság érdekében
        epd.sleep()
        
        logger.info("Kijelző sikeresen frissítve")
    
    except Exception as e:
        logger.error(f"Hiba a kijelző frissítésekor: {e}")
        # Próbáljuk meg alvó módba tenni a kijelzőt, még ha hiba történt is
        try:
            if epd is not None:
                epd.sleep()
        except:
            pass

def main():
    """Fő függvény a kijelző periodikus frissítéséhez."""
    # Jelkezelő regisztrálása
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    logger.info("E-paper kijelző szolgáltatás indítása")
    
    while True:
        try:
            update_display()
        except Exception as e:
            logger.error(f"Váratlan hiba a fő ciklusban: {e}")
        
        logger.info("Várakozás 5 percig...")
        # Alvás kisebb részletekben, hogy reagálhasson a jelekre
        for _ in range(30):  # 30 * 10 másodperc = 5 perc
            time.sleep(10)

if __name__ == "__main__":
    main()
EOF

# Systemd szolgáltatás fájl létrehozása
echo "Systemd szolgáltatás létrehozása..."
cat > /etc/systemd/system/e-paper-display.service << EOF
[Unit]
Description=E-Paper Display Service
After=network.target

[Service]
ExecStart=/usr/bin/python3 $APP_DIR/display.py
WorkingDirectory=$APP_DIR
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

# SPI interfész engedélyezése
echo "SPI interfész engedélyezése..."
if ! grep -q "dtparam=spi=on" /boot/config.txt; then
  echo "dtparam=spi=on" >> /boot/config.txt
fi

# Jogosultságok beállítása
echo "Jogosultságok beállítása..."
chmod +x "$APP_DIR/display.py"

# Szolgáltatás engedélyezése és indítása
echo "Szolgáltatás engedélyezése és indítása..."
systemctl daemon-reload
systemctl enable e-paper-display.service
systemctl start e-paper-display.service

echo "===================================================="
echo "Telepítés kész!"
echo "Az e-paper kijelző most a https://naptarak.com/e-paper.html tartalmat mutatja"
echo "és 5 percenként frissül."
echo "Az állapot ellenőrzéséhez: sudo systemctl status e-paper-display.service"
echo "Naplók megtekintéséhez: cat $APP_DIR/display.log"
echo "===================================================="
