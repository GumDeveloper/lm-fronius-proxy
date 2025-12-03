#!/usr/bin/env python3
"""
🔋 FRONIUS MULTI-DEVICE PROXY FÜR RASPBERRY PI
==============================================

Features:
- Mehrere Fronius-Wechselrichter verwalten
- Daten akkumulieren (Solar, Grid, etc. zusammenrechnen)
- CORS-Problem lösen
- Konfiguration via REST-API (für Flutter App)
- Persistente Speicherung der Config

INSTALLATION:
    pip3 install flask requests

STARTEN:
    python3 fronius_proxy.py

ENDPOINTS:
    GET  /                     - Info
    GET  /health               - Health Check
    GET  /fronius?ip=X.X.X.X   - Einzelner Fronius (Legacy)
    GET  /devices              - Alle konfigurierten Geräte
    POST /devices              - Gerät hinzufügen
    DELETE /devices/<id>       - Gerät löschen
    GET  /data                 - Akkumulierte Daten aller Geräte
    GET  /data/<id>            - Daten eines Geräts
"""

from flask import Flask, request, jsonify
import requests
import time
import json
import os
import threading
import logging
from datetime import datetime
from typing import Dict, List, Optional

# ═══════════════════════════════════════════════════════════════════════════
# KONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════

CONFIG_FILE = os.path.expanduser('~/.fronius_proxy_config.json')
POLL_INTERVAL = 10  # Sekunden
PORT = 5000

# Logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s'
)
logger = logging.getLogger('fronius-proxy')

app = Flask(__name__)

# ═══════════════════════════════════════════════════════════════════════════
# DATEN-STRUKTUREN
# ═══════════════════════════════════════════════════════════════════════════

class FroniusDevice:
    """Repräsentiert einen Fronius-Wechselrichter"""
    
    def __init__(self, device_id: str, ip: str, name: str = None):
        self.id = device_id
        self.ip = ip
        self.name = name or f"Fronius {device_id}"
        self.is_reachable = False
        self.last_check = None
        self.last_data = None
        self.error_count = 0
    
    def to_dict(self) -> dict:
        return {
            'id': self.id,
            'ip': self.ip,
            'name': self.name,
            'is_reachable': self.is_reachable,
            'last_check': self.last_check.isoformat() if self.last_check else None,
            'error_count': self.error_count,
            'has_data': self.last_data is not None
        }
    
    def fetch_data(self) -> Optional[dict]:
        """Holt Daten vom Fronius"""
        url = f"http://{self.ip}/solar_api/v1/GetPowerFlowRealtimeData.fcgi"
        
        try:
            start = time.time()
            response = requests.get(url, timeout=10, headers={
                'User-Agent': 'Lademeyer-Proxy/3.0',
                'Accept': 'application/json'
            })
            response_time = round((time.time() - start) * 1000, 2)
            
            if response.status_code != 200:
                raise Exception(f"HTTP {response.status_code}")
            
            data = response.json()
            
            # Fronius-Daten extrahieren
            site = data.get('Body', {}).get('Data', {}).get('Site', {})
            inverters = data.get('Body', {}).get('Data', {}).get('Inverters', {})
            
            # Werte extrahieren (in kW)
            pv_power = abs(site.get('P_PV', 0) or 0) / 1000
            grid_power = (site.get('P_Grid', 0) or 0) / 1000  # negativ = Export
            load_power = abs(site.get('P_Load', 0) or 0) / 1000
            akku_power = (site.get('P_Akku', 0) or 0) / 1000
            
            # Batterie SOC (falls vorhanden)
            akku_soc = 0
            for inv_data in inverters.values():
                if 'SOC' in inv_data:
                    akku_soc = inv_data.get('SOC', 0)
                    break
            
            self.last_data = {
                'pv_power': pv_power,
                'grid_power': grid_power,
                'load_power': load_power,
                'akku_power': akku_power,
                'akku_soc': akku_soc,
                'response_time_ms': response_time,
                'timestamp': datetime.now().isoformat(),
                'raw': data
            }
            
            self.is_reachable = True
            self.last_check = datetime.now()
            self.error_count = 0
            
            logger.info(f"[OK] {self.name} ({self.ip}): PV={pv_power:.1f}kW, Grid={grid_power:.1f}kW")
            return self.last_data
            
        except Exception as e:
            self.is_reachable = False
            self.last_check = datetime.now()
            self.error_count += 1
            logger.warning(f"[FEHLER] {self.name} ({self.ip}): {e}")
            return None


