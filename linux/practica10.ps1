#!/bin/bash

echo "Instalando Docker y dependencias necesarias..."
apt-get update -y
apt-get install -y ca-certificates curl gnupg ftp
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "Liberando puerto 80 local..."
systemctl stop apache2 2>/dev/null
systemctl disable apache2 2>/dev/null

IP_HOST=$(ip -4 addr show dev enp0s9 | awk '/inet / {print $2}' | cut -d/ -f1)
PASS_DB="AdminUAS2026"
PASS_FTP="secreto"

echo "Limpiando entorno previo..."
docker rm -f servidor_web servidor_ftp servidor_bd 2>/dev/null
docker network rm infra_red 2>/dev/null

echo "Creando red y volumenes..."
docker network create --driver bridge --subnet=172.20.0.0/16 infra_red
docker volume create db_data
docker volume create web_content

echo "Preparando directorio de respaldos..."
mkdir -p /respaldos_postgres
chmod 777 /respaldos_postgres

echo "Generando Dockerfile Hardened..."
cat << 'EOF' > Dockerfile
FROM nginx:alpine
RUN sed -i '/http {/a \    server_tokens off;' /etc/nginx/nginx.conf
RUN sed -i 's/80;/8080;/g' /etc/nginx/conf.d/default.conf
RUN sed -i '/^user /d' /etc/nginx/nginx.conf
RUN sed -i '/^pid /d' /etc/nginx/nginx.conf
RUN chown -R nginx:nginx /var/cache/nginx /var/log/nginx /etc/nginx /usr/share/nginx/html
USER nginx
EXPOSE 8080
CMD ["nginx", "-g", "daemon off; pid /tmp/nginx.pid;"]
EOF

echo "Construyendo imagen web..."
docker build -t web_seguro_uas . > /dev/null

echo "Levantando PostgreSQL..."
docker run -d \
  --name servidor_bd \
  --network infra_red \
  --memory="512m" --cpuset-cpus="0" \
  -e POSTGRES_PASSWORD=$PASS_DB \
  -v db_data:/var/lib/postgresql/data \
  -v /respaldos_postgres:/respaldos \
  postgres:15-alpine > /dev/null

echo "Levantando Servidor FTP con IP ${IP_HOST}..."
docker run -d \
  --name servidor_ftp \
  --network infra_red \
  --memory="256m" --cpuset-cpus="0" \
  -p 21:21 \
  -p 21000-21010:21000-21010 \
  -e USERS="adminweb|${PASS_FTP}|/home/adminweb" \
  -e ADDRESS=$IP_HOST \
  -v web_content:/home/adminweb \
  delfer/alpine-ftp-server > /dev/null

echo "Levantando Nginx Seguro..."
docker run -d \
  --name servidor_web \
  --network infra_red \
  --memory="512m" --cpuset-cpus="0" \
  -p 80:8080 \
  -v web_content:/usr/share/nginx/html \
  web_seguro_uas > /dev/null

echo "Despliegue finalizado. Contenedores activos:"
sleep 3
docker ps