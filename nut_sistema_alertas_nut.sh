#!/bin/bash
# ============================================================
#  Sistema Alertas NUT — Builder v5.9 (Proxmox Edition)
#
#  El .deb generado:
#    1. Detecta el SAI via nut-scanner -U
#    2. Permite seleccionar el driver manualmente
#    3. Configura NUT, Postfix y alertas por correo
#    4. Crea /INFORMATICA/SCRIPTS_AUTOMATIZADOS/SAI/ si no existe
#       e instala monitor-sai.sh en esa ruta
#    5. Se autoeliminará al terminar la instalación
#
#  En el cliente solo hace falta:
#    apt install ./nut-alertas-sistema-alertas-nut.deb
# ============================================================

set -e

mkdir -p /root/nut-alertas-final/DEBIAN

# ── CONTROL ──────────────────────────────────────────────────────────────────
cat << 'EOF' > /root/nut-alertas-final/DEBIAN/control
Package: nut-alertas-sistema-alertas-nut
Version: 5.9
Architecture: all
Maintainer: Sistema alertas nut <avisos@informaxdns.net>
Depends: nut, nut-client, nut-server, postfix, mailutils, libsasl2-modules, whiptail, util-linux
Description: Sistema corporativo de alertas SAI via NUT para Proxmox (Sistema alertas nut v5.9).
 Deteccion automatica del hardware del SAI con seleccion manual de driver. 
 Compatible con APC, Eaton, Salicru, Riello y otros.
 Notificaciones por correo ante cortes de luz, bateria critica y apagado seguro.
 Apagado ordenado de VMs y contenedores Proxmox antes de apagar el host.
 Incluye monitor-sai.sh en /INFORMATICA/SCRIPTS_AUTOMATIZADOS/SAI/.
EOF

# ── POSTINST ─────────────────────────────────────────────────────────────────
cat << 'POSTINST_EOF' > /root/nut-alertas-final/DEBIAN/postinst
#!/bin/bash
export TERM=linux
exec < /dev/tty

if ! tty -s; then
    echo "ERROR: Este instalador requiere una terminal interactiva." >&2
    exit 1
fi

SCRIPT_DIR="/INFORMATICA/SCRIPTS_AUTOMATIZADOS/SAI"

echo ""
echo "  Lanzando asistente de configuración de NUT..."
echo ""
sleep 1

# ─────────────────────────────────────────────────────────────────────────────
# Preparar base NUT
# ─────────────────────────────────────────────────────────────────────────────
whiptail --title "Preparando NUT" \
    --infobox "Deteniendo servicios anteriores y preparando la configuración..." 6 60
sleep 1

upsdrvctl stop >/dev/null 2>&1 || true
systemctl stop nut-client nut-server >/dev/null 2>&1 || true
mkdir -p /etc/nut

echo "MODE=standalone" > /etc/nut/nut.conf
chmod 640 /etc/nut/nut.conf
chown root:nut /etc/nut/nut.conf >/dev/null 2>&1 || true

# ─────────────────────────────────────────────────────────────────────────────
# Funciones auxiliares
# ─────────────────────────────────────────────────────────────────────────────
es_email_valido()  { echo "$1" | grep -qE '^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$'; }
es_puerto_valido() { echo "$1" | grep -qE '^[0-9]+$' && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; }
es_entero_valido() { echo "$1" | grep -qE '^[0-9]+$' && [ "$1" -ge 1 ] && [ "$1" -le 99 ]; }

# ─────────────────────────────────────────────────────────────────────────────
# DETECCIÓN AUTOMÁTICA DEL SAI via nut-scanner
# ─────────────────────────────────────────────────────────────────────────────
whiptail --title "Detectando SAI..." \
    --infobox "Escaneando puertos USB en busca del SAI conectado...\nEsto puede tardar unos segundos." 7 65
sleep 1

NUT_SCANNER_BIN=$(command -v nut-scanner 2>/dev/null || command -v nut-scan 2>/dev/null || echo "")

SCAN_OUTPUT=""
if [ -n "$NUT_SCANNER_BIN" ]; then
    SCAN_OUTPUT=$($NUT_SCANNER_BIN -U 2>/dev/null || echo "")
fi

UPS_PORT="auto"
UPS_VENDORID=""
UPS_PRODUCTID=""
UPS_DESC=""

if [ -n "$SCAN_OUTPUT" ] && echo "$SCAN_OUTPUT" | grep -q "driver"; then
    UPS_PORT=$(echo      "$SCAN_OUTPUT" | grep -m1 'port'      | awk -F'"' '{print $2}')
    UPS_VENDORID=$(echo  "$SCAN_OUTPUT" | grep -m1 'vendorid'  | awk -F'"' '{print $2}')
    UPS_PRODUCTID=$(echo "$SCAN_OUTPUT" | grep -m1 'productid' | awk -F'"' '{print $2}')
    SCAN_VENDOR=$(echo   "$SCAN_OUTPUT" | grep -m1 'vendor '   | awk -F'"' '{print $2}')
    SCAN_PRODUCT=$(echo  "$SCAN_OUTPUT" | grep -m1 'product '  | awk -F'"' '{print $2}')
    UPS_DESC="${SCAN_VENDOR} ${SCAN_PRODUCT}"

    whiptail --title "SAI detectado" --msgbox \
"Se ha identificado el siguiente dispositivo USB:

  Fabricante : ${SCAN_VENDOR:-desconocido}
  Modelo     : ${SCAN_PRODUCT:-desconocido}
  Puerto     : ${UPS_PORT:-auto}
  VendorID   : ${UPS_VENDORID:-N/A}
  ProductID  : ${UPS_PRODUCTID:-N/A}

A continuación selecciona el driver manualmente." \
    16 65
else
    whiptail --title "SAI no detectado automáticamente" --msgbox \
"No se encontró ningún SAI USB de forma automática.

Comprueba que:
  • El cable USB del SAI está conectado al servidor
  • El SAI está encendido

A continuación selecciona el driver manualmente." \
    12 65
fi

# ─────────────────────────────────────────────────────────────────────────────
# SELECCIÓN MANUAL DEL DRIVER
# ─────────────────────────────────────────────────────────────────────────────
UPS_DRIVER=$(whiptail --title "Seleccionar driver del SAI" \
    --menu "Selecciona el driver que corresponde a tu SAI:" \
    17 70 7 \
    "usbhid-ups"   "APC, Eaton, Powervar, Tripplite, Powercom (HID estándar)" \
    "nutdrv_qx"    "Salicru, Riello, PowerWalker (chip Cypress/Megatec)" \
    "blazer_usb"   "SAIs genéricos Megatec/Q1 (modelos antiguos)" \
    "richcomm_usb" "Richcomm USB" \
    "powercom-hid" "Powercom HID" \
    "gamatronic"   "Gamatronic" \
    "genericups"   "Genérico — puerto serie RS232" \
    3>&1 1>&2 2>&3) || exit 1

