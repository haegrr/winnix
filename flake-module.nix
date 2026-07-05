{
  lib,
  ...
}:
{
  options.flake.windowsConfigurations = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.raw;
    default = { };
    description = "Windows DSC configurations";
  };
}
