#!/bin/bash

# --- CONFIGURACIÓN ---
# ¡ADVERTENCIA! Tu contraseña de root está aquí, en texto plano.
ROOT_PASS="ask"

# Lista de tus VMs de Linux
HOSTS_LINUX=(
    "192.168.56.20" 
    # Añade más IPs aquí si las tienes
)
# --------------------

echo "--- Iniciando tareas en hosts Linux (con sshpass) ---"

for HOST in "${HOSTS_LINUX[@]}"; do
    echo ""
    echo "--- $HOST ---"
    
    # -p "$ROOT_PASS": Pasa la contraseña
    # -o StrictHostKeyChecking=no: Responde "yes" automáticamente
    sshpass -p "$ROOT_PASS" ssh -o StrictHostKeyChecking=no root@$HOST "hostname; uptime"
    
    if [ $? -eq 0 ]; then
        echo "Comando ejecutado con éxito en $HOST"
    else
        echo "ERROR al conectar o ejecutar en $HOST"
    fi
done

echo ""
echo "--- Proceso de Linux finalizado ---"