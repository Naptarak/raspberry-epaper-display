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

# HTML-PNG konverzióhoz szükséges csomagok
PACKAGES="$PACKAGES wkhtmltopdf xvfb"

# Chromium alapú rendereléshez (alternatíva)
PACKAGES="$PACKAGES chromium-browser"

if [ -n "$TIFF_PACKAGE" ]; then
  PACKAGES="$PACKAGES $TIFF_PACKAGE"
fi

apt-get install -y $PACKAGES

# Python csomagok telepítése apt-get használatával pip helyett
echo "Python csomagok telepítése apt segítségével..."
apt-get install -y python3-rpi.gpio python3-spidev python3-requests python3-pil python3-venv

# Selenium és egyéb csomagok telepítése a jobb HTML rendereléshez
apt-get install -y python3-selenium python3-bs4

# Alkalmazás könyvtár létrehozása
echo "Alkalmazás könyvtár létrehozása..."
APP_DIR="/opt/e-paper-display"
mkdir -p "$APP_DIR"

# Waveshare e-Paper könyvtár klónozása
echo "Waveshare e-Paper könyvtár letöltése..."
git clone https://github.com/waveshare/e-Paper.git /tmp/e-Paper
cp -r /tmp/e-Paper/RaspberryPi_JetsonNano/python/lib/waveshare_epd "$APP_DIR/"
rm -rf /tmp/e-Paper

# HTML-PNG konvertáló wrapper script létrehozása
echo "HTML-PNG konvertáló script létrehozása..."
cat > "$APP_DIR/html2png.sh" << 'EOF'
#!/bin/bash
# HTML-to-PNG konvertáló script xvfb segítségével
# Használat: ./html2png.sh <url> <output_file> <width> <height>

URL="$1"
OUTPUT="$2"
WIDTH="${3:-640}"
HEIGHT="${4:-400}"

# Futtatás virtuális framebufferrel és megnövelt JavaScript várakozási idővel
xvfb-run --server-args="-screen 0, ${WIDTH}x${HEIGHT}x24" wkhtmltoimage \
  --width $WIDTH \
  --height $HEIGHT \
  --quality 100 \
  --disable-smart-width \
  --enable-javascript \
  --javascript-delay 10000 \
  --no-stop-slow-scripts \
  --debug-javascript \
  --load-error-handling ignore \
  --custom-header "Cache-Control" "no-cache" \
  --custom-header-propagation \
  "$URL" "$OUTPUT"

# Ellenőrizzük, hogy sikeres volt-e a konverzió
if [ -f "$OUTPUT" ] && [ -s "$OUTPUT" ]; then
  echo "Sikeres konverzió: $OUTPUT"
  exit 0
else
  echo "Hiba a konverzió során!"
  exit 1
fi
EOF

chmod +x "$APP_DIR/html2png.sh"

# Python alapú HTML-PNG konverter a Selenium segítségével
echo "Selenium alapú HTML-PNG konverter létrehozása..."
cat > "$APP_DIR/selenium_capture.py" << 'EOF'
#!/usr/bin/env python3
# -*- coding:utf-8 -*-

import os
import sys
import time
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC

