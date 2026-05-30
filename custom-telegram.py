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
TOKEN = "8616255944:AAG2rCUaRL26oPEr9sGv8pXMCNG3V7WgzNk"
CHAT_ID = "838464469"
url = f"https://api.telegram.org/bot{TOKEN}/sendMessage"
payload = {"chat_id": CHAT_ID, "text": mensaje}

requests.post(url, data=payload)
