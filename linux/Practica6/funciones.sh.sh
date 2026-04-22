#!/bin/bash

desplegar_apache() {
    local version=$1
    local puerto=$2
    
    echo "Desplegando Apache2 version $version en puerto $puerto..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y -qq --allow-downgrades \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        apache2="$version" apache2-bin="$version" apache2-data="$version" apache2-utils="$version" > /dev/null 2>&1
    
    local dir_vhost="/var/www/apache_$puerto"
    mkdir -p "$dir_vhost"

    echo "Listen $puerto" > /etc/apache2/ports.conf

    cat <<EOF > /etc/apache2/sites-available/000-default.conf
<VirtualHost *:$puerto>
    ServerAdmin webmaster@localhost
    DocumentRoot $dir_vhost
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF

    echo "Aplicando configuracion de seguridad a Apache..."
    sed -i 's/ServerTokens OS/ServerTokens Prod/g' /etc/apache2/conf-available/security.conf
    sed -i 's/ServerSignature On/ServerSignature Off/g' /etc/apache2/conf-available/security.conf
    
    generar_pagina_inicio "$dir_vhost" "Apache2" "$version" "$puerto"
    
    chown -R www-data:www-data "$dir_vhost"
    chmod -R 755 "$dir_vhost"
    
    a2enmod headers > /dev/null 2>&1
    habilitar_puerto_firewall "$puerto"
    systemctl restart apache2
    echo "Apache2 listo en puerto $puerto (Directorio: $dir_vhost)"
}

