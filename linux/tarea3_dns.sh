#!/bin/bash

ARCHIVO_CONF="/etc/dhcp/dhcpd.conf"
INTERFAZ=""

# FUNCIONES BASE Y DHCP

detectar_interfaz() {
    echo "" >&2
    echo "---DETECCION DE RED---" >&2
    echo "Estas son las interfaces de red disponibles:" >&2
    
    ip -o link show | awk -F': ' '{print $2}' | grep -v "lo" >&2
    
    echo "" >&2
    echo "'enp0s3' Internet. 'enp0s8' Red Interna." >&2
    echo "" >&2
    
    while true; do
        read -p "Escribe EXACTAMENTE la interfaz a usar (ej. enp0s8): " INTERFAZ_USR >&2
        
        if ip link show "$INTERFAZ_USR" > /dev/null 2>&1; then
            INTERFAZ=$INTERFAZ_USR
            echo "Usando interfaz: $INTERFAZ" >&2
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
            echo "ERROR IP no valida." >&2
        fi
    done
}

solicitar_entero_positivo() {
    local mensaje=$1
    local valor=""
    while true; do
        read -p "$mensaje: " valor >&2
        valor=$(echo "$valor" | tr -d '\r')
        if [[ "$valor" =~ ^[1-9][0-9]*$ ]]; then
            echo "$valor"
            return 0
        else
            echo "ERROR: Ingresa un numero entero positivo valido (sin puntos ni signos)." >&2
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

instalar_dhcp() {
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

monitorear_dhcp() {
    systemctl status isc-dhcp-server --no-pager | grep "Active:"
    if [ -f "/var/lib/dhcp/dhcpd.leases" ]; then grep "lease " "/var/lib/dhcp/dhcpd.leases" | sort | uniq; fi
}

# FUNCIONES DNS

verificar_instalaciones() {
    echo "--- ESTADO DE SERVICIOS ---"
    if dpkg -l | grep -q isc-dhcp-server; then echo "[DHCP] INSTALADO"; else echo "[DHCP] NO INSTALADO"; fi
    if dpkg -l | grep -q bind9; then echo "[DNS]  INSTALADO"; else echo "[DNS]  NO INSTALADO"; fi
}

verificar_ip_fija() {
    echo "" >&2
    echo "--- VALIDACION DE IP FIJA ---" >&2
    detectar_interfaz || return
    local ip_actual=$(ip -o -4 addr list "$INTERFAZ" | awk '{print $4}' | cut -d/ -f1)
    
    if [ -z "$ip_actual" ]; then
        echo "No hay IP asignada en $INTERFAZ." >&2
        IP_NUEVA=$(solicitar_ip "Ingresa la IP fija a asignar para el servidor (ej. 192.168.100.10)")
        ip addr add "$IP_NUEVA/24" dev "$INTERFAZ"
        ip link set "$INTERFAZ" up
        echo "IP $IP_NUEVA asignada a $INTERFAZ." >&2
    else
        echo "La interfaz $INTERFAZ ya tiene la IP configurada: $ip_actual" >&2
    fi
}

instalar_dns() {
    echo "" >&2
    if dpkg -l | grep -q bind9; then
        read -p "El servicio DNS (bind9) ya existe. Reinstalar? (s/n): " resp >&2
        if [[ "$resp" == "s" ]]; then
            apt-get purge bind9 bind9utils bind9-doc -y -qq >/dev/null
            apt-get autoremove -y -qq >/dev/null
        else
            return
        fi
    fi
    echo "Instalando BIND9 y utilidades..." >&2
    apt-get update -qq >/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get install bind9 bind9utils bind9-doc dnsutils -y -qq >/dev/null
    
    echo "Instalacion de DNS completada." >&2
}

agregar_dominio() {
    echo "" >&2
    echo "--- AGREGAR DOMINIO DNS ---" >&2
    read -p "Ingresa el nombre del dominio (ej. reprobados.com): " DOMINIO
    
    CONF_LOCAL="/etc/bind/named.conf.local"
    ZONA_FILE="/var/cache/bind/db.$DOMINIO"

    if grep -q "zone \"$DOMINIO\"" "$CONF_LOCAL"; then
        echo "El dominio $DOMINIO ya esta registrado." >&2
        return
    fi

    IP_DOMINIO=$(solicitar_ip "Ingresa la IP a la que apuntara el dominio")

    if [ -z "$INTERFAZ" ]; then detectar_interfaz || return; fi
    IP_SERVER=$(ip -o -4 addr list "$INTERFAZ" | awk '{print $4}' | cut -d/ -f1)
    if [ -z "$IP_SERVER" ]; then IP_SERVER="127.0.0.1"; fi 

    cat >> "$CONF_LOCAL" <<EOF
zone "$DOMINIO" {
    type master;
    file "$ZONA_FILE";
};
EOF

    cat > "$ZONA_FILE" <<EOF
\$TTL    604800
@       IN      SOA     ns1.$DOMINIO. admin.$DOMINIO. (
                              2         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      ns1.$DOMINIO.
ns1     IN      A       $IP_SERVER
@       IN      A       $IP_DOMINIO
www     IN      CNAME   $DOMINIO.
EOF

    IFS='.' read -r d1 d2 d3 d4 <<< "$IP_DOMINIO"
    ZONA_INVERSA="$d3.$d2.$d1.in-addr.arpa"
    ARCHIVO_INV="/var/cache/bind/db.$d1.$d2.$d3"

    if ! grep -q "zone \"$ZONA_INVERSA\"" "$CONF_LOCAL"; then
        cat >> "$CONF_LOCAL" <<EOF
zone "$ZONA_INVERSA" {
    type master;
    file "$ARCHIVO_INV";
};
EOF
    fi

    if [ ! -f "$ARCHIVO_INV" ]; then
        cat > "$ARCHIVO_INV" <<EOF
\$TTL    604800
@       IN      SOA     ns1.$DOMINIO. admin.$DOMINIO. (
                              2         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      ns1.$DOMINIO.
EOF
    fi

    if ! grep -q -w "$d4.*PTR.*$DOMINIO" "$ARCHIVO_INV" 2>/dev/null; then
        echo "$d4       IN      PTR     $DOMINIO." >> "$ARCHIVO_INV"
        echo "$d4       IN      PTR     www.$DOMINIO." >> "$ARCHIVO_INV"
    fi

    systemctl restart bind9
    echo "Dominio $DOMINIO (y su zona inversa) creados exitosamente." >&2
}

eliminar_dominio() {
    echo "" >&2
    echo "--- ELIMINAR DOMINIO DNS ---" >&2
    read -p "Ingresa el dominio a eliminar: " DOMINIO
    CONF_LOCAL="/etc/bind/named.conf.local"
    ZONA_FILE="/var/cache/bind/db.$DOMINIO"

    if ! grep -q "zone \"$DOMINIO\"" "$CONF_LOCAL"; then
        echo "ERROR El dominio $DOMINIO no existe en la configuracion." >&2
        return
    fi

    for archivo in /var/cache/bind/db.*; do
        if [[ -f "$archivo" && "$archivo" != "$ZONA_FILE" ]]; then
            sed -i "/PTR.*$DOMINIO\./d" "$archivo"
        fi
    done

    sed -i "/zone \"$DOMINIO\" {/,/};/d" "$CONF_LOCAL"
    
    rm -f "$ZONA_FILE"

    systemctl restart bind9
    echo "Dominio $DOMINIO y sus registros de IP eliminados exitosamente." >&2
}

listar_dominios() {
    echo "" >&2
    echo "--- DOMINIOS CONFIGURADOS ACTUALMENTE ---" >&2
    if grep -q "zone " /etc/bind/named.conf.local; then
        grep "zone " /etc/bind/named.conf.local | awk -F\" '{print $2}' | grep -v "in-addr.arpa"
    else
        echo "No hay dominios configurados." >&2
    fi
    echo "-----------------------------------------" >&2
}

validar_resolucion() {
    echo "" >&2
    echo "--- PRUEBAS DE RESOLUCION (MONITOREO DNS) ---" >&2
    echo "1. Revisando sintaxis (named-checkconf)..."
    named-checkconf
    if [ $? -eq 0 ]; then
        echo "Sintaxis de BIND9 correcta."
    else
        echo "Hay un problema de sintaxis en la configuracion de BIND."
        return
    fi
    
    read -p "Ingresa el dominio o IP a buscar en nslookup (ej. reprobados.com o 192.168.10.10): " BUSQUEDA
    echo ""
    echo "--- Ejecutando NSLOOKUP hacia $BUSQUEDA ---"
    nslookup "$BUSQUEDA" localhost
    
    echo ""
    read -p "Ingresa el nombre del dominio para el PING (ej. reprobados.com): " DOM_PING
    echo "--- Ejecutando PING a www.$DOM_PING ---"
    ping -c 3 "www.$DOM_PING"
}

# --- MENU PRINCIPAL ---

while true; do
    echo ""
    echo "-------------------------------------"
    echo "     	    ( DHCP | DNS )            "
    echo "-------------------------------------"
    echo "*** SERVICIO DHCP ***"
    echo "1. Instalar DHCP"
    echo "2. Configurar DHCP (Asigna IP y Rango)"
    echo "3. Monitorear DHCP"
    echo "*** SERVICIO DNS ***"
    echo "4. Instalar DNS (BIND9)"
    echo "5. Verificar IP Fija en Interfaz"
    echo "6. Agregar Dominio DNS"
    echo "7. Eliminar Dominio DNS"
    echo "8. Ver Dominios DNS Configurados"
    echo "9. Validar y Probar DNS (nslookup/ping)"
    echo "*** SISTEMA ***"
    echo "10. Verificar Instalaciones"
    echo "11. Salir"
    echo "-------------------------------------"
    read -p "Opcion: " op >&2
    case $op in
        1) instalar_dhcp ;;
        2) configurar_dhcp ;;
        3) monitorear_dhcp ;;
        4) instalar_dns ;;
        5) verificar_ip_fija ;;
        6) agregar_dominio ;;
        7) eliminar_dominio ;;
        8) listar_dominios ;;
        9) validar_resolucion ;;
        10) verificar_instalaciones ;;
        11) echo "Saliendo..."; exit 0 ;;
        *) echo "ERROR Opcion invalida." >&2 ;;
    esac
done