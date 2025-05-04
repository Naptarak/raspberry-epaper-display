#!/bin/bash

# =====================================================
# WAVESHARE E-PAPER HTML RENDERER TELEPÍTŐ - JAVÍTOTT
# HTML tartalom renderelésével - Raspberry Pi OS kompatibilitással
# =====================================================

# Kilépés hiba esetén
set -e

echo "======================================================"
echo "  WAVESHARE E-PAPER HTML RENDERER TELEPÍTŐ"
echo "  (HTML tartalom megjelenítésével - JAVÍTOTT)"
echo "======================================================"

# Aktuális felhasználó és könyvtárak beállítása
CURRENT_USER=$(whoami)
CURRENT_GROUP=$(id -gn)
HOME_DIR=$(eval echo ~$CURRENT_USER)
INSTALL_DIR="$HOME_DIR/e-paper-display"

echo "Telepítés a következő felhasználónak: $CURRENT_USER"
echo "Telepítési könyvtár: $INSTALL_DIR"

# Csomagkezelő javítása
echo "Csomagkezelő javítása..."
sudo dpkg --configure -a
sudo apt-get update

# SPI interfész engedélyezése
echo "SPI interfész ellenőrzése és engedélyezése..."
if ! grep -q "^dtparam=spi=on" /boot/config.txt; then
    echo "SPI interfész nincs engedélyezve. Engedélyezés..."
    sudo bash -c "echo 'dtparam=spi=on' >> /boot/config.txt"
    REBOOT_NEEDED=true
else
    echo "Az SPI interfész már engedélyezve van."
fi

# Szükséges csomagok telepítése
echo "Szükséges csomagok telepítése..."
sudo apt-get install -y python3-pip python3-pil python3-numpy python3-requests python3-rpi.gpio python3-spidev git python3-selenium python3-bs4 firefox-esr wget unzip xvfb python3-venv

# Virtuális környezet létrehozása
echo "Python virtuális környezet létrehozása..."
mkdir -p $INSTALL_DIR
python3 -m venv $INSTALL_DIR/venv
source $INSTALL_DIR/venv/bin/activate

# Selenium telepítése a virtuális környezetbe
echo "Selenium webdriver telepítése a virtuális környezetbe..."
pip install selenium webdriver-manager pyvirtualdisplay

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

# Telepítési könyvtár jogosultságainak beállítása
echo "Telepítési könyvtár jogosultságainak beállítása..."
sudo chown -R $CURRENT_USER:$CURRENT_GROUP $INSTALL_DIR

# Waveshare e-Paper könyvtár telepítése
echo "Waveshare e-Paper könyvtár telepítése..."
cd /tmp
sudo rm -rf e-Paper
git clone https://github.com/waveshare/e-Paper.git
cp -r e-Paper/RaspberryPi_JetsonNano/python/lib/waveshare_epd $INSTALL_DIR/
cp -r e-Paper/RaspberryPi_JetsonNano/python/pic $INSTALL_DIR/

# Konfigurációs fájl létrehozása
echo "Konfigurációs fájl létrehozása..."
cat > $INSTALL_DIR/config.ini << EOL
[Settings]
url = https://naptarak.com/e-paper.html
refresh_interval = $refresh_interval
width = 640
height = 400
viewport_width = 800
viewport_height = 600
EOL

# Python szkript létrehozása
echo "Python szkript létrehozása..."
cat > $INSTALL_DIR/display_website.py << 'EOL'
#!/usr/bin/env python3
# -*- coding:utf-8 -*-

import os
import sys
import time
import logging
import configparser
import requests
from PIL import Image, ImageDraw, ImageFont
from io import BytesIO
import tempfile

# Aktuális könyvtár beállítása
INSTALL_DIR = os.path.dirname(os.path.abspath(__file__))

# Logging beállítása
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(os.path.join(INSTALL_DIR, "app.log")),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger("e-paper-display")

# Konfiguráció betöltése
config = configparser.ConfigParser()
config.read(os.path.join(INSTALL_DIR, "config.ini"))

URL = config.get('Settings', 'url')
REFRESH_INTERVAL = int(config.get('Settings', 'refresh_interval'))
EPD_WIDTH = int(config.get('Settings', 'width', fallback=640))
EPD_HEIGHT = int(config.get('Settings', 'height', fallback=400))
VIEWPORT_WIDTH = int(config.get('Settings', 'viewport_width', fallback=800))
VIEWPORT_HEIGHT = int(config.get('Settings', 'viewport_height', fallback=600))

# Waveshare könyvtár betöltése
try:
    sys.path.append(INSTALL_DIR)
    from waveshare_epd import epd4in01f
    epd_available = True
    logger.info("Waveshare e-Paper könyvtár sikeresen betöltve")
except ImportError as e:
    epd_available = False
    logger.error(f"Waveshare e-Paper könyvtár betöltési hiba: {e}")
    logger.error("Ellenőrizd, hogy a könyvtár a megfelelő helyen van-e: " + INSTALL_DIR)
    sys.exit(1)

