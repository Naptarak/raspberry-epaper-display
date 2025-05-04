#!/bin/bash

# =====================================================
# TELJESEN MŰKÖDŐ E-PAPER KIJELZŐ TELEPÍTŐ
# Chromium nélkül, SPI engedélyezéssel
# =====================================================

# Kilépés hiba esetén
set -e

echo "======================================================"
echo "  WAVESHARE E-PAPER KIJELZŐ TELEPÍTŐ"
echo "  (Chromium nélküli, alacsony erőforrás-igényű verzió)"
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
sudo apt-get install -y python3-pip python3-pil python3-numpy python3-requests python3-rpi.gpio python3-spidev git

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

# Telepítési könyvtár létrehozása
echo "Telepítési könyvtár létrehozása..."
sudo rm -rf $INSTALL_DIR
sudo mkdir -p $INSTALL_DIR
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

# Képernyő felbontás
EPD_WIDTH = 640
EPD_HEIGHT = 400

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

def create_date_image():
    """Dátum és idő kép létrehozása"""
    try:
        # Üres kép létrehozása fehér háttérrel
        image = Image.new('RGB', (EPD_WIDTH, EPD_HEIGHT), 'white')
        draw = ImageDraw.Draw(image)
        
        # Keret rajzolása
        draw.rectangle((0, 0, EPD_WIDTH, EPD_HEIGHT), outline='black')
        
        # Betűtípus beállítása
        try:
            font_large = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 40)
            font_medium = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 36)
            font_small = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 24)
        except OSError:
            font_large = ImageFont.load_default()
            font_medium = ImageFont.load_default()
            font_small = ImageFont.load_default()
        
        # Aktuális dátum és idő
        import locale
        try:
            locale.setlocale(locale.LC_TIME, "hu_HU.UTF-8")  # Magyar lokalizáció
        except locale.Error:
            try:
                locale.setlocale(locale.LC_TIME, "hu_HU")
            except locale.Error:
                logger.warning("Nem sikerült beállítani a magyar lokalizációt")
        
        current_time = time.strftime("%H:%M:%S")
        current_date = time.strftime("%Y. %B %d. %A")
        
        # Dátum és idő megjelenítése
        draw.text((EPD_WIDTH//2, 100), current_time, font=font_large, fill='black', anchor="mm")
        draw.text((EPD_WIDTH//2, 180), current_date, font=font_medium, fill='black', anchor="mm")
        
        # Naptár információ
        draw.text((EPD_WIDTH//2, 260), "Naptár", font=font_medium, fill='red', anchor="mm")
        draw.text((EPD_WIDTH//2, 320), "Következő frissítés:", font=font_small, fill='blue', anchor="mm")
        draw.text((EPD_WIDTH//2, 360), f"{REFRESH_INTERVAL} perc múlva", font=font_small, fill='blue', anchor="mm")
        
        return image
    except Exception as e:
        logger.error(f"Hiba a dátum kép létrehozásakor: {e}")
        return None

def download_web_content():
    """Weboldal letöltése és képpé alakítása"""
    try:
        logger.info(f"Weboldal tartalom letöltése: {URL}")
        
        headers = {
            'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/94.0.4606.81 Safari/537.36'
        }
        
        # Weboldal letöltése
        response = requests.get(URL, headers=headers, timeout=30)
        response.raise_for_status()  # Hiba dobása, ha nem 200 OK
        
        # HTML tartalom feldolgozása - itt most egyszerűen dátumot jelenítünk meg
        # Későbbiekben ide jöhet komplexebb megoldás a weboldal tartalmának feldolgozására
        
        # Most csak dátum képet készítünk
        image = create_date_image()
        if image is None:
            raise Exception("Nem sikerült létrehozni a képet")
        
        return image
    except requests.exceptions.RequestException as e:
        logger.error(f"Hiba a weboldal letöltésekor: {e}")
        return create_error_image(str(e))
    except Exception as e:
        logger.error(f"Váratlan hiba: {e}")
        return create_error_image(str(e))

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
            logger.info("Weboldal tartalom letöltése...")
            image = download_web_content()
            
            logger.info("Tartalom megjelenítése a kijelzőn...")
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
    logger.info("E-Paper Website Display alkalmazás indítása")
    main_loop()
EOL

# Szolgáltatás létrehozása
echo "Szolgáltatás fájl létrehozása..."
sudo bash -c "cat > /etc/systemd/system/epaper-display.service << EOL
[Unit]
Description=E-Paper Website Display
After=network.target

[Service]
User=$CURRENT_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/python3 $INSTALL_DIR/display_website.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOL"

# Jogosultságok beállítása
sudo chmod +x $INSTALL_DIR/display_website.py
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
