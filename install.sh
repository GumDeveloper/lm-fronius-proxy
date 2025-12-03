#!/bin/bash
# ===============================================================================
# LADEMEYER RASPBERRY PI AUTO-INSTALLER v3.0
# ===============================================================================
# 
# Dieses Script installiert die Lademeyer Web-App + Fronius Multi-Proxy
# vollautomatisch auf dem Pi.
# 
# VERWENDUNG:
#   1. USB-Stick in den Pi stecken
#   2. Terminal oeffnen
#   3. cd /media/pi/USB-NAME/.usb
#   4. chmod +x install.sh && sudo ./install.sh
#
# NEU IN v3.0:
#   - Python Fronius Multi-Device Proxy
#   - Mehrere Wechselrichter gleichzeitig
#   - Automatische Daten-Akkumulation
#
# ===============================================================================

set -e  # Bei Fehlern abbrechen

# -----------------------------------------------------------------------------
# KONFIGURATION
# -----------------------------------------------------------------------------
APP_NAME="lademeyer"
WEB_DIR="/var/www/lademeyer"
PROXY_DIR="/opt/lademeyer"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Farben fuer Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}"
echo "==================================================================="
echo "  LADEMEYER ENERGY COMMAND CENTER v3.0"
echo "  RASPBERRY PI INSTALLER"
echo "==================================================================="
echo -e "${NC}"
echo ""
echo -e "  ${CYAN}Features:${NC}"
echo "    - Flutter Web App im Kiosk-Modus"
echo "    - Python Fronius Multi-Device Proxy"
echo "    - Automatische Daten-Akkumulation"
echo "    - CORS-Bypass fuer alle Wechselrichter"
echo ""

# -----------------------------------------------------------------------------
# VORAUSSETZUNGEN PRUEFEN
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[1/9] Pruefe Voraussetzungen...${NC}"

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}FEHLER: Bitte als root ausfuehren: sudo ./install.sh${NC}"
    exit 1
fi

if [ ! -d "$SCRIPT_DIR/web" ]; then
    echo -e "${RED}FEHLER: Web-Ordner nicht gefunden! Stelle sicher, dass 'web/' im selben Verzeichnis liegt.${NC}"
    exit 1
fi

if [ ! -f "$SCRIPT_DIR/fronius_proxy.py" ]; then
    echo -e "${RED}FEHLER: fronius_proxy.py nicht gefunden!${NC}"
    exit 1
fi

echo -e "${GREEN}[OK] Voraussetzungen OK${NC}"

# -----------------------------------------------------------------------------
# SYSTEM UPDATE
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[2/9] Aktualisiere System...${NC}"
apt update -qq
apt upgrade -y -qq
echo -e "${GREEN}[OK] System aktualisiert${NC}"

# -----------------------------------------------------------------------------
# NGINX INSTALLIEREN
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[3/9] Installiere Nginx...${NC}"
apt install -y -qq nginx
echo -e "${GREEN}[OK] Nginx installiert${NC}"

# -----------------------------------------------------------------------------
# PYTHON + FLASK INSTALLIEREN
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[4/9] Installiere Python und Flask...${NC}"
apt install -y -qq python3 python3-pip python3-flask python3-requests
pip3 install --break-system-packages flask requests 2>/dev/null || pip3 install flask requests
echo -e "${GREEN}[OK] Python + Flask installiert${NC}"

# -----------------------------------------------------------------------------
# WEB-APP KOPIEREN
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[5/9] Kopiere Web-App nach $WEB_DIR...${NC}"

# Altes Verzeichnis loeschen falls vorhanden
rm -rf "$WEB_DIR"
mkdir -p "$WEB_DIR"

# Web-App kopieren
cp -r "$SCRIPT_DIR/web/"* "$WEB_DIR/"

# Berechtigungen setzen
chown -R www-data:www-data "$WEB_DIR"
chmod -R 755 "$WEB_DIR"

echo -e "${GREEN}[OK] Web-App kopiert${NC}"

