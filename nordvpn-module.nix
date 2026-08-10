{
  config,
  lib,
  pkgs,
  ...
}:

let
  # MARK: Modify Values Here
  version = "5.3.0";

  dummyHash = "sha256-0000000000000000000000000000000000000000000=";

  cliUrl = "https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/n/nordvpn/nordvpn_${version}_amd64.deb";
  cliHash = "sha256-NM3qcqdclwDChblQ7S7Jasru1NYHATo6vRg2ZzH4wzQ=";

  guiUrl = "https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/n/nordvpn-gui/nordvpn-gui_${version}_amd64.deb";
  guiHash = "sha256-4uOhXNPr0nzcIVcLZvNDWprRavRe8pr4xcOZqN8YUTM=";

  cfg = config.services.nordvpn;

  # -- CLI + daemon (FHS-wrapped) ----------------------------------------
  nordVpnBase = pkgs.stdenv.mkDerivation {
    pname = "nordvpn-base";
    inherit version cliHash;
    src = pkgs.fetchurl {
      url = cliUrl;
      hash = cliHash;
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
    inherit version;
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
    inherit version guiHash;
    src = pkgs.fetchurl {
      url = guiUrl;
      hash = guiHash;
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
      # Fix Exec path in .desktop file
      substituteInPlace $out/share/applications/nordvpn-gui.desktop \
        --replace-fail "Exec=nordvpn-gui" "Exec=$out/bin/nordvpn-gui"
    '';
  };

in
with lib;
{
  options.services.nordvpn = with types; {
    enable = mkEnableOption "NordVPN daemon and CLI";

    users = mkOption {
      type = listOf str;
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

    enableGui = mkOption {
      type = bool;
      default = false;
      description = ''
        Whether to install the official NordVPN GUI app (Flutter/GTK3).
        Set to false for a CLI-only install.
      '';
    };

    autoStart = mkOption {
      type = bool;
      default = true;
      description = ''
        Whether to start nordvpnd at boot. Defaults to false (on-demand)
        because typical laptop usage starts the VPN per session. Set to
        true together with `nordvpn set autoconnect on <country>` for
        always-on VPN.
      '';
    };

    enableResolved = mkOption {
      type = bool;
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

    setReversePath = mkOption {
      type = nullOr (
        either bool (enum [
          "strict"
          "loose"
        ])
      );
      default = "loose";
      description = ''
        Set `networking.firewall.checkReversePath`. NordVPN's
        asymmetric routing through the tunnel is dropped by default strict
        rp_filter. Thus loose or false is required for proper functioning.
      '';
    };

    openFirewall = mkOption {
      type = bool;
      default = false;
      description = ''
        Whether to open the firewall for NordVPN.
        This add ports TCP 443 and UDP 1194 to the respective allowlists.
      '';
      example = true;
    };

    mtu = mkOption {
      type = nullOr int;
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

  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ nordVpnPkg ] ++ optional cfg.enableGui nordVpnGui;

    # if services.nordvpn.users is defined, add the specified users to the nordvpn group,
    # otherwise ensure group exists by setting users.groups.nordvpn = {}
    # changed to simpler on AI suggestion. For the (quickly accessible) record: used to be
    # members = mkIf (config.services.nordvpn.users != [ ]) config.services.nordvpn.users;
    users.groups.nordvpn.members = config.services.nordvpn.users;

    networking.firewall = {
      allowedTCPPorts = mkIf config.services.nordvpn.openFirewall [ 443 ];
      allowedUDPPorts = mkIf config.services.nordvpn.openFirewall [ 1194 ];

      checkReversePath = mkIf (
        config.services.nordvpn.setReversePath != null
      ) config.services.nordvpn.setReversePath;
    };

    networking.interfaces = mkIf (config.services.nordvpn.mtu != null) {
      nordlynx.mtu = config.services.nordvpn.mtu;
    };

    services.resolved.enable = mkIf cfg.enableResolved true;

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

    # Settings live in /var/lib/nordvpn (sqlite), which persists across rebuilds.
    # Guarded by a marker file so this runs only on fresh state, not every boot.
    # To re-apply: rm /var/lib/nordvpn/.nix-settings-applied && systemctl start nordvpn-settings
    systemd.services.nordvpn-settings = {
      description = "Apply NordVPN settings (first boot only)";
      after = [ "nordvpn.service" ];
      requires = [ "nordvpn.service" ];
      # Pulled in whenever nordvpn.service starts; condition below makes it a no-op after first run.
      wantedBy = [ "nordvpn.service" ];
      unitConfig.ConditionPathExists = "!/var/lib/nordvpn/.nix-settings-applied";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;

        ExecStart = pkgs.writeShellScript "nordvpn-apply-settings" ''
          # Bounded wait for daemon socket, not a long poll.
          for _ in $(seq 1 10); do
            ${nordVpnPkg}/bin/nordvpn settings >/dev/null 2>&1 && break
            sleep 1
          done
          ${nordVpnPkg}/bin/nordvpn set technology nordwhisper
          ${nordVpnPkg}/bin/nordvpn set threatprotectionlite on
          touch /var/lib/nordvpn/.nix-settings-applied
        '';
      };
    };
  };
}
