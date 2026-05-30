{
  config,
  lib,
  pkgs,
  ...
}:
let
  nordVpnPkg = pkgs.callPackage (
    {
      autoPatchelfHook,
      buildFHSEnvChroot,
      dpkg,
      fetchurl,
      lib,
      stdenv,
      sysctl,
      iptables,
      iproute2,
      procps,
      cacert,
      sqlite,
      libnl,
      libcap_ng,
      libxml2,
      libidn2,
      zlib,
      wireguard-tools,
    }:
    let
      pname = "nordvpn";
      # MARK: version nr here
      version = "4.5.0";

      nordVPNBase = stdenv.mkDerivation {
        inherit pname version;

        src = fetchurl {
          url = "https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/n/nordvpn/nordvpn_${version}_amd64.deb";
          # MARK: hash here.
          hash = "sha256-bekJOzhLGwFsYRuPagANwUduyCufaU4XoJPwWoBniR8=";
        };

        buildInputs = [
          libxml2
          libidn2
          libnl
          libcap_ng
          sqlite
        ];
        nativeBuildInputs = [
          dpkg
          autoPatchelfHook
          stdenv.cc.cc.lib
        ];

        dontConfigure = true;
        dontBuild = true;

        unpackPhase = ''
          runHook preUnpack
          dpkg --extract $src .
          runHook postUnpack
        '';

        installPhase = ''
          runHook preInstall
          mkdir -p $out
          mv usr/* $out/
          mv var/ $out/
          mv etc/ $out/
          runHook postInstall
        '';
      };

      nordVPNfhs = buildFHSEnvChroot {
        name = "nordvpnd";
        runScript = "nordvpnd";

        # hardcoded path to /sbin/ip
        targetPkgs = pkgs: [
          sqlite
          nordVPNBase
          sysctl
          iptables
          iproute2
          procps
          cacert
          libxml2
          libnl
          libcap_ng
          libidn2
          zlib
          wireguard-tools
        ];
      };
    in
    stdenv.mkDerivation {
      inherit pname version;

      dontUnpack = true;
      dontConfigure = true;
      dontBuild = true;

      installPhase = ''
        runHook preInstall
        mkdir -p $out/bin $out/share
        ln -s ${nordVPNBase}/bin/nordvpn $out/bin
        ln -s ${nordVPNfhs}/bin/nordvpnd $out/bin
        ln -s ${nordVPNBase}/share/* $out/share/
        ln -s ${nordVPNBase}/var $out/
        runHook postInstall
      '';

      meta = with lib; {
        description = "CLI client for NordVPN";
        homepage = "https://www.nordvpn.com";
        license = licenses.unfreeRedistributable;
        maintainers = with maintainers; [ dr460nf1r3 ];
        platforms = [ "x86_64-linux" ];
      };
    }
  ) { };
in
with lib;
{
  options.services.nordvpn.enable = mkOption {
    type = types.bool;
    default = false;
    description = ''
      Whether to enable the NordVPN daemon.
    '';
  };

  options.services.nordvpn.users = mkOption {
    type = types.listOf types.str;
    default = [ ];
    description = ''
      Which users to add to the "nordvpn" group.
      Your current user must be in the group for a successful
      login. If you prefer to set this elsewhere, like
      `users.users.<username>.extraGroups`, set this to `[]`.
      Keep in mind that updating groups may require reboot/re-login.
    '';
    example = [ "alice" ];
  };

  options.services.nordvpn.openFirewall = mkOption {
    type = types.bool;
    default = false;
    description = ''
      Whether to open the firewall for NordVPN.
      This includes setting
      adding ports TCP 443 and UDP 1194 to the respective allowlists.
    '';
    example = true;
  };

  options.services.nordvpn.checkReversePath = mkOption {
    type = lib.types.nullOr (
      lib.types.either lib.types.bool (
        lib.types.enum [
          "strict"
          "loose"
        ]
      )
    );
    default = null;
    description = ''
      Set `networking.firewall.checkReversePath;` option
      NordVPN works best with value of false.
      But you may want a different value (eg EduVPN works best with
      "loose" instead)
    '';
    example = false;
  };

  options.services.nordvpn.mtu = mkOption {
    type = types.nullOr types.int;
    default = null;
    description = ''
      MTU (max network package size) - smaller means more fragmentation,
      but larger packages can fail to transmit. Leave empty to use the default,
      set to something like `1280` if connection issues occur.
      (Hint: you can test if MTU is low enough using `ping -M do -s 1280 1.1.1.1`,
      replacing `1280` by the MTU you want to try. If too large, it will
      fail with `ping: sendmsg: Message too long`.)
    '';
    example = 1280;
  };

  config = mkIf config.services.nordvpn.enable {
    environment.systemPackages = [ nordVpnPkg ];

    networking.firewall = {
      allowedTCPPorts = mkIf config.services.nordvpn.openFirewall [ 443 ];
      allowedUDPPorts = mkIf config.services.nordvpn.openFirewall [ 1194 ];

      checkReversePath = mkIf (
        config.services.nordvpn.checkReversePath != null
      ) config.services.nordvpn.checkReversePath;
    };

    networking.interfaces = mkIf (config.services.nordvpn.mtu != null) {
      nordlynx.mtu = config.services.nordvpn.mtu;
    };

    # if services.nordvpn.users is defined, add the specified users to the nordvpn group,
    # otherwise ensure group exists by setting users.groups.nordvpn = {}
    # TODO this might be unnecessary with empty-list default.
    # may just need `= config.service.nordvpn.users`
    users.groups.nordvpn = {
      members = mkIf (config.services.nordvpn.users != [ ]) config.services.nordvpn.users;
    };

    systemd = {
      services.nordvpn = {
        description = "NordVPN daemon.";
        serviceConfig = {
          ExecStart = "${nordVpnPkg}/bin/nordvpnd";
          ExecStartPre = pkgs.writeShellScript "nordvpn-start" ''
            mkdir -m 700 -p /var/lib/nordvpn;
            if [ -z "$(ls -A /var/lib/nordvpn)" ]; then
              cp -r ${nordVpnPkg}/var/lib/nordvpn/* /var/lib/nordvpn;
            fi
          '';
          NonBlocking = true;
          KillMode = "process";
          Restart = "on-failure";
          RestartSec = 5;
          RuntimeDirectory = "nordvpn";
          RuntimeDirectoryMode = "0750";
          Group = "nordvpn";
        };
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
      };
    };
  };
}
