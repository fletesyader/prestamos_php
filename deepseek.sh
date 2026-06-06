#!/bin/bash
# Script para ISO de 5.7GB - ADAPTADO para tu disco

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${RED}⚠️  ¡ATENCIÓN! Este script BORRARÁ tu Debian actual${NC}"
echo -e "${RED}Disco detectado: sda (partición actual Debian en uso)${NC}"
echo -e "${YELLOW}Tamaño disponible según lsblk: 376.5GB${NC}"
echo ""
echo -e "${RED}¿Estás SEGURO de querer borrar todo e instalar Windows?${NC}"
read -p "Escribe 'BORRAR_TODO' para continuar: " confirm

if [ "$confirm" != "BORRAR_TODO" ]; then
    echo -e "${GREEN}✅ Operación cancelada. Tu Debian está a salvo.${NC}"
    exit 1
fi

echo -e "${RED}⚠️  ÚLTIMA OPORTUNIDAD - Esto es irreversible${NC}"
read -p "Presiona Ctrl+C para cancelar o Enter para continuar: " -n 1 -r
echo

# --- Instalar paquetes necesarios ---
echo -e "${GREEN}📦 Instalando paquetes...${NC}"
apt update -y
apt install -y wimtools ntfs-3g grub-pc rsync gdisk parted p7zip-full

# --- Desmontar y limpiar disco ---
echo -e "${YELLOW}🔧 Limpiando disco /dev/sda...${NC}"
# IMPORTANTE: Salir del directorio actual antes de desmontar
cd /
umount /dev/sda* 2>/dev/null
umount /mnt 2>/dev/null
swapoff -a 2>/dev/null

# Limpiar firmas
wipefs -a /dev/sda
dd if=/dev/zero of=/dev/sda bs=1M count=10 status=progress

# --- Crear particiones (optimizado para 376GB+ disponible) ---
echo -e "${YELLOW}🔧 Creando particiones GPT...${NC}"
parted /dev/sda --script -- mklabel gpt

# Partición 1: Windows (60GB - suficiente para Windows 10/11)
parted /dev/sda --script -- mkpart primary ntfs 1MB 60GB
# Partición 2: Temporal para ISO (25GB)
parted /dev/sda --script -- mkpart primary ntfs 60GB 85GB
# Partición 3: Almacenamiento adicional (resto del espacio)
parted /dev/sda --script -- mkpart primary ntfs 85GB 100%
# Marcar partición 1 como booteable
parted /dev/sda --script set 1 boot on

# Informar de la creación
echo -e "${GREEN}✅ Particiones creadas:${NC}"
lsblk /dev/sda

# --- Formatear particiones ---
echo -e "${YELLOW}💿 Formateando particiones NTFS...${NC}"
mkfs.ntfs -f /dev/sda1 -Q
mkfs.ntfs -f /dev/sda2 -Q
mkfs.ntfs -f /dev/sda3 -Q

# --- Montar partición principal ---
mount /dev/sda1 /mnt

# --- Instalar GRUB ---
echo -e "${YELLOW}🔧 Instalando GRUB...${NC}"
grub-install --target=i386-pc --root-directory=/mnt /dev/sda

# Crear configuración GRUB
mkdir -p /mnt/boot/grub
cat > /mnt/boot/grub/grub.cfg << 'EOF'
set timeout=10
set default=0

menuentry "Windows 10/11 Installer" {
    insmod part_gpt
    insmod ntfs
    insmod search_fs_uuid
    search --no-floppy --set=root --file /bootmgr
    ntldr /bootmgr
    boot
}

menuentry "Boot from hard disk" {
    insmod part_gpt
    insmod ntfs
    insmod chain
    set root=(hd0,1)
    chainloader +1
}
EOF

# --- Directorios temporales ---
mkdir -p /root/win_iso /tmp/win_mount /tmp/windata

# Montar partición temporal
mount /dev/sda2 /tmp/windata

# --- DESCARGAR ISO (usando fuente confiable) ---
echo -e "${YELLOW}⬇️  Descargando ISO de Windows...${NC}"
echo -e "${YELLOW}Nota: Necesitarás una URL válida de ISO de Windows${NC}"
echo -e "${YELLOW}Puedes usar:${NC}"
echo "  - https://www.microsoft.com/es-es/software-download/windows10"
echo "  - O transferir una ISO existente vía SCP/FTP"

