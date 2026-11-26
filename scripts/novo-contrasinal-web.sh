#!/usr/bin/env bash
# CastroCloud · Pon un contrasinal novo a unha conta de WordPress.
#
#   ./novo-contrasinal-web.sh USUARIO
#
# Móstrao unha soa vez (non se garda): entrégase á persoa, que o cambia ao entrar.

set -euo pipefail

IP_WEB="${IP_WEB:-192.168.0.232}"
USUARIO="${1:-}"
[[ "$USUARIO" =~ ^[a-z0-9._-]{3,30}$ ]] || { echo "uso: $0 USUARIO" >&2; exit 1; }

PASS="$(openssl rand -base64 18 | tr -d '/+=' | cut -c1-20)"
ssh -o BatchMode=yes "root@$IP_WEB" \
    "cd /opt/castrocloud/wordpress && docker compose run --rm cli wp user update \
     $(printf '%q' "$USUARIO") --user_pass=$(printf '%q' "$PASS") --skip-email" >/dev/null

echo
echo "  Usuario:     $USUARIO"
echo "  Contrasinal: $PASS   (só se mostra agora; cambiala ao entrar)"
echo