# ─────────────────────────────────────────────────────────────────────────────
# Nombre del SAI
# ─────────────────────────────────────────────────────────────────────────────
while true; do
    UPS_NAME=$(whiptail --title "Nombre del SAI en NUT" \
        --inputbox "Nombre que se asignará al SAI en NUT.\n(Solo letras, números y guiones. Ej: salicru, apc-oficina, ups-rack)" \
        10 65 "sai" 3>&1 1>&2 2>&3) || exit 1
    echo "$UPS_NAME" | grep -qE '^[a-zA-Z0-9_-]+$' && break
    whiptail --title "Nombre no válido" \
        --msgbox "El nombre solo puede contener letras, números, guiones y guiones bajos. Sin espacios." \
        8 65
done

# ─────────────────────────────────────────────────────────────────────────────
# Pasos 1-7: Configuración SMTP y umbrales
# ─────────────────────────────────────────────────────────────────────────────
while true; do
    SMTP_SERVER=$(whiptail --title "Paso 1 de 7 — Servidor SMTP" \
        --inputbox "Dirección del servidor de correo saliente (relay):" \
        10 65 "nodo.informax.es" 3>&1 1>&2 2>&3) || exit 1
    [ -n "$SMTP_SERVER" ] && break
    whiptail --title "Campo obligatorio" --msgbox "El servidor SMTP no puede estar vacío." 7 50
done

while true; do
    SMTP_PORT=$(whiptail --title "Paso 2 de 7 — Puerto SMTP" \
        --inputbox "Puerto del servidor de correo:\n(587 para TLS · 465 para SSL)" \
        10 65 "587" 3>&1 1>&2 2>&3) || exit 1
    es_puerto_valido "$SMTP_PORT" && break
    whiptail --title "Puerto no válido" --msgbox "Introduce un número de puerto entre 1 y 65535." 7 50
done

while true; do
    SMTP_USER=$(whiptail --title "Paso 3 de 7 — Usuario SMTP" \
        --inputbox "Dirección de correo para autenticación en el servidor:" \
        10 65 "avisos@informaxdns.net" 3>&1 1>&2 2>&3) || exit 1
    es_email_valido "$SMTP_USER" && break
    whiptail --title "Correo no válido" --msgbox "Introduce una dirección de correo electrónico válida." 7 55
done

while true; do
    SMTP_PASS=$(whiptail --title "Paso 4 de 7 — Contraseña SMTP" \
        --passwordbox "Contraseña de la cuenta de correo:" \
        10 65 3>&1 1>&2 2>&3) || exit 1
    [ -n "$SMTP_PASS" ] && break
    whiptail --title "Campo obligatorio" --msgbox "La contraseña no puede estar vacía." 7 50
done
SMTP_PASS_ESCAPED=$(echo "$SMTP_PASS" | sed 's/:/\\:/g')

while true; do
    DEST_EMAIL=$(whiptail --title "Paso 5 de 7 — Correo de destino" \
        --inputbox "Dirección de correo donde se enviarán las alertas del cliente:" \
        10 65 "avisos@informaxdns.net" 3>&1 1>&2 2>&3) || exit 1
    es_email_valido "$DEST_EMAIL" && break
    whiptail --title "Correo no válido" --msgbox "Introduce una dirección de correo electrónico válida." 7 55
done

while true; do
    BATT_WARN=$(whiptail --title "Paso 6 de 7 — Umbral de aviso" \
        --inputbox "Porcentaje de batería para el PRIMER aviso por correo.\n(Recomendado: 50)" \
        10 65 "50" 3>&1 1>&2 2>&3) || exit 1
    es_entero_valido "$BATT_WARN" && break
    whiptail --title "Valor no válido" --msgbox "Introduce un número entero entre 1 y 99." 7 50
done

while true; do
    BATT_CRIT=$(whiptail --title "Paso 7 de 7 — Umbral de apagado" \
        --inputbox "Porcentaje de batería al que el servidor debe APAGARSE.\n(Recomendado: 20 · Debe ser menor que el umbral de aviso)" \
        10 65 "20" 3>&1 1>&2 2>&3) || exit 1
    es_entero_valido "$BATT_CRIT" || {
        whiptail --title "Valor no válido" --msgbox "Introduce un número entero entre 1 y 99." 7 50
        continue
    }
    [ "$BATT_WARN" -gt "$BATT_CRIT" ] && break
    whiptail --title "Error de configuración" --msgbox \
        "El umbral de aviso ($BATT_WARN%) debe ser mayor que el de apagado ($BATT_CRIT%).\n\nEjemplo correcto: Aviso = 50% · Apagado = 20%" \
        9 65
done

whiptail --title "Instalando..." \
    --infobox "Generando configuración de NUT — Sistema Alertas NUT v5.9...\nSAI: $UPS_NAME ($UPS_DRIVER)" 6 65
sleep 1

# ─────────────────────────────────────────────────────────────────────────────
# Guardar nombre del SAI
# ─────────────────────────────────────────────────────────────────────────────
echo "$UPS_NAME" > /etc/nut/ups_name
chmod 644 /etc/nut/ups_name

# ─────────────────────────────────────────────────────────────────────────────
# Regla UDEV
# ─────────────────────────────────────────────────────────────────────────────
if [ -n "$UPS_VENDORID" ] && [ -n "$UPS_PRODUCTID" ]; then
    echo "SUBSYSTEM==\"usb\", ATTRS{idVendor}==\"${UPS_VENDORID}\", ATTRS{idProduct}==\"${UPS_PRODUCTID}\", MODE=\"0666\", GROUP=\"nut\"" \
        > /etc/udev/rules.d/99-nut-${UPS_NAME}.rules
    udevadm control --reload-rules >/dev/null 2>&1 || true
    udevadm trigger >/dev/null 2>&1 || true
fi

# ─────────────────────────────────────────────────────────────────────────────
# ups.conf
# ─────────────────────────────────────────────────────────────────────────────
{
    echo "[${UPS_NAME}]"
    echo "        driver = \"${UPS_DRIVER}\""
    echo "        port = \"${UPS_PORT}\""
    [ -n "$UPS_VENDORID" ]  && echo "        vendorid = \"${UPS_VENDORID}\""
    [ -n "$UPS_PRODUCTID" ] && echo "        productid = \"${UPS_PRODUCTID}\""
    echo "        desc = \"${UPS_DESC:-SAI Local} - Gestionado por Sistema alertas nut\""
    echo "        override.battery.charge.low = ${BATT_CRIT}"
} > /etc/nut/ups.conf
chmod 640 /etc/nut/ups.conf
chown root:nut /etc/nut/ups.conf >/dev/null 2>&1 || true

