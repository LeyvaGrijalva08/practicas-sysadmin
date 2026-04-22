#!/bin/bash
set -euo pipefail

DOMAIN_NAME="practica8_repo.com"      # Nombre del dominio
DOMAIN_UPPER="PRACTICA8_REPO.COM"     # Kerberos realm (MAYUSCULAS)
DOMAIN_SHORT="PRACTICA8"              # NetBIOS
DC_IP="192.168.56.100"               # IP del servidor Windows Server 2022
DOMAIN_ADMIN="Administrator"          # Admin del dominio (servidor en ingles)
                                      # Contrasena: Leyvagrijalva08* (se pide interactivo)
AD_SUDO_GROUP="GRP_Cuates"           # Grupo AD con permisos sudo en Linux

LINUX_IP="192.168.56.102"          
LINUX_IFACE=""                    

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log_ok()    { echo -e "${GREEN}[+] $1${NC}"; }
log_info()  { echo -e "${CYAN}[i] $1${NC}"; }
log_warn()  { echo -e "${YELLOW}[!] $1${NC}"; }
log_error() { echo -e "${RED}[X] $1${NC}"; }
log_title() { echo -e "\n${CYAN}===== $1 =====${NC}"; }

if [ "$EUID" -ne 0 ]; then
    log_error "Ejecutar como root: sudo bash $0"
    exit 1
fi

log_title "CONFIGURANDO IP ESTATICA EN ADAPTADOR 3 (HOST-ONLY)"

IFACES=($(ip -o link show | grep -v 'lo' | awk '{print $2}' | tr -d ':'))
log_info "Adaptadores detectados: ${IFACES[*]}"

