# Lademeyer Fronius Multi-Device Proxy

Ein Python-Proxy für Raspberry Pi, der mehrere Fronius-Wechselrichter gleichzeitig abfragen und die Daten akkumulieren kann.

## Features

- **Multi-Device Support**: Mehrere Fronius-Wechselrichter gleichzeitig verwalten
- **Daten-Akkumulation**: Solar, Grid, Load, Batterie werden automatisch summiert
- **REST-API**: Einfache Geräteverwaltung über HTTP-Endpoints
- **CORS-Bypass**: Löst CORS-Probleme für Web-Apps
- **Kiosk-Modus**: Automatischer Vollbild-Start mit Chromium
- **Default-Konfiguration**: 192.168.200.51 ist voreingestellt

## Schnellstart (One-Click Setup)

### Vorbereitung

1. **USB-Stick/Verzeichnis** auf dem Raspberry Pi Desktop vorbereiten:
   ```
   USB-Verzeichnis/
   ├── web/                    ← Flutter Web Build (von deinem PC kopieren)
   ├── check-requirements.sh   ← Von GitHub (oder USB)
   └── setup.sh                ← Von GitHub (oder USB)
   ```

2. **Oder direkt klonen** (wenn Internet vorhanden):
   ```bash
   cd ~/Desktop
   mkdir lademeyer-setup
   cd lademeyer-setup
   
   # Repo klonen
   git clone https://github.com/GumDeveloper/lm-fronius-proxy.git
   
   # web/ Ordner hierher kopieren (von USB)
   cp -r /media/pi/USB-STICK/web ./
   ```

### Installation

```bash
cd ~/Desktop/lademeyer-setup

# 1. Voraussetzungen pruefen
chmod +x check-requirements.sh
./check-requirements.sh

# 2. Setup starten (macht alles automatisch!)
chmod +x setup.sh
sudo ./setup.sh
```

Das `setup.sh` macht automatisch:
1. Klont das Repo (falls nötig)
2. Kopiert den web/ Ordner
3. Installiert alles (Nginx, Python, Flask, etc.)
4. **Prüft ob Fronius Daten liefert**
5. Fragt ob Kiosk-Modus gestartet werden soll

## Was wird geprüft? (check-requirements.sh)

| Check | Beschreibung |
|-------|--------------|
| Betriebssystem | Raspberry Pi OS erkannt? |
| Root/Sudo | Berechtigungen vorhanden? |
| Git | Installiert? |
| Internet | GitHub erreichbar? |
| Python3 | Installiert? |
| curl | Installiert? |
| web/ Ordner | Flutter Build vorhanden? |
| Fronius | 192.168.200.51 erreichbar? (optional) |

## Was wird installiert?

- **Nginx** - Webserver für die Flutter-App
- **Python Flask** - Für den Fronius-Proxy
- **Chromium** - Im Kiosk-Modus (Vollbild)
- **Systemd Services** - Automatischer Start

## Verzeichnisse nach Installation

| Pfad | Inhalt |
|------|--------|
| `/var/www/lademeyer/` | Web-App |
| `/opt/lademeyer/` | Proxy + Skripte |
| `~/.fronius_proxy_config.json` | Geräte-Konfiguration |

## Befehle

```bash
# Kiosk-Modus starten/stoppen
lademeyer-start
lademeyer-stop

# Proxy-Status
sudo systemctl status lademeyer-proxy

# Proxy-Logs
sudo journalctl -u lademeyer-proxy -f
```

## API-Endpoints

| Endpoint | Methode | Beschreibung |
|----------|---------|--------------|
| `/health` | GET | Health-Check |
| `/devices` | GET | Alle Geräte auflisten |
| `/devices` | POST | Gerät hinzufügen |
| `/devices/<id>` | DELETE | Gerät entfernen |
| `/data` | GET | Akkumulierte Daten aller Geräte |

## Fronius-Geräte verwalten

```bash
# Gerät hinzufügen
curl -X POST http://localhost:5000/devices \
     -H "Content-Type: application/json" \
     -d '{"ip": "192.168.200.51", "name": "Fronius Dach"}'

# Alle Geräte auflisten
curl http://localhost:5000/devices

# Akkumulierte Daten abrufen
curl http://localhost:5000/data
```

## Update

```bash
cd /opt/lademeyer
git pull
sudo ./update.sh
```

## Fehlerbehebung

### Proxy startet nicht
```bash
sudo journalctl -u lademeyer-proxy -n 50
python3 /opt/lademeyer/fronius_proxy.py
```

### Keine Fronius-Daten
```bash
curl http://localhost:5000/health
curl http://192.168.200.51/solar_api/v1/GetPowerFlowRealtimeData.fcgi
```

### Kiosk beenden
```bash
lademeyer-stop
# oder Alt + F4
# oder pkill -f chromium
```

## Lizenz

MIT License

## Support

Bei Fragen: [Issue erstellen](https://github.com/GumDeveloper/lm-fronius-proxy/issues)