# ─────────────────────────────────────────────────────────────────────────────
# upsd.conf
# ─────────────────────────────────────────────────────────────────────────────
printf "LISTEN 127.0.0.1 3493\nLISTEN ::1 3493\n" > /etc/nut/upsd.conf
chmod 640 /etc/nut/upsd.conf
chown root:nut /etc/nut/upsd.conf >/dev/null 2>&1 || true

# ─────────────────────────────────────────────────────────────────────────────
# upsd.users
# ─────────────────────────────────────────────────────────────────────────────
NUT_PASS=$(openssl rand -hex 20)
cat > /etc/nut/upsd.users << EOF_USERS
[localmon]
    password = ${NUT_PASS}
    upsmon master
EOF_USERS
chmod 640 /etc/nut/upsd.users
chown root:nut /etc/nut/upsd.users >/dev/null 2>&1 || true

# ─────────────────────────────────────────────────────────────────────────────
# upsmon.conf
# ─────────────────────────────────────────────────────────────────────────────
cat > /etc/nut/upsmon.conf << EOF_MONITOR
MONITOR ${UPS_NAME}@localhost 1 localmon ${NUT_PASS} master

MINSUPPLIES    1
SHUTDOWNCMD    "/etc/nut/proxmox_shutdown.sh"
POWERDOWNFLAG  /etc/killpower
NOTIFYCMD      /etc/nut/notify.sh

POLLFREQ       5
POLLFREQALERT  5
HOSTSYNC       15
DEADTIME       15
NOCOMMWARNTIME 300
RBWARNTIME     43200
FINALDELAY     5

NOTIFYFLAG ONBATT    SYSLOG+WALL+EXEC
NOTIFYFLAG ONLINE    SYSLOG+EXEC
NOTIFYFLAG LOWBATT   SYSLOG+WALL+EXEC
NOTIFYFLAG SHUTDOWN  SYSLOG+WALL+EXEC
NOTIFYFLAG FSD       SYSLOG+WALL+EXEC
NOTIFYFLAG REPLBATT  SYSLOG+EXEC
NOTIFYFLAG COMMOK    SYSLOG+EXEC
NOTIFYFLAG COMMBAD   SYSLOG+EXEC
EOF_MONITOR
chmod 640 /etc/nut/upsmon.conf
chown root:nut /etc/nut/upsmon.conf >/dev/null 2>&1 || true

# ─────────────────────────────────────────────────────────────────────────────
# Postfix
# ─────────────────────────────────────────────────────────────────────────────
echo "[${SMTP_SERVER}]:${SMTP_PORT} ${SMTP_USER}:${SMTP_PASS_ESCAPED}" > /etc/postfix/sasl_passwd
chmod 600 /etc/postfix/sasl_passwd
postmap /etc/postfix/sasl_passwd

echo "/.*/ ${SMTP_USER}" > /etc/postfix/smtp_generic
postmap /etc/postfix/smtp_generic

POSTFIX_VER=$(postconf -d mail_version 2>/dev/null | awk '{print $3}' | cut -d. -f1-2)
postconf -e "relayhost = [${SMTP_SERVER}]:${SMTP_PORT}"
postconf -e "inet_protocols = ipv4"
postconf -e "smtp_sasl_auth_enable = yes"
postconf -e "smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd"
postconf -e "smtp_sasl_security_options = noanonymous"
postconf -e "smtp_tls_security_level = encrypt"
postconf -e "smtp_tls_wrappermode = yes"
postconf -e "smtp_tls_session_cache_database = btree:\${data_directory}/smtp_scache"
postconf -e "smtp_tls_session_cache_timeout = 3600s"
postconf -e "compatibility_level = ${POSTFIX_VER}"
postconf -e "smtputf8_enable = no"
postconf -e "smtp_generic_maps = hash:/etc/postfix/smtp_generic"

# ── UTF-8 encoding para correos ──
postconf -e "mail_name = Sistema Alertas NUT"
printf '/^Content-Type:.*charset/d
' > /etc/postfix/mime_header_checks
postmap /etc/postfix/mime_header_checks 2>/dev/null || true
postconf -e "mime_header_checks = regexp:/etc/postfix/mime_header_checks"

# ─────────────────────────────────────────────────────────────────────────────
# Directorios de trabajo NUT
# ─────────────────────────────────────────────────────────────────────────────
mkdir -p /var/lib/nut /var/run/nut
chown -R nut:nut /var/lib/nut /var/run/nut >/dev/null 2>&1 || true
chmod 750 /var/lib/nut /var/run/nut
echo "d /var/run/nut 0750 nut nut -" > /etc/tmpfiles.d/nut-alertas-sistema-alertas-nut.conf
systemd-tmpfiles --create /etc/tmpfiles.d/nut-alertas-sistema-alertas-nut.conf 2>/dev/null || true

# ─────────────────────────────────────────────────────────────────────────────
# proxmox_shutdown.sh
# ─────────────────────────────────────────────────────────────────────────────
cat > /etc/nut/proxmox_shutdown.sh << 'SCRIPT_SD'
#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

if [ -z "$NUT_DETACHED" ]; then
    export NUT_DETACHED=1
    nohup setsid "$0" "$@" >/dev/null 2>&1 &
    exit 0
fi

logger -t "nut-alertas-sistema-alertas-nut" "APAGADO: iniciando secuencia de apagado ordenado de Proxmox"
sleep 15

if command -v qm >/dev/null 2>&1; then
    for VMID in $(qm list 2>/dev/null | awk 'NR>1 && $3=="running" {print $1}'); do
        logger -t "nut-alertas-sistema-alertas-nut" "Apagando VM $VMID"
        qm shutdown "$VMID" --timeout 60 >/dev/null 2>&1 &
    done
fi

if command -v pct >/dev/null 2>&1; then
    for CTID in $(pct list 2>/dev/null | awk 'NR>1 && $2=="running" {print $1}'); do
        logger -t "nut-alertas-sistema-alertas-nut" "Apagando CT $CTID"
        pct shutdown "$CTID" --timeout 60 >/dev/null 2>&1 &
    done
fi

WAITED=0
while [ $WAITED -lt 120 ]; do
    VMS_ON=0; CTS_ON=0
    command -v qm  >/dev/null 2>&1 && VMS_ON=$(qm  list 2>/dev/null | awk 'NR>1 && $3=="running"' | wc -l)
    command -v pct >/dev/null 2>&1 && CTS_ON=$(pct list 2>/dev/null | awk 'NR>1 && $2=="running"' | wc -l)
    [ $((VMS_ON + CTS_ON)) -eq 0 ] && break
    logger -t "nut-alertas-sistema-alertas-nut" "Esperando: $VMS_ON VM(s) y $CTS_ON CT(s) activos..."
    sleep 5; WAITED=$((WAITED + 5))
done

logger -t "nut-alertas-sistema-alertas-nut" "Apagando el host Proxmox."
/sbin/shutdown -h +0
SCRIPT_SD
chmod +x /etc/nut/proxmox_shutdown.sh

