# Placeholder. nixos-anywhere writes the real file:
#   nixos-anywhere --flake ./nix#homelab \
#     --generate-hardware-config nixos-generate-config ./nix/hosts/homelab/hardware-configuration.nix \
#     <user>@<ip>
{ ... }:
{
  nixpkgs.hostPlatform = "x86_64-linux";
}
