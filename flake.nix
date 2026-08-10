{
  description = "NordVPN NixOS flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, ... }: {
    nixosModules.nordvpn = {
      imports = [ ./nordvpn-module.nix ];
      services.nordvpn = {
        enable = true;
      };
    };

  };
}
