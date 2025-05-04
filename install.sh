#!/bin/bash

# E-Paper Website Display Telepítő (Javított)
# Készítette: Claude

echo "=================================================="
echo "  E-Paper Website Display Telepítő (Javított)"
echo "=================================================="
echo ""

# Telepítési könyvtár létrehozása
INSTALL_DIR="/home/pi/e-paper-display"
mkdir -p $INSTALL_DIR

# Frissítési időköz beállítása
DEFAULT_REFRESH=5
echo -n "Milyen gyakran frissüljön a kijelző? (percekben, alapértelmezett: 5): "
read refresh_interval
if [ -z "$refresh_interval" ]; then
    refresh_interval=$DEFAULT_REFRESH
fi

# Ellenőrizzük, hogy érvényes szám-e
if ! [[ "$refresh_interval" =~ ^[0-9]+$ ]]; then
    echo "Érvénytelen érték. Az alapértelmezett 5 perc lesz használva."
    refresh_interval=$DEFAULT_REFRESH
fi

echo "A kijelző $refresh_interval percenként fog frissülni."
echo ""

# Szükséges csomagok telepítése apt segítségével
echo "Szükséges csomagok telepítése..."
sudo apt-get update
sudo apt-get install -y python3-pip python3-pil python3-numpy chromium-browser unclutter x11-xserver-utils xdotool python3-venv

# Virtuális környezet létrehozása
echo "Python virtuális környezet létrehozása..."
python3 -m venv $INSTALL_DIR/venv
source $INSTALL_DIR/venv/bin/activate

# Python csomagok telepítése a virtuális környezetbe
echo "Python csomagok telepítése..."
$INSTALL_DIR/venv/bin/pip install selenium webdriver-manager RPi.GPIO spidev

# Waveshare e-Paper könyvtár telepítése
echo "Waveshare e-Paper könyvtár telepítése..."
cd /tmp
git clone https://github.com/waveshare/e-Paper.git
cp -r e-Paper/RaspberryPi_JetsonNano/python/lib/waveshare_epd $INSTALL_DIR/
cp -r e-Paper/RaspberryPi_JetsonNano/python/pic $INSTALL_DIR/

# Alkalmazás fájlok másolása
echo "Alkalmazás fájlok másolása..."
cat > $INSTALL_DIR/config.ini << EOL
[Settings]
url = https://naptarak.com/e-paper.html
refresh_interval = $refresh_interval
EOL

cat > $INSTALL_DIR/display_website.py << 'EOL'
#!/usr/bin/env python3
# -*- coding:utf-8 -*-

import os
import sys
import time
import configparser
import logging
from PIL import Image, ImageOps
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC

