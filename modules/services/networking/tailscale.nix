{ config, lib, ... }:

with lib;

let
  cfg = config.services.tailscale;
in
{
  options.services.tailscale = {
    enable = mkEnableOption "Tailscale client daemon";
    openFirewall = mkOption {
      type = types.bool;
      default = false;
    };
    port = mkOption {
      type = types.port;
      default = 41641;
      readOnly = true;
    };
  };

  config = mkIf cfg.enable {
    dsc.resources = [
      {
        name = "Install Tailscale";
        type = "Microsoft.WinGet.DSC/WinGetPackage";
        properties = {
          id = "Tailscale.Tailscale";
          source = "winget";
        };
      }
    ];

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];
  };
}