def capture_page(url, output_path, width=640, height=400, wait_time=30):
    """
    Weboldal képernyőképének készítése Selenium és Chromium segítségével.
    A script megvárja, amíg az oldal teljesen betöltődik, beleértve a JavaScript API hívásokat is.
    """
    print(f"Weboldal mentése képként: {url} -> {output_path}")
    
    # Chromium opciók beállítása
    chrome_options = Options()
    chrome_options.add_argument("--headless")
    chrome_options.add_argument("--no-sandbox")
    chrome_options.add_argument("--disable-dev-shm-usage")
    chrome_options.add_argument(f"--window-size={width},{height}")
    chrome_options.add_argument("--disable-gpu")
    
    try:
        # Böngésző indítása
        driver = webdriver.Chrome(options=chrome_options)
        driver.set_window_size(width, height)
        
        # Oldal betöltése
        print("Oldal betöltése...")
        driver.get(url)
        
        # Várakozás, hogy az oldal teljesen betöltődjön
        # Először egy alapvető várakozás, hogy az oldal betöltsön
        time.sleep(5)
        
        # Majd várunk, amíg a "Betöltés..." felirat eltűnik, vagy lejár az idő
        try:
            # Speciális várakozás, hogy az időjárási adatok betöltődjenek
            print("Várakozás az időjárási adatok betöltődésére...")
            for _ in range(wait_time):
                page_content = driver.page_source.lower()
                # Ellenőrizzük, van-e még "betöltés..." szöveg az oldalon
                if "betöltés..." not in page_content and "--°c" not in page_content:
                    print("Az adatok sikeresen betöltődtek!")
                    break
                time.sleep(1)
        except Exception as e:
            print(f"Várakozás hiba (folytatás): {e}")
        
        # Még egy kis plusz idő, hogy a megjelenítés befejeződjön
        time.sleep(2)
        
        # Képernyőkép készítése
        print("Képernyőkép készítése...")
        driver.save_screenshot(output_path)
        
        # Böngésző bezárása
        driver.quit()
        
        # Ellenőrizzük, hogy a képernyőkép sikeres volt-e
        if os.path.exists(output_path) and os.path.getsize(output_path) > 0:
            print(f"Képernyőkép sikeresen elmentve: {output_path}")
            return True
        else:
            print("Hiba: üres képernyőkép fájl")
            return False
            
    except Exception as e:
        print(f"Hiba a képernyőkép készítése során: {e}")
        return False

if __name__ == "__main__":
    # Parancssori argumentumok ellenőrzése
    if len(sys.argv) < 3:
        print("Használat: python selenium_capture.py <url> <output_path> [width] [height] [wait_time]")
        sys.exit(1)
    
    url = sys.argv[1]
    output_path = sys.argv[2]
    width = int(sys.argv[3]) if len(sys.argv) > 3 else 640
    height = int(sys.argv[4]) if len(sys.argv) > 4 else 400
    wait_time = int(sys.argv[5]) if len(sys.argv) > 5 else 30
    
    success = capture_page(url, output_path, width, height, wait_time)
    sys.exit(0 if success else 1)
EOF

chmod +x "$APP_DIR/selenium_capture.py"

# Fő Python script létrehozása
echo "Kijelző script létrehozása..."
cat > "$APP_DIR/display.py" << 'EOF'
#!/usr/bin/env python3
# -*- coding:utf-8 -*-

import os
import time
import logging
import requests
import subprocess
from PIL import Image
from io import BytesIO
import sys
import signal
import tempfile

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

# Kijelző méretei
DISPLAY_WIDTH = 640  # Waveshare 4.01" HAT szélesség
DISPLAY_HEIGHT = 400  # Waveshare 4.01" HAT magasság

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

def capture_with_selenium(url, output_path):
    """Selenium használata a HTML tartalom renderelésére és PNG képpé konvertálására"""
    logger.info(f"Weboldal renderelése Selenium segítségével: {url}")
    
    selenium_script = os.path.join(os.path.dirname(os.path.realpath(__file__)), "selenium_capture.py")
    
    try:
        # Selenium script futtatása a képernyőkép készítéséhez
        result = subprocess.run(
            ["python3", selenium_script, url, output_path, str(DISPLAY_WIDTH), str(DISPLAY_HEIGHT), "45"],
            capture_output=True,
            text=True,
            check=True
        )
        
        if os.path.exists(output_path) and os.path.getsize(output_path) > 0:
            logger.info(f"Selenium képernyőkép sikeresen létrehozva: {output_path}")
            return True
        else:
            logger.error("Selenium képernyőkép sikertelen, üres fájl")
            return False
    
    except subprocess.CalledProcessError as e:
        logger.error(f"Hiba a Selenium képernyőkép készítése során: {e}")
        logger.error(f"STDOUT: {e.stdout}")
        logger.error(f"STDERR: {e.stderr}")
        return False
    
    except Exception as e:
        logger.error(f"Váratlan hiba a Selenium képernyőkép készítése során: {e}")
        return False

