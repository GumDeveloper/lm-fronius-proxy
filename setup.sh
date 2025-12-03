#!/bin/bash
# ===============================================================================
# LADEMEYER FRONIUS PROXY - ONE-CLICK SETUP
# ===============================================================================
#
# Dieses Script macht ALLES in einem Schritt:
#   1. Klont das Repo (falls nicht schon im Repo-Verzeichnis)
#   2. Kopiert den web/ Ordner automatisch
#   3. Startet die Installation
#   4. Prueft ob Fronius Daten liefert
#   5. Startet Kiosk-Modus (optional)
#
# VERWENDUNG (im USB-Verzeichnis auf dem Desktop):
#   chmod +x setup.sh
#   sudo ./setup.sh
#
# ===============================================================================

set -e

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "==================================================================="
echo "  LADEMEYER FRONIUS PROXY - ONE-CLICK SETUP"
echo "==================================================================="
echo -e "${NC}"

# -----------------------------------------------------------------------------
# SCHRITT 0: Wo sind wir?
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo -e "${YELLOW}[INFO] Script-Verzeichnis: $SCRIPT_DIR${NC}"

# Pruefen ob wir im geklonten Repo sind (fronius_proxy.py existiert)
if [ -f "$SCRIPT_DIR/fronius_proxy.py" ]; then
    echo -e "${GREEN}[OK] Bereits im Repo-Verzeichnis${NC}"
    REPO_DIR="$SCRIPT_DIR"
    PARENT_DIR="$(dirname "$SCRIPT_DIR")"
else
    # Wir sind im USB-Verzeichnis, Repo muss geklont werden
    echo -e "${YELLOW}[INFO] Nicht im Repo - klone von GitHub...${NC}"
    PARENT_DIR="$SCRIPT_DIR"
    REPO_DIR="$SCRIPT_DIR/lm-fronius-proxy"
    
    if [ -d "$REPO_DIR" ]; then
        echo -e "${YELLOW}[INFO] Repo existiert bereits - aktualisiere...${NC}"
        cd "$REPO_DIR"
        git pull
    else
        echo -e "${YELLOW}[INFO] Klone Repo...${NC}"
        git clone https://github.com/GumDeveloper/lm-fronius-proxy.git "$REPO_DIR"
    fi
    
    echo -e "${GREEN}[OK] Repo bereit: $REPO_DIR${NC}"
fi

# -----------------------------------------------------------------------------
# SCHRITT 1: Web-Ordner finden und kopieren
# -----------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}[1/5] Suche web/ Ordner...${NC}"

WEB_SOURCE=""

if [ -d "$PARENT_DIR/web" ] && [ -f "$PARENT_DIR/web/index.html" ]; then
    WEB_SOURCE="$PARENT_DIR/web"
    echo -e "${GREEN}[OK] web/ gefunden: $WEB_SOURCE${NC}"
elif [ -d "$REPO_DIR/web" ] && [ -f "$REPO_DIR/web/index.html" ]; then
    WEB_SOURCE="$REPO_DIR/web"
    echo -e "${GREEN}[OK] web/ bereits im Repo: $WEB_SOURCE${NC}"
elif [ -d "./web" ] && [ -f "./web/index.html" ]; then
    WEB_SOURCE="./web"
    echo -e "${GREEN}[OK] web/ gefunden: $WEB_SOURCE${NC}"
else
    echo -e "${RED}[FEHLER] web/ Ordner nicht gefunden!${NC}"
    echo ""
    echo "Bitte stelle sicher, dass der web/ Ordner im selben Verzeichnis liegt."
    exit 1
fi

if [ "$WEB_SOURCE" != "$REPO_DIR/web" ]; then
    echo -e "${YELLOW}[INFO] Kopiere web/ nach $REPO_DIR/web/...${NC}"
    rm -rf "$REPO_DIR/web"
    cp -r "$WEB_SOURCE" "$REPO_DIR/web"
    echo -e "${GREEN}[OK] web/ kopiert${NC}"
fi

