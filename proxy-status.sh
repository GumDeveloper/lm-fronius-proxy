#!/bin/bash
# ===============================================================================
# LADEMEYER PROXY STATUS
# ===============================================================================
#
# Zeigt detaillierten Status des Fronius Multi-Device Proxy
#
# ===============================================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "==================================================================="
echo "  LADEMEYER FRONIUS PROXY STATUS"
echo "==================================================================="
echo -e "${NC}"

# -----------------------------------------------------------------------------
# Service Status
# -----------------------------------------------------------------------------
echo -e "${CYAN}[SERVICES]${NC}"

if systemctl is-active --quiet lademeyer-proxy 2>/dev/null; then
    echo -e "  Fronius Proxy:  ${GREEN}[AKTIV]${NC}"
else
    echo -e "  Fronius Proxy:  ${RED}[INAKTIV]${NC}"
fi

if systemctl is-active --quiet nginx 2>/dev/null; then
    echo -e "  Nginx:          ${GREEN}[AKTIV]${NC}"
else
    echo -e "  Nginx:          ${RED}[INAKTIV]${NC}"
fi

echo ""

# -----------------------------------------------------------------------------
# API Health Check
# -----------------------------------------------------------------------------
echo -e "${CYAN}[PROXY API]${NC}"

HEALTH=$(curl -s http://localhost:5000/health 2>/dev/null)
if [ -n "$HEALTH" ]; then
    DEVICES=$(echo "$HEALTH" | grep -o '"devices":[0-9]*' | grep -o '[0-9]*')
    REACHABLE=$(echo "$HEALTH" | grep -o '"reachable":[0-9]*' | grep -o '[0-9]*')
    
    echo -e "  Endpoint:       ${GREEN}http://localhost:5000${NC}"
    echo -e "  Geraete:        ${YELLOW}$DEVICES konfiguriert${NC}"
    echo -e "  Erreichbar:     ${GREEN}$REACHABLE von $DEVICES${NC}"
else
    echo -e "  Endpoint:       ${RED}Nicht erreichbar${NC}"
fi

echo ""

# -----------------------------------------------------------------------------
# Geraete-Liste
# -----------------------------------------------------------------------------
echo -e "${CYAN}[FRONIUS GERAETE]${NC}"

DEVICES_JSON=$(curl -s http://localhost:5000/devices 2>/dev/null)
if [ -n "$DEVICES_JSON" ]; then
    # Parse JSON und zeige Geraete
    echo "$DEVICES_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    devices = data.get('devices', [])
    if not devices:
        print('  Keine Geraete konfiguriert')
    else:
        for d in devices:
            status = '[OK]' if d.get('is_reachable') else '[FEHLER]'
            print(f\"  {status} {d.get('name', 'Unbekannt'):20} {d.get('ip', '?'):15} (ID: {d.get('id', '?')})\")
except:
    print('  Fehler beim Parsen der Geraete-Liste')
" 2>/dev/null || echo "  Keine Verbindung zum Proxy"
else
    echo "  Keine Verbindung zum Proxy"
fi

echo ""

# -----------------------------------------------------------------------------
# Live-Daten
# -----------------------------------------------------------------------------
echo -e "${CYAN}[LIVE DATEN]${NC}"

DATA=$(curl -s http://localhost:5000/data 2>/dev/null)
if [ -n "$DATA" ]; then
    echo "$DATA" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    if d.get('success'):
        print(f\"  Solar:      {d.get('solarPower', 0):.1f} kW\")
        grid = d.get('gridPower', 0)
        if grid < 0:
            print(f\"  Netz:       {abs(grid):.1f} kW (Einspeisung)\")
        else:
            print(f\"  Netz:       {grid:.1f} kW (Bezug)\")
        print(f\"  Haus:       {d.get('housePower', 0):.1f} kW\")
        print(f\"  Batterie:   {d.get('batterySOC', 0):.0f}%\")
    else:
        print('  Keine Daten verfuegbar')
except Exception as e:
    print(f'  Fehler: {e}')
" 2>/dev/null || echo "  Keine Daten verfuegbar"
else
    echo "  Keine Verbindung zum Proxy"
fi

echo ""
echo -e "${CYAN}===================================================================${NC}"
echo ""
echo -e "Befehle:"
echo "  Geraet hinzufuegen:   curl -X POST localhost:5000/devices -H 'Content-Type: application/json' -d '{\"ip\":\"192.168.x.x\"}'"
echo "  Proxy Logs:           sudo journalctl -u lademeyer-proxy -f"
echo ""
