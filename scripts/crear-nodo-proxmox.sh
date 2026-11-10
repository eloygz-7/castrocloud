#!/usr/bin/env bash
# CastroCloud · Crea unha máquina virtual de VirtualBox lista para instalar Proxmox VE.
#
# Uso:   ./crear-nodo-proxmox.sh NOME [RAM_MB] [CPUS] [DISCO_GB]
# Ex.:   ./crear-nodo-proxmox.sh pve1
#        IFACE=wlp3s0 ./crear-nodo-proxmox.sh pve3 6144 4 32
#
# Variables opcionais:
#   IFACE  interface física á que se conecta a rede da MV en modo ponte
#          (por defecto: wlp3s0, a wifi; con cable sería eno1)
#   ISO    ruta da ISO de Proxmox VE (descárgase e compróbase se non existe)
#
# A MV queda con:
#   - virtualización aniñada activada, para que Proxmox poida executar KVM dentro;
#   - unha tarxeta en modo ponte sobre a wifi, co modo promiscuo permitido.
#     Pola wifi, VirtualBox reescribe os enderezos MAC: o nodo ten rede, pero
#     os contedores de dentro poden quedar sen ela (a demo funciona igual);
#   - arranque desde o disco e, se está baleiro, desde a ISO do instalador.

set -euo pipefail

NOME="${1:?Uso: $0 NOME [RAM_MB] [CPUS] [DISCO_GB]}"
RAM="${2:-6144}"
CPUS="${3:-4}"
DISCO_GB="${4:-32}"
IFACE="${IFACE:-wlp3s0}"

VERSION_ISO="proxmox-ve_9.2-1.iso"
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
    info "Descargando $VERSION_ISO (~1,6 GB) en $(dirname "$ISO")"
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
    --nested-hw-virt on --nested-paging on \
    --firmware bios --rtc-use-utc on \
    --graphicscontroller vmsvga --vram 32 \
    --nic1 bridged --bridge-adapter1 "$IFACE" --nictype1 82540EM --nic-promisc1 allow-all \
    --boot1 disk --boot2 dvd --boot3 none --boot4 none

# 3. Disco (reserva dinámica: ocupa só o que se usa) e unidade de DVD coa ISO
VBoxManage storagectl "$NOME" --name SATA --add sata --controller IntelAhci --portcount 2
VBoxManage createmedium disk --filename "$DISCO" --size $((DISCO_GB * 1024)) --format VDI >/dev/null
VBoxManage storageattach "$NOME" --storagectl SATA --port 0 --device 0 --type hdd --medium "$DISCO"
VBoxManage storageattach "$NOME" --storagectl SATA --port 1 --device 0 --type dvddrive --medium "$ISO"

info "Feito. Arrancar con:  VBoxManage startvm $NOME"
info "Despois de instalar Proxmox, quitar a ISO con:"
echo "    VBoxManage storageattach $NOME --storagectl SATA --port 1 --device 0 --type dvddrive --medium emptydrive"
