#!/bin/bash

source ./funciones.sh

if [ "$EUID" -ne 0 ]; then
    echo "Acceso denegado. Ejecuta el script como root."
    exit 1
fi

declare -A mapa_servicios=(
    [1]="apache2"
    [2]="nginx"
    [3]="tomcat10"
)

mostrar_menu() {
    echo "-------------------------------------------------"
    echo "       Despliegue Dinamico de Servicios HTTP     "
    echo "-------------------------------------------------"
    echo " Seleccione el servidor HTTP que desea instalar: "
    echo " 1) Apache2"
    echo " 2) Nginx"
    echo " 3) Tomcat"
    echo " 4) Limpiar entorno"
    echo " 5) Salir"
    echo "-------------------------------------------------"
}

procesar_seleccion() {
    local opcion=$1

    [[ "$opcion" == "5" ]] && return 5
    [[ "$opcion" == "4" ]] && { limpiar_servicios_web; return 4; }

    local servicio="${mapa_servicios[$opcion]}"
    if [[ -z "$servicio" ]]; then
        echo "Opcion no valida. Intenta de nuevo."
        return 0
    fi

    local puerto
    puerto=$(pedir_puerto)

    echo "Consultando versiones para $servicio en los repositorios..."
    local version
    version=$(escoger_version "$servicio")

    if [[ -z "$version" ]]; then
        echo "No se obtuvo version valida. Operacion cancelada."
        return 0
    fi

    ejecutar_despliegue "$servicio" "$version" "$puerto"
}

ejecutar_despliegue() {
    local servicio=$1
    local version=$2
    local puerto=$3

    case $servicio in
        apache2)  desplegar_apache  "$version" "$puerto" ;;
        nginx)    desplegar_nginx   "$version" "$puerto" ;;
        tomcat10) desplegar_tomcat  "$version" "$puerto" ;;
    esac
}

preparar_entorno_base

while true; do
    mostrar_menu
    read -p "Opcion: " opcion

    procesar_seleccion "$opcion"
    codigo=$?

    [[ $codigo -eq 5 ]] && { echo "Saliendo..."; break; }
    [[ $codigo -eq 4 ]] && continue

    read -p "¿Realizar otra operacion? (s/n): " continuar
    [[ "$continuar" != "s" && "$continuar" != "S" ]] && break
done