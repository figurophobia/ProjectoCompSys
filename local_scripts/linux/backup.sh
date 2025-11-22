#!/bin/bash
#
# SCRIPT DE BACKUP CON LVM SNAPSHOT (PULL)
# Garantiza consistencia de datos (Atomic Backup).
#

set -o pipefail

# --- CONFIGURACIÓN ---
SSH_USER="root"

# Datos del LVM Remoto (TIENES QUE EDITAR ESTO SEGÚN TU SERVIDOR)
# Ejecuta 'lsblk' o 'lvdisplay' en el remoto para saber estos nombres.
REMOTE_VG="ubuntu-vg"     # Nombre del Grupo de Volúmenes (ej: ubuntu-vg, centos)
REMOTE_LV="ubuntu-lv"     # Nombre del Volumen Lógico donde están los datos (ej: root, data)
SNAPSHOT_SIZE="512M"      # Tamaño reservado para cambios durante el backup (reducido a 512MB)

if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
    echo "Uso: $0 <ip> \"<ruta_relativa_dentro_del_snapshot>\" <dir_destino>"
    echo "Ejemplo: $0 192.168.1.50 var/www /backups"
    exit 1
fi

TARGET_IP="$1"
# Nota: Al montar el snapshot, la ruta ya no es /var/www, sino /mnt/backup_snap/var/www
# Por eso pedimos la ruta relativa (sin la primera barra /)
SOURCE_REL_PATH="$2" 
LOCAL_BACKUP_DIR="$3"

mkdir -p "$LOCAL_BACKUP_DIR"

# Verificación de conexión
if ! ssh -o ConnectTimeout=5 "${SSH_USER}@${TARGET_IP}" "echo ok" >/dev/null 2>&1; then
    echo "ERROR: No se pudo conectar a $TARGET_IP."
    exit 1
fi

TIMESTAMP=$(date +%Y-%m-%d_%H%M)
REMOTE_SNAP_NAME="snap_backup_${TIMESTAMP}"
REMOTE_MOUNT_POINT="/mnt/backup_temp_${TIMESTAMP}"
REMOTE_TEMP_FILE="/tmp/backup-${TARGET_IP}.tar.gz"
LOCAL_FILE="$LOCAL_BACKUP_DIR/backup-${TARGET_IP}-${TIMESTAMP}.tar.gz"

echo "--------------------------------------------------"
echo "Iniciando Backup LVM Consistente de $TARGET_IP"
echo "--------------------------------------------------"

# 1. CREAR SNAPSHOT, MONTAR, COMPRIMIR Y LIMPIAR (Todo en un bloque SSH para seguridad)
# Usamos 'trap' dentro del remoto para asegurar que el snapshot se borra aunque falle el tar.

echo "[1/3] Generando Snapshot y empaquetando en remoto..."

ssh "${SSH_USER}@${TARGET_IP}" "
    set -e # Si algo falla, parar
    
    # 1. Crear Snapshot
    echo '>>> Creando LVM Snapshot...'
    lvcreate -L $SNAPSHOT_SIZE -s -n $REMOTE_SNAP_NAME /dev/$REMOTE_VG/$REMOTE_LV >/dev/null
    
    # Función de limpieza segura (se ejecuta al terminar, falle o no)
    cleanup() {
        echo '>>> Limpiando Snapshot...'
        umount $REMOTE_MOUNT_POINT 2>/dev/null || true
        lvremove -f /dev/$REMOTE_VG/$REMOTE_SNAP_NAME >/dev/null || true
        rmdir $REMOTE_MOUNT_POINT 2>/dev/null || true
    }
    trap cleanup EXIT

    # 2. Montar Snapshot
    mkdir -p $REMOTE_MOUNT_POINT
    mount /dev/$REMOTE_VG/$REMOTE_SNAP_NAME $REMOTE_MOUNT_POINT
    
    # 3. Crear el TAR desde el punto de montaje (Datos Congelados)
    # Aquí está la magia: Backup consistente
    echo '>>> Comprimiendo datos...'
    # Entramos al directorio montado para que las rutas en el tar sean limpias
    cd $REMOTE_MOUNT_POINT
    tar -czf \"$REMOTE_TEMP_FILE\" $SOURCE_REL_PATH
" 2>&1

if [ $? -ne 0 ]; then
    echo "ERROR CRÍTICO: Falló el proceso de snapshot/compresión remoto."
    exit 1
fi

echo "[2/3] Descargando archivo..."
rsync --progress -e ssh "${SSH_USER}@${TARGET_IP}:${REMOTE_TEMP_FILE}" "$LOCAL_FILE"

if [ $? -eq 0 ]; then
    echo "[3/3] Eliminando temporal remoto..."
    ssh "${SSH_USER}@${TARGET_IP}" "rm -f \"$REMOTE_TEMP_FILE\""
    
    echo "--------------------------------------------------"
    echo "BACKUP COMPLETADO EXITOSAMENTE"
    echo "Archivo: $LOCAL_FILE"
    echo "--------------------------------------------------"
else
    echo "ERROR: Falló la descarga."
    exit 1
fi