# -----------------------------------------------------------------------------
# FRONIUS PROXY INSTALLIEREN
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[6/9] Installiere Fronius Multi-Device Proxy...${NC}"

# Verzeichnis erstellen
mkdir -p "$PROXY_DIR"

# Proxy kopieren
cp "$SCRIPT_DIR/fronius_proxy.py" "$PROXY_DIR/"
chmod +x "$PROXY_DIR/fronius_proxy.py"

# Systemd Service erstellen
cat > /etc/systemd/system/lademeyer-proxy.service << 'PROXY_SERVICE'
[Unit]
Description=Lademeyer Fronius Multi-Device Proxy
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/opt/lademeyer
ExecStart=/usr/bin/python3 /opt/lademeyer/fronius_proxy.py
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=lademeyer-proxy

[Install]
WantedBy=multi-user.target
PROXY_SERVICE

# Service aktivieren und starten
systemctl daemon-reload
systemctl enable lademeyer-proxy
systemctl start lademeyer-proxy

echo -e "${GREEN}[OK] Fronius Proxy installiert und gestartet${NC}"

# -----------------------------------------------------------------------------
# NGINX KONFIGURIEREN
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[7/9] Konfiguriere Nginx...${NC}"

# Nginx Konfiguration erstellen
cat > /etc/nginx/sites-available/lademeyer << 'NGINX_CONFIG'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    
    server_name _;
    root /var/www/lademeyer;
    index index.html;
    
    # Gzip Kompression
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml;
    
    # Flutter Web App - SPA Routing
    location / {
        try_files $uri $uri/ /index.html;
    }
    
    # Cache statische Assets
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # ===================================================================
    # FRONIUS MULTI-DEVICE PROXY (Python auf Port 5000)
    # ===================================================================
    
    # Proxy API - Alle Geraete akkumuliert
    location /api/fronius/ {
        proxy_pass http://127.0.0.1:5000/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        
        # CORS Headers
        add_header Access-Control-Allow-Origin * always;
        add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Content-Type, Authorization" always;
        
        # OPTIONS Preflight
        if ($request_method = OPTIONS) {
            return 204;
        }
    }
    
    # Legacy Proxy Endpoint (Einzelabfrage)
    location /fronius-proxy {
        proxy_pass http://127.0.0.1:5000/fronius;
        proxy_set_header Host $host;
        add_header Access-Control-Allow-Origin * always;
    }
}
NGINX_CONFIG

# Site aktivieren
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/lademeyer /etc/nginx/sites-enabled/

# Nginx testen und neustarten
nginx -t
systemctl restart nginx
systemctl enable nginx

echo -e "${GREEN}[OK] Nginx konfiguriert${NC}"

# -----------------------------------------------------------------------------
# CHROMIUM KIOSK AUTOSTART
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[8/9] Konfiguriere Chromium Kiosk-Modus...${NC}"

# Hole den normalen Benutzer (nicht root)
NORMAL_USER=$(who | awk '{print $1}' | head -1)
if [ -z "$NORMAL_USER" ]; then
    NORMAL_USER="pi"
fi
USER_HOME="/home/$NORMAL_USER"

# Autostart-Verzeichnis erstellen
mkdir -p "$USER_HOME/.config/autostart"

# Desktop-Datei fuer Autostart erstellen
cat > "$USER_HOME/.config/autostart/lademeyer-kiosk.desktop" << DESKTOP_FILE
[Desktop Entry]
Type=Application
Name=Lademeyer Energy Command Center
Comment=Startet die Lademeyer Web-App im Vollbildmodus
Exec=/usr/bin/chromium-browser --kiosk --noerrdialogs --disable-infobars --disable-session-crashed-bubble --disable-restore-session-state --start-fullscreen http://localhost/#/data_v2
Terminal=false
Categories=Utility;
X-GNOME-Autostart-enabled=true
DESKTOP_FILE

chown "$NORMAL_USER:$NORMAL_USER" "$USER_HOME/.config/autostart/lademeyer-kiosk.desktop"

