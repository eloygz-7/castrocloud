#!/usr/bin/env bash
# CastroCloud · Crea unha máquina virtual de VirtualBox lista para instalar
# Proxmox VE (nodos do clúster) ou Proxmox Backup Server (servidor de copias).
#
# Uso:   ./crear-nodo-proxmox.sh NOME [RAM_MB] [CPUS] [DISCO_GB]
# Ex.:   ./crear-nodo-proxmox.sh pve1
#        IFACE=wlp3s0 ./crear-nodo-proxmox.sh pve3 6144 4 32
#        TIPO=pbs DATOS_GB=64 ./crear-nodo-proxmox.sh pbs 2048 2 16
#        DATOS_GB=16 COPIAS_GB=4 ./crear-nodo-proxmox.sh pve1 4096 2 32
#          (nodo completo: ZFS en sdb e tres discos de copias en RAID-Z1 en sdc-sde)
#
# Variables opcionais:
#   IFACE     interface física á que se conecta a rede da MV en modo ponte
#             (por defecto: wlp3s0, a wifi; con cable sería eno1)
#   TIPO      pve (por defecto) ou pbs (Proxmox Backup Server)
#   COPIAS_GB se se indica, engade tres discos dese tamaño (portos 3, 4 e 5:
#             /dev/sdc, sdd e sde) para as copias do PBS en RAID-Z1
#   DATOS_GB  se se indica, engade un segundo disco dese tamaño para os datos
#             (no PBS é onde se gardan as copias, separado do sistema)
#   ISO       ruta da ISO (descárgase e compróbase se non existe)
#
# A MV queda con:
#   - virtualización aniñada activada nos nodos pve, para que Proxmox poida
#     executar KVM dentro (o PBS non a precisa);
#   - unha tarxeta en modo ponte sobre a wifi, co modo promiscuo permitido.
#     Pola wifi, VirtualBox reescribe os enderezos MAC: o nodo ten rede, pero
#     os contedores de dentro poden quedar sen ela (a demo funciona igual);
#   - arranque desde o disco e, se está baleiro, desde a ISO do instalador.

set -euo pipefail

NOME="${1:?Uso: $0 NOME [RAM_MB] [CPUS] [DISCO_GB]}"
RAM="${2:-8192}"
CPUS="${3:-4}"
DISCO_GB="${4:-32}"
IFACE="${IFACE:-wlp3s0}"
TIPO="${TIPO:-pve}"
DATOS_GB="${DATOS_GB:-}"
COPIAS_GB="${COPIAS_GB:-}"

case "$TIPO" in
    pve) VERSION_ISO="proxmox-ve_9.2-1.iso"; ANINADA=on ;;
    pbs) VERSION_ISO="proxmox-backup-server_4.2-1.iso"; ANINADA=off ;;
    *)   echo "ERRO: TIPO ten que ser pve ou pbs" >&2; exit 1 ;;
esac
URL_ISO="https://enterprise.proxmox.com/iso/${VERSION_ISO}"
URL_SUMAS="https://enterprise.proxmox.com/iso/SHA256SUMS"
ISO="${ISO:-$HOME/ISOs/${VERSION_ISO}}"

erro() { echo "ERRO: $*" >&2; exit 1; }
info() { echo "==> $*"; }

command -v VBoxManage >/dev/null || erro "non se atopa VBoxManage (está instalado VirtualBox?)"
[[ "$NOME" =~ ^[a-zA-Z0-9-]+$ ]] || erro "o nome só pode levar letras, números e guións"

if VBoxManage showvminfo "$NOME" >/dev/null 2>&1; then
    erro "xa existe unha MV chamada '$NOME'"
fi

# A interface ten que existir para a ponte
VBoxManage list bridgedifs | grep -q "^Name: *${IFACE}$" \
    || erro "a interface '$IFACE' non aparece en 'VBoxManage list bridgedifs'"

