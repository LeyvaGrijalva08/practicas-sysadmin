#!/bin/bash

function verificar_ip_fija() {
    echo "" >&2
    echo "VALIDACION DE IP FIJA" >&2
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

function instalar_dns() {
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

function agregar_dominio() {
    echo "" >&2
    echo "AGREGAR DOMINIO DNS" >&2
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

function eliminar_dominio() {
    echo "" >&2
    echo "ELIMINAR DOMINIO DNS" >&2
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

function listar_dominios() {
    echo "" >&2
    echo "--- DOMINIOS CONFIGURADOS ACTUALMENTE ---" >&2
    if grep -q "zone " /etc/bind/named.conf.local; then
        grep "zone " /etc/bind/named.conf.local | awk -F\" '{print $2}' | grep -v "in-addr.arpa"
    else
        echo "No hay dominios configurados." >&2
    fi
    echo "-----------------------------------------" >&2
}

function validar_resolucion() {
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
