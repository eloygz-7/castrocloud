#!/usr/bin/env bash
# CastroCloud · IaaS: crea un servidor virtual para un cliente a partir dunha
# plantilla de Debian 13, cun dos tres tamaños do apartado 2 do documento:
#
#   Tamaño  vCPU  RAM    Disco
#   S       1     2 GB    40 GB
#   M       2     4 GB    80 GB
#   L       4     8 GB   160 GB
#
# Execútase como root nun nodo de servizos (pve1 ou pve3):
#   crear-servidor-iaas.sh CLIENTE TAMAÑO IP "CLAVE_SSH_PÚBLICA_DO_CLIENTE"
# Desde o equipo de Eloy, sen copiar o script ao nodo (exemplo):
#   ssh root@192.168.0.213 "bash -s -- asesoria-rias S 10.10.30.101 '$(cat ~/.ssh/id_ed25519.pub)'" < crear-servidor-iaas.sh
#
# O servidor vai na VLAN 30 (IaaS), illada das VLANs dos servizos por
# OPNsense, que é a súa pasarela (10.10.30.1). A IP vai de 10.10.30.100 a
# 10.10.30.199. O cliente entra por SSH co usuario «cliente» e a súa clave
# pública (sen contrasinal).
#
# A primeira vez en cada nodo crea a plantilla (descarga uns 400 MB). Despois
# cada servidor é un clon ligado da plantilla en ZFS: créase en segundos e só
# ocupa o que cambia. A copia diaria do clúster tamén o inclúe.

set -euo pipefail

CLIENTE="${1:-}"; TAMANO="${2:-}"; IP="${3:-}"; CLAVE="${4:-}"
ALMACEN="${ALMACEN:-zfs-datos}"
PONTE="${PONTE:-vmbr1}"
VLAN="${VLAN:-30}"
PASARELA="${PASARELA:-10.10.30.1}"
DNS="${DNS:-10.10.10.13}"
DOMINIO="${DOMINIO:-castrocloud.lan}"
IMAXE_URL="https://cloud.debian.org/images/cloud/trixie/latest"
IMAXE="debian-13-genericcloud-amd64.qcow2"

erro() { echo "ERRO: $*" >&2; exit 1; }
info() { echo "==> $*"; }

[[ -n "$CLAVE" ]] || erro "uso: CLIENTE TAMAÑO(S|M|L) IP \"CLAVE_SSH_PÚBLICA\""
[[ $EUID -eq 0 ]] || erro "hai que executalo como root nun nodo de Proxmox"
command -v qm >/dev/null || erro "isto non é un nodo de Proxmox VE"
[[ "$CLIENTE" =~ ^[a-z0-9][a-z0-9-]{1,30}$ ]] || erro "o nome do cliente só pode levar minúsculas, números e guións"
case "${TAMANO^^}" in
    S) CPU=1; RAM=2048; DISCO=40 ;;
    M) CPU=2; RAM=4096; DISCO=80 ;;
    L) CPU=4; RAM=8192; DISCO=160 ;;
    *) erro "tamaño descoñecido: $TAMANO (S, M ou L)" ;;
esac
[[ "$IP" =~ ^10\.10\.30\.1[0-9][0-9]$ ]] || erro "a IP ten que ir de 10.10.30.100 a 10.10.30.199"
grep -qs "ip=$IP/" /etc/pve/nodes/*/qemu-server/*.conf && erro "a IP $IP xa a ten outro servidor"
[[ "$CLAVE" =~ ^ssh-(ed25519|rsa)\  ]] || erro "a clave SSH non parece unha clave pública (ssh-ed25519 ... ou ssh-rsa ...)"

NODO="$(hostname -s)"
PLANTILLA=$((9000 + ${NODO//[!0-9]/}))         # 9001 en pve1, 9003 en pve3

# As MV de Proxmox dentro de VirtualBox poden non ter virtualización aniñada:
# entón emúlase a CPU (máis lento, pero abonda para a demo)
KVM=1; [[ -e /dev/kvm ]] || { KVM=0; info "Sen /dev/kvm: o servidor irá con CPU emulada"; }

TMP=""; trap 'rm -rf "${TMP:-}" "${FCLAVE:-}"' EXIT
FCLAVE="$(mktemp)"; echo "$CLAVE" > "$FCLAVE"

# --- 1. Plantilla de Debian 13 (só a primeira vez en cada nodo) ---
if ! qm status "$PLANTILLA" >/dev/null 2>&1; then
    info "Creando a plantilla $PLANTILLA en $NODO (descarga de Debian 13 cloud)"
    TMP="$(mktemp -d)"
    wget -q --show-progress -O "$TMP/$IMAXE" "$IMAXE_URL/$IMAXE"
    wget -q -O "$TMP/SHA512SUMS" "$IMAXE_URL/SHA512SUMS"
    (cd "$TMP" && grep " $IMAXE\$" SHA512SUMS | sha512sum -c --quiet) || erro "a imaxe descargada está corrupta"

    qm create "$PLANTILLA" --name plantilla-debian13 --ostype l26 --kvm "$KVM" \
        --cores 1 --memory 1024 --net0 "virtio,bridge=$PONTE,tag=$VLAN" \
        --scsihw virtio-scsi-single --scsi0 "$ALMACEN:0,import-from=$TMP/$IMAXE,discard=on" \
        --ide2 "$ALMACEN:cloudinit" --boot order=scsi0 \
        --serial0 socket --vga serial0 --agent enabled=1 \
        --description "CastroCloud: plantilla do IaaS (Debian 13 con cloud-init)"
    qm template "$PLANTILLA"
fi

# --- 2. Primeiro ID libre do rango do IaaS (301-399) ---
VMID=""
for id in $(seq 301 399); do
    pvesh get /cluster/nextid --vmid "$id" >/dev/null 2>&1 && { VMID="$id"; break; }
done
[[ -n "$VMID" ]] || erro "non quedan ID libres no rango 301-399"
NOME="iaas-$CLIENTE-$VMID"

# --- 3. Clon e tamaño ---
info "Creando $NOME (tamaño ${TAMANO^^}: $CPU vCPU, $((RAM / 1024)) GB, $DISCO GB) en $NODO"
qm clone "$PLANTILLA" "$VMID" --name "$NOME" >/dev/null
qm set "$VMID" --cores "$CPU" --memory "$RAM" --kvm "$KVM" --net0 "virtio,bridge=$PONTE,tag=$VLAN" \
    --ipconfig0 "ip=$IP/24,gw=$PASARELA" --nameserver "$DNS" --searchdomain "$DOMINIO" \
    --ciuser cliente --sshkeys "$FCLAVE" \
    --tags "iaas;cliente-$CLIENTE;tamano-${TAMANO,,}" \
    --description "CastroCloud IaaS: cliente $CLIENTE, tamaño ${TAMANO^^}, creado o $(date +%F)" >/dev/null
qm resize "$VMID" scsi0 "${DISCO}G" >/dev/null
qm start "$VMID"

cat <<FIN

==> Servidor $NOME (ID $VMID) arrancando en $NODO.
    Acceso do cliente:  ssh cliente@$IP   (nun ou dous minutos, cando remate cloud-init)
    Ver na web:         https://$(hostname -I | awk '{print $1}'):8006  ->  $VMID ($NOME)
    Borralo:            qm stop $VMID && qm destroy $VMID --purge
FIN