# ─────────────────────────────────────────────────────────────────────────────
# notify.sh
# ─────────────────────────────────────────────────────────────────────────────
cat > /etc/nut/notify.sh << SCRIPT_NOTIFY
#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

UPS_NAME=\$(cat /etc/nut/ups_name 2>/dev/null)
[ -z "\$UPS_NAME" ] && exit 0

HOST=\$(hostname)
BATERIA=\$(timeout 5 upsc "\$UPS_NAME" battery.charge 2>/dev/null || echo "desconocida")
TIMESTAMP=\$(date '+%d/%m/%Y %H:%M:%S')
FLAG_DIR="/var/lib/nut"

enviar_correo() {
    {
        echo "Servidor : \$HOST"
        echo "Evento   : \$NOTIFYTYPE"
        echo "Batería  : \${BATERIA}%"
        echo "Hora     : \$TIMESTAMP"
        echo ""
        echo "\$2"
        echo ""
        echo "---"
        echo "Sistema de alertas SAI — Sistema alertas nut"
    } | mail -a "From: Alertas SAI Sistema alertas nut <${SMTP_USER}>" \
              -a "Content-Type: text/plain; charset=UTF-8" \
              -a "MIME-Version: 1.0" \
              -s "[\$HOST] \$1 - Bateria: \${BATERIA}%" \
              "${DEST_EMAIL}"
    postfix flush >/dev/null 2>&1 || true
}

case "\$NOTIFYTYPE" in
    ONBATT)
        [ -f "\${FLAG_DIR}/estado_onbatt" ] && exit 0
        touch "\${FLAG_DIR}/estado_onbatt"
        enviar_correo "AVISO — Corte de luz detectado" \
"El SAI ha entrado en modo batería. El servidor está funcionando con batería.

Aviso de batería al  : ${BATT_WARN}%
Apagado automático al: ${BATT_CRIT}%"
        ;;
    ONLINE)
        rm -f "\${FLAG_DIR}/estado_onbatt" \
              "\${FLAG_DIR}/aviso_bateria_enviado" \
              "\${FLAG_DIR}/estado_critico" \
              "\${FLAG_DIR}/aviso_replbatt_enviado"
        enviar_correo "INFO — Suministro eléctrico restaurado" \
"El suministro eléctrico ha vuelto. El SAI está cargando la batería."
        ;;
    LOWBATT)
        enviar_correo "CRÍTICO — Batería al límite" \
"El SAI ha alcanzado el nivel crítico de batería.
El servidor iniciará el apagado seguro en breve."
        ;;
    SHUTDOWN)
        enviar_correo "CRÍTICO — Apagado del servidor iniciado" \
"Las VMs y contenedores de Proxmox se están apagando ordenadamente.
El servidor arrancará automáticamente cuando vuelva la luz."
        ;;
    FSD)
        enviar_correo "CRÍTICO — Apagado de emergencia por NUT" \
"El sistema NUT ha ordenado un apagado de emergencia (FSD)."
        ;;
    REPLBATT)
        [ -f "\${FLAG_DIR}/aviso_replbatt_enviado" ] && exit 0
        touch "\${FLAG_DIR}/aviso_replbatt_enviado"
        enviar_correo "AVISO — Batería del SAI necesita reemplazo" \
"El SAI indica que su batería interna debe ser reemplazada.
El sistema seguirá funcionando pero con protección reducida ante cortes."
        ;;
    COMMBAD)
        # Ignorar COMMBAD durante los primeros 120s de uptime (arranque del sistema)
        UPTIME_SECS=\$(awk '{print int(\$1)}' /proc/uptime 2>/dev/null || echo 999)
        if [ "\$UPTIME_SECS" -lt 120 ]; then
            logger -t "nut-alertas-sistema-alertas-nut" "COMMBAD ignorado — sistema arrancando (uptime: \${UPTIME_SECS}s)"
            exit 0
        fi
        enviar_correo "AVISO - Perdida de comunicacion con el SAI" \
"Se ha perdido la comunicacion con el SAI.
No es posible monitorizar el estado de la bateria.
Comprueba el cable USB del SAI."
        ;;
    COMMOK)
        enviar_correo "INFO — Comunicación con el SAI restaurada" \
"La comunicación con el SAI se ha restaurado correctamente."
        ;;
    *)
        exit 0
        ;;
esac
SCRIPT_NOTIFY
chmod +x /etc/nut/notify.sh

# ─────────────────────────────────────────────────────────────────────────────
# aviso_intermedio.sh
# ─────────────────────────────────────────────────────────────────────────────
cat > /etc/nut/aviso_intermedio.sh << SCRIPT_AVISO
#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

UPS_NAME=\$(cat /etc/nut/ups_name 2>/dev/null)
[ -z "\$UPS_NAME" ] && exit 0

FLAG_DIR="/var/lib/nut"
FLAG_AVISO="\${FLAG_DIR}/aviso_bateria_enviado"
FLAG_ONBATT="\${FLAG_DIR}/estado_onbatt"
FLAG_CRITICO="\${FLAG_DIR}/estado_critico"

BATERIA_RAW=\$(timeout 5 upsc "\$UPS_NAME" battery.charge 2>/dev/null)
ESTADO=\$(timeout 5 upsc "\$UPS_NAME" ups.status 2>/dev/null)

[ -z "\$BATERIA_RAW" ] && exit 0
BATERIA_ENTERA=\${BATERIA_RAW%.*}
[[ "\$BATERIA_ENTERA" =~ ^[0-9]+\$ ]] || exit 0