def convert_html_to_png(url, output_path):
    """HTML tartalom konvertálása PNG képpé"""
    logger.info(f"HTML konvertálása PNG-vé: {url}")
    
    html2png_script = os.path.join(os.path.dirname(os.path.realpath(__file__)), "html2png.sh")
    
    try:
        # HTML letöltése és konvertálása PNG-vé
        result = subprocess.run(
            [html2png_script, url, output_path, str(DISPLAY_WIDTH), str(DISPLAY_HEIGHT)],
            capture_output=True,
            text=True,
            check=True
        )
        
        if os.path.exists(output_path) and os.path.getsize(output_path) > 0:
            logger.info(f"HTML sikeresen konvertálva PNG-vé: {output_path}")
            return True
        else:
            logger.error("HTML-PNG konverzió sikertelen, üres fájl")
            return False
    
    except subprocess.CalledProcessError as e:
        logger.error(f"Hiba a HTML-PNG konverzió során: {e}")
        logger.error(f"STDOUT: {e.stdout}")
        logger.error(f"STDERR: {e.stderr}")
        return False
    
    except Exception as e:
        logger.error(f"Váratlan hiba a HTML-PNG konverzió során: {e}")
        return False

def fetch_image():
    """
    Weboldal tartalmának megszerzése különböző módszerekkel.
    Először a Selenium-ot próbáljuk, majd wkhtmltoimage-et.
    """
    logger.info("Tartalom letöltése a weboldalról különböző módszerekkel...")
    
    # Ideiglenes fájlok létrehozása
    selenium_output = os.path.join(os.path.dirname(os.path.realpath(__file__)), "temp_selenium.png")
    wkhtml_output = os.path.join(os.path.dirname(os.path.realpath(__file__)), "temp_wkhtml.png")
    
    # 1. Először próbáljuk meg a Selenium-ot (jobb JavaScript támogatás)
    logger.info("Próbálkozás Selenium-mal...")
    if capture_with_selenium(URL, selenium_output):
        try:
            img = Image.open(selenium_output)
            return img
        except Exception as e:
            logger.error(f"Hiba a Selenium kép megnyitásakor: {e}")
    
    # 2. Ha a Selenium nem működött, próbáljuk a wkhtmltoimage-et
    logger.info("Próbálkozás wkhtmltoimage-gel...")
    if convert_html_to_png(URL, wkhtml_output):
        try:
            img = Image.open(wkhtml_output)
            return img
        except Exception as e:
            logger.error(f"Hiba a wkhtmltoimage kép megnyitásakor: {e}")
    
    # Ha egyik sem működött, ellenőrizzük a közvetlen kép lehetőségeket
    logger.info("Próbálkozás közvetlen kép letöltéssel...")
    try:
        headers = {
            'User-Agent': 'RaspberryPiZero/1.0 EPaperDisplay/1.0',
        }
        
        # Próbáljuk meg közvetlen paraméterrel
        response = requests.get(URL + "?direct=1", headers=headers, timeout=30)
        
        if response.status_code == 200:
            content_type = response.headers.get('Content-Type', '')
            if 'image' in content_type:
                try:
                    img = Image.open(BytesIO(response.content))
                    logger.info("Kép közvetlenül letöltve az URL-ről")
                    return img
                except Exception as e:
                    logger.error(f"Nem sikerült megnyitni a képet: {e}")
        
        # Meta tag keresése
        response = requests.get(URL, headers=headers, timeout=30)
        if response.status_code == 200:
            html = response.text
            image_url = None
            
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
    
    except Exception as e:
        logger.error(f"Hiba a közvetlen kép letöltése során: {e}")
    
    logger.error("Nem sikerült tartalmat szerezni egyik módszerrel sem")
    return None

def update_display():
    """Az e-paper kijelző frissítése a legújabb képpel."""
    global epd
    
    try:
        # Kijelző inicializálása
        logger.info("Kijelző inicializálása...")
        epd = epd4in01f.EPD()
        epd.init()
        
        # Kép letöltése vagy HTML konvertálása
        img = fetch_image()
        if img is None:
            logger.error("Nem sikerült tartalmat szerezni a kijelzőhöz")
            return
        
        # Kép mód és átméretezés kezelése ha szükséges
        if img.mode != 'RGB':
            img = img.convert('RGB')
        
        # Kép átméretezése, ha szükséges
        if img.size != (DISPLAY_WIDTH, DISPLAY_HEIGHT):
            logger.info(f"Kép átméretezése {img.size}-ről {(DISPLAY_WIDTH, DISPLAY_HEIGHT)}-re")
            img = img.resize((DISPLAY_WIDTH, DISPLAY_HEIGHT))
        
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
