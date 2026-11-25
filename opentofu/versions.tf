terraform {
  # Checked with OpenTofu 1.13.10 (2026-11-25).
  required_version = ">= 1.13.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.123.1"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.9.1"
    }
  }

  # State stays OUTSIDE the Git repo. The path is given at init time:
  #   tofu init -backend-config=backend.hcl
  # See backend.hcl.example and docs/09-git-state-secrets.md.
  backend "local" {}
}
