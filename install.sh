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

# Alkalmazás könyvtár létrehozása
echo "Alkalmazás könyvtár létrehozása..."
APP_DIR="/opt/e-paper-display"
mkdir -p "$APP_DIR"

# Csak a minimálisan szükséges csomagok telepítése - csomagkezelő frissítése nélkül
echo "Szükséges csomagok telepítése (frissítés nélkül)..."
apt-get install -y --no-install-recommends python3-pip python3-pil python3-numpy \
  python3-rpi.gpio python3-spidev python3-requests \
  libopenjp2-7 git wget wkhtmltopdf xvfb curl imagemagick

# Waveshare e-Paper könyvtár letöltése Git nélkül, ZIP fájlként
echo "Waveshare e-Paper könyvtár letöltése ZIP-ként..."
wget -q -O /tmp/waveshare.zip https://github.com/waveshare/e-Paper/archive/master.zip
mkdir -p /tmp/waveshare
unzip -q /tmp/waveshare.zip -d /tmp/waveshare
cp -r /tmp/waveshare/e-Paper-master/RaspberryPi_JetsonNano/python/lib/waveshare_epd "$APP_DIR/"
rm -rf /tmp/waveshare /tmp/waveshare.zip

# Egyedi közvetlenül a képernyőn megjelenítendő oldal
echo "Egyedi HTML oldal létrehozása..."
cat > "$APP_DIR/capture.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=640, height=400, initial-scale=1.0">
    <title>Időjárás E-Paper kijelzőhöz</title>
    <style>
        body, html {
            margin: 0;
            padding: 0;
            width: 640px;
            height: 400px;
            background-color: white;
            overflow: hidden;
            font-family: Arial, sans-serif;
        }
        #content {
            width: 640px;
            height: 400px;
            border: none;
            overflow: hidden;
        }
    </style>
</head>
<body>
    <div id="content">
        <iframe src="https://naptarak.com/e-paper.html?epaper=1&width=640&height=400&ts=TIMESTAMP" 
               width="640" height="400" frameborder="0" scrolling="no"></iframe>
    </div>
    <script>
        // Cache elkerülése egyedi időbélyeggel
        document.addEventListener('DOMContentLoaded', function() {
            const iframe = document.querySelector('iframe');
            const ts = new Date().getTime();
            iframe.src = iframe.src.replace('TIMESTAMP', ts);
            
            // Újratöltés, ha 45 másodperc után is betöltési állapotban van
            setTimeout(function() {
                const newTs = new Date().getTime();
                iframe.src = iframe.src.replace(ts, newTs);
            }, 45000);
        });
    </script>
</body>
</html>
EOF

# Direct Chromium alapú megoldás
echo "Képernyőkép készítő script létrehozása..."
cat > "$APP_DIR/capture_weather.py" << 'EOF'
#!/usr/bin/env python3
import os
import sys
import time
import subprocess
import logging
from datetime import datetime
from PIL import Image, ImageEnhance, ImageOps

# Naplózás beállítása
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Paraméterek
HTML_PATH = os.path.join(os.path.dirname(os.path.realpath(__file__)), "capture.html")
OUTPUT_PATH = os.path.join(os.path.dirname(os.path.realpath(__file__)), "weather.png")
WIDTH = 640
HEIGHT = 400
MAX_ATTEMPTS = 5

def optimize_image(image_path):
    """Kép optimalizálása e-Paper kijelzőhöz"""
    try:
        img = Image.open(image_path)
        
        # RGB-re konvertálás, ha szükséges
        if img.mode != 'RGB':
            img = img.convert('RGB')
        
        # Kontraszt növelése
        enhancer = ImageEnhance.Contrast(img)
        img = enhancer.enhance(1.5)
        
        # Élesség növelése
        enhancer = ImageEnhance.Sharpness(img)
        img = enhancer.enhance(1.3)
        
        # Fényesség beállítása
        enhancer = ImageEnhance.Brightness(img)
        img = enhancer.enhance(1.1)
        
        # Átméretezés a kijelző felbontására
        img = img.resize((WIDTH, HEIGHT), Image.LANCZOS)
        
        # Kép mentése
        img.save(image_path)
        logger.info(f"Kép optimalizálva: {image_path}")
        return True
    except Exception as e:
        logger.error(f"Hiba a kép optimalizálása során: {e}")
        return False

