#!/usr/bin/env bash
# CastroCloud · Prepara o Proxmox Backup Server para recibir as copias do clúster.
#
# Execútase como root DENTRO do PBS (na súa Shell web ou por SSH), unha soa vez,
# despois de instalalo.
#
# Uso:   ./configurar-pbs.sh [DISCO] [ALMACEN]
# Ex.:   ./configurar-pbs.sh            (usa /dev/sdb e o almacén "copias")
#
# Fai o seguinte:
#   1. Formata o disco de datos e crea nel o almacén (datastore) das copias.
#   2. Programa a limpeza (garbage collection), a poda e a verificación.
#   3. Crea o usuario castrocloud@pbs e un token só con permiso para facer
#      copias nese almacén (DatastoreBackup), en vez de usar root.
#   4. Mostra os datos que hai que levar ao clúster (configurar-copias.sh).

set -euo pipefail

DISCO="${1:-sdb}"
ALMACEN="${2:-copias}"
USUARIO="castrocloud@pbs"
TOKEN="pve"

erro() { echo "ERRO: $*" >&2; exit 1; }
info() { echo "==> $*"; }

[[ $EUID -eq 0 ]] || erro "hai que executalo como root"
command -v proxmox-backup-manager >/dev/null || erro "isto non parece un Proxmox Backup Server"
DISCO="${DISCO#/dev/}"
[[ -b "/dev/$DISCO" ]] || erro "non existe o disco /dev/$DISCO (mira con: lsblk)"

# 1. Almacén das copias nun disco propio, separado do sistema
if proxmox-backup-manager datastore list --output-format json | grep -q "\"name\":\"$ALMACEN\""; then
    info "O almacén '$ALMACEN' xa existe: non se toca o disco"
else
    info "Formatando /dev/$DISCO (ext4) e creando o almacén '$ALMACEN'"
    proxmox-backup-manager disk fs create "$ALMACEN" --disk "$DISCO" --filesystem ext4 --add-datastore true
fi

# 2. Mantemento automático
#    - garbage collection: libera o espazo dos bloques que xa non usa ningunha copia
#    - poda: garda 7 copias diarias, 4 semanais e 3 mensuais
#    - verificación: comproba cada semana que as copias se poden ler
info "Programando limpeza, poda e verificación"
proxmox-backup-manager datastore update "$ALMACEN" --gc-schedule "daily"
proxmox-backup-manager prune-job list --output-format json | grep -q '"id":"poda-diaria"' \
    || proxmox-backup-manager prune-job create poda-diaria --store "$ALMACEN" --schedule "daily" \
        --keep-daily 7 --keep-weekly 4 --keep-monthly 3
proxmox-backup-manager verify-job list --output-format json | grep -q '"id":"verificacion-semanal"' \
    || proxmox-backup-manager verify-job create verificacion-semanal --store "$ALMACEN" --schedule "sat 03:00" \
        --ignore-verified true --outdated-after 30

# 3. Usuario e token con permisos mínimos
proxmox-backup-manager user list --output-format json | grep -q "\"userid\":\"$USUARIO\"" \
    || proxmox-backup-manager user create "$USUARIO" --comment "Copias do clúster CastroCloud"

if proxmox-backup-manager user list-tokens "$USUARIO" --output-format json | grep -q "$USUARIO!$TOKEN"; then
    info "O token $USUARIO!$TOKEN xa existe: non se volve crear (o segredo só se mostrou a primeira vez)"
    SEGREDO="(xa creado antes)"
else
    SEGREDO="$(proxmox-backup-manager user generate-token "$USUARIO" "$TOKEN" --output-format json \
        | sed -n 's/.*"value":"\([^"]*\)".*/\1/p')"
fi
proxmox-backup-manager acl update "/datastore/$ALMACEN" DatastoreBackup --auth-id "$USUARIO!$TOKEN"

# 4. Datos para o clúster
PEGADA="$(proxmox-backup-manager cert info | awk '/Fingerprint/ {print $NF}')"
IP="$(hostname -I | awk '{print $1}')"

cat <<FIN

==> Feito. Datos para executar configurar-copias.sh en pve1:

    Servidor:  $IP
    Almacén:   $ALMACEN
    Token:     $USUARIO!$TOKEN
    Segredo:   $SEGREDO
    Pegada:    $PEGADA

O segredo só se mostra agora: cópiao. Non se sube a git nin se ensina no vídeo.
FIN
