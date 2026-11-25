# Writes the Ansible inventory from the VMs OpenTofu just created.
# The file is regenerated at every apply and ignored by Git.
resource "local_file" "ansible_inventory" {
  filename             = "${path.module}/../ansible/inventory/hosts.yml"
  file_permission      = "0644"
  directory_permission = "0755"

  content = templatefile("${path.module}/templates/inventory.yml.tftpl", {
    vm_username = var.vm_username
    hosts = {
      for name, vm in var.vms : name => {
        ip     = local.vm_ips[name]
        groups = vm.groups
      }
    }
    groups = distinct(flatten([for vm in var.vms : vm.groups]))
  })

  # Write the inventory only once the VMs exist.
  depends_on = [proxmox_virtual_environment_vm.lab]
}
