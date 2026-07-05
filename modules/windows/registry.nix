{ config, lib, ... }:

with builtins;
with lib;

let
  cfg = config.windows.registry;

  registryTypes = [
    "String"
    "ExpandString"
    "MultiString"
    "Binary"
    "DWord"
    "QWord"
  ];

  matchesRegistryValueType =
    type: value:
    {
      String = isString value;
      ExpandString = isString value;
      MultiString = isList value && all isString value;
      Binary = isList value && all (v: isInt v && v >= 0 && v <= 255) value;
      DWord = isInt value && value >= 0 && value <= 4294967295;
      QWord = isInt value;
    }
    .${type};

  isRegistryEntry = value: isAttrs value && value ? type && value ? value;

  isPartialRegistryEntry =
    value: isAttrs value && (value ? type || value ? value) && !isRegistryEntry value;

  validateRegistryEntry =
    path: entry:
    let
      fullPath = concatStringsSep "\\" path;
      invalidType = !elem entry.type registryTypes;
      invalidValue = !matchesRegistryValueType entry.type entry.value;
    in
    if length path < 2 then
      throw "Windows registry entry `${fullPath}` must include a hive, key path, and value name."
    else if invalidType then
      throw "Windows registry entry `${fullPath}` has unsupported type `${entry.type}`."
    else if invalidValue then
      throw "Windows registry entry `${fullPath}` value does not match registry type `${entry.type}`."
    else
      {
        inherit path entry;
      };

  flattenRegistry =
    path: value:
    if isRegistryEntry value then
      [
        (validateRegistryEntry path value)
      ]
    else if isPartialRegistryEntry value then
      throw "Windows registry entry `${concatStringsSep "\\" path}` must define both `type` and `value`."
    else if isAttrs value then
      concatLists (mapAttrsToList (name: child: flattenRegistry (path ++ [ name ]) child) value)
    else
      throw "Windows registry subtree `${concatStringsSep "\\" path}` must be an attribute set.";

  isAlphaNum = char: match "[A-Za-z0-9]" char != null;

  sanitizeNamePart =
    part: concatStrings (map (char: if isAlphaNum char then char else " ") (stringToCharacters part));

  mkResourceName = path: concatStringsSep " " (map sanitizeNamePart path);

  mkRegistryResource =
    { path, entry }:
    {
      name = mkResourceName path;
      type = "Microsoft.Windows/Registry";
      properties = {
        keyPath = concatStringsSep "\\" (init path);
        valueName = last path;
        valueData = {
          ${entry.type} = entry.value;
        };
      };
    };

  registryEntries = flattenRegistry [ ] cfg;
in
{
  options.windows.registry = mkOption {
    type = types.attrsOf types.anything;
    default = { };
    description = "Windows registry values managed through Microsoft.Windows/Registry DSC resources.";
  };

  config = {
    dsc.resources = map mkRegistryResource registryEntries;
  };
}
