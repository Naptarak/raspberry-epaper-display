#!/bin/bash

# E-Paper Website Display Újratelepítő
# Készítette: Claude

echo "=================================================="
echo "  E-Paper Website Display Újratelepítő"
echo "=================================================="
echo ""
echo "Ez a script újratelepíti az E-Paper Website Display alkalmazást."
echo ""

# Ellenőrizzük, hogy létezik-e a telepítési könyvtár
INSTALL_DIR="/home/pi/e-paper-display"
if [ ! -d "$INSTALL_DIR" ]; then
    echo "Az E-Paper Website Display még nincs telepítve."
    echo "Kérlek futtasd először az install.sh szkriptet."
    exit 1
fi

# Leállítjuk a szolgáltatást
echo "Az E-Paper Display szolgáltatás leállítása..."
sudo systemctl stop epaper-display.service

# Jelenlegi beállítások betöltése
current_url=$(grep "url =" $INSTALL_DIR/config.ini | cut -d'=' -f2 | tr -d ' ')
current_refresh=$(grep "refresh_interval =" $INSTALL_DIR/config.ini | cut -d'=' -f2 | tr -d ' ')

# Frissítési időköz beállítása
echo "Jelenlegi frissítési időköz: $current_refresh perc"
echo -n "Add meg az új frissítési időközt (percekben, Enter a jelenlegi megtartásához): "
read refresh_interval
if [ -z "$refresh_interval" ]; then
    refresh_interval=$current_refresh
fi

# Ellenőrizzük, hogy érvényes szám-e
if ! [[ "$refresh_interval" =~ ^[0-9]+$ ]]; then
    echo "Érvénytelen érték. A jelenlegi $current_refresh perc lesz használva."
    refresh_interval=$current_refresh
fi

# URL beállítása
echo "Jelenlegi URL: $current_url"
echo -n "Add meg az új URL-t (Enter a jelenlegi megtartásához): "
read new_url
if [ -z "$new_url" ]; then
    new_url=$current_url
fi

# Konfiguráció frissítése
echo "Konfiguráció frissítése..."
cat > $INSTALL_DIR/config.ini << EOL
[Settings]
url = $new_url
refresh_interval = $refresh_interval
EOL

# Automatikus indítás beállítása
if [ "$new_url" != "$current_url" ]; then
    echo "URL frissítése az automatikus böngésző indításában..."
    sed -i "s|chromium-browser --kiosk --incognito .*|chromium-browser --kiosk --incognito $new_url \&|g" $INSTALL_DIR/start_browser.sh
fi

# Szolgáltatás újraindítása
echo "Az E-Paper Display szolgáltatás újraindítása..."
sudo systemctl daemon-reload
sudo systemctl restart epaper-display.service

echo ""
echo "==================================================="
echo "  Újratelepítés befejezve!"
echo "==================================================="
echo ""
echo "Az új beállítások:"
echo "URL: $new_url"
echo "Frissítési időköz: $refresh_interval perc"
echo ""
echo "Nyomj Enter-t a folytatáshoz..."
read