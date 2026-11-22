#!/usr/bin/env bash
# CastroCloud · Conecta o clúster Proxmox VE co Proxmox Backup Server e programa
# a copia diaria de todos os contedores e máquinas virtuais.
#
# Execútase como root nun nodo do clúster (pve1), unha soa vez: a configuración
# de almacenamento e de copias é do clúster, así que vale para os tres nodos.
#
# Uso:   ./configurar-copias.sh SERVIDOR PEGADA [ALMACEN] [HORA]
# Ex.:   ./configurar-copias.sh 192.168.0.214 ab:cd:...:ef
#
# Os datos (servidor, pegada e segredo) móstraos configurar-pbs.sh ao rematar.
# O segredo do token pídese por teclado, para que non quede no historial.
#
# Opcións por variable:
#   PROBAR=1  ao rematar, fai xa unha copia de todo para comprobar que funciona

set -euo pipefail

SERVIDOR="${1:?Uso: $0 SERVIDOR PEGADA [ALMACEN] [HORA]}"
PEGADA="${2:?Falta a pegada (fingerprint) do certificado do PBS}"
ALMACEN="${3:-copias}"
HORA="${4:-02:00}"
TOKEN="castrocloud@pbs!pve"
STORAGE="pbs-castrocloud"
TAREFA="copia-diaria"

erro() { echo "ERRO: $*" >&2; exit 1; }
info() { echo "==> $*"; }

[[ $EUID -eq 0 ]] || erro "hai que executalo como root"
command -v pvesm >/dev/null || erro "isto non parece un nodo de Proxmox VE"
pvecm status >/dev/null 2>&1 || erro "este nodo non está nun clúster con quórum"

# 1. Almacenamento de tipo PBS no clúster
if pvesm status | awk 'NR > 1 {print $1}' | grep -qx "$STORAGE"; then
    info "O almacenamento '$STORAGE' xa existe: non se volve crear"
else
    read -rsp "Segredo do token $TOKEN: " SEGREDO; echo
    [[ -n "$SEGREDO" ]] || erro "o segredo non pode estar baleiro"
    info "Engadindo o PBS ($SERVIDOR, almacén '$ALMACEN') como '$STORAGE'"
    pvesm add pbs "$STORAGE" --server "$SERVIDOR" --datastore "$ALMACEN" \
        --username "$TOKEN" --password "$SEGREDO" --fingerprint "$PEGADA" \
        --content backup
fi
pvesm status --storage "$STORAGE" | grep -q active || erro "o clúster non consegue falar co PBS (IP, pegada ou segredo?)"

# 2. Tarefa de copia diaria de todo o clúster
#    - modo snapshot: copia sen parar os contedores nin as MV
#    - a retención (7 diarias, 4 semanais e 3 mensuais) faina o propio PBS
if pvesh get /cluster/backup --output-format json | grep -q "\"id\":\"$TAREFA\""; then
    info "A tarefa '$TAREFA' xa existe: actualízase a hora"
    pvesh set "/cluster/backup/$TAREFA" --schedule "$HORA" --storage "$STORAGE"
else
    info "Programando a copia diaria ás $HORA"
    pvesh create /cluster/backup --id "$TAREFA" --schedule "$HORA" --storage "$STORAGE" \
        --all 1 --mode snapshot --enabled 1 --compress zstd \
        --notes-template "{{guestname}} ({{node}})"
fi

# 3. Proba opcional: copia agora de todo o que hai neste nodo
if [[ "${PROBAR:-0}" == 1 ]]; then
    info "Facendo unha copia de proba dos invitados de $(hostname)"
    vzdump --all 1 --storage "$STORAGE" --mode snapshot
fi

info "Feito. Na web: Datacenter → Backup (tarefa) e $STORAGE → Backups (copias feitas)."