if [[ "\$ESTADO" == *"OB"* ]]; then

    touch "\$FLAG_ONBATT"
    HOST=\$(hostname)
    TIMESTAMP=\$(date '+%d/%m/%Y %H:%M:%S')

    if [ "\$BATERIA_ENTERA" -le "${BATT_WARN}" ] && [ ! -f "\$FLAG_AVISO" ]; then
        {
            echo "Servidor : \$HOST"
            echo "Batería  : \${BATERIA_RAW}%"
            echo "Umbral   : ${BATT_WARN}%"
            echo "Hora     : \$TIMESTAMP"
            echo ""
            echo "El SAI ha bajado del umbral de aviso configurado."
            echo "Si el corte de luz continúa, el servidor se apagará al llegar al ${BATT_CRIT}%."
            echo ""
            echo "---"
            echo "Sistema de alertas SAI — Sistema alertas nut"
        } | mail -a "From: Alertas SAI Sistema alertas nut <${SMTP_USER}>" \
                      -a "Content-Type: text/plain; charset=UTF-8" \
                      -a "MIME-Version: 1.0" \
                  -s "[\$HOST] Aviso bateria - \${BATERIA_RAW}% (umbral: ${BATT_WARN}%)" \
                  "${DEST_EMAIL}"
        postfix flush >/dev/null 2>&1 || true
        touch "\$FLAG_AVISO"
        logger -t "nut-alertas-sistema-alertas-nut" "Aviso de batería enviado: \${BATERIA_RAW}% (umbral: ${BATT_WARN}%)"
    fi

    if [ "\$BATERIA_ENTERA" -le "${BATT_CRIT}" ] && [ ! -f "\$FLAG_CRITICO" ]; then
        touch "\$FLAG_CRITICO"
        logger -t "nut-alertas-sistema-alertas-nut" "WATCHDOG: nivel crítico (\${BATERIA_ENTERA}% <= ${BATT_CRIT}%). Forzando apagado."
        {
            echo "Servidor : \$HOST"
            echo "Batería  : \${BATERIA_RAW}%"
            echo "Hora     : \$TIMESTAMP"
            echo ""
            echo "Nivel CRÍTICO alcanzado. Iniciando apagado de emergencia."
            echo ""
            echo "---"
            echo "Sistema de alertas SAI — Sistema alertas nut"
        } | mail -a "From: Alertas SAI Sistema alertas nut <${SMTP_USER}>" \
                      -a "Content-Type: text/plain; charset=UTF-8" \
                      -a "MIME-Version: 1.0" \
                  -s "[\$HOST] CRITICO - Apagado de emergencia (\${BATERIA_RAW}%)" \
                  "${DEST_EMAIL}"
        postfix flush >/dev/null 2>&1 || true
        sleep 3
        NUT_DETACHED=1 nohup setsid /etc/nut/proxmox_shutdown.sh >/dev/null 2>&1 &
    fi

elif [[ "\$ESTADO" == *"OL"* ]]; then
    rm -f "\$FLAG_AVISO" "\$FLAG_CRITICO" "\$FLAG_ONBATT"
fi
SCRIPT_AVISO
chmod +x /etc/nut/aviso_intermedio.sh

# ─────────────────────────────────────────────────────────────────────────────
# arranque.sh
# ─────────────────────────────────────────────────────────────────────────────
cat > /etc/nut/arranque.sh << SCRIPT_ARRANQUE
#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

rm -f /var/lib/nut/estado_onbatt \
      /var/lib/nut/aviso_bateria_enviado \
      /var/lib/nut/estado_critico \
      /var/lib/nut/aviso_replbatt_enviado

timeout 120 bash -c 'until systemctl is-active --quiet postfix; do sleep 5; done' || exit 1

UPS_NAME=\$(cat /etc/nut/ups_name 2>/dev/null || echo "desconocido")
HOST=\$(hostname)
TIMESTAMP=\$(date '+%d/%m/%Y %H:%M:%S')
BATERIA=\$(timeout 5 upsc "\$UPS_NAME" battery.charge 2>/dev/null || echo "desconocida")
ESTADO=\$(timeout 5 upsc "\$UPS_NAME" ups.status 2>/dev/null || echo "desconocido")

{
    echo "Servidor : \$HOST"
    echo "Hora     : \$TIMESTAMP"
    echo "SAI      : \$UPS_NAME"
    echo "Batería  : \${BATERIA}%"
    echo "Estado   : \$ESTADO"
    echo ""
    echo "El servidor ha arrancado correctamente y todos los servicios están operativos."
    echo "Si hubo un apagado de emergencia previo, el suministro eléctrico se ha restablecido."
    echo ""
    echo "---"
    echo "Sistema de alertas SAI — Sistema alertas nut"
} | mail -a "From: Alertas SAI Sistema alertas nut <${SMTP_USER}>" \
              -a "Content-Type: text/plain; charset=UTF-8" \
              -a "MIME-Version: 1.0" \
         -s "[\$HOST] INFO - Servidor iniciado y operativo" \
         "${DEST_EMAIL}"
postfix flush >/dev/null 2>&1 || true
SCRIPT_ARRANQUE
chmod +x /etc/nut/arranque.sh

# ─────────────────────────────────────────────────────────────────────────────
# Cron
# ─────────────────────────────────────────────────────────────────────────────
if ! crontab -l 2>/dev/null | grep -q "/etc/nut/aviso_intermedio.sh"; then
    (crontab -l 2>/dev/null
     echo "* * * * * /usr/bin/flock -n /tmp/nut-aviso.lock /etc/nut/aviso_intermedio.sh >/dev/null 2>&1"
    ) | crontab -
fi
if ! crontab -l 2>/dev/null | grep -q "/etc/nut/arranque.sh"; then
    (crontab -l 2>/dev/null
     echo "@reboot /etc/nut/arranque.sh >/dev/null 2>&1"
    ) | crontab -
fi

# ─────────────────────────────────────────────────────────────────────────────
# Arranque de servicios NUT
# ─────────────────────────────────────────────────────────────────────────────
systemctl daemon-reload >/dev/null 2>&1 || true

if systemctl list-unit-files 2>/dev/null | grep -q "nut-driver-enumerator"; then
    systemctl restart nut-driver-enumerator >/dev/null 2>&1 || true
    sleep 2
fi

systemctl enable nut-server nut-client >/dev/null 2>&1 || true
systemctl start "nut-driver@${UPS_NAME}.service" >/dev/null 2>&1 || true
sleep 3
systemctl restart nut-server  >/dev/null 2>&1 || true
sleep 2
systemctl restart nut-client  >/dev/null 2>&1 || true
sleep 2
systemctl restart postfix     >/dev/null 2>&1 || true

# ─────────────────────────────────────────────────────────────────────────────
# Re-aplicar configuración SMTP tras reinicio de Postfix
# ─────────────────────────────────────────────────────────────────────────────
postconf -e "relayhost = [${SMTP_SERVER}]:${SMTP_PORT}"
postconf -e "smtp_tls_wrappermode = yes"
postconf -e "smtp_tls_security_level = encrypt"
postconf -e "mydestination = localhost"
postfix reload >/dev/null 2>&1 || true

# ─────────────────────────────────────────────────────────────────────────────
# Instalar monitor-sai.sh en la ruta corporativa
# ─────────────────────────────────────────────────────────────────────────────
mkdir -p "$SCRIPT_DIR"

cat > "${SCRIPT_DIR}/monitor-sai.sh" << 'MONITOR_EOF'
#!/bin/bash
# ============================================================
#  Sistema Alertas NUT — Monitor SAI en tiempo real v5.9.2
#  Uso: bash monitor-sai.sh
#  Refresco automático cada 3s sin parpadeo.
# ============================================================

# ── Colores ANSI ─────────────────────────────────────────────────────────────
R='\033[0;31m'
RB='\033[1;31m'
Y='\033[0;33m'
YB='\033[1;33m'
G='\033[0;32m'
GB='\033[1;32m'
B='\033[0;34m'
C='\033[0;36m'
CB='\033[1;36m'
W='\033[1;37m'
D='\033[0;90m'
N='\033[0m'

