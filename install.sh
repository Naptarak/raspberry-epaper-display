#!/bin/bash

# E-Paper időjárás kijelző telepítő Raspberry Pi Zero 2W-hez
# Waveshare 4.01 HAT (F) e-paper kijelzőhöz
# API-alapú időjárás megjelenítés, 5 perces frissítéssel

echo "===================================================="
echo "E-Paper időjárás kijelző telepítése Raspberry Pi Zero 2W-re"
echo "Kijelző: Waveshare 4.01 inch HAT (F) e-paper"
echo "Időjárás forrás: OpenWeatherMap API"
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
mkdir -p "$APP_DIR/fonts"
mkdir -p "$APP_DIR/icons"

# Minimális csomagok telepítése (rendszerfrissítés nélkül)
echo "Szükséges csomagok telepítése (frissítés nélkül)..."
apt-get install -y --no-install-recommends python3-pip python3-pil python3-numpy \
  python3-rpi.gpio python3-spidev python3-requests python3-pillow \
  libopenjp2-7 git wget unzip curl

# Waveshare e-Paper könyvtár letöltése
echo "Waveshare e-Paper könyvtár letöltése ZIP-ként..."
wget -q -O /tmp/waveshare.zip https://github.com/waveshare/e-Paper/archive/master.zip
mkdir -p /tmp/waveshare
unzip -q /tmp/waveshare.zip -d /tmp/waveshare
cp -r /tmp/waveshare/e-Paper-master/RaspberryPi_JetsonNano/python/lib/waveshare_epd "$APP_DIR/"
rm -rf /tmp/waveshare /tmp/waveshare.zip

# Időjárás ikonok letöltése
echo "Időjárás ikonok letöltése..."
ICONS_URL="https://openweathermap.org/themes/openweathermap/assets/vendor/owm/img/widgets/"
ICONS=("01d.png" "01n.png" "02d.png" "02n.png" "03d.png" "03n.png" "04d.png" "04n.png" 
       "09d.png" "09n.png" "10d.png" "10n.png" "11d.png" "11n.png" "13d.png" "13n.png" "50d.png" "50n.png")

for icon in "${ICONS[@]}"; do
  wget -q "${ICONS_URL}${icon}" -O "$APP_DIR/icons/${icon}"
done

# Napsugár ikonok letöltése napkeltéhez és napnyugtához
wget -q "https://cdn-icons-png.flaticon.com/512/869/869869.png" -O "$APP_DIR/icons/sunrise.png"
wget -q "https://cdn-icons-png.flaticon.com/512/10156/10156491.png" -O "$APP_DIR/icons/sunset.png"

# Font letöltése
echo "Betűtípusok letöltése..."
wget -q "https://github.com/google/fonts/raw/main/ofl/roboto/Roboto-Regular.ttf" -O "$APP_DIR/fonts/Roboto-Regular.ttf"
wget -q "https://github.com/google/fonts/raw/main/ofl/roboto/Roboto-Bold.ttf" -O "$APP_DIR/fonts/Roboto-Bold.ttf"

# Időjárási adatokat megjelenítő Python script
echo "Időjárás megjelenítő script létrehozása..."
cat > "$APP_DIR/weather_display.py" << 'EOF'
#!/usr/bin/env python3
# -*- coding:utf-8 -*-

import os
import sys
import time
import logging
import json
import requests
from datetime import datetime, timedelta
from PIL import Image, ImageDraw, ImageFont
import signal

# Waveshare e-paper kijelző könyvtár importálása
lib_dir = os.path.join(os.path.dirname(os.path.realpath(__file__)), 'waveshare_epd')
if os.path.exists(lib_dir):
    sys.path.append(lib_dir)
    try:
        from waveshare_epd import epd4in01f
    except ImportError as e:
        print(f"Hiba a Waveshare könyvtár importálásakor: {e}")
        sys.exit(1)
else:
    print(f"A 'waveshare_epd' könyvtár nem található: {lib_dir}")
    sys.exit(1)

