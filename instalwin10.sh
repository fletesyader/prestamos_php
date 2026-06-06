#!/bin/bash
# Script optimizado para ISO de 5.7GB y disco de 64GB

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}🚀 Instalación Windows (ISO 5.7GB) en disco 64GB${NC}"

# Instalar paquetes
apt update -y && apt upgrade -y
apt install -y wimtools ntfs-3g grub-pc rsync gdisk parted

# --- LIMPIAR DISCO ---
echo -e "${RED}⚠️  Se BORRARÁN todas las particiones existentes${NC}"
read -p "Escribe 'SI' para continuar: " confirm
if [ "$confirm" != "SI" ]; then
    echo -e "${RED}❌ Cancelado${NC}"
    exit 1
fi

umount /dev/sda* 2>/dev/null
wipefs -a /dev/sda

# --- CREAR PARTICIONES (para ISO 5.7GB) ---
echo -e "${YELLOW}🔧 Creando particiones...${NC}"
parted /dev/sda --script -- mklabel gpt
parted /dev/sda --script -- mkpart primary ntfs 1MB 25GB   # sda1: 25GB (suficiente)
parted /dev/sda --script -- mkpart primary ntfs 25GB 45GB  # sda2: 20GB (temporal)
parted /dev/sda --script set 1 boot on

# Formatear
mkfs.ntfs -f /dev/sda1
mkfs.ntfs -f /dev/sda2

# --- MONTAR Y CONFIGURAR GRUB ---
mount /dev/sda1 /mnt
grub-install --root-directory=/mnt /dev/sda

mkdir -p /mnt/boot/grub
cat > /mnt/boot/grub/grub.cfg << 'EOF'
menuentry "Windows Installer" {
    insmod ntfs
    search --set=root --file=/bootmgr
    ntldr /bootmgr
    boot
}
EOF

# --- DESCARGAR ISO (5.7GB) ---
mkdir -p /root/win_iso /tmp/win_mount
mount /dev/sda2 /tmp/windata

echo -e "${YELLOW}⬇️  Descargando ISO (5.7GB)...${NC}"
wget -O /root/win_iso/windows.iso \
     --user-agent="Mozilla/5.0" \
     --progress=bar:force \
     https://archive.org/download/Win10_22H2_English_x64/Win10_22H2_English_x64.iso

# --- COPIAR ARCHIVOS DE INSTALACIÓN ---
echo -e "${YELLOW}💿 Copiando archivos (esto tomará unos minutos)...${NC}"
mount -o loop /root/win_iso/windows.iso /tmp/win_mount
rsync -avz --progress /tmp/win_mount/* /mnt/
umount /tmp/win_mount

# --- DRIVERS VIRTIO ---
echo -e "${YELLOW}⬇️  Descargando VirtIO...${NC}"
wget -O /root/win_iso/virtio.iso https://bit.ly/tsvirtio

mkdir -p /tmp/virtio_mount /mnt/sources/virtio_drivers
mount -o loop /root/win_iso/virtio.iso /tmp/virtio_mount
rsync -avz --progress /tmp/virtio_mount/* /mnt/sources/virtio_drivers/

# --- MODIFICAR BOOT.WIM ---
cd /mnt/sources
echo 'add virtio_drivers /virtio_drivers' > cmd.txt
wimlib-imagex update boot.wim 2 < cmd.txt 2>/dev/null || \
wimlib-imagex update boot.wim 1 < cmd.txt 2>/dev/null

echo -e "${GREEN}✅ Instalador preparado. Reiniciando...${NC}"
cd /
umount /tmp/virtio_mount 2>/dev/null
umount /tmp/win_mount 2>/dev/null
umount /tmp/windata 2>/dev/null
umount /mnt 2>/dev/null

sleep 5
reboot