# 1. ISO: descargar se falta e comprobar sempre a suma SHA-256
if [[ ! -f "$ISO" ]]; then
    info "Descargando $VERSION_ISO (~1,5 GB) en $(dirname "$ISO")"
    mkdir -p "$(dirname "$ISO")"
    curl -fL --progress-bar -o "${ISO}.part" "$URL_ISO"
    mv "${ISO}.part" "$ISO"
fi
info "Comprobando a suma SHA-256 da ISO"
SUMA_ESPERADA="$(curl -fsS "$URL_SUMAS" | awk -v f="$VERSION_ISO" '$2 == f {print $1}')"
[[ -n "$SUMA_ESPERADA" ]] || erro "non se atopou a suma de $VERSION_ISO en $URL_SUMAS"
SUMA_REAL="$(sha256sum "$ISO" | awk '{print $1}')"
[[ "$SUMA_REAL" == "$SUMA_ESPERADA" ]] || erro "a suma da ISO non coincide: bórraa e volve executar o script"

# 2. Crear e rexistrar a MV
CARTAFOL="$(VBoxManage list systemproperties | awk -F': +' '/^Default machine folder/ {print $2}')"
DISCO="${CARTAFOL}/${NOME}/${NOME}.vdi"

info "Creando a MV $NOME (${RAM} MB de RAM, ${CPUS} CPU, ${DISCO_GB} GB de disco, ponte en ${IFACE})"
VBoxManage createvm --name "$NOME" --ostype Debian_64 --groups /CastroCloud --register >/dev/null

VBoxManage modifyvm "$NOME" \
    --memory "$RAM" --cpus "$CPUS" --ioapic on \
    --nested-hw-virt "$ANINADA" --nested-paging on \
    --firmware bios --rtc-use-utc on \
    --graphicscontroller vmsvga --vram 32 \
    --nic1 bridged --bridge-adapter1 "$IFACE" --nictype1 82540EM --nic-promisc1 allow-all \
    --boot1 disk --boot2 dvd --boot3 none --boot4 none

# 3. Disco (reserva dinámica: ocupa só o que se usa) e unidade de DVD coa ISO
VBoxManage storagectl "$NOME" --name SATA --add sata --controller IntelAhci --portcount 6
VBoxManage createmedium disk --filename "$DISCO" --size $((DISCO_GB * 1024)) --format VDI >/dev/null
VBoxManage storageattach "$NOME" --storagectl SATA --port 0 --device 0 --type hdd --medium "$DISCO"
VBoxManage storageattach "$NOME" --storagectl SATA --port 1 --device 0 --type dvddrive --medium "$ISO"

# 4. Disco de datos opcional (no PBS, o almacén das copias: dentro verase como /dev/sdb)
if [[ -n "$DATOS_GB" ]]; then
    DISCO_DATOS="${CARTAFOL}/${NOME}/${NOME}-datos.vdi"
    info "Engadindo un disco de datos de ${DATOS_GB} GB"
    VBoxManage createmedium disk --filename "$DISCO_DATOS" --size $((DATOS_GB * 1024)) --format VDI >/dev/null
    VBoxManage storageattach "$NOME" --storagectl SATA --port 2 --device 0 --type hdd --medium "$DISCO_DATOS"
fi

# 5. Tres discos opcionais para as copias do PBS en RAID-Z1 (/dev/sdc, sdd e sde)
if [[ -n "$COPIAS_GB" ]]; then
    info "Engadindo tres discos de ${COPIAS_GB} GB para as copias (RAID-Z1)"
    for n in 1 2 3; do
        DISCO_COPIAS="${CARTAFOL}/${NOME}/${NOME}-pbs${n}.vdi"
        VBoxManage createmedium disk --filename "$DISCO_COPIAS" --size $((COPIAS_GB * 1024)) --format VDI >/dev/null
        VBoxManage storageattach "$NOME" --storagectl SATA --port $((2 + n)) --device 0 --type hdd --medium "$DISCO_COPIAS"
    done
fi

info "Feito. Arrancar con:  VBoxManage startvm $NOME"
info "Despois de instalar Proxmox, quitar a ISO con:"
echo "    VBoxManage storageattach $NOME --storagectl SATA --port 1 --device 0 --type dvddrive --medium emptydrive"
