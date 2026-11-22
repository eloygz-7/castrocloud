# Copias de seguridade no Proxmox Backup Server, instalado dentro de pve1 e con
# o almacén no disco externo (ver scripts/configurar-pbs.sh).
# Só se crean cando en terraform.tfvars están pbs_pegada e pbs_segredo.

# 1. O PBS como almacenamento do clúster (só para copias)
resource "proxmox_storage_pbs" "copias" {
  count = var.pbs_pegada == "" ? 0 : 1

  id          = "pbs-castrocloud"
  server      = var.pbs_servidor
  datastore   = var.pbs_almacen
  username    = var.pbs_token_id
  password    = var.pbs_segredo
  fingerprint = var.pbs_pegada
  content     = ["backup"]
}

# 2. Copia diaria de todos os contedores e MV do clúster, sen paralos (snapshot).
#    A retención (7 diarias, 4 semanais e 3 mensuais) faina o propio PBS.
resource "proxmox_backup_job" "diaria" {
  count = length(proxmox_storage_pbs.copias)

  id             = "copia-diaria"
  schedule       = var.copia_hora
  storage        = proxmox_storage_pbs.copias[0].id
  all            = true
  mode           = "snapshot"
  compress       = "zstd"
  enabled        = true
  notes_template = "{{guestname}} ({{node}})"
  comment        = "Copia diaria de todo o clúster (Terraform)"
}
