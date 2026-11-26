#!/usr/bin/env bash
# CastroCloud · Publica en Internet SÓ a web de WordPress (HTTPS), por un porto.
#
# Para que Yara edite a web desde a súa casa. O router de Eloy redirixe un
# único porto (por defecto 8443) a pve3; pve3 pásao ao HTTPS de ct-web e a
# nada máis:
#
#   Internet --TCP 58843--> router --> pve3 (192.168.0.213:8443) --> ct-web:443
#   (o porto público, 58843, escóllese no router; o 8443 é o do nodo)
#
# Que garante que non se chegue a outra cousa:
#   - o router só reenvía ese porto (a web de Proxmox, SSH etc. non se ven);
#   - pve3 traduce ese porto a un único destino, ct-web:443 (Nginx con HTTPS);
#   - o cortalumes de pve3 só deixa pasar cara a ct-web, desde fóra da rede
#     local, ese porto 443: calquera outro tráfico redirixido descártase;
#   - en WordPress, a persoa ten rol de editora (non instala plugins nin
#     temas), o acceso ten límite de intentos e XML-RPC está pechado.
#
# Execútase como root en pve3, unha vez:
#   ssh root@192.168.0.213 'bash -s' < scripts/publicar-web.sh
# Para retiralo:  ssh root@192.168.0.213 'bash -s -- --quitar' < scripts/publicar-web.sh
#
# Opcións: PORTO (8443), DESTINO (IP de ct-web, 192.168.0.232) e REDE_LOCAL.
# Coas VLANs, DESTINO pasa a ser a WAN de OPNsense (10.99.0.2), que fai a
# súa propia redirección a 10.10.10.12:443 (opnsense/LEEME.md).

set -euo pipefail

PORTO="${PORTO:-8443}"
DESTINO="${DESTINO:-192.168.0.232}"
PORTO_DESTINO="${PORTO_DESTINO:-443}"
REDE_LOCAL="${REDE_LOCAL:-192.168.0.0/24}"
PONTE="${PONTE:-vmbr0}"

[[ $EUID -eq 0 ]] || { echo "ERRO: hai que executalo como root" >&2; exit 1; }

if [[ "${1:-}" == --quitar ]]; then
    systemctl disable -q --now castrocloud-web.service 2>/dev/null || true
    nft delete table ip castrocloud_web 2>/dev/null || true
    rm -f /etc/castrocloud-web.nft /etc/systemd/system/castrocloud-web.service
    echo "==> A web xa non se publica"
    exit 0
fi

cat > /etc/castrocloud-web.nft <<FIN
table ip castrocloud_web
delete table ip castrocloud_web
table ip castrocloud_web {
    # Só este porto, e só cara a ct-web:443
    chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
        iifname "$PONTE" tcp dport $PORTO dnat to $DESTINO:$PORTO_DESTINO
    }
    # Se a petición vén da propia rede local (probas, ou o router cando se
    # entra pola IP pública desde dentro), ct-web respondería directo e a
    # conexión fallaría: nese caso o nodo pon a súa IP como orixe
    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        ct status dnat ip saddr $REDE_LOCAL ip daddr $DESTINO tcp dport $PORTO_DESTINO masquerade
    }
    # O que veña redirixido de fóra da rede local só pode ir a ct-web:443
    chain forward {
        type filter hook forward priority filter; policy accept;
        ct status dnat ip saddr != $REDE_LOCAL ip daddr $DESTINO tcp dport $PORTO_DESTINO accept
        ct status dnat ip saddr != $REDE_LOCAL drop
    }
}
FIN
nft -f /etc/castrocloud-web.nft

cat > /etc/systemd/system/castrocloud-web.service <<'FIN'
[Unit]
Description=CastroCloud: publicación da web de WordPress por un porto
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/nft -f /etc/castrocloud-web.nft
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
FIN
systemctl daemon-reload
systemctl enable -q castrocloud-web.service

echo "==> Web publicada: porto $PORTO de $(hostname -s) -> $DESTINO:$PORTO_DESTINO"
nft list table ip castrocloud_web
