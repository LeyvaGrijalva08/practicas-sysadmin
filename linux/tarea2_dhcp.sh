#!/bin/bash

ARCHIVO_CONF="/etc/dhcp/dhcpd.conf"
INTERFAZ=""

# FUNCIONES

detectar_interfaz() {
    echo "" >&2
    echo "DETECCION DE RED" >&2
    echo "Estas son tus interfaces de red disponibles:" >&2
    
    ip -o link show | awk -F': ' '{print $2}' | grep -v "lo" >&2
    
    echo "" >&2
    echo "ATENCION: 'enp0s3' suele ser Internet. 'enp0s8' suele ser Red Interna." >&2
    echo "" >&2
    
    while true; do
        read -p "Escribe EXACTAMENTE la interfaz a usar (ej. enp0s8): " INTERFAZ_USR >&2
        
        if ip link show "$INTERFAZ_USR" > /dev/null 2>&1; then
            INTERFAZ=$INTERFAZ_USR
            echo "[INFO] Usando interfaz: $INTERFAZ" >&2
            return 0
        else
            echo "Esa interfaz no existe. Intenta de nuevo." >&2
        fi
    done
}

validar_formato_ip() {
    local ip=$1
    if [[ ! $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then return 1; fi
    if [[ "$ip" == "0.0.0.0" || "$ip" == "127.0.0.1" || "$ip" == "255.255.255.255" ]]; then return 1; fi
    IFS='.' read -r i1 i2 i3 i4 <<< "$ip"
    if [ "$i1" -gt 255 ] || [ "$i2" -gt 255 ] || [ "$i3" -gt 255 ] || [ "$i4" -gt 255 ]; then return 1; fi
    return 0
}

solicitar_ip() {
    local mensaje=$1
    local ip_ingresada=""
    while true; do
        read -p "$mensaje: " ip_raw >&2
        ip_ingresada=$(echo "$ip_raw" | tr -d '\r')
        if validar_formato_ip "$ip_ingresada"; then
            echo "$ip_ingresada"
            return 0
        else
            echo "IP no valida." >&2
        fi
    done
}

calcular_siguiente() {
    local ip=$1
    IFS='.' read -r i1 i2 i3 i4 <<< "$ip"
    local nuevo_i4=$((i4 + 1))
    echo "$i1.$i2.$i3.$nuevo_i4"
}

verificar_rango() {
    local ip_fin=$1
    local ip_ini=$2
    IFS='.' read -r f1 f2 f3 f4 <<< "$ip_fin"
    IFS='.' read -r i1 i2 i3 i4 <<< "$ip_ini"
    if [ "$f4" -gt "$i4" ]; then return 0; else return 1; fi
}

# MENU

instalar_servicio() {
    echo "" >&2
    if dpkg -l | grep -q isc-dhcp-server; then
        read -p "El servicio ya existe. Reinstalar? (s/n): " resp >&2
        if [[ "$resp" == "s" ]]; then
            apt-get purge isc-dhcp-server -y -qq >/dev/null
            apt-get autoremove -y -qq >/dev/null
        else
            return
        fi
    fi
    echo "Instalando..." >&2
    apt-get update -qq >/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get install isc-dhcp-server -y -qq >/dev/null
}

verificar_servicio() {
    if dpkg -l | grep -q isc-dhcp-server; then echo "INSTALADO"; else echo "NO INSTALADO"; fi
}

configurar_dhcp() {
    echo "" >&2
    detectar_interfaz || return

    MI_IP=$(solicitar_ip "IP Servidor (Inicio)")
    RANGO_INICIO=$(calcular_siguiente "$MI_IP")

    echo "Limpiando IP previa en $INTERFAZ..." >&2
    ip addr flush dev "$INTERFAZ"
    ip addr add "$MI_IP/24" dev "$INTERFAZ"
    ip link set "$INTERFAZ" up

    while true; do
        IP_FINAL=$(solicitar_ip "IP Final (Mayor a $RANGO_INICIO)")
        if verificar_rango "$IP_FINAL" "$RANGO_INICIO"; then break; fi
        echo "Error: IP final debe ser mayor." >&2
    done

    read -p "Tiempo concesion: " TIEMPO >&2
    read -p "Gateway (Enter vacio): " GW >&2
    read -p "DNS (Enter vacio): " DNS >&2
    read -p "Dominio: " DOM >&2

    sed -i 's/^INTERFACESv4=.*/INTERFACESv4="'"$INTERFAZ"'"/' /etc/default/isc-dhcp-server

    IFS='.' read -r i1 i2 i3 i4 <<< "$MI_IP"
    SUBNET="$i1.$i2.$i3.0"
    BROADCAST="$i1.$i2.$i3.255"

    cat > "$ARCHIVO_CONF" <<EOF
default-lease-time $TIEMPO;
max-lease-time $((TIEMPO * 2));
authoritative;
subnet $SUBNET netmask 255.255.255.0 {
    range $RANGO_INICIO $IP_FINAL;
    option broadcast-address $BROADCAST;
EOF
    GW=$(echo "$GW" | tr -d '\r'); DNS=$(echo "$DNS" | tr -d '\r'); DOM=$(echo "$DOM" | tr -d '\r')
    
    if [ ! -z "$GW" ]; then echo "    option routers $GW;" >> "$ARCHIVO_CONF"; fi
    if [ ! -z "$DNS" ]; then echo "    option domain-name-servers $DNS;" >> "$ARCHIVO_CONF"; fi
    if [ ! -z "$DOM" ]; then echo "    option domain-name \"$DOM\";" >> "$ARCHIVO_CONF"; fi
    echo "}" >> "$ARCHIVO_CONF"

    echo "Reiniciando..." >&2
    systemctl restart isc-dhcp-server
    if systemctl is-active --quiet isc-dhcp-server; then
        echo "EXITO: Servicio activo en interfaz $INTERFAZ." >&2
    else
        echo "FALLO: Revisa 'systemctl status isc-dhcp-server'." >&2
    fi
}

monitorear() {
    systemctl status isc-dhcp-server --no-pager | grep "Active:"
    if [ -f "/var/lib/dhcp/dhcpd.leases" ]; then grep "lease " "/var/lib/dhcp/dhcpd.leases" | sort | uniq; fi
}

while true; do
    echo "1.Instalar 2.Verificar 3.Configurar 4.Monitorear 5.Salir"
    read -p "Opcion: " op >&2
    case $op in
        1) instalar_servicio ;;
        2) verificar_servicio ;;
        3) configurar_dhcp ;;
        4) monitorear ;;
        5) exit 0 ;;
    esac
done