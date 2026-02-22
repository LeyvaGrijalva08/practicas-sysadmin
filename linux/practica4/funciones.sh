#!/bin/bash

INTERFAZ=""

function verificar_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "ERROR: Por favor, ejecuta este script como root (o usa sudo)." >&2
        exit 1
    fi
}

function detectar_interfaz() {
    echo "" >&2
    echo "DETECCION DE RED" >&2
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

function validar_formato_ip() {
    local ip=$1
    if [[ ! $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then return 1; fi
    if [[ "$ip" == "0.0.0.0" || "$ip" == "127.0.0.1" || "$ip" == "255.255.255.255" ]]; then return 1; fi
    IFS='.' read -r i1 i2 i3 i4 <<< "$ip"
    if [ "$i1" -gt 255 ] || [ "$i2" -gt 255 ] || [ "$i3" -gt 255 ] || [ "$i4" -gt 255 ]; then return 1; fi
    return 0
}

function solicitar_ip() {
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

function solicitar_entero_positivo() {
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

function verificar_instalaciones() {
    echo "ESTADO DE SERVICIOS"
    if dpkg -l | grep -q isc-dhcp-server; then echo "[DHCP] INSTALADO"; else echo "[DHCP] NO INSTALADO"; fi
    if dpkg -l | grep -q bind9; then echo "[DNS]  INSTALADO"; else echo "[DNS]  NO INSTALADO"; fi
}
