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

# Alkalmazás könyvtár törlése
echo "Alkalmazásfájlok törlése..."
APP_DIR="/opt/e-paper-display"
rm -rf "$APP_DIR"

echo "Az e-paper kijelző alkalmazás eltávolítva."
echo "Megjegyzés: Ez a szkript nem távolította el a rendszercsomagokat vagy Python könyvtárakat,"
echo "amelyeket más alkalmazások is használhatnak."
echo "===================================================="