class FroniusManager:
    """Verwaltet mehrere Fronius-Geräte"""
    
    def __init__(self):
        self.devices: Dict[str, FroniusDevice] = {}
        self._lock = threading.Lock()
        self._poll_thread = None
        self._running = False
        self.load_config()
    
    def load_config(self):
        """Lädt Konfiguration aus Datei oder erstellt Default-Config"""
        try:
            if os.path.exists(CONFIG_FILE):
                with open(CONFIG_FILE, 'r') as f:
                    config = json.load(f)
                    for device_data in config.get('devices', []):
                        device = FroniusDevice(
                            device_id=device_data['id'],
                            ip=device_data['ip'],
                            name=device_data.get('name')
                        )
                        self.devices[device.id] = device
                logger.info(f"[OK] {len(self.devices)} Geraete aus Config geladen")
            else:
                # DEFAULT-KONFIGURATION: Fronius bei 192.168.200.51
                logger.info("[INIT] Keine Config gefunden - erstelle Default-Konfiguration")
                default_device = FroniusDevice(
                    device_id='fronius_1',
                    ip='192.168.200.51',
                    name='Fronius Hauptgeraet'
                )
                self.devices['fronius_1'] = default_device
                self.save_config()
                logger.info(f"[OK] Default-Geraet konfiguriert: 192.168.200.51")
        except Exception as e:
            logger.error(f"Config laden fehlgeschlagen: {e}")
    
    def save_config(self):
        """Speichert Konfiguration in Datei"""
        try:
            config = {
                'devices': [
                    {'id': d.id, 'ip': d.ip, 'name': d.name}
                    for d in self.devices.values()
                ],
                'updated_at': datetime.now().isoformat()
            }
            with open(CONFIG_FILE, 'w') as f:
                json.dump(config, f, indent=2)
            logger.info(f"[SAVE] Config gespeichert ({len(self.devices)} Geraete)")
        except Exception as e:
            logger.error(f"Config speichern fehlgeschlagen: {e}")
    
    def add_device(self, ip: str, name: str = None) -> FroniusDevice:
        """Fügt ein neues Gerät hinzu"""
        with self._lock:
            # Generiere ID
            device_id = f"fronius_{len(self.devices) + 1}"
            while device_id in self.devices:
                device_id = f"fronius_{int(device_id.split('_')[1]) + 1}"
            
            device = FroniusDevice(device_id, ip, name)
            self.devices[device_id] = device
            self.save_config()
            
            # Sofort Daten holen
            device.fetch_data()
            
            logger.info(f"[ADD] Geraet hinzugefuegt: {device.name} ({ip})")
            return device
    
    def remove_device(self, device_id: str) -> bool:
        """Entfernt ein Gerät"""
        with self._lock:
            if device_id in self.devices:
                device = self.devices.pop(device_id)
                self.save_config()
                logger.info(f"[DEL] Geraet entfernt: {device.name}")
                return True
            return False
    
    def update_device(self, device_id: str, ip: str = None, name: str = None) -> Optional[FroniusDevice]:
        """Aktualisiert ein Gerät"""
        with self._lock:
            if device_id in self.devices:
                device = self.devices[device_id]
                if ip:
                    device.ip = ip
                if name:
                    device.name = name
                self.save_config()
                return device
            return None
    
    def get_accumulated_data(self) -> dict:
        """Akkumuliert Daten aller erreichbaren Geräte"""
        total = {
            'pv_power': 0.0,
            'grid_power': 0.0,
            'load_power': 0.0,
            'akku_power': 0.0,
            'akku_soc': 0.0,
            'device_count': 0,
            'reachable_count': 0,
            'devices': [],
            'timestamp': datetime.now().isoformat()
        }
        
        soc_values = []
        
        with self._lock:
            for device in self.devices.values():
                total['device_count'] += 1
                
                device_info = device.to_dict()
                
                if device.last_data:
                    total['reachable_count'] += 1
                    total['pv_power'] += device.last_data.get('pv_power', 0)
                    total['grid_power'] += device.last_data.get('grid_power', 0)
                    total['load_power'] += device.last_data.get('load_power', 0)
                    total['akku_power'] += device.last_data.get('akku_power', 0)
                    
                    soc = device.last_data.get('akku_soc', 0)
                    if soc > 0:
                        soc_values.append(soc)
                    
                    device_info['data'] = {
                        'pv_power': device.last_data.get('pv_power', 0),
                        'grid_power': device.last_data.get('grid_power', 0),
                        'load_power': device.last_data.get('load_power', 0),
                        'akku_power': device.last_data.get('akku_power', 0),
                        'akku_soc': device.last_data.get('akku_soc', 0),
                    }
                
                total['devices'].append(device_info)
        
        # SOC: Durchschnitt aller Batterien
        if soc_values:
            total['akku_soc'] = sum(soc_values) / len(soc_values)
        
        # Runden
        for key in ['pv_power', 'grid_power', 'load_power', 'akku_power', 'akku_soc']:
            total[key] = round(total[key], 2)
        
        return total
    
    def poll_all(self):
        """Holt Daten von allen Geräten"""
        with self._lock:
            devices = list(self.devices.values())
        
        for device in devices:
            device.fetch_data()
    
    def start_polling(self):
        """Startet Hintergrund-Polling"""
        if self._running:
            return
        
        self._running = True
        
        def poll_loop():
            while self._running:
                self.poll_all()
                time.sleep(POLL_INTERVAL)
        
        self._poll_thread = threading.Thread(target=poll_loop, daemon=True)
        self._poll_thread.start()
        logger.info(f"[POLL] Polling gestartet (alle {POLL_INTERVAL}s)")
    
    def stop_polling(self):
        """Stoppt Hintergrund-Polling"""
        self._running = False


