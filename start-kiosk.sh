#!/bin/bash
# ===============================================================================
# LADEMEYER KIOSK-MODUS STARTEN
# ===============================================================================
#
# Startet sowohl den Fronius-Proxy als auch den Chromium Kiosk
#
# ===============================================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "==================================================================="
echo "  LADEMEYER ENERGY COMMAND CENTER"
echo "==================================================================="
echo -e "${NC}"

# -----------------------------------------------------------------------------
# 1. Fronius Proxy starten (falls nicht schon laeuft)
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[1/3] Pruefe Fronius Proxy...${NC}"

if systemctl is-active --quiet lademeyer-proxy; then
    echo -e "${GREEN}[OK] Proxy laeuft bereits${NC}"
else
    echo -e "${YELLOW}[...] Starte Proxy...${NC}"
    sudo systemctl start lademeyer-proxy
    sleep 2
    
    if systemctl is-active --quiet lademeyer-proxy; then
        echo -e "${GREEN}[OK] Proxy gestartet${NC}"
    else
        echo -e "${YELLOW}[WARN] Proxy konnte nicht gestartet werden - starte manuell...${NC}"
        python3 /opt/lademeyer/fronius_proxy.py &
        sleep 2
    fi
fi

# Proxy Health-Check
echo -e "${YELLOW}[2/3] Pruefe Proxy-Verbindung...${NC}"
if curl -s http://localhost:5000/health > /dev/null 2>&1; then
    DEVICE_COUNT=$(curl -s http://localhost:5000/health | grep -o '"devices":[0-9]*' | grep -o '[0-9]*')
    echo -e "${GREEN}[OK] Proxy erreichbar ($DEVICE_COUNT Geraete konfiguriert)${NC}"
else
    echo -e "${YELLOW}[WARN] Proxy nicht erreichbar auf Port 5000${NC}"
fi

# -----------------------------------------------------------------------------
# 2. Screensaver deaktivieren
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[3/3] Starte Kiosk-Modus...${NC}"

xset s off 2>/dev/null || true
xset -dpms 2>/dev/null || true
xset s noblank 2>/dev/null || true

# -----------------------------------------------------------------------------
# 3. Chromium im Kiosk-Modus starten
# -----------------------------------------------------------------------------
echo -e "${GREEN}Starte Chromium im Kiosk-Modus...${NC}"
echo ""
echo -e "  ${CYAN}Tipp: Zum Beenden: lademeyer-stop oder Alt+F4${NC}"
echo ""

chromium-browser \
    --kiosk \
    --noerrdialogs \
    --disable-infobars \
    --disable-session-crashed-bubble \
    --disable-restore-session-state \
    --start-fullscreen \
    --app=http://localhost/#/data_v2
