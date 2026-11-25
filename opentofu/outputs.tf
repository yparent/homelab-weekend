output "vm_ips" {
  description = "Private IP of each VM (reachable through the Tailscale subnet router)."
  value       = local.vm_ips
}

output "ssh_commands" {
  description = "Ready-to-paste SSH commands."
  value       = { for name, ip in local.vm_ips : name => "ssh ${var.vm_username}@${ip}" }
}

output "ansible_inventory_file" {
  description = "Inventory generated for Ansible."
  value       = abspath(local_file.ansible_inventory.filename)
}

output "k3s_server_ip" {
  description = "IP of the VM in the k3s_server group (Sunday)."
  value       = one([for name, vm in var.vms : local.vm_ips[name] if contains(vm.groups, "k3s_server")])
}
