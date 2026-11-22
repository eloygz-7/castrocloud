# Alta dispoñibilidade (HA): se cae un nodo, os seus contedores arrancan sós
# noutro nodo nun ou dous minutos.
#
# Como non hai almacenamento compartido, cada contedor replícase cada
# var.replicacion_cada minutos aos OUTROS DOUS nodos (replicación de ZFS). Se
# o seu nodo cae, arranca nun deles coa última copia replicada.

locals {
  # Unha tarefa por contedor e nodo de destino: "201-0" => pve2, "201-1" => pve3...
  replicas = merge([
    for nome, ct in var.contedores : {
      for n, destino in sort(tolist(setsubtract(local.nodos, [ct.nodo]))) :
      "${ct.vm_id}-${n}" => { nome = nome, n = n, destino = destino }
    }
  ]...)
}

# 1. Replicación de cada contedor aos outros nodos
resource "proxmox_replication" "contedores" {
  for_each = local.replicas

  id       = "${proxmox_virtual_environment_container.demo[each.value.nome].vm_id}-${each.value.n}"
  target   = each.value.destino
  type     = "local"
  schedule = var.replicacion_cada
  comment  = "${each.value.nome} -> ${each.value.destino}"
}

# 2. Cada contedor pasa a estar xestionado pola HA de Proxmox
resource "proxmox_haresource" "contedores" {
  for_each = var.contedores

  resource_id  = "ct:${proxmox_virtual_environment_container.demo[each.key].vm_id}"
  state        = "started"
  max_restart  = 1
  max_relocate = 1
  comment      = "${each.key} (Terraform)"

  depends_on = [proxmox_replication.contedores]
}

# 3. Preferencia de nodo: cada contedor volve ao seu nodo cando este se recupera
resource "proxmox_harule" "preferencia" {
  for_each = local.nodos

  rule      = "preferir-${each.key}"
  type      = "node-affinity"
  comment   = "Os contedores de ${each.key} prefiren ese nodo"
  resources = [for nome, ct in var.contedores : proxmox_haresource.contedores[nome].resource_id if ct.nodo == each.key]
  nodes     = { for n in local.nodos : n => (n == each.key ? 2 : 1) }
  strict    = false
}
