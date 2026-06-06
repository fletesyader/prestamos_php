#!/bin/bash
# Script mejorado para instalar Windows Server en VPS (basado en tutorial de Technical Sahil)
# Compatible con Contabo, Hetzner, DigitalOcean, etc.

# Colores para mejor legibilidad
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # Sin Color

# --- 1. Configuración Inicial ---
echo -e "${GREEN}🚀 Iniciando instalación automatizada de Windows Server...${NC}"

# Actualizar sistema e instalar dependencias (corregido: grub2 -> grub-pc)
echo -e "${YELLOW}📦 Instalando paquetes necesarios...${NC}"
apt update -y && apt upgrade -y
apt install -y gparted wimtools ntfs-3g grub-pc rsync gdisk

# --- 2. Preparar el Disco (sda) ---
# Atención: ¡Esto BORRARÁ todo el contenido de /dev/sda!
echo -e "${RED}⚠️  ¡ADVERTENCIA! Se van a borrar todas las particiones de /dev/sda.${NC}"
read -p "¿Estás seguro de que quieres continuar? (escribe 'SALIR' para cancelar): " confirmation
if [ "$confirmation" != "SALIR" ]; then
    echo -e "${RED}❌ Operación cancelada por el usuario.${NC}"
    exit 1
fi

# Desmontar cualquier partición montada (por si acaso)
umount /dev/sda* 2>/dev/null

# Crear tabla de particiones GPT
parted /dev/sda --script -- mklabel gpt

# Crear particiones:
# sda1: 15GB NTFS (Instalador de Windows y drivers)
# sda2: 20GB NTFS (Datos temporales)
# El resto del espacio quedará libre para la instalación final de Windows
parted /dev/sda --script -- mkpart primary ntfs 1MB 15GB   # /dev/sda1
parted /dev/sda --script -- mkpart primary ntfs 15GB 35GB  # /dev/sda2

# Formatear particiones NTFS
mkfs.ntfs -f /dev/sda1
mkfs.ntfs -f /dev/sda2

# --- 3. Hacer la Partición Booteable (Corregido) ---
echo -e "${YELLOW}🔧 Configurando bandera de arranque en /dev/sda1...${NC}"
# Establecer flag de arranque en la partición 1 (más compatible que el método "r g p w y")
parted /dev/sda --script set 1 boot on
# Alternativa/adicional con gdisk para asegurar
echo -e "x\nA\n1\n2\nw\nY\n" | gdisk /dev/sda

# --- 4. Montar Particiones y Configurar GRUB ---
echo -e "${YELLOW}🔧 Instalando y configurando GRUB...${NC}"
mount /dev/sda1 /mnt

# Instalar GRUB en el disco /dev/sda (para arranque BIOS)
grub-install --root-directory=/mnt /dev/sda

# Crear archivo de configuración de GRUB
mkdir -p /mnt/boot/grub
cat > /mnt/boot/grub/grub.cfg << 'EOF'
menuentry "Windows Installer" {
    insmod ntfs
    search --set=root --file=/bootmgr
    ntldr /bootmgr
    boot
}
EOF

# Montar sda2 para uso temporal
mkdir -p /tmp/windata
mount /dev/sda2 /tmp/windata

# --- 5. Descargar y Copiar Archivos de Windows ---
cd /root
mkdir -p /root/win_iso /tmp/win_mount

echo -e "${YELLOW}⬇️  Descargando ISO de Windows...${NC}"
# URL del tutorial (puedes cambiarla por tu propia ISO si prefieres)
wget -O /root/win_iso/win10.iso --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36" https://bit.ly/tswin10

echo -e "${YELLOW}💿 Montando ISO y copiando archivos a /dev/sda1...${NC}"
mount -o loop /root/win_iso/win10.iso /tmp/win_mount
rsync -avz --progress /tmp/win_mount/* /mnt/
umount /tmp/win_mount

# --- 6. Descargar e Integrar Drivers VirtIO (CORREGIDO - Añadido rsync faltante) ---
echo -e "${YELLOW}⬇️  Descargando Drivers VirtIO...${NC}"
wget -O /root/win_iso/virtio.iso https://bit.ly/tsvirtio

echo -e "${YELLOW}💾 Integrando drivers VirtIO en el instalador...${NC}"
mkdir -p /tmp/virtio_mount /mnt/sources/virtio_drivers
mount -o loop /root/win_iso/virtio.iso /tmp/virtio_mount

# *** COMANDO FALTANTE EN EL TUTORIAL ORIGINAL ***
rsync -avz --progress /tmp/virtio_mount/* /mnt/sources/virtio_drivers/

# --- 7. Modificar boot.wim para Incluir Drivers Automáticamente ---
echo -e "${YELLOW}🛠️  Modificando boot.wim para inyección automática de drivers...${NC}"
cd /mnt/sources

# El archivo cmd.txt debe contener el comando para añadir la carpeta de drivers
echo 'add virtio_drivers /virtio_drivers' > cmd.txt

# Actualizar el índice 2 del boot.wim (generalmente el de instalación)
# Si falla, prueba con el índice 1 o revisa con: wimlib-imagex info boot.wim
wimlib-imagex update boot.wim 2 < cmd.txt
if [ $? -ne 0 ]; then
    echo -e "${YELLOW}⚠️  Falló la actualización del índice 2. Intentando con índice 1...${NC}"
    wimlib-imagex update boot.wim 1 < cmd.txt
fi

# --- 8. Limpieza y Reinicio ---
echo -e "${GREEN}✅ Instalación preparada. Limpiando y reiniciando...${NC}"
cd /
umount /tmp/virtio_mount
umount /tmp/win_mount
umount /tmp/windata
umount /mnt

echo -e "${RED}🔄 El sistema se reiniciará en 10 segundos. Presiona Ctrl+C para cancelar.${NC}"
sleep 10
reboot