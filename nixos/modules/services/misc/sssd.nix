{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.services.sssd;
  nscd = config.services.nscd;
in {
  options = {
    services.sssd = {
      enable = mkEnableOption "the System Security Services Daemon";

      config = mkOption {
        type = types.lines;
        description = "Contents of <filename>sssd.conf</filename>.";
        default = ''
          [sssd]
          config_file_version = 2
          services = nss, pam
          domains = shadowutils

          [nss]

          [pam]

          [domain/shadowutils]
          id_provider = proxy
          proxy_lib_name = files
          auth_provider = proxy
          proxy_pam_target = sssd-shadowutils
          proxy_fast_alias = True
        '';
      };

      sshAuthorizedKeysIntegration = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to make sshd look up authorized keys from SSS.
          For this to work, the <literal>ssh</literal> SSS service must be enabled in the sssd configuration.
        '';
      };

      kcm = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to use SSS as a Kerberos Cache Manager (KCM).
          Kerberos will be configured to cache credentials in SSS.
        '';
      };
    };
  };
  config = mkMerge [
    (mkIf cfg.enable {
      systemd.services.sssd = {
        description = "System Security Services Daemon";
        wantedBy    = [ "multi-user.target" ];
        before = [ "systemd-user-sessions.service" "nss-user-lookup.target" ];
        after = [ "network-online.target" "nscd.service" ];
        requires = [ "network-online.target" "nscd.service" ];
        wants = [ "nss-user-lookup.target" ];
        restartTriggers = [
          config.environment.etc."nscd.conf".source
          config.environment.etc."sssd/sssd.conf".source
        ];
        script = ''
          export LDB_MODULES_PATH+="''${LDB_MODULES_PATH+:}${pkgs.ldb}/modules/ldb:${pkgs.sssd}/modules/ldb"
          mkdir -p /var/lib/sss/{pubconf,db,mc,pipes,gpo_cache,secrets} /var/lib/sss/pipes/private /var/lib/sss/pubconf/krb5.include.d
          ${pkgs.sssd}/bin/sssd -D
        '';
        serviceConfig = {
          Type = "forking";
          PIDFile = "/run/sssd.pid";
        };
      };

      environment.etc."sssd/sssd.conf" = {
        text = cfg.config;
        mode = "0400";
      };

      system.nssModules = [ pkgs.sssd ];
      system.nssDatabases = {
        group = [ "sss" ];
        passwd = [ "sss" ];
        services = [ "sss" ];
        shadow = [ "sss" ];
      };
      services.dbus.packages = [ pkgs.sssd ];
    })

    (mkIf cfg.kcm {
      systemd.services.sssd-kcm = {
        description = "SSSD Kerberos Cache Manager";
        requires = [ "sssd-kcm.socket" ];
        serviceConfig = {
          ExecStartPre = "-${pkgs.sssd}/bin/sssd --genconf-section=kcm";
          ExecStart = "${pkgs.sssd}/libexec/sssd/sssd_kcm --uid 0 --gid 0";
        };
        restartTriggers = [
          config.environment.etc."sssd/sssd.conf".source
        ];
      };
      systemd.sockets.sssd-kcm = {
        description = "SSSD Kerberos Cache Manager responder socket";
        wantedBy = [ "sockets.target" ];
        # Matches the default in MIT krb5 and Heimdal:
        # https://github.com/krb5/krb5/blob/krb5-1.19.3-final/src/include/kcm.h#L43
        listenStreams = [ "/var/run/.heim_org.h5l.kcm-socket" ];
      };
      krb5.libdefaults.default_ccache_name = "KCM:";
    })

    (mkIf cfg.sshAuthorizedKeysIntegration {
    # Ugly: sshd refuses to start if a store path is given because /nix/store is group-writable.
    # So indirect by a symlink.
    environment.etc."ssh/authorized_keys_command" = {
      mode = "0755";
      text = ''
        #!/bin/sh
        exec ${pkgs.sssd}/bin/sss_ssh_authorizedkeys "$@"
      '';
    };
    services.openssh.authorizedKeysCommand = "/etc/ssh/authorized_keys_command";
    services.openssh.authorizedKeysCommandUser = "nobody";
  })];

  meta.maintainers = with maintainers; [ bbigras ];
}