REFRESCO=3

if ! tty -s; then
    echo "ERROR: Este script requiere una terminal interactiva." >&2
    exit 1
fi

UPS_NAME_FILE="/etc/nut/ups_name"

if [ ! -f "$UPS_NAME_FILE" ]; then
    echo -e "${R}ERROR:${N} No se encuentra $UPS_NAME_FILE"
    echo "Asegúrate de que nut-alertas-sistema-alertas-nut está instalado correctamente."
    exit 1
fi

UPS_NAME=$(tr -d '[:space:]' < "$UPS_NAME_FILE")

if [ -z "$UPS_NAME" ]; then
    echo -e "${R}ERROR:${N} El archivo $UPS_NAME_FILE está vacío."
    exit 1
fi

if ! command -v upsc >/dev/null 2>&1; then
    echo -e "${R}ERROR:${N} El comando 'upsc' no está disponible. Instala el paquete nut-client."
    exit 1
fi

ANCHO_TOTAL=66
ANCHO_ETIQ=20
ANCHO_VAL=$((ANCHO_TOTAL - ANCHO_ETIQ - 2))

linea() {
    local ETIQ="$1"
    local VAL="$2"
    local COLOR="${3:-$N}"
    printf "  ${C}%-${ANCHO_ETIQ}s${N}${COLOR}%-${ANCHO_VAL}s${N}\n" "$ETIQ" "$VAL"
}

separador() {
    echo -e "  ${D}$(printf '─%.0s' $(seq 1 $ANCHO_TOTAL))${N}"
}

barra() {
    local VAL=$1
    local ANCHO_BARRA=28
    local COLOR
    if   [ "$VAL" -ge 70 ]; then COLOR=$GB
    elif [ "$VAL" -ge 30 ]; then COLOR=$YB
    else                         COLOR=$RB
    fi
    local RELLENO=$(( VAL * ANCHO_BARRA / 100 ))
    local VACIO=$(( ANCHO_BARRA - RELLENO ))
    local STR_R="" STR_V=""
    [ "$RELLENO" -gt 0 ] && STR_R=$(printf '%*s' "$RELLENO" '' | tr ' ' '█')
    [ "$VACIO"   -gt 0 ] && STR_V=$(printf '%*s' "$VACIO"   '' | tr ' ' '░')
    printf "${COLOR}[${STR_R}${D}${STR_V}${COLOR}] %3d%%${N}" "$VAL"
}

etiqueta_estado() {
    local ST="$1"
    local ETIQUETA COLOR
    case "$ST" in
        *OL*CHRG*) ETIQUETA="EN RED  (cargando)";  COLOR=$GB ;;
        *OL*)      ETIQUETA="EN RED";               COLOR=$GB ;;
        *OB*LB*)   ETIQUETA="BATERÍA CRÍTICA";      COLOR=$RB ;;
        *OB*)      ETIQUETA="EN BATERÍA";           COLOR=$YB ;;
        *FSD*)     ETIQUETA="APAGADO FORZADO";      COLOR=$RB ;;
        *BYPASS*)  ETIQUETA="BYPASS";               COLOR=$YB ;;
        *OFF*)     ETIQUETA="APAGADO";              COLOR=$RB ;;
        "")        ETIQUETA="Sin datos";            COLOR=$D  ;;
        *)         ETIQUETA="$ST";                  COLOR=$D  ;;
    esac
    printf "${COLOR}%-${ANCHO_VAL}s${N}" "$ETIQUETA"
}

fmt_runtime() {
    local RT="$1"
    if [[ "$RT" =~ ^[0-9]+$ ]]; then
        local H=$(( RT / 3600 ))
        local M=$(( (RT % 3600) / 60 ))
        local S=$(( RT % 60 ))
        if [ "$H" -gt 0 ]; then
            printf "%dh %02dm %02ds" "$H" "$M" "$S"
        else
            printf "%dm %02ds" "$M" "$S"
        fi
    else
        echo "—"
    fi
}

val() {
    [ -n "$1" ] && echo "$1" || printf "${D}—${N}"
}

flag_activo() {
    local ARCHIVO="$1"
    local TEXTO="$2"
    if [ -f "$ARCHIVO" ]; then
        printf "${YB}⚑ %s${N}" "$TEXTO"
    else
        printf "${D}—${N}"
    fi
}

trap 'tput cnorm; tput rmcup; echo ""; exit 0' INT TERM EXIT
tput smcup
tput civis
clear

FALLOS_CONSECUTIVOS=0
MAX_FALLOS=5

