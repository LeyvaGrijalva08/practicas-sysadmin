#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

msg_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
msg_error() { echo -e "${RED}[ERROR]${NC} $1"; }

instalar_ftp() {
    if dpkg -s vsftpd >/dev/null 2>&1; then
        read -p "vsftpd ya esta instalado. Deseas reinstalar y resetear la configuracion? (s/n): " resp
        [[ "$resp" != "s" ]] && return
    fi

    if apt-get update > /dev/null 2>&1 && DEBIAN_FRONTEND=noninteractive apt-get install -y vsftpd ftp > /dev/null 2>&1; then
        msg_info "Paquetes instalados correctamente."
    else
        msg_error "Fallo la instalacion de los paquetes."
        return
    fi

    if ! grep -q "^/bin/false$" /etc/shells; then
        echo "/bin/false" >> /etc/shells
    fi

    cat <<EOF > /etc/vsftpd.conf
listen=NO
listen_ipv6=YES
anonymous_enable=YES
no_anon_password=YES
anon_root=/srv/ftp
local_enable=YES
write_enable=YES
local_umask=000
file_open_mode=0777
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES
chroot_local_user=YES
allow_writeable_chroot=YES
secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=vsftpd
user_sub_token=\$USER
local_root=/home/\$USER/ftp
EOF

    mkdir -p /srv/ftp/general
    chown -R ftp:ftp /srv/ftp/general
    chmod 555 /srv/ftp
    chmod 777 /srv/ftp/general

    groupadd -f reprobados
    groupadd -f recursadores

    systemctl restart vsftpd
    msg_info "Servicio FTP instalado con exito."
}

crear_usuarios() {
    read -p "Numero de usuarios a crear: " n
    
    for (( i=1; i<=n; i++ )); do
        echo "--- Usuario $i ---"
        read -p "Nombre de usuario: " username
        read -s -p "Contrasena: " password
        echo
        
        while true; do
            read -p "Grupo (1: reprobados, 2: recursadores): " g_opt
            case $g_opt in
                1) grupo="reprobados"; break ;;
                2) grupo="recursadores"; break ;;
                *) msg_error "Opcion no valida." ;;
            esac
        done

        if id "$username" &>/dev/null; then
            msg_error "El usuario $username ya existe."
            continue
        fi

        useradd -m -g "$grupo" -s /bin/false "$username"
        echo "$username:$password" | chpasswd

        BASE_DIR="/home/$username/ftp"
        mkdir -p "$BASE_DIR/general"
        mkdir -p "$BASE_DIR/$grupo"
        mkdir -p "$BASE_DIR/$username"

        DATA_ROOT="/var/ftp_data"
        mkdir -p "$DATA_ROOT/grupos/$grupo"
        mkdir -p "$DATA_ROOT/usuarios/$username"

        chown "$username:$grupo" "$DATA_ROOT/usuarios/$username"
        chmod 770 "$DATA_ROOT/usuarios/$username"
        
        chown :"$grupo" "$DATA_ROOT/grupos/$grupo"
        chmod 777 "$DATA_ROOT/grupos/$grupo"

        echo "/srv/ftp/general $BASE_DIR/general none bind 0 0" >> /etc/fstab
        echo "$DATA_ROOT/grupos/$grupo $BASE_DIR/$grupo none bind 0 0" >> /etc/fstab
        echo "$DATA_ROOT/usuarios/$username $BASE_DIR/$username none bind 0 0" >> /etc/fstab
        
        systemctl daemon-reload
        mount -a
        
        msg_info "Usuario $username creado y vinculado al grupo $grupo."
    done
}

cambiar_grupo() {
    read -p "Nombre del usuario a modificar: " username
    if ! id "$username" &>/dev/null; then
        msg_error "El usuario no existe."
        return
    fi

    grupo_viejo=$(id -gn "$username")
    
    while true; do
        read -p "Nuevo Grupo (1: reprobados, 2: recursadores): " g_opt
        case $g_opt in
            1) grupo_nuevo="reprobados"; break ;;
            2) grupo_nuevo="recursadores"; break ;;
            *) msg_error "Opcion no valida." ;;
        esac
    done

    if [ "$grupo_viejo" == "$grupo_nuevo" ]; then
        msg_error "El usuario ya pertenece a este grupo."
        return
    fi

    usermod -g "$grupo_nuevo" "$username"

    BASE_DIR="/home/$username/ftp"
    
    umount "$BASE_DIR/$grupo_viejo"
    rmdir "$BASE_DIR/$grupo_viejo"
    
    sed -i "s|grupos/$grupo_viejo $BASE_DIR/$grupo_viejo|grupos/$grupo_nuevo $BASE_DIR/$grupo_nuevo|" /etc/fstab
    
    mkdir -p "$BASE_DIR/$grupo_nuevo"
    systemctl daemon-reload
    mount -a
    
    msg_info "Usuario $username movido a $grupo_nuevo exitosamente."
}

while true; do
    echo -e "\nMENU DE GESTION FTP"
    echo "1. Instalar/Reinstalar Servidor FTP"
    echo "2. Creacion Masiva de Usuarios"
    echo "3. Cambiar Usuario de Grupo"
    echo "4. Salir"
    read -p "Seleccione una opcion: " opcion

    case $opcion in
        1) instalar_ftp ;;
        2) crear_usuarios ;;
        3) cambiar_grupo ;;
        4) exit 0 ;;
        *) msg_error "Opcion no valida." ;;
    esac
done