# Globális beállítások - ezek a beállítások megfelelnek Pécsnek
CITY = "Pécs"
COUNTRY = "HU"
LAT = 46.0763
LON = 18.2281
API_KEY = "1e39a49c6785626b3aca124f4d4ce591"
LOCALE = "hu"
TZ = "Europe/Budapest"
DISPLAY_WIDTH = 640
DISPLAY_HEIGHT = 400
APP_DIR = os.path.dirname(os.path.realpath(__file__))
LOG_FILE = os.path.join(APP_DIR, "weather.log")
FONT_REGULAR = os.path.join(APP_DIR, "fonts", "Roboto-Regular.ttf")
FONT_BOLD = os.path.join(APP_DIR, "fonts", "Roboto-Bold.ttf")
ICON_DIR = os.path.join(APP_DIR, "icons")

# Magyar nap nevek a heti előrejelzéshez
DAY_NAMES_HU = {
    'Monday': 'Hét',
    'Tuesday': 'Ke',
    'Wednesday': 'Sze',
    'Thursday': 'Csü',
    'Friday': 'Pén',
    'Saturday': 'Szo',
    'Sunday': 'Vas'
}

# Időjárás leírások fordítása magyarra
WEATHER_TRANSLATIONS = {
    "clear sky": "tiszta égbolt",
    "few clouds": "kevés felhő",
    "scattered clouds": "szórványos felhőzet",
    "broken clouds": "szakadozott felhőzet",
    "shower rain": "záporeső",
    "rain": "eső",
    "thunderstorm": "zivatar",
    "snow": "havazás",
    "mist": "köd",
    "overcast clouds": "felhős"
}

# Naplózás beállítása
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Globális változók
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

def get_weather_data():
    """Időjárási adatok lekérése az OpenWeatherMap API-tól"""
    try:
        # Aktuális időjárás lekérése
        current_url = f"https://api.openweathermap.org/data/2.5/weather?lat={LAT}&lon={LON}&appid={API_KEY}&units=metric&lang={LOCALE}"
        current_response = requests.get(current_url, timeout=10)
        current_data = current_response.json()
        
        # Előrejelzés lekérése
        forecast_url = f"https://api.openweathermap.org/data/2.5/forecast?lat={LAT}&lon={LON}&appid={API_KEY}&units=metric&lang={LOCALE}&cnt=40"
        forecast_response = requests.get(forecast_url, timeout=10)
        forecast_data = forecast_response.json()
        
        # Napkelte/napnyugta időzónák beállítása
        sunrise_timestamp = current_data['sys']['sunrise']
        sunset_timestamp = current_data['sys']['sunset']
        sunrise = datetime.fromtimestamp(sunrise_timestamp).strftime('%H:%M')
        sunset = datetime.fromtimestamp(sunset_timestamp).strftime('%H:%M')
        
        # Holnapi napkelte/napnyugta (egyszerűsített becslés)
        tomorrow_sunrise = (datetime.fromtimestamp(sunrise_timestamp) + timedelta(days=1)).strftime('%H:%M')
        tomorrow_sunset = (datetime.fromtimestamp(sunset_timestamp) + timedelta(days=1)).strftime('%H:%M')
        
        # Aktuális dátum magyar formátumban
        now = datetime.now()
        month_names = ['jan', 'feb', 'már', 'ápr', 'máj', 'jún', 'júl', 'aug', 'szep', 'okt', 'nov', 'dec']
        date_str = f"{now.year}. {month_names[now.month-1]} {now.day}."
        
        # Időjárás leírás fordítása magyarra, ha szükséges
        description = current_data['weather'][0]['description']
        if description in WEATHER_TRANSLATIONS:
            description = WEATHER_TRANSLATIONS[description]
        
        # Napi előrejelzés összeállítása
        daily_forecast = {}
        
        # A következő 4 nap előrejelzése
        for item in forecast_data['list']:
            forecast_date = datetime.fromtimestamp(item['dt'])
            if forecast_date.date() <= now.date():
                continue  # A mai napot kihagyjuk
                
            day_name = forecast_date.strftime('%A')  # Angol nap név
            if day_name in DAY_NAMES_HU:
                day_name = DAY_NAMES_HU[day_name]  # Magyar nap név
                
            if day_name not in daily_forecast:
                daily_forecast[day_name] = {
                    'temp_min': float(item['main']['temp_min']),
                    'temp_max': float(item['main']['temp_max']),
                    'icon': item['weather'][0]['icon'],
                    'date': forecast_date.date()
                }
            else:
                daily_forecast[day_name]['temp_min'] = min(daily_forecast[day_name]['temp_min'], float(item['main']['temp_min']))
                daily_forecast[day_name]['temp_max'] = max(daily_forecast[day_name]['temp_max'], float(item['main']['temp_max']))
                
        # Csak az első 4 napot tartjuk meg
        forecast_sorted = sorted(daily_forecast.items(), key=lambda x: x[1]['date'])
        daily_forecast = dict(forecast_sorted[:4])
        
        # Adatok összegyűjtése
        weather_data = {
            'city': CITY,
            'date': date_str,
            'description': description,
            'icon': current_data['weather'][0]['icon'],
            'temp': int(round(current_data['main']['temp'])),
            'feels_like': int(round(current_data['main']['feels_like'])),
            'humidity': current_data['main']['humidity'],
            'pressure': current_data['main']['pressure'],
            'wind_speed': current_data['wind']['speed'],
            'sunrise': sunrise,
            'sunset': sunset,
            'tomorrow_sunrise': tomorrow_sunrise,
            'tomorrow_sunset': tomorrow_sunset,
            'forecast': daily_forecast
        }
        
        return weather_data
    except Exception as e:
        logger.error(f"Hiba az időjárási adatok lekérésekor: {e}")
        return None