# Globaler Manager
manager = FroniusManager()

# ═══════════════════════════════════════════════════════════════════════════
# CORS MIDDLEWARE
# ═══════════════════════════════════════════════════════════════════════════

@app.after_request
def add_cors_headers(response):
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization'
    return response

# ═══════════════════════════════════════════════════════════════════════════
# REST API ENDPOINTS
# ═══════════════════════════════════════════════════════════════════════════

@app.route('/', methods=['GET'])
def index():
    """Info-Seite"""
    return jsonify({
        'service': 'Lademeyer Fronius Multi-Device Proxy',
        'version': '3.0',
        'endpoints': {
            'GET /health': 'Health Check',
            'GET /devices': 'Alle Geräte auflisten',
            'POST /devices': 'Gerät hinzufügen ({"ip": "X.X.X.X", "name": "..."})',
            'DELETE /devices/<id>': 'Gerät entfernen',
            'PUT /devices/<id>': 'Gerät aktualisieren',
            'GET /data': 'Akkumulierte Daten aller Geräte',
            'GET /data/<id>': 'Daten eines Geräts',
            'GET /fronius?ip=X.X.X.X': 'Einzelabfrage (Legacy)'
        },
        'device_count': len(manager.devices)
    })


@app.route('/health', methods=['GET'])
def health():
    """Health Check"""
    data = manager.get_accumulated_data()
    return jsonify({
        'status': 'ok',
        'service': 'fronius-proxy',
        'version': '3.0',
        'devices': data['device_count'],
        'reachable': data['reachable_count'],
        'timestamp': datetime.now().isoformat()
    })


