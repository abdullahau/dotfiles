{
  description = "homelab: NixOS host and home-manager config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
  };

  outputs =
    {
      nixpkgs,
      home-manager,
      sops-nix,
      disko,
      nixos-hardware,
      ...
    }:
    let
      system = "x86_64-linux";
      user = "abdullah";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    in
    {
      # Phase 1: the current Ubuntu box.
      #   home-manager switch --flake ./nix#abdullah
      homeConfigurations.${user} = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = { inherit user; };
        modules = [
          ./home
          { targets.genericLinux.enable = true; }
        ];
      };

      # Phase 2: the future NixOS install.
      #   nixos-anywhere --flake ./nix#homelab <user>@<ip>
      #   nixos-rebuild switch --flake ./nix#homelab
      nixosConfigurations.homelab = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit user; };
        modules = [
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          nixos-hardware.nixosModules.apple-macbook-pro-12-1
          home-manager.nixosModules.home-manager
          ./hosts/homelab
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              backupFileExtension = "hm-backup";
              extraSpecialArgs = { inherit user; };
              users.${user} = import ./home;
            };
          }
        ];
      };

      formatter.${system} = pkgs.nixfmt;
    };
}
