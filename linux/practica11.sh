#!/bin/bash

echo "Configurando la interfaz de red enp0s9..."
ip addr add 192.168.56.30/24 dev enp0s9 || echo "La IP ya está asignada o la interfaz no existe."
ip link set dev enp0s9 up

echo "Creando directorio de trabajo..."
mkdir -p /opt/practica_orquestacion
cd /opt/practica_orquestacion

echo "Generando archivo de variables de entorno (.env)..."
cat <<EOF > .env
# Credenciales seguras
POSTGRES_USER=admin_db
POSTGRES_PASSWORD=SuperSecretPassword2026!
POSTGRES_DB=practica_db
PGADMIN_DEFAULT_EMAIL=admin@practica.local
PGADMIN_DEFAULT_PASSWORD=AdminPassword2026!
EOF

echo "Generando configuración del Balanceador Nginx (nginx.conf)..."
cat <<EOF > nginx.conf
worker_processes 1;
events { worker_connections 1024; }

http {
    server_tokens off;

    upstream app_interna {
        server internal_webapp:80;
    }

    server {
        listen 80;
        server_name localhost;

        location / {
            proxy_pass http://app_interna;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
        }
    }
}
EOF

echo "Generando aplicación web secundaria (index.html)..."
cat <<EOF > index.html
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>Servicio Interno Seguro</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #f4f4f9; color: #333; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }
        .container { background-color: white; padding: 40px; border-radius: 10px; box-shadow: 0 4px 15px rgba(0,0,0,0.1); text-align: center; max-width: 500px; border-top: 5px solid #612766; }
        h1 { color: #003d82; margin-bottom: 10px;}
        p { color: #555; line-height: 1.6; }
        .badge { background-color: #612766; color: white; padding: 5px 15px; border-radius: 20px; font-size: 0.9em; font-weight: bold; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Acceso Concedido</h1>
        <p>Estás viendo el contenedor interno a través del balanceador Nginx.</p>
        <span class="badge">Red Aislada</span>
    </div>
</body>
</html>
EOF
echo "¡Archivos generados con exito! El siguiente paso es crear el docker-compose.yml"