def capture_with_wkhtmltoimage():
    """Képernyőkép készítése wkhtmltoimage-dzsel"""
    timestamp = int(time.time())
    html_content = ""
    
    # HTML tartalom olvasása és időbélyeg frissítése
    with open(HTML_PATH, 'r') as file:
        html_content = file.read().replace('TIMESTAMP', str(timestamp))
    
    # Ideiglenes HTML létrehozása az időbélyeggel
    temp_html = f"{HTML_PATH}.{timestamp}.html"
    with open(temp_html, 'w') as file:
        file.write(html_content)
    
    try:
        # wkhtmltoimage futtatása Xvfb-vel
        cmd = [
            'xvfb-run', '--server-args="-screen 0, 640x400x24"', 
            'wkhtmltoimage',
            '--width', str(WIDTH),
            '--height', str(HEIGHT),
            '--quality', '100',
            '--disable-smart-width',
            '--enable-javascript',
            '--javascript-delay', '60000',
            '--no-stop-slow-scripts',
            f'file://{temp_html}',
            OUTPUT_PATH
        ]
        
        logger.info(f"Képernyőkép készítése: {' '.join(cmd)}")
        result = subprocess.run(' '.join(cmd), shell=True, capture_output=True, text=True)
        
        # Ideiglenes HTML törlése
        if os.path.exists(temp_html):
            os.remove(temp_html)
        
        if result.returncode != 0:
            logger.error(f"Hiba a képernyőkép készítése során: {result.stderr}")
            return False
        
        # Ellenőrizzük a létrejött képet
        if os.path.exists(OUTPUT_PATH) and os.path.getsize(OUTPUT_PATH) > 10000:
            # Kép optimalizálása
            return optimize_image(OUTPUT_PATH)
        else:
            logger.error("A létrehozott kép túl kicsi vagy nem létezik")
            return False
            
    except Exception as e:
        logger.error(f"Kivétel a képernyőkép készítése során: {e}")
        return False
    finally:
        # Biztosítsuk, hogy a temp HTML mindenképp törölve legyen
        if os.path.exists(temp_html):
            os.remove(temp_html)

def create_fallback_image():
    """Fallback kép létrehozása, ha minden próbálkozás sikertelen"""
    try:
        # Egyszerű kép létrehozása
        img = Image.new('RGB', (WIDTH, HEIGHT), color='white')
        
        # ImageMagick használata a szöveg hozzáadásához
        current_time = datetime.now().strftime("%Y-%m-%d %H:%M")
        
        temp_text_file = f"{APP_DIR}/temp_text.txt"
        with open(temp_text_file, 'w') as f:
            f.write(f"Pécs Időjárás\n\nIdőjárási adatok betöltése\nnem sikerült.\n\n{current_time}\n\nA kijelző 5 perc múlva\nújra próbálkozik.")
        
        cmd = [
            'convert', f'{OUTPUT_PATH}', '-fill', 'black', '-font', 'DejaVu-Sans-Bold',
            '-pointsize', '36', '-gravity', 'center',
            '-annotate', '+0+0', f'@{temp_text_file}',
            f'{OUTPUT_PATH}'
        ]
        
        subprocess.run(' '.join(cmd), shell=True)
        
        # Ideiglenes fájl törlése
        if os.path.exists(temp_text_file):
            os.remove(temp_text_file)
            
        return True
    except Exception as e:
        logger.error(f"Hiba a fallback kép létrehozása során: {e}")
        return False

def main():
    """Fő függvény"""
    for attempt in range(1, MAX_ATTEMPTS + 1):
        logger.info(f"Kísérlet {attempt}/{MAX_ATTEMPTS}")
        
        if capture_with_wkhtmltoimage():
            logger.info(f"Képernyőkép sikeresen elkészült a(z) {attempt}. kísérletre!")
            sys.exit(0)
        
        logger.info("Várakozás 10 másodpercet az újrapróbálkozás előtt...")
        time.sleep(10)
    
    logger.error(f"Nem sikerült képernyőképet készíteni {MAX_ATTEMPTS} próbálkozás után sem.")
    if create_fallback_image():
        logger.info("Fallback kép sikeresen létrehozva.")
    
    sys.exit(1)

if __name__ == "__main__":
    main()
EOF

chmod +x "$APP_DIR/capture_weather.py"

# Fő Python script létrehozása az e-paper kijelzőhöz
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
from datetime import datetime, timedelta

# Waveshare e-paper kijelző könyvtár importálása
sys.path.append(os.path.join(os.path.dirname(os.path.realpath(__file__)), 'waveshare_epd'))
try:
    from waveshare_epd import epd4in01f
