#!/bin/bash
# ===============================================================================
# LADEMEYER KIOSK-MODUS BEENDEN
# ===============================================================================
#
# Beendet den Kiosk-Modus. Der Fronius-Proxy laeuft weiter.
#
# ===============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${RED}"
echo "==================================================================="
echo "  LADEMEYER KIOSK BEENDEN"
echo "==================================================================="
echo -e "${NC}"

# -----------------------------------------------------------------------------
# Chromium beenden
# -----------------------------------------------------------------------------
echo -e "${YELLOW}Beende Chromium...${NC}"
pkill -f chromium 2>/dev/null || true
pkill -f "chromium-browser" 2>/dev/null || true

echo -e "${GREEN}[OK] Kiosk beendet${NC}"
echo ""

# -----------------------------------------------------------------------------
# Status anzeigen
# -----------------------------------------------------------------------------
echo -e "${CYAN}===================================================================${NC}"
echo -e "${CYAN}Status:${NC}"

# Proxy Status
if systemctl is-active --quiet lademeyer-proxy 2>/dev/null; then
    echo -e "  Fronius Proxy:  ${GREEN}[LAEUFT]${NC}"
else
    echo -e "  Fronius Proxy:  ${RED}[GESTOPPT]${NC}"
fi

# Nginx Status
if systemctl is-active --quiet nginx 2>/dev/null; then
    echo -e "  Nginx:          ${GREEN}[LAEUFT]${NC}"
else
    echo -e "  Nginx:          ${RED}[GESTOPPT]${NC}"
fi

echo ""
echo -e "${CYAN}Befehle:${NC}"
echo "  Kiosk neu starten:      lademeyer-start"
echo "  Proxy stoppen:          sudo systemctl stop lademeyer-proxy"
echo "  Proxy Logs:             sudo journalctl -u lademeyer-proxy -f"
echo "  Fronius-Geraete:        curl localhost:5000/devices"
echo ""
echo -e "${CYAN}===================================================================${NC}"
