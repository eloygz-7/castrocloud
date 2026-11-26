# CastroCloud · OPNsense: cortalumes e enrutador das VLANs.
#
# Máquina virtual en pve1, replicada a pve3 e con alta dispoñibilidade como os
# demais servidores. Terraform crea a MV co DVD de instalación; a instalación
# e a configuración inicial fanse na consola e na web (opnsense/LEEME.md), e a
# configuración final gárdase en opnsense/config.xml.
#
#   net0 (vtnet0) -> vmbr2: WAN, 10.99.0.2/30, pasarela o nodo (10.99.0.1)
#   net1 (vtnet1) -> vmbr1: troncal. Sen etiqueta, administración (192.168.56.2);
#                   VLAN 10, 20 e 30, cada unha coa súa .1

resource "proxmox_download_file" "opnsense" {
  node_name               = var.opnsense.nodo
  datastore_id            = "local"
  content_type            = "iso"
  file_name               = "OPNsense-dvd-amd64.iso"
  url                     = var.opnsense_iso.url
  checksum                = var.opnsense_iso.sha256
  checksum_algorithm      = "sha256"
  decompression_algorithm = "bz2"
  upload_timeout          = 3600
}

resource "proxmox_virtual_environment_vm" "opnsense" {
  node_name   = var.opnsense.nodo
  vm_id       = var.opnsense.vm_id
  name        = "opnsense"
  description = "CastroCloud: cortalumes e enrutador das VLANs (Terraform)"
  tags        = ["castrocloud", "terraform", "rede"]
  on_boot     = true

  cpu {
    cores = 1
    type  = "host"
  }

  memory {
    dedicated = var.opnsense.ram
  }

  disk {
    datastore_id = proxmox_storage_zfspool.datos.id
    interface    = "scsi0"
    size         = var.opnsense.disco
    discard      = "on"
  }

  scsi_hardware = "virtio-scsi-single"

  cdrom {
    interface = "ide2"
    file_id   = var.opnsense_instalado ? "none" : proxmox_download_file.opnsense.id
  }

  boot_order = var.opnsense_instalado ? ["scsi0"] : ["scsi0", "ide2"]

  network_device {
    bridge = proxmox_network_linux_bridge.saida[var.opnsense.nodo].name
  }

  network_device {
    bridge = proxmox_network_linux_bridge.troncal[var.opnsense.nodo].name
  }

  operating_system {
    type = "other" # FreeBSD
  }

  lifecycle {
    ignore_changes = [node_name]
  }
}

resource "proxmox_replication" "opnsense" {
  for_each = toset(sort(tolist(setsubtract(local.servizos, [var.opnsense.nodo]))))

  id       = "${proxmox_virtual_environment_vm.opnsense.vm_id}-0"
  target   = each.key
  type     = "local"
  schedule = var.replicacion_cada
  comment  = "opnsense -> ${each.key}"
}

resource "proxmox_haresource" "opnsense" {
  resource_id  = "vm:${proxmox_virtual_environment_vm.opnsense.vm_id}"
  state        = "started"
  max_restart  = 1
  max_relocate = 1
  comment      = "opnsense (Terraform)"

  depends_on = [proxmox_replication.opnsense]
}
