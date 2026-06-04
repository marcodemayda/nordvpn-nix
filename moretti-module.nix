# NordVPN CLI (`nordvpn`), daemon (`nordvpnd`), and official Flutter/GTK3 GUI
# as a single NixOS module.
#
# Lineage:
#   - https://github.com/chomes/nix_modules (CLI base, MIT)
#   - https://github.com/Lallapallooza/simple_nix (GUI extension, Apache-2.0)
#   - This repo: standalone flake packaging, configurable options, systemd-
#     resolved requirement made explicit, comprehensive README.

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.nordvpn;

  # -- CLI + daemon (FHS-wrapped) ----------------------------------------
  nordVpnBase = pkgs.stdenv.mkDerivation {
    pname = "nordvpn-base";
    version = cfg.package.version;
    src = pkgs.fetchurl {
      url = "https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/n/nordvpn/nordvpn_${cfg.package.version}_amd64.deb";
      hash = cfg.package.cliHash;
    };
    buildInputs = with pkgs; [
      libxml2
      libidn2
      libnl
      libcap_ng
      sqlite
    ];
    nativeBuildInputs = with pkgs; [
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
    meta.license = lib.licenses.unfreeRedistributable;
  };

  nordVpnDaemon = pkgs.buildFHSEnv {
    name = "nordvpnd";
    runScript = "nordvpnd";
    targetPkgs =
      _: with pkgs; [
        sqlite
        nordVpnBase
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

  nordVpnPkg = pkgs.stdenv.mkDerivation {
    pname = "nordvpn";
    version = cfg.package.version;
    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin $out/share
      ln -s ${nordVpnBase}/bin/nordvpn $out/bin
      ln -s ${nordVpnDaemon}/bin/nordvpnd $out/bin
      ln -s ${nordVpnBase}/share/* $out/share/
      ln -s ${nordVpnBase}/var $out/
      runHook postInstall
    '';
    meta = with lib; {
      description = "CLI client for NordVPN";
      homepage = "https://www.nordvpn.com";
      license = licenses.unfreeRedistributable;
      platforms = [ "x86_64-linux" ];
    };
  };

  # -- GUI (Flutter/GTK3, FHS-wrapped) -----------------------------------
  nordVpnGuiBase = pkgs.stdenv.mkDerivation {
    pname = "nordvpn-gui-base";
    version = cfg.package.version;
    src = pkgs.fetchurl {
      url = "https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/n/nordvpn-gui/nordvpn-gui_${cfg.package.version}_amd64.deb";
      hash = cfg.package.guiHash;
    };
    nativeBuildInputs = [ pkgs.dpkg ];
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
      cp -r opt/nordvpn-gui/* $out/
      mkdir -p $out/share
      cp -r usr/share/* $out/share/
      runHook postInstall
    '';
    meta.license = lib.licenses.unfreeRedistributable;
  };

  nordVpnGui = pkgs.buildFHSEnv {
    name = "nordvpn-gui";
    runScript = "${nordVpnGuiBase}/nordvpn-gui";
    targetPkgs =
      _: with pkgs; [
        nordVpnGuiBase
        gtk3
        gdk-pixbuf
        pango
        cairo
        harfbuzz
        atk
        glib
        libx11
        libxcursor
        libxrandr
        libxi
        libxext
        libxcomposite
        libxdamage
        libxfixes
        libxtst
        libepoxy
        fontconfig
        freetype
        libGL
        mesa
        dbus
        stdenv.cc.cc.lib
      ];
    extraInstallCommands = ''
      mkdir -p $out/share/applications $out/share/icons
      cp -r ${nordVpnGuiBase}/share/applications/* $out/share/applications/ 2>/dev/null || true
      cp -r ${nordVpnGuiBase}/share/icons/* $out/share/icons/ 2>/dev/null || true
      substituteInPlace $out/share/applications/nordvpn-gui.desktop \
        --replace-fail "Exec=nordvpn-gui" "Exec=$out/bin/nordvpn-gui"
    '';
  };

  presetScript = pkgs.writeShellScript "nordvpn-apply-presets" (
    ''
      # Bounded wait for the daemon socket to come up.
      for _ in $(seq 1 10); do
        ${nordVpnPkg}/bin/nordvpn settings >/dev/null 2>&1 && break
        sleep 1
      done
    ''
    + lib.concatStringsSep "\n" (
      lib.mapAttrsToList (k: v: "${nordVpnPkg}/bin/nordvpn set ${k} ${v}") cfg.presets
    )
    + ''

      touch /var/lib/nordvpn/.nix-presets-applied
    ''
  );
in
{
  options.services.nordvpn = {
    enable = lib.mkEnableOption "NordVPN daemon and CLI";

    enableGui = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to install the official NordVPN GUI app (Flutter/GTK3).
        Set to false for a CLI-only install.
      '';
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to start nordvpnd at boot. Defaults to false (on-demand)
        because typical laptop usage starts the VPN per session. Set to
        true together with `nordvpn set autoconnect on <country>` for
        always-on VPN.
      '';
    };

    enableResolved = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable systemd-resolved. Required on NixOS — without it, the
        daemon's DNS configuration fails (it iterates resolved → resolvectl
        → nmcli → resolvconf → /etc/resolv.conf, and every path fails) and
        the connection rolls back after the WireGuard handshake succeeds.
        Set this to false ONLY if you've enabled `services.resolved`
        elsewhere in your config.
      '';
    };

    setReversePath = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Set `networking.firewall.checkReversePath = "loose"`. NordVPN's
        asymmetric routing through the tunnel is dropped by default strict
        rp_filter. Disable only if you handle this yourself.
      '';
    };

    presets = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = lib.literalExpression ''
        {
          technology = "nordlynx";
          threatprotectionlite = "on";
          killswitch = "on";
        }
      '';
      description = ''
        Settings applied via `nordvpn set <key> <value>` on first daemon
        start. Idempotent — a marker file at
        /var/lib/nordvpn/.nix-presets-applied prevents re-running. To
        re-apply, delete the marker and restart the service.
      '';
    };

    package = {
      version = lib.mkOption {
        type = lib.types.str;
        default = "4.6.0";
        description = "NordVPN .deb version to fetch from repo.nordvpn.com.";
      };

      cliHash = lib.mkOption {
        type = lib.types.str;
        default = "sha256-t+kvgKzjLJY0PK9eg6Edv9+opVrqWUl9WMRIuHDJQuM=";
        description = ''
          SRI hash of the `nordvpn_<version>_amd64.deb` file. Refresh with
          `nix-prefetch-url` + `nix hash convert --to sri` after a version
          bump.
        '';
      };

      guiHash = lib.mkOption {
        type = lib.types.str;
        default = "sha256-h6I1+Xrc4Br4uHVWvZ9wJdgHThxYeQBZaN/EH4hOobE=";
        description = ''
          SRI hash of the `nordvpn-gui_<version>_amd64.deb` file.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ nordVpnPkg ] ++ lib.optional cfg.enableGui nordVpnGui;

    users.groups.nordvpn = { };

    networking.firewall.checkReversePath = lib.mkIf cfg.setReversePath "loose";

    services.resolved.enable = lib.mkIf cfg.enableResolved true;

    systemd.services.nordvpn = {
      description = "NordVPN daemon";
      serviceConfig = {
        ExecStart = "${nordVpnPkg}/bin/nordvpnd";
        ExecStartPre = pkgs.writeShellScript "nordvpn-start" ''
          mkdir -m 700 -p /var/lib/nordvpn
          if [ -z "$(ls -A /var/lib/nordvpn)" ]; then
            cp -r ${nordVpnPkg}/var/lib/nordvpn/* /var/lib/nordvpn
            chmod -R u+w /var/lib/nordvpn
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
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = lib.mkIf cfg.autoStart [ "multi-user.target" ];
    };

    systemd.services.nordvpn-presets = lib.mkIf (cfg.presets != { }) {
      description = "Apply NordVPN presets (first run only)";
      after = [ "nordvpn.service" ];
      requires = [ "nordvpn.service" ];
      wantedBy = [ "nordvpn.service" ];
      unitConfig.ConditionPathExists = "!/var/lib/nordvpn/.nix-presets-applied";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = presetScript;
      };
    };
  };
}
