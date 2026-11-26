#!/usr/bin/env bash
# CastroCloud · Alta dun cliente (despacho ou peme) no servizo SaaS.
#
# Fai en poucos segundos o que a man levaría un bo anaco:
#   1. lldap: crea o grupo do cliente (cliente-NOME) e as súas persoas usuarias,
#      con contrasinal aleatorio.
#   2. Nextcloud: dá a cada persoa a cota do seu plan e crea unha carpeta común
#      do despacho (app Group folders) só para o grupo do cliente.
#   3. Garda os contrasinais iniciais nun CSV só para o administrador, para
#      entregalos ao cliente (cada persoa cámbiao ao entrar).
#
# Execútase no equipo de administración (o de Eloy), despois de Ansible:
#   ./alta-cliente.sh NOME PLAN usuario[:correo] [usuario[:correo] ...]
#
# Exemplo:
#   ./alta-cliente.sh asesoria-rias basico ana.lopez:ana@asesoriarias.gal xan.vila
#
# Plans (apartado 2 do documento):
#   basico       ata 5 persoas usuarias,  50 GB por persoa
#   profesional  de 6 a 15,              100 GB por persoa
#   empresa      de 16 a 30,             200 GB por persoa
#
# Pódese repetir para engadir persoas: as que xa existen non se tocan.
# Precisa: curl, jq, openssl e acceso SSH como root aos servidores.

set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SEGREDOS="${SEGREDOS:-$DIR/../ansible/segredos}"
IP_SERVIZOS="${IP_SERVIZOS:-192.168.0.233}"
IP_NEXTCLOUD="${IP_NEXTCLOUD:-192.168.0.231}"
DOMINIO="${DOMINIO:-castrocloud.lan}"
LLDAP="http://$IP_SERVIZOS:17170"
ALTAS="${ALTAS:-$DIR/../altas}"

erro() { echo "ERRO: $*" >&2; exit 1; }
info() { echo "==> $*"; }

[[ $# -ge 3 ]] || { sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
CLIENTE="$1"; PLAN="$2"; shift 2
USUARIOS=("$@")

for c in curl jq openssl ssh; do command -v "$c" >/dev/null || erro "falta o programa $c"; done
[[ "$CLIENTE" =~ ^[a-z0-9][a-z0-9-]{1,30}$ ]] || erro "o nome do cliente só pode levar minúsculas, números e guións"
case "$PLAN" in
    basico)      MAXIMO=5;  COTA="50 GB" ;;
    profesional) MAXIMO=15; COTA="100 GB" ;;
    empresa)     MAXIMO=30; COTA="200 GB" ;;
    *) erro "plan descoñecido: $PLAN (basico, profesional ou empresa)" ;;
esac
GRUPO="cliente-$CLIENTE"
[[ -r "$SEGREDOS/lldap_admin" ]] || erro "non se atopa $SEGREDOS/lldap_admin (xérao Ansible)"
ADMIN_PASS="$(< "$SEGREDOS/lldap_admin")"

# --- Axudas para falar con lldap (API GraphQL) e Nextcloud (occ por SSH) ---
TOKEN="$(jq -n --arg p "$ADMIN_PASS" '{username: "admin", password: $p}' \
    | curl -sf -H 'Content-Type: application/json' -d @- "$LLDAP/auth/simple/login" | jq -r .token)" \
    || erro "non se puido entrar en lldap ($LLDAP)"

gql() {   # gql CONSULTA [VARIABLES_JSON] -> campo data da resposta
    local resposta variables="${2:-}"
    [[ -n "$variables" ]] || variables='{}'
    resposta="$(jq -n --arg q "$1" --argjson v "$variables" '{query: $q, variables: $v}' \
        | curl -sf -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
            -d @- "$LLDAP/api/graphql")" || erro "fallou a petición a lldap"
    if jq -e '.errors' <<< "$resposta" >/dev/null; then
        erro "lldap: $(jq -r '.errors[0].message' <<< "$resposta")"
    fi
    jq '.data' <<< "$resposta"
}

occ() {   # occ ARGUMENTOS... -> executa occ de Nextcloud no seu servidor
    ssh -o BatchMode=yes "root@$IP_NEXTCLOUD" \
        "cd /opt/castrocloud/nextcloud && docker compose exec -T -u www-data app php occ $(printf '%q ' "$@")"
}

contrasinal() { openssl rand -base64 18 | tr -d '/+=' | cut -c1-16; }

# --- 1. Grupo do cliente en lldap ---
GRUPOS="$(gql '{ groups { id displayName } }')"
GRUPO_ID="$(jq -r --arg g "$GRUPO" '.groups[] | select(.displayName == $g) | .id' <<< "$GRUPOS")"
if [[ -z "$GRUPO_ID" ]]; then
    GRUPO_ID="$(gql 'mutation($n: String!) { createGroup(name: $n) { id } }' \
        "$(jq -n --arg n "$GRUPO" '{n: $n}')" | jq -r .createGroup.id)"
    info "Grupo $GRUPO creado en lldap"
