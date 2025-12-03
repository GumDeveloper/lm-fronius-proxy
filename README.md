# Lademeyer Fronius Multi-Device Proxy

Ein Python-Proxy für Raspberry Pi, der mehrere Fronius-Wechselrichter gleichzeitig abfragen und die Daten akkumulieren kann.

## Features

- **Multi-Device Support**: Mehrere Fronius-Wechselrichter gleichzeitig verwalten
- **Daten-Akkumulation**: Solar, Grid, Load, Batterie werden automatisch summiert
- **REST-API**: Einfache Geräteverwaltung über HTTP-Endpoints
- **CORS-Bypass**: Löst CORS-Probleme für Web-Apps
- **Kiosk-Modus**: Automatischer Vollbild-Start mit Chromium
- **Persistente Config**: Geräte-Konfiguration wird gespeichert

## Schnellstart

### 1. Repository klonen

```bash
git clone https://github.com/GumDeveloper/lm-fronius-proxy.git
cd lm-fronius-proxy
```

### 2. Web-App hinzufügen (separat)

Die Flutter Web-App muss separat in den `web/` Ordner kopiert werden:

```bash
# Option A: Von USB-Stick
cp -r /media/pi/USB-STICK/web ./web/

# Option B: Per SCP vom Entwicklungs-PC
scp -r user@pc:/pfad/zum/flutter/build/web ./web/
```

### 3. Installation starten

```bash
chmod +x install.sh
sudo ./install.sh
```

Nach dem Neustart startet der Pi automatisch im Kiosk-Modus.

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

# Detaillierter Status
/opt/lademeyer/proxy-status.sh
```

## API-Endpoints

| Endpoint | Methode | Beschreibung |
|----------|---------|--------------|
| `/` | GET | Service-Info |
| `/health` | GET | Health-Check |
| `/devices` | GET | Alle Geräte auflisten |
| `/devices` | POST | Gerät hinzufügen |
| `/devices/<id>` | DELETE | Gerät entfernen |
| `/devices/<id>/test` | POST | Verbindung testen |
| `/data` | GET | Akkumulierte Daten aller Geräte |
| `/data/<id>` | GET | Daten eines Geräts |
| `/fronius?ip=X.X.X.X` | GET | Legacy-Einzelabfrage |

## Fronius-Geräte verwalten

### Über die API

```bash
# Gerät hinzufügen
curl -X POST http://localhost:5000/devices \
     -H "Content-Type: application/json" \
     -d '{"ip": "192.168.200.51", "name": "Fronius Dach"}'

# Alle Geräte auflisten
curl http://localhost:5000/devices

# Akkumulierte Daten abrufen
curl http://localhost:5000/data

# Gerät löschen
curl -X DELETE http://localhost:5000/devices/fronius_1
```

### Über die App

1. SystemData V2 Screen öffnen
2. Zahnrad-Button in der AppBar klicken
3. IP eingeben und hinzufügen

## URLs nach Installation

| URL | Beschreibung |
|-----|--------------|
| http://localhost/ | Web-App |
| http://localhost/#/data_v2 | Energy Dashboard |
| http://localhost/api/fronius/ | Proxy-API (via Nginx) |
| http://localhost:5000/ | Proxy direkt |

## Update

```bash
cd /opt/lademeyer
git pull
sudo ./update.sh
```

## Fehlerbehebung

### Proxy startet nicht

```bash
# Logs prüfen
sudo journalctl -u lademeyer-proxy -n 50

# Manuell testen
python3 /opt/lademeyer/fronius_proxy.py
```

### Keine Fronius-Daten

```bash
# Proxy erreichbar?
curl http://localhost:5000/health

# Fronius direkt erreichbar?
curl http://192.168.x.x/solar_api/v1/GetPowerFlowRealtimeData.fcgi
```

### Kiosk beenden

```bash
lademeyer-stop
# oder
Alt + F4
# oder
pkill -f chromium
```

## Architektur

```
┌─────────────────────────────────────────────────────────────────────────┐
│  RASPBERRY PI                                                           │
│                                                                         │
│  ┌────────────────────┐     ┌─────────────────────────────────────────┐│
│  │ Python Proxy       │     │ Chromium (Kiosk-Modus)                  ││
│  │ localhost:5000     │◄────│                                         ││
│  │                    │     │ Flutter Web App                         ││
│  │ GET /devices       │────►│ - Sankey Energy Flow                    ││
│  │ POST /devices      │     │ - Fronius Config Widget                 ││
│  │ DELETE /devices    │     │ - Live-Daten anzeigen                   ││
│  │ GET /data          │     │                                         ││
│  └─────────┬──────────┘     └─────────────────────────────────────────┘│
│            │                                                            │
│            ▼                                                            │
│  ┌─────────────────────┐                                                │
│  │ Fronius Inverter 1  │  192.168.x.100                                │
│  │ Fronius Inverter 2  │  192.168.x.101   ← Akkumulierte Daten!       │
│  │ Fronius Inverter 3  │  192.168.x.102                                │
│  └─────────────────────┘                                                │
└─────────────────────────────────────────────────────────────────────────┘
```

## Lizenz

MIT License

## Support

Bei Fragen: [Issue erstellen](https://github.com/GumDeveloper/lm-fronius-proxy/issues)