def create_error_image(error_message):
    """Hibaüzenet képként"""
    try:
        # Üres kép létrehozása fehér háttérrel
        image = Image.new('RGB', (EPD_WIDTH, EPD_HEIGHT), 'white')
        draw = ImageDraw.Draw(image)
        
        # Keret rajzolása
        draw.rectangle((0, 0, EPD_WIDTH, EPD_HEIGHT), outline='red')
        
        # Betűtípus beállítása
        try:
            font_title = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 30)
            font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 20)
        except OSError:
            font_title = ImageFont.load_default()
            font = ImageFont.load_default()
        
        # Hibaüzenet több sorba tördelése
        import textwrap
        wrapped_text = textwrap.wrap(error_message, width=40)
        
        # Hibaüzenet megjelenítése
        draw.text((EPD_WIDTH//2, 60), "HIBA!", font=font_title, fill='red', anchor="mm")
        
        y_position = 120
        for line in wrapped_text[:5]:  # Maximum 5 sor
            draw.text((EPD_WIDTH//2, y_position), line, font=font, fill='black', anchor="mm")
            y_position += 30
        
        # Aktuális idő megjelenítése
        current_time = time.strftime("%Y-%m-%d %H:%M:%S")
        draw.text((EPD_WIDTH//2, 300), f"Időpont: {current_time}", font=font, fill='blue', anchor="mm")
        draw.text((EPD_WIDTH//2, 340), f"Újrapróbálkozás {REFRESH_INTERVAL} perc múlva", font=font, fill='blue', anchor="mm")
        
        return image
    except Exception as e:
        logger.error(f"Hiba a hibaüzenet kép létrehozásakor: {e}")
        # Végső mentsvár - egy teljesen minimális kép
        try:
            img = Image.new('RGB', (EPD_WIDTH, EPD_HEIGHT), 'white')
            return img
        except:
            return None

def capture_website_screenshot():
    """Weboldal képernyőkép készítése Selenium használatával"""
    try:
        logger.info(f"Weboldal képernyőkép készítése: {URL}")
        
        # Selenium importálása
        from selenium import webdriver
        from selenium.webdriver.firefox.options import Options
        from selenium.webdriver.firefox.service import Service
        from webdriver_manager.firefox import GeckoDriverManager
        from pyvirtualdisplay import Display
        
        # Virtuális kijelző létrehozása
        display = Display(visible=0, size=(VIEWPORT_WIDTH, VIEWPORT_HEIGHT))
        display.start()
        
        # Firefox driver beállítások
        options = Options()
        options.add_argument("--headless")
        options.add_argument("--no-sandbox")
        options.add_argument("--disable-dev-shm-usage")
        options.add_argument(f"--window-size={VIEWPORT_WIDTH},{VIEWPORT_HEIGHT}")
        
        # Firefox driver inicializálása
        try:
            service = Service(GeckoDriverManager().install())
            driver = webdriver.Firefox(service=service, options=options)
        except Exception as e:
            logger.error(f"Hiba a Firefox driver inicializálásakor: {e}")
            logger.info("Alternatív inicializálási mód használata...")
            driver = webdriver.Firefox(options=options)
        
        # Weboldal betöltése
        driver.get(URL)
        
        # Várakozás a betöltésre (1 másodperc)
        time.sleep(1)
        
        # Képernyőkép készítése
        screenshot_file = os.path.join(tempfile.gettempdir(), "website_screenshot.png")
        driver.save_screenshot(screenshot_file)
        
        # Képernyőkép betöltése és méretezése
        image = Image.open(screenshot_file)
        image = image.resize((EPD_WIDTH, EPD_HEIGHT), Image.LANCZOS)
        
        # Ideiglenes fájl törlése
        os.remove(screenshot_file)
        
        # Erőforrások felszabadítása
        driver.quit()
        display.stop()
        
        return image
    except Exception as e:
        logger.error(f"Hiba a weboldal képernyőkép készítésekor: {e}")
        return create_error_image(str(e))

def display_image(image):
    """Kép megjelenítése az e-Paper kijelzőn"""
    if not epd_available:
        logger.error("Waveshare e-Paper könyvtár nem érhető el")
        return False
    
    try:
        logger.info("E-Paper kijelző inicializálása...")
        epd = epd4in01f.EPD()
        epd.init()
        
        logger.info("Kép megjelenítése...")
        if image is not None:
            # Kép átméretezése, ha szükséges
            if image.width != EPD_WIDTH or image.height != EPD_HEIGHT:
                image = image.resize((EPD_WIDTH, EPD_HEIGHT))
            
            # Kép megjelenítése
            epd.display(epd.getbuffer(image))
            logger.info("Kép sikeresen megjelenítve")
            return True
        else:
            logger.error("Nincs megjeleníthető kép")
            return False
            
    except Exception as e:
        logger.error(f"Hiba a kép megjelenítésekor: {e}")
        return False

def perform_display_test():
    """Kezdeti teszt végrehajtása"""
    logger.info("E-Paper kijelző teszt végrehajtása...")
    
    try:
        # Teszt kép létrehozása
        test_image = Image.new('RGB', (EPD_WIDTH, EPD_HEIGHT), 'white')
        draw = ImageDraw.Draw(test_image)
        
        # Színes tesztkeret
        draw.rectangle((0, 0, EPD_WIDTH, EPD_HEIGHT), outline='black')
        draw.rectangle((10, 10, EPD_WIDTH-10, EPD_HEIGHT-10), outline='red')
        draw.rectangle((20, 20, EPD_WIDTH-20, EPD_HEIGHT-20), outline='blue')
        draw.rectangle((30, 30, EPD_WIDTH-30, EPD_HEIGHT-30), outline='green')
        
        # Betűtípus beállítása
        try:
            font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 36)
        except OSError:
            font = ImageFont.load_default()
        
        # Szöveg hozzáadása
        draw.text((EPD_WIDTH//2, 100), "E-Paper Kijelző Teszt", font=font, fill='black', anchor="mm")
        draw.text((EPD_WIDTH//2, 160), "Ha ezt látod,", font=font, fill='red', anchor="mm")
        draw.text((EPD_WIDTH//2, 220), "a kijelző működik!", font=font, fill='blue', anchor="mm")
        
        # Idő hozzáadása
        current_time = time.strftime("%Y-%m-%d %H:%M:%S")
        draw.text((EPD_WIDTH//2, 280), f"Idő: {current_time}", font=font, fill='green', anchor="mm")
        
        # Információ a következő frissítésről
        draw.text((EPD_WIDTH//2, 340), f"Indulás {5} másodperc múlva...", font=font, fill='black', anchor="mm")
        
        # Kép megjelenítése
        success = display_image(test_image)
        
        if success:
            logger.info("Teszt sikeresen végrehajtva")
        else:
            logger.error("Teszt sikertelen")
            
        # Várunk 5 másodpercet a normál működés előtt
        time.sleep(5)
        
    except Exception as e:
        logger.error(f"Hiba a teszt során: {e}")

def main_loop():
    """Fő program ciklus"""
    # Teszt végrehajtása az induláskor
    perform_display_test()
    
    while True:
        try:
            logger.info("Weboldal képernyőkép készítése...")
            image = capture_website_screenshot()
            
            logger.info("Képernyőkép megjelenítése a kijelzőn...")
            display_image(image)
            
            # Várjunk a következő frissítésig
            logger.info(f"Várakozás {REFRESH_INTERVAL} percet a következő frissítésig...")
            time.sleep(REFRESH_INTERVAL * 60)
            
        except KeyboardInterrupt:
            logger.info("Program leállítva (KeyboardInterrupt)")
            break
        except Exception as e:
            logger.error(f"Váratlan hiba a fő ciklusban: {e}")
            logger.info("Várakozás 1 percet az újrapróbálkozás előtt...")
            time.sleep(60)  # Hiba esetén várunk 1 percet, majd újrapróbáljuk

if __name__ == "__main__":
    logger.info("E-Paper HTML Renderer alkalmazás indítása")
    main_loop()
EOL

# Indítószript létrehozása
echo "Indítószript létrehozása..."
cat > $INSTALL_DIR/start.sh << EOL
#!/bin/bash
# Virtuális környezet aktiválása és a program indítása
cd $INSTALL_DIR
source venv/bin/activate
python display_website.py
EOL

# Jogosultságok beállítása
chmod +x $INSTALL_DIR/start.sh
chmod +x $INSTALL_DIR/display_website.py

# Szolgáltatás létrehozása
echo "Szolgáltatás fájl létrehozása..."
sudo bash -c "cat > /etc/systemd/system/epaper-display.service << EOL
[Unit]
Description=E-Paper HTML Renderer
After=network.target

[Service]
User=$CURRENT_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/start.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOL"

# Jogosultságok beállítása
sudo chmod 644 /etc/systemd/system/epaper-display.service

# Szolgáltatás beállítása
echo "Szolgáltatás beállítása..."
sudo systemctl daemon-reload
sudo systemctl stop epaper-display.service 2>/dev/null || true
sudo systemctl disable epaper-display.service 2>/dev/null || true
sudo systemctl enable epaper-display.service
sudo systemctl start epaper-display.service

# Telepítés befejezve
echo ""
echo "======================================================"
echo "  TELEPÍTÉS SIKERESEN BEFEJEZVE!"
echo "======================================================"
echo ""
echo "Szolgáltatás státusza:"
sudo systemctl status epaper-display.service --no-pager
echo ""

# Újraindítás, ha szükséges
if [ "$REBOOT_NEEDED" = "true" ]; then
    echo "FONTOS: Az SPI interfész engedélyezéséhez újra kell indítani"
    echo "a Raspberry Pi-t. Szeretnéd most újraindítani? (i/n)"
    read restart_now
    
    if [ "$restart_now" = "i" ]; then
        echo "Újraindítás 5 másodperc múlva..."
        sleep 5
        sudo reboot
    else
        echo "Ne felejtsd el később újraindítani a rendszert:"
        echo "sudo reboot"
    fi
fi

echo ""
echo "A napló megtekintéséhez:"
echo "cat $INSTALL_DIR/app.log"
echo ""
echo "A szolgáltatás állapotának ellenőrzéséhez:"
echo "sudo systemctl status epaper-display.service"
echo ""
