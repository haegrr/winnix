{ config, lib, ... }:

with lib;

let
  cfg = config.services.radarr;
in
{
  options.services.radarr = {
    enable = mkEnableOption "Radarr";
    openFirewall = mkOption {
      type = types.bool;
      default = false;
    };
    port = mkOption {
      type = types.port;
      default = 7878;
      readOnly = true;
    };
  };

  config = mkIf cfg.enable {
    dsc.resources = [
      {
        name = "Install Radarr";
        type = "Microsoft.WinGet.DSC/WinGetPackage";
        properties = {
          id = "TeamRadarr.Radarr";
          source = "winget";
        };
      }
    ];

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];
  };
}
