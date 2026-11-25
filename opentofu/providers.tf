# No credentials here. The provider reads them from the environment:
#   PROXMOX_VE_ENDPOINT   e.g. https://10.10.10.1:8006/ (through Tailscale)
#   PROXMOX_VE_API_TOKEN  tofu@pve!homelab=xxxxxxxx-xxxx-...
#   PROXMOX_VE_INSECURE   true (self-signed Proxmox certificate)
# Those variables come from secrets/tofu.enc.env, decrypted on the fly by sops:
#   sops exec-env ../secrets/tofu.enc.env 'tofu plan'
provider "proxmox" {}
