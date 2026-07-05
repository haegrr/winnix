{ config, lib, ... }:

with lib;

let
  cfg = config.services.sonarr;
in
{
  options.services.sonarr = {
    enable = mkEnableOption "Sonarr";
    openFirewall = mkOption {
      type = types.bool;
      default = false;
    };
    port = mkOption {
      type = types.port;
      default = 8989;
      readOnly = true;
    };
  };

  config = mkIf cfg.enable {
    dsc.resources = [
      {
        name = "Install Sonarr";
        type = "Microsoft.WinGet.DSC/WinGetPackage";
        properties = {
          id = "TeamSonarr.Sonarr";
          source = "winget";
        };
      }
    ];

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];
  };
}
