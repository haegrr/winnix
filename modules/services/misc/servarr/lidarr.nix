{ config, lib, ... }:

with lib;

let
  cfg = config.services.lidarr;
in
{
  options.services.lidarr = {
    enable = mkEnableOption "Lidarr";
    openFirewall = mkOption {
      type = types.bool;
      default = false;
    };
    port = mkOption {
      type = types.port;
      default = 8686;
      readOnly = true;
    };
  };

  config = mkIf cfg.enable {
    dsc.resources = [
      {
        name = "Install Lidarr";
        type = "Microsoft.WinGet.DSC/WinGetPackage";
        properties = {
          id = "TeamLidarr.Lidarr";
          source = "winget";
        };
      }
    ];

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];
  };
}