# Logging beállítása
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler("/home/pi/e-paper-display/app.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger("e-paper-display")

# Konfiguráció betöltése
config = configparser.ConfigParser()
config.read('/home/pi/e-paper-display/config.ini')

URL = config.get('Settings', 'url')
REFRESH_INTERVAL = int(config.get('Settings', 'refresh_interval'))

# Képernyő felbontás
EPD_WIDTH = 640
EPD_HEIGHT = 400

# Waveshare könyvtár betöltése
try:
    from waveshare_epd import epd4in01f
    epd_available = True
    logger.info("Waveshare e-Paper könyvtár sikeresen betöltve")
except ImportError:
    epd_available = False
    logger.warning("Waveshare e-Paper könyvtár nem elérhető - szimuláció módban fut")

def setup_driver():
    """Selenium webdriver beállítása"""
    chrome_options = Options()
    chrome_options.add_argument("--headless")
    chrome_options.add_argument("--no-sandbox")
    chrome_options.add_argument("--disable-dev-shm-usage")
    chrome_options.add_argument(f"--window-size={EPD_WIDTH},{EPD_HEIGHT}")
    
    service = Service('/usr/bin/chromedriver')
    driver = webdriver.Chrome(service=service, options=chrome_options)
    return driver

def capture_website(driver, url, output_path="/tmp/screenshot.png"):
    """Weboldal képernyőképének készítése"""
    try:
        logger.info(f"Weboldal betöltése: {url}")
        driver.get(url)
        
        # Várjunk, amíg az oldal betöltődik (max 30 másodperc)
        WebDriverWait(driver, 30).until(
            EC.presence_of_element_located((By.TAG_NAME, "body"))
        )
        
        # Adunk még egy kis időt a JS futtatásához
        time.sleep(2)
        
        # Képernyőkép készítése
        driver.save_screenshot(output_path)
        logger.info(f"Képernyőkép elmentve: {output_path}")
        return True
    except Exception as e:
        logger.error(f"Hiba a weboldal betöltésekor: {str(e)}")
        return False

def process_image(input_path, output_path=None):
    """Kép feldolgozása az e-Paper kijelzőhöz"""
    if output_path is None:
        output_path = input_path
    
    try:
        # Kép betöltése
        img = Image.open(input_path)
        
        # Kép átméretezése az e-Paper felbontásához
        img = img.resize((EPD_WIDTH, EPD_HEIGHT), Image.LANCZOS)
        
        # Kép mentése
        img.save(output_path)
        logger.info(f"Feldolgozott kép elmentve: {output_path}")
        return True
    except Exception as e:
        logger.error(f"Hiba a kép feldolgozásakor: {str(e)}")
        return False

def display_image(image_path):
    """Kép megjelenítése az e-Paper kijelzőn"""
    if not epd_available:
        logger.info("Szimuláció mód: a kép megjelenítése át lett ugorva")
        return True
    
    try:
        # e-Paper inicializálása
        epd = epd4in01f.EPD()
        epd.init()
        
        # Kép betöltése és konvertálása
        img = Image.open(image_path)
        epd.display(epd.getbuffer(img))
        
        logger.info("Kép sikeresen megjelenítve az e-Paper kijelzőn")
        return True
    except Exception as e:
        logger.error(f"Hiba a kép megjelenítésekor: {str(e)}")
        return False

def main_loop():
    """Fő program ciklus"""
    driver = setup_driver()
    
    while True:
        try:
            screenshot_path = "/tmp/screenshot.png"
            processed_path = "/tmp/processed.png"
            
            # Weboldal betöltése és képernyőkép készítése
            if capture_website(driver, URL, screenshot_path):
                # Kép feldolgozása
                if process_image(screenshot_path, processed_path):
                    # Kép megjelenítése
                    display_image(processed_path)
            
            # Várjunk a következő frissítésig
            logger.info(f"Várakozás {REFRESH_INTERVAL} percet a következő frissítésig...")
            time.sleep(REFRESH_INTERVAL * 60)
        except KeyboardInterrupt:
            logger.info("Program leállítva")
            break
        except Exception as e:
            logger.error(f"Váratlan hiba: {str(e)}")
            time.sleep(60)  # Hiba esetén várunk 1 percet, majd újrapróbáljuk

if __name__ == "__main__":
    logger.info("E-Paper Website Display alkalmazás indítása")
    main_loop()
EOL

# Automatikus indítás beállítása
echo "Automatikus indítás beállítása..."

# Létrehozzuk az asztalra a weboldal megjelenítő szkriptet
cat > $INSTALL_DIR/start_browser.sh << EOL
#!/bin/bash
chromium-browser --kiosk --incognito https://naptarak.com/e-paper.html &
# Kilépési kombináció beállítása (Alt+F4)
while true; do
    if xdotool search --sync --onlyvisible --name "Chromium"; then
        break
    fi
    sleep 1
done
xdotool key alt+F11
EOL

# HDMI kijelzőn futó alkalmazás beállítása
mkdir -p /home/pi/.config/autostart
cat > /home/pi/.config/autostart/browser.desktop << EOL
[Desktop Entry]
Type=Application
Name=Fullscreen Browser
Exec=/home/pi/e-paper-display/start_browser.sh
X-GNOME-Autostart-enabled=true
EOL

# E-Paper service beállítása
cat > /tmp/epaper-display.service << EOL
[Unit]
Description=E-Paper Website Display
After=network.target

[Service]
User=pi
WorkingDirectory=/home/pi/e-paper-display
ExecStart=/home/pi/e-paper-display/venv/bin/python /home/pi/e-paper-display/display_website.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOL

sudo mv /tmp/epaper-display.service /etc/systemd/system/
sudo chmod 644 /etc/systemd/system/epaper-display.service
sudo systemctl daemon-reload
sudo systemctl enable epaper-display.service

# Végrehajtási jogosultságok beállítása
chmod +x $INSTALL_DIR/display_website.py
chmod +x $INSTALL_DIR/start_browser.sh

echo ""
echo "==================================================="
echo "  Telepítés befejezve!"
echo "==================================================="
echo ""
echo "Hogyan használd:"
echo ""
echo "1. HDMI kijelzőn:"
echo "   - A rendszer automatikusan elindítja a böngészőt teljes képernyőn"
echo "   - Az Alt+F4 billentyűkombinációval kiléphetsz a böngészőből"
echo ""
echo "2. E-Paper kijelzővel:"
echo "   - Kapcsold ki a Raspberry Pi-t"
echo "   - Csatlakoztasd a Waveshare 4.01 inch e-Paper HAT (F) kijelzőt"
echo "   - Kapcsold be a Raspberry Pi-t"
echo "   - A rendszer automatikusan elindítja az e-Paper alkalmazást"
echo ""
echo "A frissítési időköz módosításához szerkeszd a következő fájlt:"
echo "/home/pi/e-paper-display/config.ini"
echo ""
echo "A Raspberry Pi újraindításához használd a következő parancsot:"
echo "sudo reboot"
echo ""
echo "Most kapcsold ki a Raspberry Pi-t és csatlakoztasd az e-Paper kijelzőt:"
echo "sudo shutdown -h now"
echo ""
echo "Nyomj Enter-t a folytatáshoz..."
read
sudo shutdown -h now
