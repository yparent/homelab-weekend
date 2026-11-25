variable "proxmox_node" {
  description = "Proxmox node name (pvesh get /nodes, or the name shown in the UI)."
  type        = string
  default     = "pve"
}

variable "datastore_id" {
  description = "Storage for the VM disks and cloud-init drives (pvesm status --content images)."
  type        = string
  default     = "local"
}

variable "template_vm_id" {
  description = "VMID of the Debian 13 template built by host/create-template.sh."
  type        = number
  default     = 9000
}

variable "bridge" {
  description = "Private bridge of the VMs (NAT through the host)."
  type        = string
  default     = "vmbr1"
}

variable "vm_network_cidr" {
  description = "Private network of the VMs. The gateway is the first address (the host on vmbr1)."
  type        = string
  default     = "10.10.10.0/24"

  validation {
    condition     = can(cidrhost(var.vm_network_cidr, 1))
    error_message = "vm_network_cidr must be a valid IPv4 CIDR, e.g. 10.10.10.0/24."
  }
}

variable "dns_servers" {
  description = "DNS servers pushed by cloud-init."
  type        = list(string)
  default     = ["1.1.1.1", "9.9.9.9"]
}

variable "vm_username" {
  description = "User created by cloud-init, used by Ansible."
  type        = string
  default     = "debian"
}

variable "ssh_public_key_file" {
  description = "Path to YOUR public SSH key (the one generated on Friday)."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "vms" {
  description = <<-EOT
    VMs to create. host_number is the last byte of the IP in vm_network_cidr.
    groups are the Ansible groups the VM belongs to.
  EOT
  type = map(object({
    vm_id       = number
    host_number = number
    cores       = number
    memory_mb   = number
    disk_gb     = number
    groups      = list(string)
  }))

  default = {
    "lab-vm1" = {
      vm_id       = 101
      host_number = 11
      cores       = 2
      memory_mb   = 4096
      disk_gb     = 20
      groups      = ["lab"]
    }
    "lab-vm2" = {
      vm_id       = 102
      host_number = 12
      cores       = 2
      memory_mb   = 4096
      disk_gb     = 20
      groups      = ["lab"]
    }
    "lab-vm3" = {
      vm_id       = 103
      host_number = 13
      cores       = 4
      memory_mb   = 8192
      disk_gb     = 40
      groups      = ["lab", "k3s_server"]
    }
  }

  validation {
    condition = alltrue([
      for name, vm in var.vms : vm.memory_mb >= 8192 if contains(vm.groups, "k3s_server")
    ])
    error_message = "The k3s VM needs at least 8192 MB: k3s + kube-prometheus-stack do not fit in less."
  }

  validation {
    condition     = length(distinct([for vm in var.vms : vm.host_number])) == length(var.vms)
    error_message = "Two VMs have the same host_number (same IP)."
  }
}
