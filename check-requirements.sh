#!/bin/bash
# ===============================================================================
# LADEMEYER - VORAUSSETZUNGEN PRUEFEN
# ===============================================================================
#
# Dieses Script prueft ob alles vorhanden ist, BEVOR setup.sh laeuft.
# Fuehre es ZUERST aus!
#
# VERWENDUNG:
#   chmod +x check-requirements.sh
#   ./check-requirements.sh
#
# ===============================================================================

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "==================================================================="
echo "  LADEMEYER - VORAUSSETZUNGEN PRUEFEN"
echo "==================================================================="
echo -e "${NC}"

ERRORS=0
WARNINGS=0

# -----------------------------------------------------------------------------
# 1. Betriebssystem pruefen
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[1/8] Betriebssystem...${NC}"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo -e "       ${GREEN}[OK] $NAME $VERSION${NC}"
else
    echo -e "       ${YELLOW}[WARNUNG] Kein /etc/os-release gefunden${NC}"
    ((WARNINGS++))
fi

# -----------------------------------------------------------------------------
# 2. Root/Sudo pruefen
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[2/8] Root-Rechte...${NC}"
if [ "$EUID" -eq 0 ]; then
    echo -e "       ${GREEN}[OK] Laeuft als root${NC}"
else
    if command -v sudo &> /dev/null; then
        echo -e "       ${GREEN}[OK] sudo verfuegbar (spaeter mit sudo ausfuehren)${NC}"
    else
        echo -e "       ${RED}[FEHLER] Weder root noch sudo verfuegbar${NC}"
        ((ERRORS++))
    fi
fi

# -----------------------------------------------------------------------------
# 3. Git pruefen
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[3/8] Git...${NC}"
if command -v git &> /dev/null; then
    GIT_VERSION=$(git --version | cut -d' ' -f3)
    echo -e "       ${GREEN}[OK] git $GIT_VERSION${NC}"
else
    echo -e "       ${RED}[FEHLER] git nicht installiert${NC}"
    echo -e "       ${YELLOW}       -> sudo apt install git${NC}"
    ((ERRORS++))
fi

# -----------------------------------------------------------------------------
# 4. Internet-Verbindung pruefen
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[4/8] Internet-Verbindung...${NC}"
if ping -c 1 github.com &> /dev/null; then
    echo -e "       ${GREEN}[OK] github.com erreichbar${NC}"
else
    if ping -c 1 8.8.8.8 &> /dev/null; then
        echo -e "       ${YELLOW}[WARNUNG] Internet OK, aber github.com nicht erreichbar (DNS?)${NC}"
        ((WARNINGS++))
    else
        echo -e "       ${RED}[FEHLER] Keine Internet-Verbindung${NC}"
        ((ERRORS++))
    fi
fi

# -----------------------------------------------------------------------------
# 5. Python3 pruefen
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[5/8] Python3...${NC}"
if command -v python3 &> /dev/null; then
    PY_VERSION=$(python3 --version | cut -d' ' -f2)
    echo -e "       ${GREEN}[OK] Python $PY_VERSION${NC}"
else
    echo -e "       ${YELLOW}[WARNUNG] python3 nicht installiert (wird bei Installation geholt)${NC}"
    ((WARNINGS++))
fi

# -----------------------------------------------------------------------------
# 6. curl pruefen
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[6/8] curl...${NC}"
if command -v curl &> /dev/null; then
    echo -e "       ${GREEN}[OK] curl installiert${NC}"
else
    echo -e "       ${YELLOW}[WARNUNG] curl nicht installiert (wird bei Installation geholt)${NC}"
    ((WARNINGS++))
fi

# -----------------------------------------------------------------------------
# 7. web/ Ordner pruefen
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[7/8] web/ Ordner (Flutter App)...${NC}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -d "$SCRIPT_DIR/web" ] && [ -f "$SCRIPT_DIR/web/index.html" ]; then
    FILE_COUNT=$(find "$SCRIPT_DIR/web" -type f | wc -l)
    echo -e "       ${GREEN}[OK] web/ gefunden ($FILE_COUNT Dateien)${NC}"
elif [ -d "./web" ] && [ -f "./web/index.html" ]; then
    FILE_COUNT=$(find "./web" -type f | wc -l)
    echo -e "       ${GREEN}[OK] web/ gefunden ($FILE_COUNT Dateien)${NC}"
else
    echo -e "       ${RED}[FEHLER] web/ Ordner nicht gefunden!${NC}"
    echo -e "       ${YELLOW}       -> Kopiere den Flutter Web Build hierher${NC}"
    ((ERRORS++))
fi

# -----------------------------------------------------------------------------
# 8. Fronius erreichbar? (optional)
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[8/8] Fronius 192.168.200.51 (optional)...${NC}"
if ping -c 1 -W 2 192.168.200.51 &> /dev/null; then
    echo -e "       ${GREEN}[OK] Fronius erreichbar${NC}"
    
    # API testen
    FRONIUS_DATA=$(curl -s --connect-timeout 3 "http://192.168.200.51/solar_api/v1/GetPowerFlowRealtimeData.fcgi" 2>/dev/null || echo "")
    if echo "$FRONIUS_DATA" | grep -q "Body"; then
        echo -e "       ${GREEN}[OK] Fronius API antwortet${NC}"
    else
        echo -e "       ${YELLOW}[WARNUNG] Fronius ping OK, aber API antwortet nicht${NC}"
        ((WARNINGS++))
    fi
else
    echo -e "       ${YELLOW}[INFO] Fronius 192.168.200.51 nicht erreichbar (IP spaeter anpassen)${NC}"
fi

# -----------------------------------------------------------------------------
# ERGEBNIS
# -----------------------------------------------------------------------------
echo ""
echo -e "${CYAN}==================================================================="
echo "  ERGEBNIS"
echo "===================================================================${NC}"
echo ""

if [ $ERRORS -eq 0 ]; then
    if [ $WARNINGS -eq 0 ]; then
        echo -e "${GREEN}  ALLES OK! Du kannst jetzt setup.sh ausfuehren:${NC}"
    else
        echo -e "${GREEN}  GRUNDVORAUSSETZUNGEN OK! ($WARNINGS Warnungen)${NC}"
        echo -e "${GREEN}  Du kannst setup.sh ausfuehren:${NC}"
    fi
    echo ""
    echo -e "    ${CYAN}sudo ./setup.sh${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}  $ERRORS FEHLER gefunden!${NC}"
    echo ""
    echo "  Bitte behebe die Fehler und fuehre dieses Script erneut aus."
    echo ""
    exit 1
fi


