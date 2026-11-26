# CastroCloud · Rede dos nodos de servizos: troncal con VLANs e saída de OPNsense.
#
#   vmbr0  wifi da casa (192.168.0.0/24): acceso aos nodos (xa existía)
#   vmbr1  troncal con VLANs entre pve1, pve3 e o equipo de administración
#          (rede «só anfitrión» de VirtualBox, vboxnet0). Sen etiqueta vai a
#          rede de administración 192.168.56.0/24; con etiqueta, as VLANs de
#          var.vlans. OPNsense enruta entre elas e aplica o cortalumes.
#   vmbr2  rede interna do nodo pola que OPNsense sae a Internet: o nodo fai
#          NAT (scripts/configurar-nat.sh), porque a wifi non deixa pasar MAC
#          aniñadas. Na produción, a WAN de OPNsense iría directa ao router.

resource "proxmox_network_linux_bridge" "troncal" {
  for_each = local.servizos

  node_name  = each.key
  name       = "vmbr1"
  ports      = [var.interface_troncal]
  vlan_aware = true
  comment    = "CastroCloud: troncal con VLANs (Terraform)"
}

resource "proxmox_network_linux_bridge" "saida" {
  for_each = local.servizos

  node_name = each.key
  name      = "vmbr2"
  address   = var.saida_opnsense
  comment   = "CastroCloud: saída a Internet de OPNsense con NAT do nodo (Terraform)"
}
