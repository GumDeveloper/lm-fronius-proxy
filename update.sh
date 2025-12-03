#!/bin/bash
# ===============================================================================
# LADEMEYER UPDATE SCRIPT v3.0
# ===============================================================================
# 
# Aktualisiert Web-App UND Fronius-Proxy
#
# VERWENDUNG:
#   sudo ./update.sh
#
# ===============================================================================

set -e

WEB_DIR="/var/www/lademeyer"
PROXY_DIR="/opt/lademeyer"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "==================================================================="
echo "  LADEMEYER UPDATE v3.0"
echo "==================================================================="
echo -e "${NC}"

# -----------------------------------------------------------------------------
# Voraussetzungen pruefen
# -----------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}FEHLER: Bitte als root ausfuehren: sudo ./update.sh${NC}"
    exit 1
fi

# -----------------------------------------------------------------------------
# 1. Web-App aktualisieren
# -----------------------------------------------------------------------------
if [ -d "$SCRIPT_DIR/web" ]; then
    echo -e "${YELLOW}[1/4] Aktualisiere Web-App...${NC}"
    
    # Backup erstellen
    if [ -d "$WEB_DIR" ]; then
        BACKUP_DIR="/var/www/lademeyer-backup-$(date +%Y%m%d-%H%M%S)"
        cp -r "$WEB_DIR" "$BACKUP_DIR"
        echo "  Backup: $BACKUP_DIR"
    fi
    
    # Neue Version kopieren
    rm -rf "$WEB_DIR"/*
    cp -r "$SCRIPT_DIR/web/"* "$WEB_DIR/"
    chown -R www-data:www-data "$WEB_DIR"
    
    echo -e "${GREEN}  [OK] Web-App aktualisiert${NC}"
else
    echo -e "${YELLOW}[1/4] Kein web/ Ordner gefunden - ueberspringe${NC}"
fi

# -----------------------------------------------------------------------------
# 2. Fronius Proxy aktualisieren
# -----------------------------------------------------------------------------
if [ -f "$SCRIPT_DIR/fronius_proxy.py" ]; then
    echo -e "${YELLOW}[2/4] Aktualisiere Fronius Proxy...${NC}"
    
    # Proxy stoppen
    systemctl stop lademeyer-proxy 2>/dev/null || true
    
    # Neuen Proxy kopieren
    mkdir -p "$PROXY_DIR"
    cp "$SCRIPT_DIR/fronius_proxy.py" "$PROXY_DIR/"
    chmod +x "$PROXY_DIR/fronius_proxy.py"
    
    # Proxy Config erhalten (falls vorhanden)
    if [ -f "/root/.fronius_proxy_config.json" ]; then
        cp "/root/.fronius_proxy_config.json" "/home/www-data/.fronius_proxy_config.json" 2>/dev/null || true
        chown www-data:www-data "/home/www-data/.fronius_proxy_config.json" 2>/dev/null || true
    fi
    
    # Proxy neu starten
    systemctl start lademeyer-proxy
    
    echo -e "${GREEN}  [OK] Proxy aktualisiert und neu gestartet${NC}"
else
    echo -e "${YELLOW}[2/4] Kein fronius_proxy.py gefunden - ueberspringe${NC}"
fi

# -----------------------------------------------------------------------------
# 3. Hilfsskripte aktualisieren
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[3/4] Aktualisiere Hilfsskripte...${NC}"

for script in start-kiosk.sh stop-kiosk.sh; do
    if [ -f "$SCRIPT_DIR/$script" ]; then
        cp "$SCRIPT_DIR/$script" "$PROXY_DIR/"
        chmod +x "$PROXY_DIR/$script"
        echo "  $script"
    fi
done

echo -e "${GREEN}  [OK] Skripte aktualisiert${NC}"

# -----------------------------------------------------------------------------
# 4. Services neu laden
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[4/4] Lade Services neu...${NC}"

systemctl reload nginx 2>/dev/null || systemctl restart nginx

echo -e "${GREEN}  [OK] Nginx neu geladen${NC}"

# -----------------------------------------------------------------------------
# Abschluss
# -----------------------------------------------------------------------------
echo ""
echo -e "${GREEN}===================================================================${NC}"
echo -e "${GREEN}  UPDATE ERFOLGREICH!${NC}"
echo -e "${GREEN}===================================================================${NC}"
echo ""

# Status anzeigen
echo -e "${CYAN}Service Status:${NC}"
if systemctl is-active --quiet lademeyer-proxy; then
    echo -e "  Fronius Proxy:  ${GREEN}[LAEUFT]${NC}"
else
    echo -e "  Fronius Proxy:  ${RED}[GESTOPPT]${NC}"
fi

if systemctl is-active --quiet nginx; then
    echo -e "  Nginx:          ${GREEN}[LAEUFT]${NC}"
else
    echo -e "  Nginx:          ${RED}[GESTOPPT]${NC}"
fi

echo ""
echo -e "${YELLOW}Tipp: Seite im Browser mit F5 neu laden!${NC}"
echo ""