desplegar_nginx() {
    local version=$1
    local puerto=$2
    
    echo "Iniciando despliegue de Nginx en modo desatendido..."
    export DEBIAN_FRONTEND=noninteractive

    pkill -9 nginx 2>/dev/null

    apt-get install -y -qq -f nginx > /dev/null 2>&1

    if [ ! -f "/lib/systemd/system/nginx.service" ]; then
        apt-get install -y --reinstall nginx-common nginx-full > /dev/null 2>&1
    fi

    local dir_vhost="/var/www/nginx_$puerto"
    mkdir -p "$dir_vhost"
    mkdir -p /etc/nginx/sites-available
    mkdir -p /etc/nginx/sites-enabled

    cat <<EOF > /etc/nginx/sites-available/default
server {
    listen $puerto;
    root $dir_vhost;
    index index.html;
    server_name _;
    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

    ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default

    generar_pagina_inicio "$dir_vhost" "Nginx" "$version" "$puerto"
    
    systemctl daemon-reload
    systemctl unmask nginx 2>/dev/null
    systemctl enable nginx 2>/dev/null
    systemctl restart nginx
    
    echo "Nginx operativo en puerto $puerto."
}

desplegar_tomcat() {
    local version=$1
    local puerto=$2
    
    local pkg="tomcat10"
    if ! apt-cache show tomcat10 > /dev/null 2>&1; then
        pkg="tomcat9"
    fi

    echo "Desplegando $pkg version $version de forma silenciosa..."
    export DEBIAN_FRONTEND=noninteractive
    
    apt-get install -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" $pkg > /dev/null 2>&1

    if [ ! -d "/etc/$pkg" ]; then
        echo "Error: La instalacion de Tomcat no fue exitosa. Verifica los repositorios." >&2
        return
    fi
    
    echo "Asignando puerto $puerto a Tomcat..."
    sed -i "s/port=\"8080\"/port=\"$puerto\"/g" /etc/$pkg/server.xml
    
    echo "Aplicando parametros de seguridad a Tomcat..."
    sed -i "s/port=\"$puerto\"/port=\"$puerto\" server=\"Apache Tomcat\"/g" /etc/$pkg/server.xml
    
    mkdir -p /var/lib/$pkg/webapps/ROOT
    generar_pagina_inicio "/var/lib/$pkg/webapps/ROOT" "Tomcat" "$version" "$puerto"
    
    chown -R $pkg:$pkg /var/lib/$pkg/webapps
    chmod -R 750 /var/lib/$pkg/webapps
    
    habilitar_puerto_firewall "$puerto"
    systemctl restart $pkg
    echo "Tomcat desplegado y asegurado correctamente en puerto $puerto."
}

habilitar_puerto_firewall() {
    local puerto=$1
    echo "Abriendo puerto $puerto en UFW..."
    ufw allow "$puerto"/tcp > /dev/null
    ufw --force enable > /dev/null
}

generar_pagina_inicio() {
    local ruta=$1
    local servicio=$2
    local version=$3
    local puerto=$4
    
    echo "<h1>Servidor: $servicio - Version: $version - Puerto: $puerto</h1>" > "$ruta/index.html"
}

escoger_version() {
    local paquete=$1
    mapfile -t lista_versiones < <(apt-cache madison "$paquete" | awk '{print $3}' | sort -Vu | tail -n 5)
    
    if [ ${#lista_versiones[@]} -eq 0 ]; then
        echo "No hay versiones disponibles para $paquete en los repositorios." >&2
        return
    fi

    echo "Versiones disponibles para $paquete:" >&2
    
    local i=1
    for ver in "${lista_versiones[@]}"; do
        echo "  $i) $ver" >&2
        ((i++))
    done

    while true; do
        read -p "Elige el numero de version (1-${#lista_versiones[@]}): " seleccion
        if [[ "$seleccion" =~ ^[0-9]+$ ]] && [ "$seleccion" -ge 1 ] && [ "$seleccion" -le "${#lista_versiones[@]}" ]; then
            local idx=$((seleccion - 1))
            echo "${lista_versiones[$idx]}"
            break
        else
            echo "Numero fuera de rango. Intenta de nuevo." >&2
        fi
    done
}

pedir_puerto() {
    local puerto
    declare -A tabla_servicios=(
        [20]="FTP" [21]="FTP" [22]="SSH" [25]="SMTP" [53]="DNS" 
        [110]="POP3" [143]="IMAP" [445]="SMB/Samba" [2222]="SSH alternativo"
        [3306]="MySQL/MariaDB" [5432]="PostgreSQL" [3389]="RDP"
    )

    local puertos_bloqueados=(1 7 9 11 13 15 17 19 20 21 22 23 25 37 42 43 53 69 77 79 110 111 113 115 117 118 119 123 135 137 139 143 161 177 179 389 427 445 465 512 513 514 515 526 530 531 532 540 548 554 556 563 587 601 636 989 990 993 995 1723 2049 2222 3306 3389 5432)

    while true; do
        read -p "Ingresa el numero de puerto para el servidor (ej. 80, 8080, 81): " puerto
        
        if [[ ! "$puerto" =~ ^[0-9]+$ ]] || [ "$puerto" -le 0 ] || [ "$puerto" -gt 65535 ]; then
            echo "Valor invalido. Ingresa un puerto entre 1 y 65535." >&2
            continue
        fi

        if [[ " ${puertos_bloqueados[*]} " =~ " ${puerto} " ]]; then
            local desc=${tabla_servicios[$puerto]:-"Servicio del sistema"}
            echo "Puerto $puerto reservado para $desc. Elige otro." >&2
            continue
        fi

        if ss -tuln | grep -q ":$puerto "; then
            echo "Puerto $puerto en uso por otro proceso. Intenta con uno diferente." >&2
            continue
        fi

        break
    done

    echo "$puerto"
}

limpiar_servicios_web() {
    echo "Ejecutando limpieza completa del entorno de servidores..."

    if ! command -v fuser &> /dev/null; then
        echo "Instalando herramienta de limpieza (psmisc)..."
        apt-get install -y -qq psmisc > /dev/null 2>&1
    fi

    echo "Parando servicios activos..."
    systemctl stop apache2 nginx tomcat10 tomcat9 2>/dev/null

    echo "Terminando procesos de servidores web en ejecucion..."
    local lista_procesos=("apache2" "nginx" "java" "httpd")
    for proc in "${lista_procesos[@]}"; do
        pids=$(pgrep -f $proc)
        if [ -n "$pids" ]; then
            kill -9 $pids 2>/dev/null
        fi
    done

    export DEBIAN_FRONTEND=noninteractive
    echo "Eliminando paquetes y archivos residuales..."
    apt-get purge -y apache2* nginx* tomcat* > /dev/null 2>&1
    apt-get autoremove -y -qq > /dev/null 2>&1
    
    rm -rf /var/www/html/*
    rm -rf /var/lib/tomcat10/webapps/ROOT/*

    echo "Sistema limpio y listo para nuevo despliegue."
}

preparar_entorno_base() {
    echo "Verificando repositorios y preparando dependencias del sistema..."
    
    if ! grep -q "bookworm" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
        echo "Registrando repositorio 'bookworm' como fuente adicional..."
        echo "deb http://deb.debian.org/debian bookworm main" >> /etc/apt/sources.list
    fi

    echo "Sincronizando indices e instalando paquetes necesarios (ufw, curl, net-tools, gawk)..."
    apt-get update -qq
    apt-get install -y -q ufw curl net-tools gawk
    apt-get install -y -qq iproute2 awk > /dev/null 2>&1
}