if [ ${#IFACES[@]} -lt 3 ]; then
    log_error "Solo se detectaron ${#IFACES[@]} adaptadores. Se necesitan al menos 3."
    log_error "Verifica que VirtualBox tenga 3 adaptadores de red habilitados."
    exit 1
fi

LINUX_IFACE="${IFACES[2]}"   # Tercer adaptador (indice 0-based = 2)
log_info "Adaptador 3 seleccionado: $LINUX_IFACE"

# Configurar IP estatica con netplan (Ubuntu 22.04 usa netplan)
NETPLAN_FILE="/etc/netplan/99-practica-hostonly.yaml"
cat > "$NETPLAN_FILE" << EOF
network:
  version: 2
  ethernets:
    $LINUX_IFACE:
      dhcp4: false
      addresses:
        - $LINUX_IP/24
      nameservers:
        addresses:
          - $DC_IP
          - 8.8.8.8
        search:
          - $DOMAIN_NAME
EOF

chmod 600 "$NETPLAN_FILE"
netplan apply 2>/dev/null || true
sleep 3
log_ok "IP estatica $LINUX_IP/24 asignada a $LINUX_IFACE"

# PASO 2: CONFIGURAR /etc/hosts Y DNS
log_title "CONFIGURANDO DNS"

if ! grep -q "$DC_IP $DOMAIN_NAME" /etc/hosts; then
    echo "$DC_IP $DOMAIN_NAME" >> /etc/hosts
    log_ok "Entrada DNS en /etc/hosts: $DC_IP $DOMAIN_NAME"
fi

# systemd-resolved: apuntar al DC como DNS primario
cat > /etc/systemd/resolved.conf << EOF
[Resolve]
DNS=$DC_IP
FallbackDNS=8.8.8.8
Domains=$DOMAIN_NAME
EOF
systemctl restart systemd-resolved
sleep 2

log_info "Verificando conectividad con el servidor ($DC_IP)..."
if ! ping -c 2 -W 3 "$DC_IP" &>/dev/null; then
    log_error "No se puede contactar al servidor en $DC_IP. Verifica la red."
    exit 1
fi
log_ok "Servidor contactado."

# PASO 3: INSTALAR PAQUETES
log_title "INSTALANDO PAQUETES"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq

apt-get install -y \
    realmd sssd sssd-tools adcli krb5-user \
    samba-common-bin oddjob oddjob-mkhomedir \
    libpam-sss libnss-sss packagekit 2>/dev/null || true

log_ok "Paquetes instalados."

# PASO 4: CONFIGURAR KERBEROS
log_title "CONFIGURANDO KERBEROS"

cat > /etc/krb5.conf << EOF
[libdefaults]
    default_realm = $DOMAIN_UPPER
    dns_lookup_realm = true
    dns_lookup_kdc = true
    ticket_lifetime = 24h
    renew_lifetime = 7d
    forwardable = true
    rdns = false

[realms]
    $DOMAIN_UPPER = {
        kdc = $DC_IP
        admin_server = $DC_IP
        default_domain = $DOMAIN_NAME
    }

[domain_realm]
    .$DOMAIN_NAME = $DOMAIN_UPPER
    $DOMAIN_NAME  = $DOMAIN_UPPER
EOF

log_ok "/etc/krb5.conf configurado."

# PASO 5: DESCUBRIR Y UNIR AL DOMINIO
log_title "UNIENDO AL DOMINIO $DOMAIN_NAME"

log_info "Descubriendo dominio..."
realm discover "$DOMAIN_NAME" 2>&1 | head -15

log_info "Ingresa la contrasena del usuario '$DOMAIN_ADMIN' del dominio (Leyvagrijalva08*):"
realm join --user="$DOMAIN_ADMIN" "$DOMAIN_NAME"
log_ok "Equipo unido al dominio '$DOMAIN_NAME'."

# PASO 6: CONFIGURAR SSSD
log_title "CONFIGURANDO SSSD"

cat > /etc/sssd/sssd.conf << EOF
[sssd]
domains = $DOMAIN_NAME
config_file_version = 2
services = nss, pam

[domain/$DOMAIN_NAME]
id_provider = ad
auth_provider = ad
ad_server = $DC_IP
ad_domain = $DOMAIN_NAME
krb5_realm = $DOMAIN_UPPER

# REQUERIDO POR LAS INSTRUCCIONES:
# %u = username (ej: cramirez), %d = dominio (ej: practica8_repo.com)
# Resultado: /home/cramirez@practica8_repo.com
fallback_homedir = /home/%u@%d

default_shell = /bin/bash

# Permite iniciar sesion solo con el nombre corto (sin @dominio)
use_fully_qualified_names = False

ldap_id_mapping = True
access_provider = ad
cache_credentials = True
debug_level = 1
EOF

chmod 600 /etc/sssd/sssd.conf
log_ok "/etc/sssd/sssd.conf configurado con fallback_homedir = /home/%u@%d"

# PASO 7: CREACION AUTOMATICA DE HOME CON ODDJOB
log_title "CONFIGURANDO CREACION AUTOMATICA DE HOME"

pam-auth-update --enable mkhomedir 2>/dev/null || {
    if ! grep -q "pam_oddjob_mkhomedir" /etc/pam.d/common-session; then
        echo "session required pam_oddjob_mkhomedir.so skel=/etc/skel umask=0077" >> /etc/pam.d/common-session
    fi
}

systemctl enable oddjobd && systemctl start oddjobd
log_ok "oddjobd configurado: homes se crean automaticamente al iniciar sesion."

# PASO 8: CONFIGURAR SUDO PARA GRUPO AD
log_title "CONFIGURANDO SUDO PARA AD"

SUDOERS_FILE="/etc/sudoers.d/ad-admins"
cat > "$SUDOERS_FILE" << EOF
# Permisos de sudo para usuarios del dominio $DOMAIN_NAME
# Grupo '$AD_SUDO_GROUP' de AD tiene sudo completo
%$AD_SUDO_GROUP ALL=(ALL:ALL) ALL
EOF

chmod 440 "$SUDOERS_FILE"
visudo -c -f "$SUDOERS_FILE" && log_ok "Sudoers valido: /etc/sudoers.d/ad-admins" || {
    log_error "Error en sudoers. Revisa el archivo."
    exit 1
}

# PASO 9: REINICIAR SERVICIOS
log_title "REINICIANDO SERVICIOS"

systemctl restart sssd && systemctl enable sssd
systemctl restart oddjobd
sleep 5

systemctl is-active --quiet sssd && log_ok "SSSD activo." || {
    log_error "SSSD no esta corriendo. Revisa: journalctl -u sssd -n 50"
    exit 1
}

log_title "UNION AL DOMINIO COMPLETADA"

echo ""
realm list
echo ""
log_info "Estado de SSSD: $(systemctl is-active sssd)"
echo ""
echo -e "${GREEN}Equipo '$(hostname)' unido a '$DOMAIN_NAME' exitosamente.${NC}"
echo ""
echo -e "${YELLOW}COMO INICIAR SESION:${NC}"
echo "  Nombre usuario: cramirez  (nombre corto, sin @dominio)"
echo "  Home: /home/cramirez@$DOMAIN_NAME"
echo ""
echo -e "${YELLOW}LOGS UTILES:${NC}"
echo "  journalctl -u sssd -f"
echo "  id cramirez    (verifica usuario desde AD)"
echo "  realm list     (estado del dominio)"
