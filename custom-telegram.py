#!/usr/bin/env python3
import sys
import json
import requests

# Leer el archivo JSON que envía Wazuh
alert_file = sys.argv[1]
with open(alert_file) as f:
    alert = json.load(f)

# Extraer la información importante del aviso
description = alert.get('rule', {}).get('description', 'Sin descripción')
level = alert.get('rule', {}).get('level', '0')
agent = alert.get('agent', {}).get('name', 'N/A')

# Preparar el mensaje que llegará al móvil
mensaje = f"🚨 ALERTA DE SEGURIDAD 🚨\nNivel: {level}\nEquipo: {agent}\nDetalle: {description}"

# Enviar a Telegram
# Valores reales de token y chat_id no expuestos por seguridad.
TOKEN = "TU_TOKEN_API_AQUI"
CHAT_ID = "TU_CHAT_ID_AQUI"
url = f"https://api.telegram.org/bot{TOKEN}/sendMessage"
payload = {"chat_id": CHAT_ID, "text": mensaje}

requests.post(url, data=payload)
