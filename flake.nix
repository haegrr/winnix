{
  inputs = {
    nixpkgs.url = "github:nix-community/nixpkgs.lib";
  };

  outputs =
    { nixpkgs, ... }:
    let
      evalConfig = import ./eval-config.nix;
    in
    {
      lib.windowsSystem =
        args:
        evalConfig (
          {
            inherit (nixpkgs) lib;
          }
          // args
        );
      flakeModules.default = import ./flake-module.nix;
    };
}
