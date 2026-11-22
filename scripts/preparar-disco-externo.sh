#!/usr/bin/env bash
# CastroCloud · Prepara o disco externo USB no equipo de Eloy (Ubuntu) e engade
# discos virtuais novos a pve1 e pve3, gardados nese disco externo:
#
#   pve1: /dev/sdb  disco ZFS (datos dos contedores, replicados entre nodos)
#         /dev/sdc  almacén do Proxmox Backup Server (as copias)
#   pve3: /dev/sdb  disco ZFS
#
# O nodo pve2 (Windows) leva o seu disco ZFS no propio PC con Windows.
#
# Uso:   ./preparar-disco-externo.sh /dev/sdX
#        (o disco externo; mírase con: lsblk -o NAME,SIZE,TRAN,MODEL)
#
# Execútase como usuario normal: pide sudo só para formatar e montar o disco.
# pve1 e pve3 teñen que estar APAGADAS (VBoxManage controlvm pveN acpipowerbutton).
#
# Variables opcionais (tamaños en GB; os discos son dinámicos: ocupan o que se usa):
#   ZFS_GB=32  PBS_GB=500  PUNTO=/mnt/castrocloud

set -euo pipefail

DISCO="${1:?Uso: $0 /dev/sdX   (o disco externo; mírao con: lsblk -o NAME,SIZE,TRAN,MODEL)}"
ZFS_GB="${ZFS_GB:-32}"
PBS_GB="${PBS_GB:-500}"
PUNTO="${PUNTO:-/mnt/castrocloud}"
ETIQUETA="castrocloud"

erro() { echo "ERRO: $*" >&2; exit 1; }
info() { echo "==> $*"; }

[[ $EUID -ne 0 ]] || erro "execútao como usuario normal (sen sudo): VirtualBox é do teu usuario"
command -v VBoxManage >/dev/null || erro "non se atopa VBoxManage"

for mv in pve1 pve3; do
    estado="$(VBoxManage showvminfo "$mv" --machinereadable | sed -n 's/^VMState="\(.*\)"/\1/p')"
    [[ "$estado" == poweroff || "$estado" == aborted ]] || erro "$mv está acesa ($estado): apágaa antes"
done

# 1. Formatar e montar o disco externo (só se aínda non está preparado)
if ! findmnt -rno TARGET "$PUNTO" >/dev/null; then
    [[ -b "$DISCO" ]] || erro "non existe $DISCO"
    [[ "$(lsblk -dno TRAN "$DISCO")" == usb ]] || erro "$DISCO non é un disco USB: por seguridade non se toca"
    lsblk -no MOUNTPOINT "$DISCO" | grep -q . && erro "$DISCO ten particións montadas: desmóntaas antes"

    lsblk -o NAME,SIZE,MODEL,FSTYPE,LABEL "$DISCO"
    echo
    read -rp "Vaise BORRAR TODO o contido de $DISCO. Escribe BORRAR para seguir: " ok
    [[ "$ok" == BORRAR ]] || erro "cancelado"

    info "Formatando $DISCO (ext4, etiqueta $ETIQUETA)"
    sudo wipefs -a "$DISCO"
    sudo parted -s "$DISCO" mklabel gpt mkpart "$ETIQUETA" ext4 0% 100%
    sudo udevadm settle
    PART="$(lsblk -lnpo NAME "$DISCO" | sed -n 2p)"
    sudo mkfs.ext4 -q -F -L "$ETIQUETA" "$PART"

    # Montaxe automática ao arrancar; «nofail» para que Ubuntu arranque igual sen o disco
    UUID="$(sudo blkid -s UUID -o value "$PART")"
    sudo mkdir -p "$PUNTO"
    grep -q "$UUID" /etc/fstab || echo "UUID=$UUID $PUNTO ext4 defaults,nofail,x-systemd.device-timeout=10 0 2" \
        | sudo tee -a /etc/fstab >/dev/null
    sudo systemctl daemon-reload
    sudo mount "$PUNTO"
    sudo chown "$USER:$USER" "$PUNTO"
else
    info "$PUNTO xa está montado: non se formata nada"
fi

# 2. Discos virtuais no disco externo
CARTAFOL="$PUNTO/virtualbox"
mkdir -p "$CARTAFOL"

engadir() {   # engadir MV PORTO NOME TAMAÑO_GB
    local mv="$1" porto="$2" nome="$3" gb="$4" vdi="$CARTAFOL/$1-$3.vdi"
    if VBoxManage showvminfo "$mv" --machinereadable | grep -q "^\"SATA-$porto-0\"=\"$vdi\""; then
        info "$mv xa ten $nome no porto $porto"; return
    fi
    [[ -f "$vdi" ]] || VBoxManage createmedium disk --filename "$vdi" --size $((gb * 1024)) --format VDI >/dev/null
    VBoxManage storageattach "$mv" --storagectl SATA --port "$porto" --device 0 --type hdd --medium "$vdi"
    info "$mv: disco $nome de $gb GB no porto $porto"
}

VBoxManage storagectl pve1 --name SATA --portcount 4
VBoxManage storagectl pve3 --name SATA --portcount 3
engadir pve1 2 zfs "$ZFS_GB"
engadir pve1 3 pbs "$PBS_GB"
engadir pve3 2 zfs "$ZFS_GB"

info "Feito. Conecta sempre o disco externo ANTES de arrancar pve1 e pve3:"
echo "    VBoxManage startvm pve1 --type headless"
echo "    VBoxManage startvm pve3 --type headless"