else
    info "O grupo $GRUPO xa existía"
fi

# Límite do plan: as persoas que xa ten o cliente máis as novas
MEMBROS="$(gql 'query($id: Int!) { group(groupId: $id) { users { id } } }' \
    "$(jq -n --argjson id "$GRUPO_ID" '{id: $id}')" | jq -r '.group.users[].id')"
XA_TEN="$(grep -c . <<< "$MEMBROS" || true)"
EXISTENTES="$(gql '{ users { id } }' | jq -r '.users[].id')"
NOVAS=0
for u in "${USUARIOS[@]}"; do grep -qxF "${u%%:*}" <<< "$EXISTENTES" || NOVAS=$((NOVAS + 1)); done
(( XA_TEN + NOVAS <= MAXIMO )) || erro "o plan $PLAN admite $MAXIMO persoas; o cliente tería $((XA_TEN + NOVAS))"

# --- 2. Persoas usuarias en lldap ---
mkdir -p "$ALTAS"; chmod 700 "$ALTAS"
CSV="$ALTAS/$CLIENTE-$(date +%F).csv"
[[ -f "$CSV" ]] || echo "usuario;correo;contrasinal_inicial" > "$CSV"
chmod 600 "$CSV"

for entrada in "${USUARIOS[@]}"; do
    u="${entrada%%:*}"
    correo="${entrada#*:}"; [[ "$entrada" == *:* ]] || correo="$u@$CLIENTE.$DOMINIO"
    [[ "$u" =~ ^[a-z0-9][a-z0-9._-]{1,30}$ ]] || erro "usuario non válido: $u"

    if grep -qxF "$u" <<< "$EXISTENTES"; then
        info "$u xa existía: non se lle cambia o contrasinal"
    else
        gql 'mutation($u: CreateUserInput!) { createUser(user: $u) { id } }' \
            "$(jq -n --arg id "$u" --arg m "$correo" '{u: {id: $id, email: $m, displayName: $id}}')" >/dev/null
        pass="$(contrasinal)"
        # O contrasinal ponse coa ferramenta que trae lldap (usa o protocolo OPAQUE)
        ssh -o BatchMode=yes "root@$IP_SERVIZOS" \
            "cd /opt/castrocloud/servizos && docker compose exec -T lldap /app/lldap_set_password \
             --base-url http://localhost:17170 --admin-username admin \
             --admin-password $(printf '%q' "$ADMIN_PASS") --username $(printf '%q' "$u") \
             --password $(printf '%q' "$pass")" >/dev/null
        echo "$u;$correo;$pass" >> "$CSV"
        info "$u creada en lldap"
    fi
    grep -qxF "$u" <<< "$MEMBROS" || gql 'mutation($u: String!, $g: Int!) { addUserToGroup(userId: $u, groupId: $g) { ok } }' \
        "$(jq -n --arg u "$u" --argjson g "$GRUPO_ID" '{u: $u, g: $g}')" >/dev/null
done

# --- 3. Nextcloud: cotas e carpeta común do despacho ---
info "Nextcloud: cota de $COTA por persoa"
for entrada in "${USUARIOS[@]}"; do
    u="${entrada%%:*}"
    occ ldap:search "$u" >/dev/null   # buscala fai que Nextcloud a rexistre xa desde o LDAP
    occ user:setting "$u" files quota "$COTA"
done

if ! occ app:list --output=json | jq -e '.enabled.groupfolders' >/dev/null; then
    info "Activando a app Group folders (carpetas comúns)"
    occ app:install groupfolders >/dev/null 2>&1 || occ app:enable groupfolders >/dev/null
fi
CARPETA="Común $CLIENTE"
CARPETA_ID="$(occ groupfolders:list --output=json \
    | jq -r --arg c "$CARPETA" 'to_entries[] | .value | select((.mountPoint // .mount_point) == $c) | .id')"
if [[ -z "$CARPETA_ID" ]]; then
    CARPETA_ID="$(occ groupfolders:create "$CARPETA" | tr -dc '0-9')"
    occ groupfolders:group "$CARPETA_ID" "$GRUPO" write share delete >/dev/null
    occ groupfolders:quota "$CARPETA_ID" "$COTA" >/dev/null
    info "Carpeta común «$CARPETA» creada (só para $GRUPO, $COTA)"
fi

cat <<FIN

==> Alta de $CLIENTE (plan $PLAN) rematada.
    Web: http://$IP_NEXTCLOUD  (ou http://nextcloud.$DOMINIO)
    Contrasinais iniciais: $CSV
    (só para entregar ao cliente: non se sobe a git nin se ensina no vídeo)
FIN
