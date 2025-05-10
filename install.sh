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

# Szükséges rendszer csomagok telepítése
echo "Szükséges rendszer csomagok telepítése..."
apt-get install -y python3-pip python3-pil python3-numpy libopenjp2-7 libatlas-base-dev git wget imagemagick wkhtmltopdf xvfb curl jq

# Python csomagok telepítése apt-get használatával pip helyett
echo "Python csomagok telepítése apt segítségével..."
apt-get install -y python3-rpi.gpio python3-spidev python3-requests python3-pil

# Alkalmazás könyvtár létrehozása
echo "Alkalmazás könyvtár létrehozása..."
APP_DIR="/opt/e-paper-display"
mkdir -p "$APP_DIR"

# Waveshare e-Paper könyvtár klónozása
echo "Waveshare e-Paper könyvtár letöltése..."
git clone https://github.com/waveshare/e-Paper.git /tmp/e-Paper
cp -r /tmp/e-Paper/RaspberryPi_JetsonNano/python/lib/waveshare_epd "$APP_DIR/"
rm -rf /tmp/e-Paper

# Speciális HTML-PNG konvertáló script
echo "HTML-PNG konvertáló script létrehozása..."
cat > "$APP_DIR/capture_weather.sh" << 'EOF'
#!/bin/bash
# Speciális script a naptarak.com időjárás oldalának megjelenítésére

URL="https://naptarak.com/e-paper.html?forcedisplay=1&delay=15000"
OUTPUT_PATH="$1"
WIDTH=640
HEIGHT=400
MAX_ATTEMPTS=3

echo "Időjárás oldal képernyőképének készítése: $URL -> $OUTPUT_PATH"

# Több kísérlet a kép elkészítésére
for (( attempt=1; attempt<=$MAX_ATTEMPTS; attempt++ ))
do
    echo "Kísérlet $attempt/$MAX_ATTEMPTS, várakozási idő: $((attempt * 15)) másodperc"
    
    # Nagyobb várakozási idő minden próbálkozással
    xvfb-run --server-args="-screen 0, ${WIDTH}x${HEIGHT}x24" wkhtmltoimage \
      --width $WIDTH \
      --height $HEIGHT \
      --quality 100 \
      --disable-smart-width \
      --enable-javascript \
      --javascript-delay $((attempt * 15000)) \
      --no-stop-slow-scripts \
      --debug-javascript \
      --load-error-handling ignore \
      --custom-header "Cache-Control" "no-cache" \
      --custom-header "User-Agent" "E-Paper-Display/1.0 (Raspberry Pi Zero)" \
      --custom-header-propagation \
      "$URL" "$OUTPUT_PATH"
    
    # Ellenőrizzük, hogy a kép létrejött-e és nem üres
    if [ -f "$OUTPUT_PATH" ] && [ $(stat -c%s "$OUTPUT_PATH") -gt 10000 ]; then
        echo "Képernyőkép sikeresen elkészült a(z) $attempt. kísérletre!"
        exit 0
    fi
    
    echo "A(z) $attempt. kísérlet nem sikerült, újrapróbálkozás..."
    sleep 2
done

echo "Nem sikerült képernyőképet készíteni $MAX_ATTEMPTS kísérlet után sem."
exit 1
EOF

chmod +x "$APP_DIR/capture_weather.sh"

# Fő Python script létrehozása
echo "Kijelző script létrehozása..."
cat > "$APP_DIR/display.py" << 'EOF'
#!/usr/bin/env python3
# -*- coding:utf-8 -*-

import os
import time
import logging
import subprocess
from PIL import Image
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

def capture_weather_page():
    """
    Időjárás oldal képernyőképének készítése a capture_weather.sh script segítségével
    """
    logger.info("Időjárás oldal képernyőképének készítése...")
    
    output_path = os.path.join(os.path.dirname(os.path.realpath(__file__)), "weather.png")
    capture_script = os.path.join(os.path.dirname(os.path.realpath(__file__)), "capture_weather.sh")
    
    try:
        # Script futtatása a képernyőkép készítéséhez
        process = subprocess.run(
            [capture_script, output_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        
        # Ha a script sikeresen lefutott
        if process.returncode == 0:
            logger.info("Képernyőkép sikeresen elkészült")
            if os.path.exists(output_path) and os.path.getsize(output_path) > 1000:
                return output_path
            else:
                logger.error("A létrehozott képfájl túl kicsi vagy nem létezik")
                return None
        else:
            logger.error(f"Hiba a képernyőkép készítése során: {process.stderr}")
            return None
            
    except Exception as e:
        logger.error(f"Kivétel a képernyőkép készítése során: {e}")
        return None

def update_display():
    """Az e-paper kijelző frissítése a legújabb képpel."""
    global epd
    
    try:
        # Kijelző inicializálása
        logger.info("Kijelző inicializálása...")
        epd = epd4in01f.EPD()
        epd.init()
        
        # Képernyőkép készítése
        image_path = capture_weather_page()
        
        if not image_path:
            logger.error("Nem sikerült képernyőképet készíteni")
            return
        
        # Kép betöltése
        logger.info(f"Kép betöltése: {image_path}")
        img = Image.open(image_path)
        
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
