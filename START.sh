#!/bin/bash
# ===============================================================================
# LADEMEYER - START HIER!
# ===============================================================================
#
# Dieses Script liegt auf dem USB-Stick neben dem web/ Ordner.
# Es macht ALLES automatisch!
#
# VERWENDUNG:
#   1. USB-Stick einstecken
#   2. Terminal oeffnen
#   3. cd /media/pi/USB-STICK-NAME/
#   4. chmod +x START.sh && sudo ./START.sh
#
# ===============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

clear
echo -e "${CYAN}"
echo "==================================================================="
echo "  LADEMEYER FRONIUS PROXY - INSTALLATION"
echo "==================================================================="
echo -e "${NC}"
echo ""

# Root check
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}[FEHLER] Bitte als root ausfuehren:${NC}"
    echo ""
    echo "    sudo ./START.sh"
    echo ""
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo -e "${YELLOW}[INFO] USB-Verzeichnis: $SCRIPT_DIR${NC}"

# -----------------------------------------------------------------------------
# Web-Ordner pruefen
# -----------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}[1/4] Pruefe web/ Ordner...${NC}"

if [ -d "$SCRIPT_DIR/web" ] && [ -f "$SCRIPT_DIR/web/index.html" ]; then
    FILE_COUNT=$(find "$SCRIPT_DIR/web" -type f | wc -l)
    echo -e "${GREEN}[OK] web/ gefunden ($FILE_COUNT Dateien)${NC}"
else
    echo -e "${RED}[FEHLER] web/ Ordner nicht gefunden!${NC}"
    echo ""
    echo "Der USB-Stick muss so aussehen:"
    echo "  USB-STICK/"
    echo "    ├── START.sh    (dieses Script)"
    echo "    └── web/        (Flutter Build)"
    echo ""
    exit 1
fi

# -----------------------------------------------------------------------------
# Git pruefen
# -----------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}[2/4] Pruefe git...${NC}"

if ! command -v git &> /dev/null; then
    echo -e "${YELLOW}[INFO] Installiere git...${NC}"
    apt update -qq
    apt install -y -qq git
fi
echo -e "${GREEN}[OK] git verfuegbar${NC}"

# -----------------------------------------------------------------------------
# Repo klonen
# -----------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}[3/4] Klone Repository...${NC}"

REPO_DIR="$SCRIPT_DIR/lm-fronius-proxy"

if [ -d "$REPO_DIR" ]; then
    echo -e "${YELLOW}[INFO] Repo existiert - aktualisiere...${NC}"
    cd "$REPO_DIR"
    git pull || true
else
    echo -e "${YELLOW}[INFO] Klone von GitHub...${NC}"
    git clone https://github.com/GumDeveloper/lm-fronius-proxy.git "$REPO_DIR"
fi

echo -e "${GREEN}[OK] Repo bereit${NC}"

# -----------------------------------------------------------------------------
# Web-Ordner kopieren und Setup starten
# -----------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}[4/4] Kopiere web/ und starte Setup...${NC}"

# web/ ins Repo kopieren
rm -rf "$REPO_DIR/web"
cp -r "$SCRIPT_DIR/web" "$REPO_DIR/web"
echo -e "${GREEN}[OK] web/ kopiert${NC}"

# Ins Repo wechseln und setup.sh starten
cd "$REPO_DIR"
chmod +x setup.sh
./setup.sh