def draw_weather_image(weather_data):
    """Időjárási adatok rajzolása képre a mellékelt képhez hasonló megjelenéssel"""
    try:
        # Új kép létrehozása
        image = Image.new('RGB', (DISPLAY_WIDTH, DISPLAY_HEIGHT), color='white')
        draw = ImageDraw.Draw(image)
        
        # Betűtípusok
        font_title = ImageFont.truetype(FONT_BOLD, 36)
        font_date = ImageFont.truetype(FONT_BOLD, 24)
        font_large = ImageFont.truetype(FONT_BOLD, 100)  # Nagyobb méretű a hőmérséklethez
        font_medium = ImageFont.truetype(FONT_BOLD, 24)
        font_small = ImageFont.truetype(FONT_REGULAR, 20)
        font_tiny = ImageFont.truetype(FONT_REGULAR, 16)
        
        # Cím és dátum
        draw.text((DISPLAY_WIDTH//2, 30), f"{weather_data['city']} Időjárás", font=font_title, fill='black', anchor='mt')
        draw.text((DISPLAY_WIDTH//2, 80), weather_data['date'], font=font_date, fill='black', anchor='mt')
        
        # Bal oldal - Mai napkelte/napnyugta
        sun_icon_size = (24, 24)
        
        # Baloldali napkelte ikon betöltése és elhelyezése
        sunrise_icon = Image.open(os.path.join(ICON_DIR, "sunrise.png"))
        sunrise_icon = sunrise_icon.resize(sun_icon_size)
        left_sunrise_pos = (70, 140)
        left_sunset_pos = (70, 180)
        image.paste(sunrise_icon, left_sunrise_pos, sunrise_icon.convert('RGBA'))
        image.paste(sunrise_icon, left_sunset_pos, sunrise_icon.convert('RGBA'))
        
        # Napkelte/napnyugta szöveg
        draw.text((110, 140), f"Kel: {weather_data['sunrise']}", font=font_small, fill='black')
        draw.text((110, 180), f"Nyugszik: {weather_data['sunset']}", font=font_small, fill='black')
        
        # Jobb oldal - Holnapi napkelte/napnyugta
        right_sunrise_pos = (450, 140)
        right_sunset_pos = (450, 180)
        image.paste(sunrise_icon, right_sunrise_pos, sunrise_icon.convert('RGBA'))
        image.paste(sunrise_icon, right_sunset_pos, sunrise_icon.convert('RGBA'))
        
        # Holnapi napkelte/napnyugta szöveg
        draw.text((490, 140), f"Kel: {weather_data['tomorrow_sunrise']}", font=font_small, fill='black')
        draw.text((490, 180), f"Nyugszik: {weather_data['tomorrow_sunset']}", font=font_small, fill='black')
        
        # Hőmérséklet - nagy piros számokkal, pontosan úgy mint a képen
        temp_text = f"{weather_data['temp']}°C"
        temp_color = (200, 0, 0) if weather_data['temp'] > 0 else (0, 0, 200)
        draw.text((DISPLAY_WIDTH//2, 220), temp_text, font=font_large, fill=temp_color, anchor='mt')
        
        # Időjárás leírás
        draw.text((DISPLAY_WIDTH//2, 320), weather_data['description'], font=font_medium, fill='black', anchor='mt')
        
        # Részletes adatok
        draw.text((80, 350), f"Szél: {weather_data['wind_speed']} km/h", font=font_small, fill='black')
        draw.text((80, 380), f"Páratartalom: {weather_data['humidity']}%", font=font_small, fill='black')
        draw.text((80, 410), f"Légnyomás: {weather_data['pressure']} hPa", font=font_small, fill='black')
        
        # Kék vízszintes vonal
        draw.line([(40, 450), (DISPLAY_WIDTH-40, 450)], fill=(0, 0, 150), width=2)
        
        # Napi előrejelzés
        forecast_x = 70
        forecast_width = 125
        forecast_y = 500
        
        # Előrejelzés címkék és adatok
        for i, (day, data) in enumerate(weather_data['forecast'].items()):
            # Nap neve
            day_x = forecast_x + i * forecast_width
            draw.text((day_x + forecast_width//2, forecast_y), day, font=font_medium, fill=(0, 0, 150), anchor='mt')
            
            # Időjárás ikon
            icon_filename = os.path.join(ICON_DIR, f"{data['icon']}.png")
            if os.path.exists(icon_filename):
                icon = Image.open(icon_filename)
                icon = icon.resize((50, 50))
                icon_pos = (day_x + forecast_width//2 - 25, forecast_y + 30)
                image.paste(icon, icon_pos, icon.convert('RGBA'))
            
            # Hőmérséklet
            temp_min = int(round(data['temp_min']))
            temp_max = int(round(data['temp_max']))
            temp_text = f"{temp_max}°C"
            draw.text((day_x + forecast_width//2, forecast_y + 90), temp_text, font=font_small, fill='black', anchor='mt')
        
        # Frissítési idő
        current_time = datetime.now().strftime('%H:%M')
        draw.text((DISPLAY_WIDTH-40, DISPLAY_HEIGHT-20), f"Frissítve: {current_time}", font=font_tiny, fill='black', anchor='rb')
        
        return image
    except Exception as e:
        logger.error(f"Hiba a kép rajzolásakor: {e}")
        return None

def draw_error_image():
    """Hibaüzenet kép készítése"""
    try:
        image = Image.new('RGB', (DISPLAY_WIDTH, DISPLAY_HEIGHT), color='white')
        draw = ImageDraw.Draw(image)
        
        # Betűtípusok
        font_title = ImageFont.truetype(FONT_BOLD, 36)
        font_text = ImageFont.truetype(FONT_REGULAR, 24)
        
        # Cím
        draw.text((DISPLAY_WIDTH//2, 100), "Pécs Időjárás", font=font_title, fill='black', anchor='mt')
        
        # Hibaüzenet
        error_messages = [
            "Időjárás adatok betöltése nem sikerült.",
            "Kérlek ellenőrizd a hálózati kapcsolatot",
            "és az API beállításokat.",
            "",
            "Újrapróbálkozás 5 perc múlva."
        ]
        
        for i, message in enumerate(error_messages):
            draw.text((DISPLAY_WIDTH//2, 180 + i*40), message, font=font_text, fill='black', anchor='mt')
        
        # Aktuális idő
        current_time = datetime.now().strftime('%Y-%m-%d %H:%M')
        draw.text((DISPLAY_WIDTH//2, 350), current_time, font=font_text, fill='black', anchor='mt')
        
        return image
    except Exception as e:
        logger.error(f"Hiba a hibaüzenet kép készítésekor: {e}")
        
        # Legegyszerűbb hibaüzenet
        try:
            image = Image.new('RGB', (DISPLAY_WIDTH, DISPLAY_HEIGHT), color='white')
            draw = ImageDraw.Draw(image)
            draw.text((100, 200), "Hiba - Újrapróbálkozás 5 perc múlva", fill='black')
            return image
        except:
            return None

def update_display():
    """Az e-paper kijelző frissítése"""
    global epd
    
    try:
        # Kijelző inicializálása
        logger.info("Kijelző inicializálása...")
        epd = epd4in01f.EPD()
        epd.init()
        
        # Időjárási adatok lekérése
        weather_data = get_weather_data()
        
        if weather_data:
            # Időjárási adatok képének elkészítése
            logger.info("Időjárási adatok képének elkészítése...")
            image = draw_weather_image(weather_data)
        else:
            # Hibaüzenet képének elkészítése
            logger.info("Hibaüzenet képének elkészítése...")
            image = draw_error_image()
        
        if image:
            # Kép megjelenítése a kijelzőn
            logger.info("Kép megjelenítése a kijelzőn...")
            epd.display(epd.getbuffer(image))
            
            # Kép mentése
            image_path = os.path.join(APP_DIR, "latest_weather.png")
            image.save(image_path)
            logger.info(f"Kép mentve: {image_path}")
            
            # Kijelző alvó módba helyezése
            time.sleep(2)  # Várunk kicsit, mielőtt alvó módba helyezzük
            epd.sleep()
            
            logger.info("Kijelző frissítve")
            return True
        else:
            logger.error("Nem sikerült képet létrehozni")
            return False
    
    except Exception as e:
        logger.error(f"Hiba a kijelző frissítésekor: {e}")
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
    """Fő függvény"""
    # Jelkezelő regisztrálása
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    logger.info("E-paper időjárás kijelző szolgáltatás indítása")
    
    # Első frissítés
    update_display()
    
    # Periodikus frissítés
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
            time.sleep(300)  # Hiba esetén várunk 5 percet

if __name__ == "__main__":
    main()
EOF

# Jogosultságok beállítása
echo "Jogosultságok beállítása..."
chmod +x "$APP_DIR/weather_display.py"

# Systemd szolgáltatás fájl létrehozása
echo "Systemd szolgáltatás létrehozása..."
cat > /etc/systemd/system/e-paper-display.service << EOF
[Unit]
Description=E-Paper Weather Display Service
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/python3 $APP_DIR/weather_display.py
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

# Szolgáltatás engedélyezése és indítása
echo "Szolgáltatás engedélyezése és indítása..."
systemctl daemon-reload
systemctl enable e-paper-display.service
systemctl start e-paper-display.service

echo "===================================================="
echo "Telepítés kész!"
echo "Az e-paper kijelző most közvetlenül a OpenWeatherMap API-ból kéri le az adatokat,"
echo "és 5 percenként frissül."
echo "Az állapot ellenőrzéséhez: sudo systemctl status e-paper-display.service"
echo "Naplók megtekintéséhez: cat $APP_DIR/weather.log"
echo "===================================================="
