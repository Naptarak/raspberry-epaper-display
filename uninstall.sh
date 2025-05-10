#!/bin/bash

# E-Paper kijelző alkalmazás eltávolító szkript

echo "===================================================="
echo "E-paper kijelző alkalmazás eltávolítása"
echo "===================================================="

# Kilépés hiba esetén
set -e

# Ellenőrizzük, hogy root-ként fut-e
if [ "$EUID" -ne 0 ]; then
  echo "Kérlek root-ként futtasd (használj sudo-t)"
  exit 1
fi

# Szolgáltatás megállítása és letiltása
echo "Szolgáltatás megállítása és letiltása..."
systemctl stop e-paper-display.service || true
systemctl disable e-paper-display.service || true
rm -f /etc/systemd/system/e-paper-display.service
systemctl daemon-reload

# Ideiglenes fájlok törlése
echo "Ideiglenes fájlok törlése..."
rm -f /tmp/temp_*.png || true
rm -f /tmp/e-paper-*.png || true

# Alkalmazás könyvtár törlése
echo "Alkalmazásfájlok törlése..."
APP_DIR="/opt/e-paper-display"
if [ -d "$APP_DIR" ]; then
  # Ha vannak ideiglenes fájlok a könyvtárban
  rm -f "$APP_DIR/temp_"*.png || true
  rm -f "$APP_DIR/"*.log || true
  
  # Teljes könyvtár törlése
  rm -rf "$APP_DIR"
  echo "Alkalmazás könyvtár törölve."
else
  echo "Alkalmazás könyvtár nem található."
fi

# Opcionális: az SPI interfész kikapcsolásának felajánlása
echo "SPI interfész megtartása (szükséges lehet más alkalmazásokhoz)."
echo "Ha szeretnéd kikapcsolni az SPI-t, használd a 'sudo raspi-config' parancsot."

echo "Az e-paper kijelző alkalmazás eltávolítva."
echo "Megjegyzés: Ez a szkript nem távolította el a rendszercsomagokat vagy Python könyvtárakat,"
echo "amelyeket más alkalmazások is használhatnak."
echo "===================================================="
