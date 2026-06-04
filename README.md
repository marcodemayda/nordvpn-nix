# nix-nordvpn

NordVPN on Nix. There is an official package hopefully coming soon,
you can check the [PR](https://github.com/NixOS/nixpkgs/pull/406725);
but in the meanwhile...

## How to use

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

You'll want to login via the CLI with an API token, follow
[NordVPN's instructions](https://support.nordvpn.com/hc/en-us/articles/20286980309265-How-to-log-in-to-NordVPN-without-a-GUI-using-a-token)

### Updating the package

As it stands, you'll want to update this module manually.

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
```
And the modify back as needed

### Notice

Both I and the original author (chomes) are
self-admitedly inexperienced with making Nix derivation.

Lallapallooza and morettimarco contributions (seem to) have heavy AI usage.
I've audited (insofar as I'm able, which isn't much), and explicitly comment on any AI code
that _**I** introduced myself_.
