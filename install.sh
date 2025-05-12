#!/bin/bash

# Hibakezelés beállítása
set -e
trap 'echo "Hiba történt a(z) $BASH_COMMAND parancs futtatásakor a(z) ${LINENO} sorban."' ERR

# Színek a jobb olvashatóságért
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Funkciók
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "A telepítőt root jogosultsággal kell futtatni!"
        log_info "Próbáld meg: sudo $0"
        exit 1
    fi
}

check_system() {
    # Rendszer ellenőrzése
    if ! grep -q "Raspberry Pi" /proc/cpuinfo; then
        log_warn "Nem Raspberry Pi rendszeren futunk. Biztos vagy benne, hogy folytatni szeretnéd? (y/N)"
        read -r response
        if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])+$ ]]; then
            log_info "Telepítés megszakítva."
            exit 0
        fi
    fi
}

install_dependencies() {
    log_info "Rendszer frissítése és függőségek telepítése..."
    
    # APT források frissítése
    apt-get update || {
        log_error "Nem sikerült frissíteni az apt forrásokat!"
        exit 1
    }
    
    # Alapvető rendszerfrissítés
    apt-get upgrade -y || log_warn "Nem sikerült minden csomagot frissíteni."
    
    # Szükséges csomagok telepítése
    PACKAGES=(
        "git"
        "nodejs"
        "npm"
        "python3-pip"
        "python3-pil"
        "python3-numpy"
        "libatlas-base-dev"
        "wiringpi"
        "chromium-browser"
    )
    
    for package in "${PACKAGES[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package"; then
            log_info "Telepítés: $package"
            apt-get install -y "$package" || {
                log_error "Nem sikerült telepíteni: $package"
                exit 1
            }
        else
            log_info "$package már telepítve van."
        fi
    done
}

setup_spi() {
    log_info "SPI interfész beállítása..."
    
    # Ellenőrizzük, hogy az SPI modul be van-e töltve
    if ! lsmod | grep -q "spi_bcm2835"; then
        # Ellenőrizzük, hogy létezik-e a config.txt
        if [ ! -f "/boot/config.txt" ]; then
            log_error "Nem található a /boot/config.txt fájl!"
            exit 1
        fi
        
        # Ha még nincs engedélyezve az SPI, akkor engedélyezzük
        if ! grep -q "^dtparam=spi=on" /boot/config.txt; then
            echo "dtparam=spi=on" >> /boot/config.txt
            log_info "SPI engedélyezve, újraindítás szükséges a használathoz."
            REBOOT_NEEDED=1
        fi
    else
        log_info "SPI már engedélyezve van."
    fi
}

setup_project() {
    local PROJECT_DIR="/opt/weather-display"
    log_info "Projekt telepítése: $PROJECT_DIR"
    
    # Projekt könyvtár létrehozása
    mkdir -p "$PROJECT_DIR"
    
    # Fájlok másolása
    cp package.json "$PROJECT_DIR/"
    cp index.js "$PROJECT_DIR/"
    
    # Jogosultságok beállítása
    chown -R pi:pi "$PROJECT_DIR"
    
    # Node.js függőségek telepítése
    cd "$PROJECT_DIR" || exit 1
    sudo -u pi npm install || {
        log_error "Nem sikerült telepíteni a Node.js függőségeket!"
        exit 1
    }
}

setup_service() {
    log_info "Systemd szolgáltatás beállítása..."
    
    # Szolgáltatás fájl létrehozása
    cat > /etc/systemd/system/weather-display.service << EOF
[Unit]
Description=Weather Display Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=pi
WorkingDirectory=/opt/weather-display
ExecStart=/usr/bin/node /opt/weather-display/index.js
Restart=always
RestartSec=10
StandardOutput=append:/var/log/weather-display.log
StandardError=append:/var/log/weather-display.log

[Install]
WantedBy=multi-user.target
EOF
    
    # Log fájl létrehozása és jogosultságok beállítása
    touch /var/log/weather-display.log
    chown pi:pi /var/log/weather-display.log
    
    # Systemd újratöltése és szolgáltatás indítása
    systemctl daemon-reload
    systemctl enable weather-display
    systemctl start weather-display || {
        log_error "Nem sikerült elindítani a szolgáltatást!"
        log_info "Ellenőrizd a logokat: journalctl -u weather-display -f"
        exit 1
    }
}

# Fő program
main() {
    log_info "Weather Display telepítő indítása..."
    
    check_root
    check_system
    install_dependencies
    setup_spi
    setup_project
    setup_service
    
    log_info "Telepítés befejezve!"
    
    if [ "$REBOOT_NEEDED" = 1 ]; then
        log_warn "A rendszert újra kell indítani az SPI interfész használatához."
        log_info "Szeretnéd most újraindítani a rendszert? (y/N)"
        read -r response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])+$ ]]; then
            reboot
        fi
    else
        log_info "A szolgáltatás fut és automatikusan indul rendszerindításkor."
        log_info "Állapot ellenőrzése: systemctl status weather-display"
        log_info "Logok megtekintése: journalctl -u weather-display -f"
    fi
}

# Program indítása
main
