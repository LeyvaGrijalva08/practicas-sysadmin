#!/bin/bash
echo "Iniciando despliegue de infraestructura de correo"
mkdir -p /opt/sistema_correo/configuracion /opt/sistema_correo/datos /opt/sistema_correo/registros /opt/sistema_correo/bd_web /opt/sistema_correo/respaldos
cd /opt/sistema_correo
cat <<EOF > .env
DOMINIO_ORG=reprobados.com
HOST_ORG=mail.reprobados.com
CLAVE_RAIZ_BD=RootSecure2026!
USUARIO_BD=admin_rc
CLAVE_BD=PassWebmail2026!
NOMBRE_BD=roundcubemail
EOF
cat <<EOF > docker-compose.yml
version: '3.8'
services:
  srv_correo:
    image: ghcr.io/docker-mailserver/docker-mailserver:latest
    container_name: srv_correo_principal
    hostname: \${HOST_ORG}
    domainname: \${DOMINIO_ORG}
    ports:
      - "25:25"
      - "143:143"
      - "587:587"
      - "993:993"
    volumes:
      - ./datos:/var/mail
      - ./configuracion:/tmp/docker-mailserver
      - ./registros:/var/log/mail
      - /etc/localtime:/etc/localtime:ro
    environment:
      - ENABLE_SPAMASSASSIN=1
      - ENABLE_CLAMAV=1
      - ENABLE_FAIL2BAN=1
      - ENABLE_POSTGREY=1
      - ONE_DIR=1
      - DMS_DEBUG=0
    restart: always
    cap_add:
      - NET_ADMIN
  srv_bd:
    image: mariadb:10
    container_name: srv_base_datos
    environment:
      MYSQL_ROOT_PASSWORD: \${CLAVE_RAIZ_BD}
      MYSQL_DATABASE: \${NOMBRE_BD}
      MYSQL_USER: \${USUARIO_BD}
      MYSQL_PASSWORD: \${CLAVE_BD}
    volumes:
      - ./bd_web:/var/lib/mysql
    restart: always
  srv_webmail:
    image: roundcube/roundcubemail:latest
    container_name: srv_portal_web
    ports:
      - "80:80"
    environment:
      - ROUNDCUBEMAIL_DB_TYPE=mysql
      - ROUNDCUBEMAIL_DB_HOST=srv_bd
      - ROUNDCUBEMAIL_DB_USER=\${USUARIO_BD}
      - ROUNDCUBEMAIL_DB_PASSWORD=\${CLAVE_BD}
      - ROUNDCUBEMAIL_DB_NAME=\${NOMBRE_BD}
      - ROUNDCUBEMAIL_DEFAULT_HOST=srv_correo
      - ROUNDCUBEMAIL_SMTP_SERVER=srv_correo
      - ROUNDCUBEMAIL_SKIN=elastic
    depends_on:
      - srv_correo
      - srv_bd
    restart: always
networks:
  default:
    name: red_mensajeria
EOF
cat <<EOF > respaldo_diario.sh
#!/bin/bash
MARCA_TIEMPO=\$(date +%Y-%m-%d_%H-%M)
tar -czf /opt/sistema_correo/respaldos/respaldo_\$MARCA_TIEMPO.tar.gz -C /opt/sistema_correo/datos .
echo "Respaldo generado exitosamente en /opt/sistema_correo/respaldos"
EOF
chmod +x respaldo_diario.sh
docker-compose up -d
echo "Despliegue finalizado sin errores"