# nix-nordvpn

This is a repo for nordvpn on nix.
Forked from https://github.com/marcodemayda/nix_modules.


## How to use

- Copy `nordvpn-module.nix` into your configuration folder.
- Add it in your imports, usually in `configuration.nix`.

```nix
  imports =
    [
    ./path/to/nordvpn-module.nix
    ];
```

- In your configuration.nix file you will then need to add the following lines

```nix
  # NordVPN configuration
  services.nordvpn =
  {
  enable = true;
  users = [ "<your-user-name>" ];
  };
```

- Rebuild your system, usually with `sudo nixos-rebuild switch`.
You'll want to login via the CLI with an API token, follow
[NordVPN's instructions](https://support.nordvpn.com/hc/en-us/articles/20286980309265-How-to-log-in-to-NordVPN-without-a-GUI-using-a-token)

### Updating the package

As it stands, you'll want to update this package manually.

You can find the latest version of the `.deb` files [here](https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/n/nordvpn/)
get the version number e.g. `4.5.0` and replace the version in:

```nix
# MARK: version number here.
version = "4.5.0";
```

You then have to match a hash to the version:

```nix
# MARK: hash here.
hash = "sha256-bekJOzhLGwFsYRuPagANwUduyCufaU4XoJPwWoBniR8=";
# hash = "sha256-0000000000000000000000000000000000000000000=";
```

If you build with the fake one (uncoment it and comment the other),
nix should fail the build, and give you the correct hash in the error message.

### Notice

Both I and the original author (chomes) are by
self-admitedly inexperienced with making Nix derivation.

Lallapallooza and morettimarco contributions (seem to) have heavy AI usage.
I've audited (insofar as I'm able), and explicitly comment on any AI code
that _**I** introduced myself_.
