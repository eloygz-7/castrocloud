#!/usr/bin/env bash
# CastroCloud · Saída a Internet dos servidores dos servizos a través do seu nodo.
#
# Por que: os nodos son MV de VirtualBox en ponte sobre a wifi. A wifi só
# deixa pasar o tráfico da propia MV, non o dos contedores que van dentro
# (outras MAC), así que os contedores non chegan ao router. Si chegan ao nodo,
# e o nodo si chega ao router: o nodo fai de pasarela con NAT (masquerade).
# Nun CPD con cable non faría falta.
#
# Execútase como root en pve1 e pve3 (os nodos con servizos), unha vez:
#   ssh root@192.168.0.211 'bash -s' < scripts/configurar-nat.sh
#   ssh root@192.168.0.213 'bash -s' < scripts/configurar-nat.sh
#
# Opcións: REDE_SERVIDORES (IP dos servidores, por defecto 192.168.0.224/27,
#          é dicir, .224–.255) e REDE_LOCAL (192.168.0.0/24).

set -euo pipefail

REDE_SERVIDORES="${REDE_SERVIDORES:-192.168.0.224/27}"
REDE_LOCAL="${REDE_LOCAL:-192.168.0.0/24}"
PONTE="${PONTE:-vmbr0}"

[[ $EUID -eq 0 ]] || { echo "ERRO: hai que executalo como root" >&2; exit 1; }
command -v nft >/dev/null || apt-get install -y nftables

# 1. Reenviar paquetes e non mandar «redirects»: se o nodo lles dixese aos
#    contedores que vaian directos ao router, volverían quedar sen saída
cat > /etc/sysctl.d/90-castrocloud-nat.conf <<FIN
net.ipv4.ip_forward = 1
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.$PONTE.send_redirects = 0
FIN
sysctl -q --system

# 2. NAT: o que saia dos servidores cara a fóra da rede local leva a IP do nodo
cat > /etc/castrocloud-nat.nft <<FIN
table ip castrocloud_nat
delete table ip castrocloud_nat
table ip castrocloud_nat {
    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        ip saddr $REDE_SERVIDORES ip daddr != $REDE_LOCAL masquerade
    }
}
FIN
nft -f /etc/castrocloud-nat.nft

# 3. Que se aplique tamén despois de cada reinicio
cat > /etc/systemd/system/castrocloud-nat.service <<'FIN'
[Unit]
Description=CastroCloud: NAT para os servidores dos servizos
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/nft -f /etc/castrocloud-nat.nft
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
FIN
systemctl daemon-reload
systemctl enable -q castrocloud-nat.service

echo "==> NAT activo en $(hostname -s) para $REDE_SERVIDORES:"
nft list table ip castrocloud_nat
