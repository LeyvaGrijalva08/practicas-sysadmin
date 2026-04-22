#!/bin/bash

DOMAIN="www.reprobados.com"

function instalar_dependencias_base() {
    echo "Preparando entorno limpio..."
    apt-get update -y > /dev/null 2>&1
    apt-get install -y curl wget openssl ufw debconf-utils authbind default-jdk > /dev/null 2>&1
    echo "Dependencias base instaladas."
}

function limpiar_entorno() {
    echo "=== LIMPIEZA DE ENTORNO ==="
    echo "Deteniendo servicios..."
    systemctl stop apache2 nginx tomcat9 vsftpd 2>/dev/null
    
    echo "Desinstalando paquetes..."
    apt-get purge -y apache2 apache2-utils apache2-bin nginx tomcat9 vsftpd > /dev/null 2>&1
    apt-get autoremove -y > /dev/null 2>&1
    
    echo "Ingrese el puerto TCP que desea liberar y limpiar (ej. 80, 443, 8080) o presione Enter para omitir:"
    read puerto_limpiar
    if [ ! -z "$puerto_limpiar" ]; then
        ufw delete allow $puerto_limpiar/tcp > /dev/null 2>&1
        echo "Puerto $puerto_limpiar liberado en el firewall."
    fi
    
    rm -rf /etc/ssl/certs/reprobados* /etc/ssl/private/reprobados*
    rm -rf /etc/apache2 /etc/nginx /etc/vsftpd.conf /var/www/html/*
    echo "Limpieza completada."
}

function configurar_ssl() {
    local servicio=$1
    echo "Generando certificado SSL para $DOMAIN..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/private/reprobados_$servicio.key \
        -out /etc/ssl/certs/reprobados_$servicio.crt \
        -subj "/C=MX/ST=Sinaloa/L=LosMochis/O=FIM/CN=$DOMAIN" 2>/dev/null
    echo "Certificado generado."
}

function verificar_hash() {
    local archivo=$1
    echo "Verificando integridad del archivo..."
    if sha256sum -c "$archivo.sha256" > /dev/null 2>&1; then
        echo "Integridad validada correctamente (SHA256 coincide)."
    else
        echo "ERROR: Archivo corrupto. El hash no coincide."
        exit 1
    fi
}

function generar_index_visual() {
    local servidor=$1
    local ssl_status=$2
    local puerto=$3
    local color="red"
    local msg="SITIO NO SEGURO (HTTP)"
    
    if [[ "$ssl_status" == "S" || "$ssl_status" == "s" ]]; then
        color="green"
        msg="SITIO SEGURO (HTTPS)"
    fi
    
    mkdir -p /var/www/html
    cat > /var/www/html/index.html <<EOF
<html>
<body>
    <p>El servidor <strong>$servidor</strong> se ha instalado y configurado correctamente.</p>
    <ul>
        <li><strong>Estado de seguridad:</strong> $msg</li>
        <li><strong>Puerto en uso:</strong> $puerto</li>
    </ul>
</body>
</html>
EOF
}

function instalar_servicio() {
    echo "=== INSTALACION DE SERVICIO ==="
    echo "1. Apache"
    echo "2. Nginx"
    echo "3. Tomcat"
    echo "4. vsftpd (FTP)"
    echo "Seleccione el servicio:"
    read opt_servicio
    
    case $opt_servicio in
        1) srv_name="apache2"; folder_name="Apache" ;;
        2) srv_name="nginx"; folder_name="Nginx" ;;
        3) srv_name="tomcat9"; folder_name="Tomcat" ;;
        4) srv_name="vsftpd"; folder_name="vsftpd" ;;
        *) echo "Opcion invalida"; return ;;
    esac

    echo "Seleccione origen de instalacion:"
    echo "1. WEB (Repositorio Oficial apt)"
    echo "2. FTP (Repositorio Privado)"
    read opt_origen

    if [ "$opt_origen" == "2" ]; then
        echo "Ingrese IP del servidor FTP:"
        read ftp_ip
        echo "Usuario FTP:"
        read ftp_user
        echo "Password FTP:"
        read -s ftp_pass
        echo ""
        
        base_url="ftps://$ftp_ip/http/Linux/$folder_name/"
        echo "Listando archivos en $base_url ..."
        
        mapfile -t archivos_versiones < <(curl -s --show-error -l --insecure -u "$ftp_user:$ftp_pass" "$base_url" | grep -v '\.sha256$' | grep -v '\.md5$')
        
        if [ ${#archivos_versiones[@]} -eq 0 ]; then
            echo "No se encontraron archivos binarios. Verifica credenciales y conexion segura."
            return 1
        fi
        
        for i in "${!archivos_versiones[@]}"; do
            archivo=$(echo "${archivos_versiones[$i]}" | tr -d '\r')
            echo "$((i+1))) $archivo"
        done
        
        read -p "Selecciona el numero de la version a descargar: " sel_ver
        local index_ver=$((sel_ver-1))
        ftp_archivo=$(echo "${archivos_versiones[$index_ver]}" | tr -d '\r')
        
        echo "Descargando $ftp_archivo y firma hash..."
        curl -s --show-error --insecure -u "$ftp_user:$ftp_pass" "$base_url$ftp_archivo" -O
        curl -s --show-error --insecure -u "$ftp_user:$ftp_pass" "$base_url$ftp_archivo.sha256" -O
        
        verificar_hash "$ftp_archivo"
        
        echo "Instalando paquete silenciosamente..."
        if [[ "$ftp_archivo" == *.deb ]]; then
            export DEBIAN_FRONTEND=noninteractive
            dpkg -i "$ftp_archivo" > /dev/null 2>&1 || apt-get install -f -y > /dev/null 2>&1
        elif [[ "$ftp_archivo" == *.tar.gz ]]; then
            tar -xzf "$ftp_archivo" -C /opt/
        fi
    else
        echo "Instalando $srv_name via WEB de forma silenciosa..."
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -y $srv_name > /dev/null 2>&1
    fi

    echo "Ingrese el puerto principal a utilizar (ej. 80 para HTTP, 21 para FTP):"
    read puerto_principal
    ufw allow $puerto_principal/tcp > /dev/null 2>&1

    echo "Desea activar SSL en este servicio? [S/N]"
    read activar_ssl
    puerto_ssl=$puerto_principal
    
    if [[ "$activar_ssl" == "S" || "$activar_ssl" == "s" ]]; then
        echo "Ingrese el puerto seguro a utilizar (ej. 443 o 990):"
        read puerto_seguro
        puerto_ssl=$puerto_seguro
        ufw allow $puerto_seguro/tcp > /dev/null 2>&1
        configurar_ssl $srv_name
    fi

    if [ "$srv_name" != "vsftpd" ]; then
        generar_index_visual "$folder_name" "$activar_ssl" "$puerto_ssl"
    fi

    # ================= CONFIGURACIONES ESPECIFICAS =================
    
    if [ "$srv_name" == "apache2" ]; then
        if [[ "$activar_ssl" == "S" || "$activar_ssl" == "s" ]]; then
            a2enmod ssl rewrite headers > /dev/null 2>&1
            cat > /etc/apache2/ports.conf <<EOF
Listen $puerto_principal
<IfModule ssl_module>
    Listen $puerto_seguro
</IfModule>
EOF
            cat > /etc/apache2/sites-available/000-default.conf <<EOF
<VirtualHost *:$puerto_principal>
    ServerName $DOMAIN
    Redirect permanent / https://$DOMAIN:$puerto_seguro/
</VirtualHost>
<VirtualHost *:$puerto_seguro>
    ServerName $DOMAIN
    DocumentRoot /var/www/html
    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/reprobados_$srv_name.crt
    SSLCertificateKeyFile /etc/ssl/private/reprobados_$srv_name.key
    Header always set Strict-Transport-Security "max-age=63072000; includeSubdomains;"
</VirtualHost>
EOF
        else
            a2dismod ssl > /dev/null 2>&1
            cat > /etc/apache2/ports.conf <<EOF
Listen $puerto_principal
EOF
            cat > /etc/apache2/sites-available/000-default.conf <<EOF
<VirtualHost *:$puerto_principal>
    ServerName $DOMAIN
    DocumentRoot /var/www/html
</VirtualHost>
EOF
        fi
        systemctl restart apache2

    elif [ "$srv_name" == "nginx" ]; then
        if [[ "$activar_ssl" == "S" || "$activar_ssl" == "s" ]]; then
            cat > /etc/nginx/sites-available/default <<EOF
server {
    listen $puerto_principal;
    server_name $DOMAIN;
    return 301 https://\$host:$puerto_seguro\$request_uri;
}
server {
    listen $puerto_seguro ssl;
    server_name $DOMAIN;
    ssl_certificate /etc/ssl/certs/reprobados_$srv_name.crt;
    ssl_certificate_key /etc/ssl/private/reprobados_$srv_name.key;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    root /var/www/html;
    index index.html;
}
EOF
        else
            cat > /etc/nginx/sites-available/default <<EOF
server {
    listen $puerto_principal;
    server_name $DOMAIN;
    root /var/www/html;
    index index.html;
}
EOF
        fi
        systemctl restart nginx

    elif [ "$srv_name" == "tomcat9" ]; then
        T_USER=$(grep -E '^tomcat' /etc/passwd | cut -d: -f1 | head -n 1)
        if [ -z "$T_USER" ]; then T_USER="tomcat9"; fi
        
        mkdir -p /etc/authbind/byport/
        touch /etc/authbind/byport/$puerto_principal
        chown $T_USER:$T_USER /etc/authbind/byport/$puerto_principal
        chmod 755 /etc/authbind/byport/$puerto_principal
        
        sed -i 's/#AUTHBIND=no/AUTHBIND=yes/' /etc/default/$srv_name
        
        mkdir -p /var/lib/$srv_name/webapps/ROOT
        cp /var/www/html/index.html /var/lib/$srv_name/webapps/ROOT/index.html
        chown -R $T_USER:$T_USER /var/lib/$srv_name/webapps/ROOT

        if [[ "$activar_ssl" == "S" || "$activar_ssl" == "s" ]]; then
            touch /etc/authbind/byport/$puerto_seguro
            chown $T_USER:$T_USER /etc/authbind/byport/$puerto_seguro
            chmod 755 /etc/authbind/byport/$puerto_seguro
            
            ks="/etc/ssl/private/tomcat_keystore.p12"
            openssl pkcs12 -export -in "/etc/ssl/certs/reprobados_$srv_name.crt" \
                -inkey "/etc/ssl/private/reprobados_$srv_name.key" -out "$ks" \
                -name tomcat -password pass:reprobados -passout pass:reprobados 2>/dev/null
            chown $T_USER:$T_USER "$ks"

            cat > /etc/$srv_name/server.xml <<EOF
<Server port="8005" shutdown="SHUTDOWN">
  <Service name="Catalina">
    <Connector port="$puerto_principal" protocol="HTTP/1.1" connectionTimeout="20000" redirectPort="$puerto_seguro" />
    <Connector port="$puerto_seguro" protocol="org.apache.coyote.http11.Http11NioProtocol" maxThreads="150" SSLEnabled="true">
      <SSLHostConfig><Certificate certificateKeystoreFile="$ks" type="RSA" certificateKeystorePassword="reprobados" /></SSLHostConfig>
    </Connector>
    <Engine name="Catalina" defaultHost="localhost">
      <Host name="localhost" appBase="webapps" unpackWARs="true" autoDeploy="true" />
    </Engine>
  </Service>
</Server>
EOF
        else
            cat > /etc/$srv_name/server.xml <<EOF
<Server port="8005" shutdown="SHUTDOWN">
  <Service name="Catalina">
    <Connector port="$puerto_principal" protocol="HTTP/1.1" connectionTimeout="20000" />
    <Engine name="Catalina" defaultHost="localhost">
      <Host name="localhost" appBase="webapps" unpackWARs="true" autoDeploy="true" />
    </Engine>
  </Service>
</Server>
EOF
        fi
        systemctl restart $srv_name
        sleep 5

    elif [ "$srv_name" == "vsftpd" ]; then
        if ! grep -q "/bin/bash" /etc/shells; then
            echo /bin/bash >> /etc/shells
        fi
        
        mkdir -p /srv/ftp/autenticados
        
        cat > /etc/vsftpd.conf <<EOF
listen=YES
listen_ipv6=NO
connect_from_port_20=YES
local_enable=YES
write_enable=YES
local_umask=002
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
pam_service_name=vsftpd
user_sub_token=\$USER
chroot_local_user=YES
allow_writeable_chroot=YES
local_root=/srv/ftp/autenticados/\$USER
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=50000
listen_port=$puerto_principal
EOF

        if [[ "$activar_ssl" == "S" || "$activar_ssl" == "s" ]]; then
            cat >> /etc/vsftpd.conf <<EOF
listen_port=$puerto_seguro
ssl_enable=YES
allow_anon_ssl=NO
force_local_data_ssl=YES
force_local_logins_ssl=YES
ssl_tlsv1=YES
ssl_sslv2=NO
ssl_sslv3=NO
require_ssl_reuse=NO
ssl_ciphers=HIGH
rsa_cert_file=/etc/ssl/certs/reprobados_$srv_name.crt
rsa_private_key_file=/etc/ssl/private/reprobados_$srv_name.key
implicit_ssl=YES
EOF
        else
            cat >> /etc/vsftpd.conf <<EOF
anonymous_enable=YES
anon_root=/srv/ftp/anon
EOF
            mkdir -p /srv/ftp/anon
        fi
        ufw allow 40000:50000/tcp > /dev/null 2>&1
        systemctl restart vsftpd
    fi
    
    echo "=== RESUMEN DE VERIFICACION ==="
    echo "Servicio $srv_name instalado."
    echo "Puerto principal configurado y abierto: $puerto_principal"
    if [[ "$activar_ssl" == "S" || "$activar_ssl" == "s" ]]; then
        echo "Puerto seguro configurado y abierto: $puerto_seguro"
    fi
    systemctl is-active $srv_name
    echo "Presione Enter para continuar..."
    read
}

instalar_dependencias_base

while true; do
    echo ""
    echo "=========================================================="
    echo "      ORQUESTADOR HIBRIDO DE SERVICIOS (LINUX)            "
    echo "=========================================================="
    echo "1. Instalar Servicio"
    echo "2. Limpiar Entorno (Puertos y Apps)"
    echo "3. Salir"
    read -p "Opcion: " opcion
    
    case $opcion in
        1) instalar_servicio ;;
        2) limpiar_entorno ;;
        3) echo "Saliendo..."; exit 0 ;;
        *) echo "Opcion no valida." ;;
    esac
done