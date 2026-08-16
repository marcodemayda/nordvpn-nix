# nix-nordvpn

Derivation for NordVPN on Nix.

NordVPN now has an official module! It is currently on unstable.
Once it gets to stable I'll stop updating this custom module (assuming
the official one works better, which I bet it will).



## Install

### Flake

If you have flakes, you can pull this module directly, and don't have to worry about
updating yourself.

In your flake.nix merge values with:

```nix
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
        services.nordvpn.enable =true;
      };
    };
```

Note: importing the flake automatically enables the service, you need only specify options. Make sure you add your user to nordvpn group with `services.nordvpn.users = ["<youruser>" ];`

If (for some obscure reason) you want to import without enabling, explicitly declare `services.nordvpn.enable = false`


### Manual Module

- Copy `nordvpn-module.nix` into your configuration folder.
- Add it in your imports, usually in `configuration.nix`:
```nix
  imports =
    [
    ./relative/path/to/nordvpn-module.nix
    ];
```

- In your configuration.nix file add the following:
```nix
  # NordVPN configuration
  services.nordvpn =
  {
  enable = true;
  users = [ "<your-user-name>" ];
  };
```

- Rebuild your system, usually with `sudo nixos-rebuild switch`.

#### Updating the package

If you're doing things manually, you'll need to run updates yourself:

You can find the latest version of the `.deb` files [here](https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/n/nordvpn/)
get the version number e.g. `4.5.0` and replace the version in:

```nix
  # MARK: Modify Values Here
  version = "4.5.0";
```

You then have to match a hash to the version. Find the links in the
module
```
nix store prefetch-file --hash-type sha256 \
<url>
```

Alternatively you can build with a dummy hash, and Nix will throw
the correct hash in the rebuild error. Temporarily set

```nix
# MARK: Modify Values Here
#...
dummyHash = "sha256-0000000000000000000000000000000000000000000=";
cliHash = dummyHash
guiHash = dummyHash
```
And the modify back as needed

## Usage

You'll want to login via the CLI with an API token, follow
[NordVPN's instructions](https://support.nordvpn.com/hc/en-us/articles/20286980309265-How-to-log-in-to-NordVPN-without-a-GUI-using-a-token).
I suggest setting up a [sops-nix](https://github.com/Mic92/sops-nix) or [agenix](https://github.com/ryantm/agenix) secret service so you always have it on hand on any device :).

Then usage is straightforward both with CLI and GUI.

## Notice

Both I and the original author (chomes) are
self-admitedly inexperienced with making Nix derivation.

Lallapallooza and morettimarco contributions (seem to) have heavy AI usage.
I've audited (insofar as I'm able, which isn't much), and explicitly comment on any AI code
that _**I** introduced myself_.
