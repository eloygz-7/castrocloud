#!/usr/bin/env bash
# CastroCloud · Copia lóxica (mysqldump) das bases de datos MySQL do servidor.
#
# Complementa a copia do PBS (02:00): a do PBS garda o servidor enteiro; esta
# garda as bases de datos nun ficheiro .sql.gz coherente, que se pode
# restaurar sen restaurar o servidor:
#   gunzip -c FICHEIRO.sql.gz | docker compose exec -T db sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot'
#
# Busca en /opt/castrocloud cada proxecto de Docker Compose cun servizo «db»
# (Nextcloud, WordPress, Zabbix) e garda a copia en /var/backups/mysql.
# Ansible instálao en /usr/local/sbin e prográmao ás 01:30, antes da copia do
# PBS, para que o PBS leve tamén estes ficheiros.
#
# Opcións: DESTINO (/var/backups/mysql), DIAS de retención (7).

set -euo pipefail

DESTINO="${DESTINO:-/var/backups/mysql}"
DIAS="${DIAS:-7}"
SERVIZOS="${SERVIZOS:-/opt/castrocloud}"
REXISTRO="${REXISTRO:-/var/log/castrocloud-copia-mysql.log}"

log() { echo "$(date '+%F %T') $*" | tee -a "$REXISTRO"; }

[[ $EUID -eq 0 ]] || { echo "ERRO: hai que executalo como root" >&2; exit 1; }
mkdir -p "$DESTINO"; chmod 700 "$DESTINO"

erros=0; copias=0
for proxecto in "$SERVIZOS"/*/; do
    proxecto="${proxecto%/}"; nome="$(basename "$proxecto")"
    [[ -f "$proxecto/compose.yml" ]] || continue
    # (gárdase antes de buscar: con pipefail, «grep -q» cortaría a tubaxe e daría erro)
    servizos="$(docker compose --project-directory "$proxecto" config --services 2>/dev/null || true)"
    grep -qx db <<< "$servizos" || continue

    ficheiro="$DESTINO/$nome-$(date +%F_%H%M).sql.gz"
    # --single-transaction: copia coherente sen bloquear as táboas (InnoDB)
    if docker compose --project-directory "$proxecto" exec -T db sh -c \
        'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysqldump -uroot --single-transaction --routines --events --triggers --all-databases' \
        | gzip > "$ficheiro.tmp" && gzip -t "$ficheiro.tmp"; then
        mv "$ficheiro.tmp" "$ficheiro"
        log "OK    $nome -> $ficheiro ($(du -h --apparent-size "$ficheiro" | cut -f1))"
        copias=$((copias + 1))
    else
        rm -f "$ficheiro.tmp"
        log "ERRO  $nome: fallou o mysqldump"
        erros=$((erros + 1))
    fi
done

# Retención: bórranse as copias de máis de $DIAS días
find "$DESTINO" -name '*.sql.gz' -mtime +"$DIAS" -print -delete | while read -r f; do log "BORRADA $f"; done

log "Remate: $copias copias, $erros erros"
(( erros == 0 ))