while true; do
    tput cup 0 0

    UPSC_OUT=$(upsc "$UPS_NAME" 2>/dev/null)

    if [ -z "$UPSC_OUT" ]; then
        FALLOS_CONSECUTIVOS=$(( FALLOS_CONSECUTIVOS + 1 ))
        tput ed
        echo ""
        echo -e "  ${RB}✗  Sin comunicación con '${UPS_NAME}'${N}"
        echo ""
        echo -e "  ${D}Comprueba que nut-server está activo:${N}"
        echo -e "  ${W}systemctl status nut-server${N}"
        echo ""
        echo -e "  ${D}Fallos consecutivos: ${FALLOS_CONSECUTIVOS}/${MAX_FALLOS}${N}"
        if [ "$FALLOS_CONSECUTIVOS" -ge "$MAX_FALLOS" ]; then
            echo ""
            echo -e "  ${Y}⚠  Demasiados fallos. Verifica el servicio NUT.${N}"
        fi
        echo ""
        echo -e "  ${D}Próximo intento en ${REFRESCO}s — Ctrl+C para salir${N}"
        sleep "$REFRESCO"
        continue
    fi

    FALLOS_CONSECUTIVOS=0

    declare -A CAMPOS
    while IFS=': ' read -r CLAVE VALOR; do
        [ -n "$CLAVE" ] && CAMPOS["$CLAVE"]="$VALOR"
    done <<< "$(echo "$UPSC_OUT" | sed 's/^[[:space:]]*//')"

    STATUS="${CAMPOS[ups.status]}"
    BATT="${CAMPOS[battery.charge]}"
    BATT_RT="${CAMPOS[battery.runtime]}"
    BATT_VOLT="${CAMPOS[battery.voltage]}"
    BATT_VOLT_NOM="${CAMPOS[battery.voltage.nominal]}"
    BATT_TYPE="${CAMPOS[battery.type]}"
    BATT_LOW="${CAMPOS[battery.charge.low]}"
    BATT_WARN_VAL="${CAMPOS[battery.charge.warning]}"
    BATT_DATE="${CAMPOS[battery.date]}"
    BATT_MFR_DATE="${CAMPOS[battery.mfr.date]}"
    INPUT_VOLT="${CAMPOS[input.voltage]}"
    INPUT_VOLT_NOM="${CAMPOS[input.voltage.nominal]}"
    INPUT_FREQ="${CAMPOS[input.frequency]}"
    INPUT_TRANSF_LOW="${CAMPOS[input.transfer.low]}"
    INPUT_TRANSF_HIGH="${CAMPOS[input.transfer.high]}"
    OUTPUT_VOLT="${CAMPOS[output.voltage]}"
    OUTPUT_FREQ="${CAMPOS[output.frequency]}"
    OUTPUT_CURRENT="${CAMPOS[output.current]}"
    LOAD="${CAMPOS[ups.load]}"
    TEMP="${CAMPOS[ups.temperature]}"
    MODEL="${CAMPOS[ups.model]}"
    MFR="${CAMPOS[ups.mfr]}"
    SERIAL="${CAMPOS[ups.serial]}"
    FIRMWARE="${CAMPOS[ups.firmware]}"
    DRIVER="${CAMPOS[driver.name]}"
    DRIVER_VER="${CAMPOS[driver.version]}"
    BEEPER="${CAMPOS[ups.beeper.status]}"
    POWER_NOM="${CAMPOS[ups.realpower.nominal]}"
    POWER_ACT="${CAMPOS[ups.realpower]}"

    BATT_INT=""
    [[ "$BATT" =~ ^[0-9]+(\.[0-9]+)?$ ]] && BATT_INT=$(printf "%.0f" "$BATT")

    LOAD_INT=""
    [[ "$LOAD" =~ ^[0-9]+(\.[0-9]+)?$ ]] && LOAD_INT=$(printf "%.0f" "$LOAD")

    RT_FMT=$(fmt_runtime "$BATT_RT")
    HORA=$(date '+%d/%m/%Y  %H:%M:%S')
    HOST=$(hostname)
    FLAG_DIR="/var/lib/nut"

    echo ""
    echo -e "  ${W}╔══════════════════════════════════════════════════════════════════╗${N}"
    echo -e "  ${W}║          MONITOR SAI — Sistema Alertas NUT v5.9.2               ║${N}"
    echo -e "  ${W}╚══════════════════════════════════════════════════════════════════╝${N}"
    echo ""
    linea "Servidor:"   "$HOST"
    linea "Fecha/Hora:" "$HORA"
    echo ""
    separador

    echo -e "  ${CB}▸ DISPOSITIVO${N}"
    separador
    linea "Nombre NUT:"    "$UPS_NAME"  "$W"
    linea "Fabricante:"    "$(val "$MFR")"
    linea "Modelo:"        "$(val "$MODEL")"
    linea "Nº de serie:"   "$(val "$SERIAL")"
    linea "Firmware:"      "$(val "$FIRMWARE")"
    linea "Driver:"        "$(val "$DRIVER") $([ -n "$DRIVER_VER" ] && echo "($DRIVER_VER)")"
    linea "Potencia nom.:" "$([ -n "$POWER_NOM" ] && echo "${POWER_NOM} W" || printf "${D}—${N}")"
    echo ""
    separador

    echo -e "  ${CB}▸ ESTADO Y BATERÍA${N}"
    separador

    printf "  ${C}%-${ANCHO_ETIQ}s${N}" "Estado:"
    etiqueta_estado "$STATUS"
    echo ""

    printf "  ${C}%-${ANCHO_ETIQ}s${N}" "Batería:"
    if [ -n "$BATT_INT" ]; then
        barra "$BATT_INT"
    else
        printf "${D}—${N}"
    fi
    echo ""

    linea "Autonomía restante:" "$RT_FMT"
    linea "Tensión batería:"    "$([ -n "$BATT_VOLT" ] && echo "${BATT_VOLT} V$([ -n "$BATT_VOLT_NOM" ] && echo " (nominal: ${BATT_VOLT_NOM} V)")" || printf "${D}—${N}")"
    linea "Tipo batería:"       "$(val "$BATT_TYPE")"
    linea "Fecha batería:"      "$(val "${BATT_DATE:-$BATT_MFR_DATE}")"
    linea "Umbral crítico:"     "$([ -n "$BATT_LOW" ] && echo "${BATT_LOW}%" || printf "${D}—${N}")"
    linea "Umbral aviso:"       "$([ -n "$BATT_WARN_VAL" ] && echo "${BATT_WARN_VAL}%" || printf "${D}—${N}")"
    linea "Zumbador:"           "$(val "$BEEPER")"
    echo ""
    separador

    echo -e "  ${CB}▸ CARGA${N}"
    separador

    printf "  ${C}%-${ANCHO_ETIQ}s${N}" "Carga SAI:"
    if [ -n "$LOAD_INT" ]; then
        barra "$LOAD_INT"
    else
        printf "${D}—${N}"
    fi
    echo ""

    linea "Potencia activa:"  "$([ -n "$POWER_ACT" ] && echo "${POWER_ACT} W" || printf "${D}—${N}")"
    linea "Corriente salida:" "$([ -n "$OUTPUT_CURRENT" ] && echo "${OUTPUT_CURRENT} A" || printf "${D}—${N}")"
    echo ""
    separador

    echo -e "  ${CB}▸ RED ELÉCTRICA${N}"
    separador
    linea "Tensión entrada:"    "$([ -n "$INPUT_VOLT" ] && echo "${INPUT_VOLT} V$([ -n "$INPUT_VOLT_NOM" ] && echo " (nominal: ${INPUT_VOLT_NOM} V)")" || printf "${D}—${N}")"
    linea "Frecuencia entrada:" "$([ -n "$INPUT_FREQ" ] && echo "${INPUT_FREQ} Hz" || printf "${D}—${N}")"
    linea "Transf. bajo/alto:"  "$([ -n "$INPUT_TRANSF_LOW" ] && echo "${INPUT_TRANSF_LOW} V / ${INPUT_TRANSF_HIGH} V" || printf "${D}—${N}")"
    linea "Tensión salida:"     "$([ -n "$OUTPUT_VOLT" ] && echo "${OUTPUT_VOLT} V" || printf "${D}—${N}")"
    linea "Frecuencia salida:"  "$([ -n "$OUTPUT_FREQ" ] && echo "${OUTPUT_FREQ} Hz" || printf "${D}—${N}")"
    linea "Temperatura:"        "$([ -n "$TEMP" ] && echo "${TEMP} °C" || printf "${D}—${N}")"
    echo ""
    separador

    echo -e "  ${CB}▸ ALERTAS ACTIVAS${N}"
    separador
    linea "En batería:"      "$(flag_activo "${FLAG_DIR}/estado_onbatt"         "Corte de luz detectado")"
    linea "Aviso umbral:"    "$(flag_activo "${FLAG_DIR}/aviso_bateria_enviado"  "Aviso de batería enviado")"
    linea "Nivel crítico:"   "$(flag_activo "${FLAG_DIR}/estado_critico"         "Apagado de emergencia activo")"
    linea "Batería agotada:" "$(flag_activo "${FLAG_DIR}/aviso_replbatt_enviado" "Reemplazo de batería pendiente")"
    echo ""
    separador

    echo -e "  ${CB}▸ SERVICIOS${N}"
    separador
    for SVC in nut-server nut-client postfix; do
        if systemctl is-active --quiet "$SVC" 2>/dev/null; then
            echo -e "  ${GB}●${N} $(printf "%-${ANCHO_TOTAL}s" "$SVC  — activo")"
        else
            echo -e "  ${RB}●${N} $(printf "%-${ANCHO_TOTAL}s" "${SVC}  — INACTIVO")"
        fi
    done
    echo ""
    echo -e "  ${D}Refresco cada ${REFRESCO}s — Ctrl+C para salir${N}"
    echo ""

    tput ed
    sleep "$REFRESCO"