# Disable Screensaver und Screen Blanking
mkdir -p "$USER_HOME/.config/lxsession/LXDE-pi"
cat > "$USER_HOME/.config/lxsession/LXDE-pi/autostart" << AUTOSTART
@lxpanel --profile LXDE-pi
@pcmanfm --desktop --profile LXDE-pi
@xset s off
@xset -dpms
@xset s noblank
@chromium-browser --kiosk --noerrdialogs --disable-infobars --disable-session-crashed-bubble http://localhost/#/data_v2
AUTOSTART

chown -R "$NORMAL_USER:$NORMAL_USER" "$USER_HOME/.config/lxsession"

echo -e "${GREEN}[OK] Kiosk-Modus konfiguriert${NC}"

# -----------------------------------------------------------------------------
# HILFSSKRIPTE KOPIEREN
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[9/9] Installiere Hilfsskripte...${NC}"

# Start-Kiosk Script
cp "$SCRIPT_DIR/start-kiosk.sh" "$PROXY_DIR/"
chmod +x "$PROXY_DIR/start-kiosk.sh"

# Stop-Kiosk Script
cp "$SCRIPT_DIR/stop-kiosk.sh" "$PROXY_DIR/"
chmod +x "$PROXY_DIR/stop-kiosk.sh"

# Update Script
cp "$SCRIPT_DIR/update.sh" "$PROXY_DIR/"
chmod +x "$PROXY_DIR/update.sh"

# Symlinks in /usr/local/bin fuer einfachen Zugriff
ln -sf "$PROXY_DIR/start-kiosk.sh" /usr/local/bin/lademeyer-start
ln -sf "$PROXY_DIR/stop-kiosk.sh" /usr/local/bin/lademeyer-stop

echo -e "${GREEN}[OK] Hilfsskripte installiert${NC}"

# -----------------------------------------------------------------------------
# ABSCHLUSS
# -----------------------------------------------------------------------------
echo ""
echo -e "${BLUE}===================================================================${NC}"
echo -e "${GREEN}  INSTALLATION ERFOLGREICH ABGESCHLOSSEN!${NC}"
echo -e "${BLUE}===================================================================${NC}"
echo ""
echo -e "  ${CYAN}Installierte Komponenten:${NC}"
echo -e "     - Web-App:       ${YELLOW}http://localhost/${NC}"
echo -e "     - Energy Center: ${YELLOW}http://localhost/#/data_v2${NC}"
echo -e "     - Proxy API:     ${YELLOW}http://localhost/api/fronius/${NC}"
echo -e "     - Proxy Health:  ${YELLOW}http://localhost/api/fronius/health${NC}"
echo ""
echo -e "  ${CYAN}Befehle:${NC}"
echo -e "     - Kiosk starten: ${YELLOW}lademeyer-start${NC}"
echo -e "     - Kiosk stoppen: ${YELLOW}lademeyer-stop${NC}"
echo -e "     - Proxy Status:  ${YELLOW}sudo systemctl status lademeyer-proxy${NC}"
echo -e "     - Proxy Logs:    ${YELLOW}sudo journalctl -u lademeyer-proxy -f${NC}"
echo ""
echo -e "  ${CYAN}Fronius-Geraete hinzufuegen:${NC}"
echo -e "     In der App: SystemData V2 -> Zahnrad-Button -> IP eingeben"
echo -e "     Oder via API: ${YELLOW}curl -X POST localhost:5000/devices -d '{\"ip\":\"192.168.x.x\"}'${NC}"
echo ""
echo -e "  ${GREEN}Der Pi startet automatisch im Kiosk-Modus nach dem Neustart.${NC}"
echo ""
echo -e "  ${YELLOW}Jetzt neustarten? (j/n)${NC}"
read -r REBOOT_NOW

if [[ "$REBOOT_NOW" =~ ^[Jj]$ ]]; then
    echo -e "${GREEN}Starte neu...${NC}"
    reboot
else
    echo -e "${YELLOW}Bitte spaeter manuell neustarten: sudo reboot${NC}"
fi