except ImportError:
    print("HIBA: Nem sikerült importálni a waveshare_epd modult!")
    print("Ellenőrizd, hogy a Waveshare könyvtár megfelelően van-e telepítve.")
    sys.exit(1)

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
    Időjárás oldal képernyőképének készítése Python scripttel
    """
    logger.info("Időjárás oldal képernyőképének készítése...")
    
    output_path = os.path.join(os.path.dirname(os.path.realpath(__file__)), "weather.png")
    capture_script = os.path.join(os.path.dirname(os.path.realpath(__file__)), "capture_weather.py")
    
    try:
        # Python script futtatása a képernyőkép készítéséhez
        process = subprocess.run(
            [sys.executable, capture_script],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        
        # Naplózzuk a script kimenetét
        for line in process.stdout.splitlines():
            logger.info(f"Capture output: {line}")
        
        for line in process.stderr.splitlines():
            logger.error(f"Capture error: {line}")
        
        # Ellenőrizzük a kép létezését
        if os.path.exists(output_path) and os.path.getsize(output_path) > 10000:
            logger.info("Kép sikeresen létrehozva")
            return output_path
        else:
            logger.error("A létrehozott kép túl kicsi vagy nem létezik")
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
            return False
        
        # Kép betöltése
        logger.info(f"Kép betöltése: {image_path}")
        img = Image.open(image_path)
        
        # Kép mód és átméretezés kezelése ha szükséges
        if img.mode != 'RGB':
            img = img.convert('RGB')
        
        # Kép átméretezése, ha szükséges
        if img.size != (DISPLAY_WIDTH, DISPLAY_HEIGHT):
            logger.info(f"Kép átméretezése {img.size}-ről {(DISPLAY_WIDTH, DISPLAY_HEIGHT)}-re")
            img = img.resize((DISPLAY_WIDTH, DISPLAY_HEIGHT), Image.LANCZOS)
        
        # Kép megjelenítése
        logger.info("Kijelző frissítése...")
        epd.display(epd.getbuffer(img))
        time.sleep(2)  # Várjunk kicsit a megjelenítés után
        
        # Kijelző alvó módba helyezése az energiatakarékosság érdekében
        epd.sleep()
        
        logger.info("Kijelző sikeresen frissítve")
        return True
    
    except Exception as e:
        logger.error(f"Hiba a kijelző frissítésekor: {e}")
        # Próbáljuk meg alvó módba tenni a kijelzőt, még ha hiba történt is
        try:
            if epd is not None:
                epd.sleep()
        except:
            pass
        return False

def get_next_update_time():
    """Következő frissítés időpontjának meghatározása (5 perces intervallumokkal)"""
    now = datetime.now()
    next_minute = ((now.minute // 5) * 5 + 5) % 60
    next_hour = now.hour + (1 if next_minute < now.minute else 0)
    
    next_update = now.replace(hour=next_hour % 24, minute=next_minute, second=0, microsecond=0)
    
    if next_update <= now:
        next_update += timedelta(hours=1)
    
    return next_update

def main():
    """Fő függvény a kijelző periodikus frissítéséhez."""
    # Jelkezelő regisztrálása
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    logger.info("E-paper kijelző szolgáltatás indítása")
    
    # Kezdeti frissítés
    if not update_display():
        logger.error("Kezdeti frissítés sikertelen, újrapróbálkozás 30 másodperc múlva...")
        time.sleep(30)
        update_display()
    
    while True:
        try:
            # Következő frissítés időpontjának kiszámítása
            next_update = get_next_update_time()
            sleep_seconds = (next_update - datetime.now()).total_seconds()
            
            logger.info(f"Következő frissítés: {next_update.strftime('%Y-%m-%d %H:%M:%S')} ({int(sleep_seconds)} másodperc múlva)")
            
            # Alvás kisebb adagokban
            time_slept = 0
            while time_slept < sleep_seconds:
                sleep_interval = min(60, sleep_seconds - time_slept)
                time.sleep(sleep_interval)
                time_slept += sleep_interval
            
            # Kijelző frissítése
            update_display()
            
        except Exception as e:
            logger.error(f"Váratlan hiba a fő ciklusban: {e}")
            time.sleep(60)  # Hiba esetén várjunk 1 percet az újrapróbálkozás előtt

if __name__ == "__main__":
    main()
EOF

# Systemd szolgáltatás fájl létrehozása
echo "Systemd szolgáltatás létrehozása..."
cat > /etc/systemd/system/e-paper-display.service << EOF
[Unit]
Description=E-Paper Display Service
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/python3 $APP_DIR/display.py
WorkingDirectory=$APP_DIR
Restart=always
RestartSec=30
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
chmod +x "$APP_DIR/capture_weather.py"

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
