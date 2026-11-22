#!/usr/bin/env bash
# CastroCloud · Prepara o Proxmox Backup Server dun nodo para as copias do clúster.
#
# Hai un PBS en cada nodo (paquete proxmox-backup-server, web no porto 8007),
# cada un co seu almacén en tres discos propios (/dev/sdc, sdd e sde) en
# RAID-Z1, o RAID 5 de ZFS: aguanta que falle un dos tres discos. E, como hai
# copias nos tres nodos, se cae un nodo enteiro seguen nos outros dous:
#
#   - pve1 é o PRINCIPAL: recibe a copia diaria do clúster ás 02:00.
#   - pve2 e pve3 son SECUNDARIOS: cada noite traen (sync job) as copias novas
#     do principal e borran as que o principal xa podou.
#
# Execútase como root en cada nodo, unha soa vez, primeiro en pve1:
#   pve1:        ./configurar-pbs.sh
#   pve2 e pve3: ORIXE=192.168.0.211 ORIXE_PEGADA=aa:bb:... ./configurar-pbs.sh
#                (os datos de ORIXE móstraos o script ao rematar en pve1;
#                 o segredo do token de sincronización pídese por teclado)
#
# Opcións: DISCOS (por defecto sdc,sdd,sde), ALMACEN (copias), SYNC_HORA (03:30).

set -euo pipefail

DISCOS="${DISCOS:-sdc,sdd,sde}"
ALMACEN="${ALMACEN:-copias}"
SYNC_HORA="${SYNC_HORA:-03:30}"
ORIXE="${ORIXE:-}"
USUARIO="castrocloud@pbs"

erro() { echo "ERRO: $*" >&2; exit 1; }
info() { echo "==> $*"; }

[[ $EUID -eq 0 ]] || erro "hai que executalo como root"
command -v proxmox-backup-manager >/dev/null || erro "non está instalado proxmox-backup-server"
DISCOS="${DISCOS//\/dev\//}"
IFS=, read -ra LISTA <<< "$DISCOS"
[[ ${#LISTA[@]} -ge 3 ]] || erro "o RAID-Z1 precisa polo menos tres discos (DISCOS=sdc,sdd,sde)"
for d in "${LISTA[@]}"; do
    [[ -b "/dev/$d" ]] || erro "non existe o disco /dev/$d (mira con: lsblk)"
done
if [[ -n "$ORIXE" ]]; then
    [[ -n "${ORIXE_PEGADA:-}" ]] || erro "nos secundarios fai falta ORIXE_PEGADA (móstraa o script en pve1)"
fi

# Crea un token do usuario e dálle un rol no almacén. Devolve o segredo (só a primeira vez).
token() {   # token NOME ROL
    local nome="$1" rol="$2" segredo="(xa creado antes: o segredo só se mostrou a primeira vez)"
    if ! proxmox-backup-manager user list-tokens "$USUARIO" --output-format json | grep -q "$USUARIO!$nome"; then
        segredo="$(proxmox-backup-manager user generate-token "$USUARIO" "$nome" --output-format json \
            | sed -n 's/.*"value":"\([^"]*\)".*/\1/p')"
    fi
    proxmox-backup-manager acl update "/datastore/$ALMACEN" "$rol" --auth-id "$USUARIO!$nome" >/dev/null
    echo "$segredo"
}

# 1. Almacén das copias nun pool ZFS en RAID-Z1, separado do sistema
if proxmox-backup-manager datastore list --output-format json | grep -q "\"name\":\"$ALMACEN\""; then
    info "O almacén '$ALMACEN' xa existe: non se tocan os discos"
else
    info "Creando o pool ZFS '$ALMACEN' en RAID-Z1 con $DISCOS e o almacén das copias"
    proxmox-backup-manager disk zpool create "$ALMACEN" --devices "$DISCOS" --raidlevel raidz \
        --compression lz4 --add-datastore true
fi
zpool status "$ALMACEN" | head -n 12

# 2. Mantemento automático (igual en todos os nodos)
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

# 3. Usuario e token para o clúster (permiso só para facer e restaurar copias)
proxmox-backup-manager user list --output-format json | grep -q "\"userid\":\"$USUARIO\"" \
    || proxmox-backup-manager user create "$USUARIO" --comment "Copias do clúster CastroCloud"
SEGREDO_PVE="$(token pve DatastoreBackup)"

NODO="$(hostname -s)"
IP="$(hostname -I | awk '{print $1}')"
PEGADA="$(proxmox-backup-manager cert info | awk '/Fingerprint/ {print $NF}')"

# 4a. Principal: token de só lectura para que os secundarios traian as copias
if [[ -z "$ORIXE" ]]; then
    SEGREDO_SYNC="$(token sync DatastoreReader)"
    EXTRA="$(cat <<FIN
==> Para pve2 e pve3 (executar alí o script con):

    ORIXE=$IP ORIXE_PEGADA=$PEGADA ./configurar-pbs.sh

    Segredo do token de sincronización ($USUARIO!sync): $SEGREDO_SYNC
FIN
)"

# 4b. Secundario: remoto cara ao principal e sincronización diaria
else
    if proxmox-backup-manager remote list --output-format json | grep -q '"name":"principal"'; then
        info "O remoto 'principal' xa existe"
    else
        read -rsp "Segredo do token $USUARIO!sync do principal: " SEGREDO_SYNC; echo
        [[ -n "$SEGREDO_SYNC" ]] || erro "o segredo non pode estar baleiro"
        proxmox-backup-manager remote create principal --host "$ORIXE" \
            --auth-id "$USUARIO!sync" --password "$SEGREDO_SYNC" --fingerprint "$ORIXE_PEGADA" \
            --comment "PBS principal (pve1)"
    fi
    proxmox-backup-manager sync-job list --output-format json | grep -q '"id":"desde-principal"' \
        || proxmox-backup-manager sync-job create desde-principal --store "$ALMACEN" \
            --remote principal --remote-store "$ALMACEN" --schedule "$SYNC_HORA" \
            --remove-vanished true --comment "Copias do PBS principal"
    info "Sincronización programada ás $SYNC_HORA. Para traer xa as copias: proxmox-backup-manager sync-job run desde-principal"
    EXTRA=""
fi

cat <<FIN

==> Feito en $NODO. En terraform.tfvars (no equipo de Eloy), dentro de cada bloque:

pbs = {
  $NODO = { servidor = "$IP", pegada = "$PEGADA" }
}
pbs_segredos = {
  $NODO = "$SEGREDO_PVE"
}

$EXTRA

Os segredos só se mostran agora: cópiaos. Non se soben a git nin se ensinan no vídeo.
FIN