# ─────────────────────────────────────────────────────────────────────────
# GERÄTE-VERWALTUNG
# ─────────────────────────────────────────────────────────────────────────

@app.route('/devices', methods=['GET'])
def list_devices():
    """Liste aller konfigurierten Geräte"""
    devices = [d.to_dict() for d in manager.devices.values()]
    return jsonify({
        'success': True,
        'count': len(devices),
        'devices': devices
    })


@app.route('/devices', methods=['POST', 'OPTIONS'])
def add_device():
    """Neues Gerät hinzufügen"""
    if request.method == 'OPTIONS':
        return '', 200
    
    data = request.get_json() or {}
    ip = data.get('ip')
    name = data.get('name')
    
    if not ip:
        return jsonify({
            'success': False,
            'error': 'IP address required'
        }), 400
    
    # IP validieren
    import re
    if not re.match(r'^(\d{1,3}\.){3}\d{1,3}$', ip):
        return jsonify({
            'success': False,
            'error': 'Invalid IP format'
        }), 400
    
    # Prüfen ob IP schon existiert
    for device in manager.devices.values():
        if device.ip == ip:
            return jsonify({
                'success': False,
                'error': f'Device with IP {ip} already exists',
                'device': device.to_dict()
            }), 409
    
    device = manager.add_device(ip, name)
    return jsonify({
        'success': True,
        'device': device.to_dict()
    }), 201


@app.route('/devices/<device_id>', methods=['DELETE', 'OPTIONS'])
def remove_device(device_id):
    """Gerät entfernen"""
    if request.method == 'OPTIONS':
        return '', 200
    
    if manager.remove_device(device_id):
        return jsonify({
            'success': True,
            'message': f'Device {device_id} removed'
        })
    else:
        return jsonify({
            'success': False,
            'error': f'Device {device_id} not found'
        }), 404


@app.route('/devices/<device_id>', methods=['PUT', 'OPTIONS'])
def update_device(device_id):
    """Gerät aktualisieren"""
    if request.method == 'OPTIONS':
        return '', 200
    
    data = request.get_json() or {}
    device = manager.update_device(
        device_id,
        ip=data.get('ip'),
        name=data.get('name')
    )
    
    if device:
        return jsonify({
            'success': True,
            'device': device.to_dict()
        })
    else:
        return jsonify({
            'success': False,
            'error': f'Device {device_id} not found'
        }), 404


@app.route('/devices/<device_id>/test', methods=['POST', 'OPTIONS'])
def test_device(device_id):
    """Verbindung zu einem Gerät testen"""
    if request.method == 'OPTIONS':
        return '', 200
    
    if device_id not in manager.devices:
        return jsonify({
            'success': False,
            'error': f'Device {device_id} not found'
        }), 404
    
    device = manager.devices[device_id]
    data = device.fetch_data()
    
    return jsonify({
        'success': data is not None,
        'device': device.to_dict(),
        'data': data
    })


# ─────────────────────────────────────────────────────────────────────────
# DATEN-ABFRAGE
# ─────────────────────────────────────────────────────────────────────────

@app.route('/data', methods=['GET'])
def get_accumulated_data():
    """Akkumulierte Daten aller Geräte (für Sankey-Widget)"""
    data = manager.get_accumulated_data()
    
    # Format für XCompanySystemDataService
    return jsonify({
        'success': True,
        'solarPower': data['pv_power'],
        'gridPower': data['grid_power'],
        'housePower': data['load_power'],
        'batteryPower': data['akku_power'],
        'batterySOC': data['akku_soc'],
        'deviceCount': data['device_count'],
        'reachableCount': data['reachable_count'],
        'devices': data['devices'],
        'timestamp': data['timestamp'],
        'proxy_info': {
            'version': '3.0',
            'server': 'raspberry-pi'
        }
    })


