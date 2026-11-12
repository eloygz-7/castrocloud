output "contedores" {
  description = "Contedores creados: nome => nodo e IP"
  value       = { for nome, ct in var.contedores : nome => "${ct.nodo} ${ct.ip}" }
}

output "contrasinal_root" {
  description = "Contrasinal de root dos contedores (ver con: terraform output -raw contrasinal_root)"
  value       = random_password.root.result
  sensitive   = true
}
