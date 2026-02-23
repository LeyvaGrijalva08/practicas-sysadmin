#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo "Advertencia: ejecuta este script como root (o usa sudo)." >&2
    exit 1
fi

function configurar_acceso_ssh() {
    if dpkg -l | grep -q openssh-server; then
        echo "OpenSSH Server ya se encuentra instalado"
    else
        echo "Instalando OpenSSH Server..."
        apt-get update -qq >/dev/null
        DEBIAN_FRONTEND=noninteractive apt-get install openssh-server -y -qq >/dev/null
        echo "Instalacion de OpenSSH Server completada."
    fi

    systemctl enable ssh --quiet
    systemctl start ssh
    
    if systemctl is-active --quiet ssh; then
        echo "Servicio SSH iniciado y configurado en el boot correctamente"
    else
        echo "Hubo un problema al iniciar el servicio SSH"
    fi

    if command -v ufw >/dev/null 2>&1; then
        echo "Verificando reglas de Firewall para el puerto 22..."
        ufw allow 22/tcp >/dev/null 2>&1
        echo "Regla de Firewall validada exitosamente."
    else
        echo "Firewall UFW no detectado. El puerto 22 esta abierto por defecto en Debian."
    fi

    IP=$(ip -o -4 addr list enp0s3 | awk '{print $4}' | cut -d/ -f1)
    
    if [ -n "$SUDO_USER" ]; then
        USUARIO="$SUDO_USER"
    else
        USUARIO=$(whoami)
    fi

    echo ""
    if [ -n "$IP" ]; then
        echo -e "\e[33mssh $USUARIO@$IP\e[0m"
    else
        echo -e "\e[31mNo se encontro una IP en el adaptador 'enp0s3'. Revisa la conexion.\e[0m"
    fi
    echo ""
}

configurar_acceso_ssh
