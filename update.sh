#!/bin/bash
# ===============================================================================
# LADEMEYER FRONIUS PROXY - UPDATE
# ===============================================================================
#
# Holt die neueste Version von GitHub und startet den Proxy neu.
#
# VERWENDUNG:
#   sudo ./update.sh
#
# ===============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "==================================================================="
echo "  LADEMEYER FRONIUS PROXY - UPDATE"
echo "==================================================================="
echo -e "${NC}"

# Root check
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}[FEHLER] Bitte als root ausfuehren: sudo ./update.sh${NC}"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/lademeyer"

# -----------------------------------------------------------------------------
# 1. Git Pull
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[1/4] Hole Updates von GitHub...${NC}"

cd "$SCRIPT_DIR"
git pull
if [ $? -eq 0 ]; then
    echo -e "${GREEN}[OK] Updates geholt${NC}"
else
    echo -e "${YELLOW}[INFO] Keine Updates oder Fehler beim Pull${NC}"
fi

# -----------------------------------------------------------------------------
# 2. Dateien kopieren
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[2/4] Kopiere Dateien nach $INSTALL_DIR...${NC}"

cp "$SCRIPT_DIR/fronius_proxy.py" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/start-kiosk.sh" "$INSTALL_DIR/" 2>/dev/null || true
cp "$SCRIPT_DIR/stop-kiosk.sh" "$INSTALL_DIR/" 2>/dev/null || true
cp "$SCRIPT_DIR/proxy-status.sh" "$INSTALL_DIR/" 2>/dev/null || true

chmod +x "$INSTALL_DIR"/*.sh 2>/dev/null || true
chmod +x "$INSTALL_DIR"/*.py

echo -e "${GREEN}[OK] Dateien kopiert${NC}"

# -----------------------------------------------------------------------------
# 3. Proxy neustarten
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[3/4] Starte Proxy neu...${NC}"

systemctl restart lademeyer-proxy
sleep 2

if systemctl is-active --quiet lademeyer-proxy; then
    echo -e "${GREEN}[OK] Proxy laeuft${NC}"
else
    echo -e "${RED}[FEHLER] Proxy konnte nicht gestartet werden${NC}"
    echo -e "${YELLOW}[INFO] Logs anzeigen mit: sudo journalctl -u lademeyer-proxy -n 20${NC}"
fi

# -----------------------------------------------------------------------------
# 4. Health Check
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[4/4] Health Check...${NC}"
sleep 1

HEALTH=$(curl -s http://localhost:5000/health 2>/dev/null)
if [ -n "$HEALTH" ]; then
    DEVICES=$(echo "$HEALTH" | grep -o '"devices":[0-9]*' | grep -o '[0-9]*' || echo "0")
    echo -e "${GREEN}[OK] Proxy erreichbar ($DEVICES Geraete)${NC}"
else
    echo -e "${RED}[FEHLER] Proxy nicht erreichbar${NC}"
fi

# -----------------------------------------------------------------------------
# Fertig
# -----------------------------------------------------------------------------
echo ""
echo -e "${GREEN}==================================================================="
echo "  UPDATE ABGESCHLOSSEN"
echo "===================================================================${NC}"
echo ""
echo "Befehle:"
echo "  - Status:    sudo systemctl status lademeyer-proxy"
echo "  - Logs:      sudo journalctl -u lademeyer-proxy -f"
echo "  - Health:    curl localhost:5000/health"
echo ""
