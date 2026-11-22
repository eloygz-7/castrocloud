# Copias de seguridade: un Proxmox Backup Server en cada nodo, cada un co seu
# almacén nun disco propio (ver scripts/configurar-pbs.sh).
#   - O PBS principal (pve1) recibe a copia diaria de todo o clúster.
#   - Os PBS de pve2 e pve3 tráena del cada noite (sync job), así que, se cae
#     un nodo, as copias seguen nos outros dous e pódense restaurar desde a web.

locals {
  pbs_activos = { for nodo, p in var.pbs : nodo => p if p.pegada != "" }
}

# 1. Cada PBS como almacenamento do clúster (só para copias)
resource "proxmox_storage_pbs" "copias" {
  for_each = local.pbs_activos

  id          = "pbs-${each.key}"
  server      = each.value.servidor
  datastore   = var.pbs_almacen
  username    = var.pbs_token_id
  password    = var.pbs_segredos[each.key]
  fingerprint = each.value.pegada
  content     = ["backup"]
}

# 2. Copia diaria de todos os contedores e MV do clúster ao PBS principal, sen
#    paralos (snapshot). A retención (7 diarias, 4 semanais e 3 mensuais) faina
#    cada PBS.
resource "proxmox_backup_job" "diaria" {
  count = contains(keys(local.pbs_activos), var.pbs_principal) ? 1 : 0

  id             = "copia-diaria"
  schedule       = var.copia_hora
  storage        = proxmox_storage_pbs.copias[var.pbs_principal].id
  all            = true
  mode           = "snapshot"
  compress       = "zstd"
  enabled        = true
  notes_template = "{{guestname}} ({{node}})"
  comment        = "Copia diaria de todo o clúster ao PBS de ${var.pbs_principal} (Terraform)"
}