done
MONITOR_EOF

chmod +x "${SCRIPT_DIR}/monitor-sai.sh"

# ─────────────────────────────────────────────────────────────────────────────
# Verificación de servicios y configuración
# ─────────────────────────────────────────────────────────────────────────────
whiptail --title "Verificando..." \
    --infobox "Verificando servicios y configuración...\nComprobando nut-server, nut-client y postfix." 7 60
sleep 3

ERRORES=""
for SVC in nut-server nut-client postfix; do
    systemctl is-active "$SVC" >/dev/null 2>&1 || ERRORES="$ERRORES $SVC"
done

if [ -n "$ERRORES" ]; then
    whiptail --title "⚠ Servicios no activos" --msgbox \
        "Los siguientes servicios no han arrancado correctamente:\n$ERRORES\n\nSin nut-client el apagado automático NO funcionará.\nRevisa el registro con: journalctl -u nut-client" \
        12 65
fi

UPS_STATUS=$(timeout 5 upsc ${UPS_NAME} ups.status 2>/dev/null || echo "")
if [ -z "$UPS_STATUS" ]; then
    whiptail --title "⚠ SAI sin respuesta" --msgbox \
        "El SAI '$UPS_NAME' no responde todavía por upsc.\nPuede tardar unos segundos en inicializarse.\n\nVerifica manualmente con: upsc ${UPS_NAME}" \
        10 65
fi

# ─────────────────────────────────────────────────────────────────────────────
# Correo de prueba
# ─────────────────────────────────────────────────────────────────────────────
whiptail --title "Verificando..." \
    --infobox "Enviando correo de prueba a ${DEST_EMAIL}...\nEspera unos segundos." 6 60
sleep 5

RESULTADO_TEST=0
{
    echo "Servidor : $(hostname)"
    echo "Hora     : $(date '+%d/%m/%Y %H:%M:%S')"
    echo "SAI      : ${UPS_NAME} — Driver: ${UPS_DRIVER}"
    echo "Estado   : ${UPS_STATUS:-desconocido}"
    echo ""
    echo "El sistema de alertas SAI está correctamente instalado y configurado."
    echo ""
    echo "Configuración activa:"
    echo "  Umbral de aviso  : ${BATT_WARN}%"
    echo "  Umbral de apagado: ${BATT_CRIT}%"
    echo "  Relay SMTP       : ${SMTP_SERVER}:${SMTP_PORT}"
    echo ""
    echo "  Monitor en tiempo real: ${SCRIPT_DIR}/monitor-sai.sh"
    echo ""
    echo "---"
    echo "Correo de prueba — Sistema alertas nut v5.9"
} | mail -a "From: Alertas SAI Sistema alertas nut <${SMTP_USER}>" \
              -a "Content-Type: text/plain; charset=UTF-8" \
              -a "MIME-Version: 1.0" \
          -s "[$(hostname)] PRUEBA - Alertas SAI instaladas correctamente" \
          "${DEST_EMAIL}" || RESULTADO_TEST=1

postfix flush >/dev/null 2>&1 || true
sleep 5

[ "$RESULTADO_TEST" -eq 0 ] \
    && MSG_CORREO="✓ Correo de prueba enviado a:\n  ${DEST_EMAIL}\n\nConfirma su recepción antes de cerrar." \
    || MSG_CORREO="✗ No se pudo enviar el correo de prueba.\n\nRevisa con: journalctl -u postfix"

whiptail --title "Instalación completada — Sistema alertas nut v5.9" --msgbox \
"Sistema de alertas SAI configurado correctamente para Proxmox.

SAI              : ${UPS_NAME}
Driver           : ${UPS_DRIVER}
Aviso de batería : ${BATT_WARN}%
Apagado crítico  : ${BATT_CRIT}%
Alertas enviadas : ${DEST_EMAIL}
Relay SMTP       : ${SMTP_SERVER}:${SMTP_PORT}

Monitor SAI      : ${SCRIPT_DIR}/monitor-sai.sh

${MSG_CORREO}" \
    22 65

# ─────────────────────────────────────────────────────────────────────────────
# Limpieza: autoeliminación del .deb
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "  Limpiando paquete de instalación..."

DEB_PATH=$(find /root /tmp /home -maxdepth 3 -name "nut-alertas-sistema-alertas-nut.deb" 2>/dev/null | head -1)
if [ -n "$DEB_PATH" ]; then
    rm -f "$DEB_PATH"
    logger -t "nut-alertas-sistema-alertas-nut" "Paquete .deb eliminado: $DEB_PATH"
    echo "  Paquete eliminado: $DEB_PATH"
else
    echo "  Paquete .deb no encontrado para eliminar (puede estar en otra ruta)."
fi

echo ""
echo "  Instalación finalizada. Todos los servicios están activos."
echo "  Monitor SAI disponible en: ${SCRIPT_DIR}/monitor-sai.sh"
echo ""
POSTINST_EOF

# ── Construcción del paquete ─────────────────────────────────────────────────
chmod 755 /root/nut-alertas-final/DEBIAN/postinst

dpkg-deb --build /root/nut-alertas-final
mv /root/nut-alertas-final.deb /root/nut-alertas-sistema-alertas-nut.deb
chmod 644 /root/nut-alertas-sistema-alertas-nut.deb
rm -rf /root/nut-alertas-final

echo ""
echo "=========================================="
echo "  Paquete generado: /root/nut-alertas-sistema-alertas-nut.deb"
echo ""
echo "  En el servidor del cliente solo hace falta:"
echo "    apt install ./nut-alertas-sistema-alertas-nut.deb"
echo ""
echo "  El gestor 'apt' instalará automáticamente:"
echo "    - Todas las dependencias del sistema de forma segura"
echo "    - La configuración interactiva NUT + Postfix"
echo "    - El script /INFORMATICA/SCRIPTS_AUTOMATIZADOS/SAI/monitor-sai.sh"
echo "    - (Se autoeliminará al terminar la instalación)"
echo "=========================================="
