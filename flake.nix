{
  description = "NordVPN NixOS flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, ... }: {
    nixosModules.nordvpn = {
      imports = [ ./module.nix ];
      services.nordvpn = {
        enable = true;
      };
    };

  };
}
