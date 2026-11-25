locals {
  gateway        = cidrhost(var.vm_network_cidr, 1)
  prefix_length  = split("/", var.vm_network_cidr)[1]
  ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_file)))

  vm_ips = { for name, vm in var.vms : name => cidrhost(var.vm_network_cidr, vm.host_number) }
}

resource "proxmox_virtual_environment_vm" "lab" {
  for_each = var.vms

  name        = each.key
  node_name   = var.proxmox_node
  vm_id       = each.value.vm_id
  description = "Managed by OpenTofu (homelab-weekend). Manual changes will be overwritten."
  tags        = sort(concat(["homelab", "opentofu"], each.value.groups))

  on_boot         = true
  started         = true
  stop_on_destroy = true

  clone {
    vm_id        = var.template_vm_id
    full         = true
    datastore_id = var.datastore_id
    # Proxmox sometimes times out when several clones start together.
    retries = 3
  }

  # qemu-guest-agent is baked into the template (host/create-template.sh).
  agent {
    enabled = true
  }

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory_mb
  }

  scsi_hardware = "virtio-scsi-single"

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = each.value.disk_gb
    discard      = "on"
    ssd          = true
    iothread     = true
  }

  network_device {
    bridge = var.bridge
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  # Debian cloud images expect a serial console. Without it, resizing the
  # boot disk can end in a kernel panic (provider known issue).
  serial_device {
    device = "socket"
  }

  initialization {
    datastore_id = var.datastore_id

    dns {
      servers = var.dns_servers
    }

    ip_config {
      ipv4 {
        address = "${local.vm_ips[each.key]}/${local.prefix_length}"
        gateway = local.gateway
      }
    }

    user_account {
      username = var.vm_username
      keys     = [local.ssh_public_key]
    }
  }
}
