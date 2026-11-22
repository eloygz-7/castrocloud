# Almacenamento para a alta dispoñibilidade: un pool ZFS chamado «datos» en
# cada nodo, sobre un disco propio. Ten que chamarse igual en todos para que
# Proxmox poida replicar os contedores dun nodo a outro.

locals {
  nodos = toset([for ct in var.contedores : ct.nodo])
}

# 1. O pool ZFS en cada nodo (o disco ten que estar baleiro)
resource "proxmox_node_disk_zfs" "datos" {
  for_each = local.nodos

  node_name   = each.key
  name        = "datos"
  devices     = [var.disco_zfs]
  raidlevel   = "single"
  compression = "lz4"
  ashift      = 12
  add_storage = false
}

# 2. Un único almacenamento do clúster que apunta ao pool de cada nodo
resource "proxmox_storage_zfspool" "datos" {
  id             = "zfs-datos"
  zfs_pool       = "datos"
  content        = ["rootdir", "images"]
  nodes          = local.nodos
  thin_provision = true

  depends_on = [proxmox_node_disk_zfs.datos]
}