@app.route('/data/<device_id>', methods=['GET'])
def get_device_data(device_id):
    """Daten eines einzelnen Geräts"""
    if device_id not in manager.devices:
        return jsonify({
            'success': False,
            'error': f'Device {device_id} not found'
        }), 404
    
    device = manager.devices[device_id]
    
    if device.last_data:
        return jsonify({
            'success': True,
            'device': device.to_dict(),
            'data': device.last_data
        })
    else:
        return jsonify({
            'success': False,
            'device': device.to_dict(),
            'error': 'No data available'
        })


# ─────────────────────────────────────────────────────────────────────────
# PROXY ENDPOINT (Flutter Web App kompatibel)
# ─────────────────────────────────────────────────────────────────────────

def _proxy_request(ip: str, endpoint: str = 'GetPowerFlowRealtimeData.fcgi'):
    """Interne Proxy-Funktion fuer Einzelabfragen"""
    # Temporaeres Device erstellen
    temp_device = FroniusDevice('temp', ip, 'Temp')
    # Custom endpoint setzen falls angegeben
    if endpoint != 'GetPowerFlowRealtimeData.fcgi':
        temp_device.api_endpoint = endpoint
    
    data = temp_device.fetch_data()
    
    if data:
        return jsonify({
            'success': True,
            'data': data.get('raw', {}),
            'proxy_info': {
                'source_ip': ip,
                'response_time_ms': data.get('response_time_ms'),
                'timestamp': data.get('timestamp'),
                'server': 'raspberry-pi-python-proxy'
            }
        })
    else:
        return jsonify({
            'success': False,
            'error': f'Connection to {ip} failed',
            'proxy_info': {
                'source_ip': ip,
                'attempted_url': f'http://{ip}/solar_api/v1/{endpoint}',
                'timestamp': datetime.now().isoformat(),
                'server': 'raspberry-pi-python-proxy'
            }
        }), 502


@app.route('/proxy', methods=['GET', 'OPTIONS'])
def proxy_endpoint():
    """
    Proxy-Endpoint fuer Flutter Web App.
    Ersetzt den PHP-Proxy (fronius_proxy.php).
    
    Verwendung: /proxy?ip=192.168.200.51&endpoint=GetPowerFlowRealtimeData.fcgi
    """
    if request.method == 'OPTIONS':
        return '', 200
    
    ip = request.args.get('ip')
    endpoint = request.args.get('endpoint', 'GetPowerFlowRealtimeData.fcgi')
    
    if not ip:
        return jsonify({
            'success': False,
            'error': 'Missing IP parameter',
            'usage': '/proxy?ip=192.168.200.51&endpoint=GetPowerFlowRealtimeData.fcgi'
        }), 400
    
    return _proxy_request(ip, endpoint)


@app.route('/fronius', methods=['GET', 'OPTIONS'])
def fronius_legacy():
    """Legacy-Endpoint fuer Einzelabfragen (Alias fuer /proxy)"""
    if request.method == 'OPTIONS':
        return '', 200
    
    ip = request.args.get('ip')
    endpoint = request.args.get('endpoint', 'GetPowerFlowRealtimeData.fcgi')
    
    if not ip:
        return jsonify({
            'success': False,
            'error': 'Missing IP parameter'
        }), 400
    
    return _proxy_request(ip, endpoint)


# ═══════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════

if __name__ == '__main__':
    print("""
===================================================================
  LADEMEYER FRONIUS MULTI-DEVICE PROXY v3.0
===================================================================

  Endpoints:
    http://localhost:5000/devices      - Geraete verwalten
    http://localhost:5000/data         - Akkumulierte Daten
    http://localhost:5000/health       - Health Check

  Default-Geraet: 192.168.200.51 (Fronius Hauptgeraet)
  Konfigurations-Datei: ~/.fronius_proxy_config.json

  Ctrl+C zum Beenden
===================================================================
    """)
    
    # Polling starten
    manager.start_polling()
    
    # Server starten
    app.run(
        host='0.0.0.0',
        port=PORT,
        debug=False,
        threaded=True
    )
