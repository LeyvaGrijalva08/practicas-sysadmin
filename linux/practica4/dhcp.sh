#!/bin/bash

ARCHIVO_CONF="/etc/dhcp/dhcpd.conf"

function calcular_siguiente() {
    local ip=$1
    IFS='.' read -r i1 i2 i3 i4 <<< "$ip"
    local nuevo_i4=$((i4 + 1))
    echo "$i1.$i2.$i3.$nuevo_i4"
}

function verificar_rango() {
    local ip_fin=$1
    local ip_ini=$2
    IFS='.' read -r f1 f2 f3 f4 <<< "$ip_fin"
    IFS='.' read -r i1 i2 i3 i4 <<< "$ip_ini"
    if [ "$f4" -gt "$i4" ]; then return 0; else return 1; fi
}

function instalar_dhcp() {
    echo "" >&2
    if dpkg -l | grep -q isc-dhcp-server; then
        read -p "El servicio DHCP ya existe. Reinstalar? (s/n): " resp >&2
        if [[ "$resp" == "s" ]]; then
            apt-get purge isc-dhcp-server -y -qq >/dev/null
            apt-get autoremove -y -qq >/dev/null
        else
            return
        fi
    fi
    echo "Instalando DHCP..." >&2
    apt-get update -qq >/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get install isc-dhcp-server -y -qq >/dev/null
}

function configurar_dhcp() {
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

    TIEMPO=$(solicitar_entero_positivo "Tiempo concesion (en segundos)")
    
    read -p "Gateway (Enter vacio): " GW >&2
    DNS=$(solicitar_ip "DNS (Obligatorio)")

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
    GW=$(echo "$GW" | tr -d '\r')
    
    if [ ! -z "$GW" ]; then echo "    option routers $GW;" >> "$ARCHIVO_CONF"; fi
    
    echo "    option domain-name-servers $DNS;" >> "$ARCHIVO_CONF"
    echo "}" >> "$ARCHIVO_CONF"

    echo "Reiniciando DHCP..." >&2
    systemctl restart isc-dhcp-server
    if systemctl is-active --quiet isc-dhcp-server; then
        echo "EXITO: Servicio activo en interfaz $INTERFAZ." >&2
    else
        echo "FALLO: Revisa 'systemctl status isc-dhcp-server'." >&2
    fi
}

function monitorear_dhcp() {
    systemctl status isc-dhcp-server --no-pager | grep "Active:"
    if [ -f "/var/lib/dhcp/dhcpd.leases" ]; then grep "lease " "/var/lib/dhcp/dhcpd.leases" | sort | uniq; fi
}
