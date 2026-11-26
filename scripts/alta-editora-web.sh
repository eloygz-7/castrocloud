#!/usr/bin/env bash
# CastroCloud · Crea unha conta de WordPress con rol de editora.
#
# Unha editora escribe e publica entradas e páxinas, pero non instala plugins
# nin temas nin crea contas: é o mínimo para editar a web desde fóra.
#
#   ./alta-editora-web.sh USUARIO CORREO
#
# Mostra o contrasinal inicial unha soa vez (non se garda): entrégase á
# persoa, que o cambia no seu perfil ao entrar.

set -euo pipefail

IP_WEB="${IP_WEB:-192.168.0.232}"
USUARIO="${1:-}"; CORREO="${2:-}"

[[ -n "$CORREO" ]] || { echo "uso: $0 USUARIO CORREO" >&2; exit 1; }
[[ "$USUARIO" =~ ^[a-z0-9._-]{3,30}$ ]] || { echo "ERRO: usuario non válido" >&2; exit 1; }

PASS="$(openssl rand -base64 18 | tr -d '/+=' | cut -c1-20)"
ssh -o BatchMode=yes "root@$IP_WEB" \
    "cd /opt/castrocloud/wordpress && docker compose run --rm cli wp user create \
     $(printf '%q' "$USUARIO") $(printf '%q' "$CORREO") --role=editor \
     --user_pass=$(printf '%q' "$PASS") --porcelain" >/dev/null

cat <<FIN
==> Conta de editora creada en WordPress
    Usuario:     $USUARIO
    Contrasinal: $PASS   (só se mostra agora; cambiala ao entrar)
FIN
