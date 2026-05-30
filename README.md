\# Desarrollo sobre Wazuh: Alertas, Respuesta Activa y Automatización SAI (NUT)



Este repositorio contiene los scripts y configuraciones desarrollados para mi Trabajo de Final de Ciclo (ASIR). El proyecto integra la seguridad lógica (SIEM/XDR) y la continuidad de negocio (tolerancia a fallos eléctricos) en un entorno virtualizado con Proxmox VE.



\## Componentes del Proyecto



\### 1. Integración Wazuh - Telegram API (`/Wazuh-Telegram`)

\* \*\*`custom-telegram.py`\*\*: Script en Python que captura las alertas críticas (Nivel 10+) generadas por Wazuh en formato JSON, las procesa y realiza una petición POST a la API REST de Telegram para enviar notificaciones \*push\* a los administradores.

\* \*\*`local\_rules.xml`\*\*: Reglas personalizadas para la detección de anomalías corporativas, incluyendo control de acceso a carpetas confidenciales fuera de horario laboral y detección de ataques de fuerza bruta (conectado con Respuesta Activa `firewall-drop`).



\### 2. Automatización y Gestión de Energía SAI (`/NUT-SAI-Proxmox`)

\* \*\*`nut\_sistema\_alertas\_nut.sh`\*\*: Script Bash avanzado (Builder) que compila dinámicamente un paquete `.deb`. Al instalarse en un nodo Proxmox:

&#x20;   \* Detecta hardware USB automáticamente (`nut-scanner`).

&#x20;   \* Configura los demonios de NUT y el relay SMTP de Postfix.

&#x20;   \* Orquesta un apagado seguro iterativo (`qm shutdown` / `pct shutdown`) de las máquinas virtuales y contenedores al alcanzar el umbral crítico de batería, finalizando con el apagado físico del host para evitar corrupción de datos.

&#x20;   \* Despliega un Dashboard interactivo en consola para monitorizar voltajes, baterías y demonios en tiempo real.



\## Tecnologías Utilizadas

`Proxmox VE` | `Wazuh` | `NUT (Network UPS Tools)` | `Python` | `Bash Scripting` | `Telegram API`