# -----------------------------------------------------------------------------
# SCHRITT 2: Ins Repo wechseln
# -----------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}[2/5] Wechsle ins Repo-Verzeichnis...${NC}"
cd "$REPO_DIR"
echo -e "${GREEN}[OK] Aktuelles Verzeichnis: $(pwd)${NC}"

# -----------------------------------------------------------------------------
# SCHRITT 3: Installation starten
# -----------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}[3/5] Starte Installation...${NC}"

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}[FEHLER] Bitte als root ausfuehren: sudo ./setup.sh${NC}"
    exit 1
fi

chmod +x install.sh

# Installation OHNE automatischen Reboot (wir fragen spaeter)
# Modifiziere install.sh temporaer um den Reboot-Prompt zu ueberspringen
sed -i 's/read -r REBOOT_NOW/REBOOT_NOW="n"/g' install.sh 2>/dev/null || true

./install.sh

echo -e "${GREEN}[OK] Installation abgeschlossen${NC}"

# -----------------------------------------------------------------------------
# SCHRITT 4: Fronius-Daten pruefen
# -----------------------------------------------------------------------------
echo ""
echo -e "${CYAN}==================================================================="
echo "  FRONIUS DATEN-CHECK"
echo "===================================================================${NC}"
echo ""

# Warte bis Proxy gestartet ist
echo -e "${YELLOW}[4/5] Warte auf Proxy-Start...${NC}"
sleep 5

# Proxy Health-Check
PROXY_OK=false
FRONIUS_OK=false

