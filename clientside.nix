{
  inputs = {
    pkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable"; # or whatever channel you like

    nordvpn = {
      url = "git+https://codeberg.org/marcodemayda/nordvpn-nix";
      # url = "github:marcodemayda/nordvpn-nix"; # github if you prefer, but i'm less active so it might be slower to update

      # inputs.nixpkgs.follows = "pkgs-unstable"; # change this to a different input if you want
    };
  };

  outputs =
    {
      self,
      pkgs-unstable,
      nordvpn,
      ...
    }:
    {
      nixosModules.nordvpn = {

        imports = [
          nordvpn.nixosModules.nordvpn
        ];
        services.nordvpn.enable = true;
      };
    };
}
