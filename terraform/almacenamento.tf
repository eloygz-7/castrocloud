# Almacenamento para a alta dispoñibilidade: un pool ZFS chamado «datos» en
# cada nodo, sobre un disco propio. Ten que chamarse igual en todos para que
# Proxmox poida replicar os contedores dun nodo a outro.

locals {
  # O pool créase nos tres nodos (o de pve2 xa existe e non se toca), pero os
  # servizos só corren e se replican en local.servizos (pve1 e pve3).
  nodos    = toset(["pve1", "pve2", "pve3"])
  servizos = toset(var.nodos_servizos)
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
