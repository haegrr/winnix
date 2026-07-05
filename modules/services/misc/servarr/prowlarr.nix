{ config, lib, ... }:

with lib;

let
  cfg = config.services.prowlarr;
in
{
  options.services.prowlarr = {
    enable = mkEnableOption "Prowlarr";
    openFirewall = mkOption {
      type = types.bool;
      default = false;
    };
    port = mkOption {
      type = types.port;
      default = 9696;
      readOnly = true;
    };
  };

  config = mkIf cfg.enable {
    dsc.resources = [
      {
        name = "Install Prowlarr";
        type = "Microsoft.WinGet.DSC/WinGetPackage";
        properties = {
          id = "TeamProwlarr.Prowlarr";
          source = "winget";
        };
      }
    ];

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];
  };
}