# Opción 1: Descargar desde URL (REEMPLAZAR CON URL VÁLIDA)
ISO_URL="https://archive.org/download/Win10_22H2_English_x64/Win10_22H2_English_x64.iso"

echo -e "${YELLOW}Intentando descargar desde: ${ISO_URL}${NC}"
wget -O /root/win_iso/windows.iso \
     --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
     --progress=bar:force \
     --timeout=30 \
     --tries=3 \
     "$ISO_URL" 2>&1

if [ ! -f /root/win_iso/windows.iso ] || [ $(stat -c%s /root/win_iso/windows.iso) -lt 1000000000 ]; then
    echo -e "${RED}❌ Error: ISO no descargada correctamente${NC}"
    echo -e "${YELLOW}Por favor, sube manualmente una ISO a /root/win_iso/windows.iso${NC}"
    echo -e "${YELLOW}Usa: scp windows.iso root@IP:/root/win_iso/${NC}"
    exit 1
fi

echo -e "${GREEN}✅ ISO descargada: $(du -h /root/win_iso/windows.iso | cut -f1)${NC}"

# --- COPIAR ARCHIVOS DE INSTALACIÓN ---
echo -e "${YELLOW}💿 Copiando archivos de instalación...${NC}"
mount -o loop /root/win_iso/windows.iso /tmp/win_mount

# Copiar usando rsync con progreso
rsync -avh --progress --stats /tmp/win_mount/* /mnt/ 2>&1 | grep -E "files transferred|total size"

# Verificar archivos críticos
if [ ! -f /mnt/bootmgr ] && [ ! -f /mnt/boot/bootmgr ]; then
    echo -e "${YELLOW}⚠️  Advertencia: bootmgr no encontrado, puede que la ISO no sea booteable${NC}"
fi

umount /tmp/win_mount

# --- DRIVERS VIRTIO (opcional) ---
echo -e "${YELLOW}⬇️  Descargando drivers VirtIO...${NC}"
VIRTIO_URL="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"

wget -O /root/win_iso/virtio.iso \
     --progress=bar:force \
     "$VIRTIO_URL" 2>/dev/null || \
echo -e "${YELLOW}⚠️  No se pudieron descargar drivers VirtIO (continuando...)${NC}"

if [ -f /root/win_iso/virtio.iso ]; then
    mkdir -p /mnt/sources/virtio_drivers
    mount -o loop /root/win_iso/virtio.iso /tmp/virtio_mount 2>/dev/null
    if [ -d /tmp/virtio_mount ]; then
        rsync -avh /tmp/virtio_mount/ /mnt/sources/virtio_drivers/
        umount /tmp/virtio_mount 2>/dev/null
        
        # Integrar drivers al boot.wim si existe
        if [ -f /mnt/sources/boot.wim ]; then
            echo -e "${YELLOW}🔧 Integrando drivers VirtIO al boot.wim...${NC}"
            apt install -y wimtools 2>/dev/null
            cd /mnt/sources
            echo 'add virtio_drivers /virtio_drivers' > cmd.txt
            wimlib-imagex update boot.wim 2 < cmd.txt 2>/dev/null || \
            wimlib-imagex update boot.wim 1 < cmd.txt 2>/dev/null || \
            echo -e "${YELLOW}⚠️  No se pudieron integrar drivers${NC}"
            cd /
        fi
    fi
fi

# --- LIMPIEZA ---
echo -e "${GREEN}🧹 Limpiando...${NC}"
cd /
umount /tmp/virtio_mount 2>/dev/null
umount /tmp/win_mount 2>/dev/null
umount /tmp/windata 2>/dev/null
umount /mnt 2>/dev/null

echo -e "${GREEN}✅ Preparación completada${NC}"
echo -e "${YELLOW}📊 Resumen final:${NC}"
lsblk /dev/sda

echo ""
echo -e "${GREEN}🚀 El sistema está listo para reiniciar${NC}"
echo -e "${RED}⚠️  Al reiniciar, arrancará el instalador de Windows${NC}"
echo -e "${YELLOW}Presiona Enter para reiniciar ahora, o Ctrl+C para abortar${NC}"
read -p "" -n 1 -r

if [[ $REPLY =~ ^$ ]]; then
    echo -e "${GREEN}Reiniciando...${NC}"
    sleep 3
    reboot
else
    echo -e "${YELLOW}Reinicio cancelado. Para reiniciar manualmente: reboot${NC}"
fi