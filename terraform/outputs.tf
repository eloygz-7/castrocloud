output "contedores" {
  description = "Servidores creados: nome => nodo preferido e IP"
  value       = { for nome, ct in var.contedores : nome => "${ct.nodo} ${ct.ip}" }
}

output "contrasinal_root" {
  description = "Contrasinal de root dos contedores (ver con: terraform output -raw contrasinal_root)"
  value       = random_password.root.result
  sensitive   = true
}

# Inventario para Ansible: Terraform crea os servidores e Ansible configúraos.
#   terraform output -raw inventario_ansible > ../ansible/inventario.ini
output "inventario_ansible" {
  description = "Inventario de Ansible cos servidores e as súas IP"
  value = join("\n", concat(
    ["# Xerado por Terraform (terraform output -raw inventario_ansible): non editar a man", "[servidores]"],
    [for nome, ct in var.contedores : "${nome} ansible_host=${ct.ip}"],
    ["", "[servidores:vars]", "ansible_user=root", ""]
  ))
}
