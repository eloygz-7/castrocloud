# Servidores dos servizos: contedores LXC con Debian 13 nos que Ansible
# instalará Docker e despregará Nextcloud, WordPress, lldap, Bind9 e Zabbix.
# Van só en pve1 e pve3 (var.nodos_servizos): pve2 non ten recursos.

# 1. Descargar a plantilla de Debian en cada nodo de servizos.
#    Descárgase unha vez por nodo, porque o almacenamento "local" é propio de cada nodo.
resource "proxmox_download_file" "plantilla_lxc" {
  for_each = local.servizos

  node_name          = each.key
  datastore_id       = "local"
  content_type       = "vztmpl"
  url                = var.plantilla_lxc.url
  checksum           = var.plantilla_lxc.sha512
  checksum_algorithm = "sha512"
  # A wifi pode ser lenta: os 10 min por defecto ás veces non chegan
  upload_timeout = 3600
}

# 2. Contrasinal aleatorio para o usuario root dos contedores
resource "random_password" "root" {
  length  = 20
  special = false
}

# 3. Os contedores
resource "proxmox_virtual_environment_container" "servizo" {
  for_each = var.contedores

  node_name   = each.value.nodo
  vm_id       = each.value.vm_id
  description = "CastroCloud: servidor de servizos creado con Terraform"
  tags        = ["castrocloud", "terraform"]

  unprivileged  = true
  start_on_boot = true
  # Docker dentro dun contedor sen privilexios: abonda con nesting.
  # (keyctl só o pode activar root@pam, non un token da API)
  features {
    nesting = true
  }

  cpu {
    cores = each.value.nucleos
  }

  memory {
    dedicated = each.value.ram
    swap      = 256
  }

  # O disco vai no ZFS (almacenamento.tf) para poder replicalo aos outros nodos
  disk {
    datastore_id = proxmox_storage_zfspool.datos.id
    size         = each.value.disco
  }

  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }

  operating_system {
    template_file_id = proxmox_download_file.plantilla_lxc[each.value.nodo].id
    type             = "debian"
  }

  initialization {
    hostname = each.key

    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        # O seu nodo fai de pasarela con NAT (pola wifi non chegan ao router)
        gateway = var.ip_nodos[each.value.nodo]
      }
    }

    dns {
      servers = var.dns
    }

    user_account {
      password = random_password.root.result
      # Ansible entra con esta clave (sen contrasinal) para configurar o servidor
      keys = [trimspace(file(pathexpand(var.ssh_clave_publica)))]
    }
  }

  # Coa alta dispoñibilidade, Proxmox pode mover o contedor a outro nodo se cae
  # o seu: Terraform non debe intentar devolvelo nin recrealo por iso.
  lifecycle {
    ignore_changes = [node_name]
  }
}
