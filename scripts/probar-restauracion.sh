#!/usr/bin/env bash
# CastroCloud · Proba de restauración das copias de seguridade (apartado 4.4:
# «probas de restauración mensuais»).
#
# Restaura a última copia dun contedor nun contedor temporal, arráncao,
# comproba que funciona e bórrao. Deixa o resultado no rexistro.
#
# Execútase como root en CADA nodo (a man ou cada mes con cron) e usa o PBS
# dese nodo, así que comproba que as copias se poden restaurar desde os tres:
#   ./probar-restauracion.sh [CTID]        (por defecto, 201 = ct-pve1-1)
#
# O contedor temporal arranca coa rede desconectada (link_down), para non
# chocar coa IP do contedor orixinal, que segue funcionando. O seu ID é 29N
# (N = número do nodo: 291 en pve1, 292 en pve2...), para que as probas dos
# tres nodos non choquen.

set -euo pipefail

CTID="${1:-201}"
NODO="$(hostname -s)"
PROBA="${PROBA_ID:-29${NODO//[!0-9]/}}"
COPIAS="${COPIAS:-pbs-$NODO}"
DESTINO="${DESTINO:-zfs-datos}"
REXISTRO="/var/log/castrocloud-restauracion.log"

log() { echo "$(date '+%F %T') $*" | tee -a "$REXISTRO"; }
falla() { log "FALLO ct $CTID: $*"; limpar; exit 1; }
limpar() {
    if pct status "$PROBA" >/dev/null 2>&1; then
        pct stop "$PROBA" >/dev/null 2>&1 || true
        pct destroy "$PROBA" --purge >/dev/null 2>&1 || true
    fi
}

[[ $EUID -eq 0 ]] || { echo "ERRO: hai que executalo como root" >&2; exit 1; }
pct status "$PROBA" >/dev/null 2>&1 && { echo "ERRO: o ID $PROBA xa está en uso" >&2; exit 1; }

# 1. Última copia do contedor no PBS
VOLID="$(pvesh get "/nodes/$NODO/storage/$COPIAS/content" --content backup --vmid "$CTID" --output-format json \
    | python3 -c 'import json,sys; c=sorted(json.load(sys.stdin), key=lambda v: v["ctime"]); print(c[-1]["volid"] if c else "")')"
[[ -n "$VOLID" ]] || falla "non hai ningunha copia en $COPIAS"
log "Restaurando $VOLID no contedor temporal $PROBA"

# 2. Restaurar e arrancar sen rede
INICIO=$SECONDS
pct restore "$PROBA" "$VOLID" --storage "$DESTINO" --unique 1 >/dev/null || falla "pct restore non rematou"
NET="$(pct config "$PROBA" | sed -n 's/^net0: //p')"
pct set "$PROBA" --net0 "${NET},link_down=1" --onboot 0 --hostname "proba-restauracion"
pct start "$PROBA" || falla "o contedor restaurado non arranca"

# 3. Comprobar que o sistema dentro responde
sleep 5
pct exec "$PROBA" -- test -s /etc/os-release || falla "o sistema restaurado non responde"
log "OK ct $CTID: restaurado e arrancado en $((SECONDS - INICIO)) s ($VOLID)"

# 4. Borrar o contedor temporal
limpar
