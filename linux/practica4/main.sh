#!/bin/bash

DIR="$(dirname "$0")"

source "$DIR/funciones.sh"
source "$DIR/dhcp.sh"
source "$DIR/dns.sh"
source "$DIR/diagnostico_SO.sh"

verificar_root

while true; do
    echo ""
    echo "-------------------------------------"
    echo "     	    MENU DEL SISTEMA           "
    echo "-------------------------------------"
    echo "*** DIAGNOSTICO ***"
    echo "0. Ejecutar Diagnostico de SO"
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
        0) ejecutar_diagnostico_so ;;
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