echo -e "${YELLOW}[INFO] Pruefe Proxy...${NC}"
HEALTH=$(curl -s http://localhost:5000/health 2>/dev/null || echo "")

if [ -n "$HEALTH" ]; then
    echo -e "${GREEN}[OK] Proxy laeuft!${NC}"
    PROXY_OK=true
    
    DEVICES=$(echo "$HEALTH" | grep -o '"devices":[0-9]*' | grep -o '[0-9]*' || echo "0")
    REACHABLE=$(echo "$HEALTH" | grep -o '"reachable":[0-9]*' | grep -o '[0-9]*' || echo "0")
    
    echo -e "    Konfigurierte Geraete: ${CYAN}$DEVICES${NC}"
    echo -e "    Erreichbare Geraete:   ${CYAN}$REACHABLE${NC}"
else
    echo -e "${RED}[FEHLER] Proxy nicht erreichbar${NC}"
fi

# Fronius-Daten abrufen
echo ""
echo -e "${YELLOW}[INFO] Rufe Fronius-Daten ab...${NC}"
sleep 2

DATA=$(curl -s http://localhost:5000/data 2>/dev/null || echo "")

if [ -n "$DATA" ]; then
    # Parse JSON mit Python
    RESULT=$(echo "$DATA" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    if d.get('success') and d.get('reachableCount', 0) > 0:
        solar = d.get('solarPower', 0)
        grid = d.get('gridPower', 0)
        house = d.get('housePower', 0)
        soc = d.get('batterySOC', 0)
        print(f'OK|Solar: {solar:.1f} kW|Grid: {grid:.1f} kW|Haus: {house:.1f} kW|Batterie: {soc:.0f}%')
    else:
        print('KEINE_DATEN|Keine erreichbaren Fronius-Geraete')
except Exception as e:
    print(f'FEHLER|{e}')
" 2>/dev/null || echo "FEHLER|Python-Fehler")

    STATUS=$(echo "$RESULT" | cut -d'|' -f1)
    
    if [ "$STATUS" = "OK" ]; then
        FRONIUS_OK=true
        echo -e "${GREEN}"
        echo "==================================================================="
        echo "  FRONIUS DATEN EMPFANGEN!"
        echo "==================================================================="
        echo -e "${NC}"
        echo "$RESULT" | cut -d'|' -f2- | tr '|' '\n' | while read line; do
            echo -e "    ${CYAN}$line${NC}"
        done
        echo ""
    else
        MSG=$(echo "$RESULT" | cut -d'|' -f2)
        echo -e "${YELLOW}[WARNUNG] $MSG${NC}"
    fi
else
    echo -e "${RED}[FEHLER] Keine Antwort vom Proxy${NC}"
fi

# -----------------------------------------------------------------------------
# SCHRITT 5: Benutzer-Entscheidung
# -----------------------------------------------------------------------------
echo ""
echo -e "${CYAN}==================================================================="
echo "  WAS MOECHTEST DU TUN?"
echo "===================================================================${NC}"
echo ""

if [ "$FRONIUS_OK" = true ]; then
    echo -e "${GREEN}  [1] Kiosk-Modus starten (Fronius OK!)${NC}"
else
    echo -e "${YELLOW}  [1] Kiosk-Modus starten (ohne Fronius-Daten)${NC}"
fi
echo "  [2] Nur Proxy laufen lassen (kein Kiosk)"
echo "  [3] Fronius-IP aendern und erneut testen"
echo "  [4] Abbrechen und spaeter manuell starten"
echo ""
echo -e "${YELLOW}Deine Wahl [1-4]:${NC} "
read -r CHOICE

case $CHOICE in
    1)
        echo ""
        echo -e "${GREEN}[OK] Starte Kiosk-Modus...${NC}"
        echo ""
        echo -e "${YELLOW}Neustart erforderlich. Jetzt neustarten? [j/n]${NC} "
        read -r REBOOT_NOW
        if [[ "$REBOOT_NOW" =~ ^[Jj]$ ]]; then
            echo -e "${GREEN}Starte neu...${NC}"
            reboot
        else
            echo -e "${YELLOW}Bitte spaeter manuell neustarten: sudo reboot${NC}"
            echo -e "${YELLOW}Oder Kiosk manuell starten: lademeyer-start${NC}"
        fi
        ;;
    2)
        echo ""
        echo -e "${GREEN}[OK] Proxy laeuft im Hintergrund.${NC}"
        echo ""
        echo "Befehle:"
        echo "  - Kiosk starten:  lademeyer-start"
        echo "  - Proxy Status:   sudo systemctl status lademeyer-proxy"
        echo "  - Proxy Logs:     sudo journalctl -u lademeyer-proxy -f"
        echo ""
        ;;
    3)
        echo ""
        echo -e "${YELLOW}Aktuelle Fronius-IP: 192.168.200.51 (Default)${NC}"
        echo -e "${YELLOW}Neue Fronius-IP eingeben:${NC} "
        read -r NEW_IP
        
        if [[ "$NEW_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo -e "${YELLOW}[INFO] Fuege $NEW_IP hinzu...${NC}"
            curl -s -X POST http://localhost:5000/devices \
                 -H "Content-Type: application/json" \
                 -d "{\"ip\": \"$NEW_IP\", \"name\": \"Fronius Neu\"}" > /dev/null
            
            echo -e "${YELLOW}[INFO] Warte auf Daten...${NC}"
            sleep 3
            
            # Erneut testen
            DATA=$(curl -s http://localhost:5000/data 2>/dev/null || echo "")
            if echo "$DATA" | grep -q '"success":true'; then
                echo -e "${GREEN}[OK] Fronius $NEW_IP antwortet!${NC}"
            else
                echo -e "${YELLOW}[WARNUNG] Keine Antwort von $NEW_IP${NC}"
            fi
            
            echo ""
            echo -e "${YELLOW}Jetzt Kiosk starten? [j/n]${NC} "
            read -r START_KIOSK
            if [[ "$START_KIOSK" =~ ^[Jj]$ ]]; then
                echo -e "${GREEN}Starte neu...${NC}"
                reboot
            fi
        else
            echo -e "${RED}[FEHLER] Ungueltige IP-Adresse${NC}"
        fi
        ;;
    4)
        echo ""
        echo -e "${YELLOW}[INFO] Abgebrochen.${NC}"
        echo ""
        echo "Spaeter manuell starten:"
        echo "  - Kiosk starten:  lademeyer-start"
        echo "  - Oder neustarten: sudo reboot"
        echo ""
        ;;
    *)
        echo -e "${RED}[FEHLER] Ungueltige Auswahl${NC}"
        ;;
esac

echo ""
echo -e "${CYAN}==================================================================="
echo "  SETUP ABGESCHLOSSEN"
echo "===================================================================${NC}"
echo ""
