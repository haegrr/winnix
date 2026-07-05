{
  lib,
  modules,
  specialArgs ? { },
}:

with builtins;
with lib;

let
  baseModules = import ./modules/module-list.nix;
  jsonValue = types.oneOf [
    types.str
    types.int
    types.float
    types.bool
    (types.attrsOf (types.nullOr jsonValue))
    (types.listOf (types.nullOr jsonValue))
  ];

  isJsonObject = value: isAttrs value && !isDerivation value;

  matchesParameterValueType =
    type: value:
    {
      string = isString value;
      secureString = isString value;
      int = isInt value;
      bool = isBool value;
      object = isJsonObject value;
      secureObject = isJsonObject value;
      array = isList value;
    }
    .${type};

  validateParameter =
    param:
    let
      check = condition: message: if condition then true else throw message;
      typeName = param.type;
      typedValueMessage = field: "DSC parameter `${field}` must match type `${typeName}`.";
      intBoundMessage = field: "DSC parameter `${field}` is only valid when type is `int`.";
      lengthBoundMessage =
        field: "DSC parameter `${field}` is only valid when type is `string`, `secureString`, or `array`.";
    in
    check (param.defaultValue == null || matchesParameterValueType typeName param.defaultValue) (
      typedValueMessage "defaultValue"
    )
    && check (
      param.allowedValues == null || all (matchesParameterValueType typeName) param.allowedValues
    ) (typedValueMessage "allowedValues")
    && check (typeName == "int" || (param.minValue == null && param.maxValue == null)) (
      intBoundMessage "minValue/maxValue"
    )
    && check (
      elem typeName [
        "string"
        "secureString"
        "array"
      ]
      || (param.minLength == null && param.maxLength == null)
    ) (lengthBoundMessage "minLength/maxLength")
    && check (
      param.minValue == null || param.maxValue == null || param.minValue < param.maxValue
    ) "DSC parameter `minValue` must be less than `maxValue`."
    && check (
      param.minLength == null || param.maxLength == null || param.minLength < param.maxLength
    ) "DSC parameter `minLength` must be less than `maxLength`.";

  parameterType = types.enum [
    "string"
    "secureString"
    "int"
    "bool"
    "object"
    "secureObject"
    "array"
  ];

  parameter = types.addCheck (types.submodule {
    options = {
      type = mkOption {
        type = parameterType;
        description = "DSC parameter data type.";
      };

      defaultValue = mkOption {
        type = types.nullOr jsonValue;
        default = null;
      };

      allowedValues = mkOption {
        type = types.nullOr (types.listOf jsonValue);
        default = null;
      };

      description = mkOption {
        type = types.nullOr types.str;
        default = null;
      };

      metadata = mkOption {
        type = types.attrsOf (types.nullOr jsonValue);
        default = { };
      };

      minValue = mkOption {
        type = types.nullOr types.int;
        default = null;
      };

      maxValue = mkOption {
        type = types.nullOr types.int;
        default = null;
      };

      minLength = mkOption {
        type = types.nullOr types.ints.unsigned;
        default = null;
      };

      maxLength = mkOption {
        type = types.nullOr types.ints.unsigned;
        default = null;
      };
    };
  }) validateParameter;

  resource = types.submodule {
    options = {
      type = mkOption {
        type = types.strMatching "^[[:alnum:]_]+(\\.[[:alnum:]_]+){0,3}/[[:alnum:]_]+$";
        description = "DSC resource fully-qualified type name.";
      };

      name = mkOption {
        type = types.strMatching "^[a-zA-Z0-9 ]+$";
        description = "Unique DSC resource instance name.";
      };

      dependsOn = mkOption {
        type = types.listOf (
          types.strMatching "^\\[resourceId\\([[:space:]]*'[[:alnum:]_]+(\\.[[:alnum:]_]+){0,2}/[[:alnum:]_]+'[[:space:]]*,[[:space:]]*'[a-zA-Z0-9 ]+'[[:space:]]*\\)\\]$"
        );
        default = [ ];
        apply =
          deps: if unique deps == deps then deps else throw "DSC resource dependsOn entries must be unique.";
      };

      properties = mkOption {
        type = types.attrsOf (types.nullOr jsonValue);
        default = { };
      };
    };
  };

  metadata = types.submodule {
    freeformType = types.attrsOf (types.nullOr jsonValue);

    options."Microsoft.DSC" = mkOption {
      type = types.nullOr (
        types.submodule {
          options.securityContext = mkOption {
            type = types.enum [
              "current"
              "elevated"
              "restricted"
            ];
            default = "current";
          };
        }
      );
      default = null;
    };
  };

  eval = evalModules {
    inherit specialArgs;

    class = "windows";
    modules = [
      ({ config, ... }: {
        options.dsc = mkOption {
          type = types.submodule {
            options = {
              "$schema" = mkOption {
                type = types.str;
                readOnly = true;
                default = "https://aka.ms/dsc/schemas/v3/bundled/config/document.json";
              };

              parameters = mkOption {
                type = types.attrsOf parameter;
                default = { };
              };

              variables = mkOption {
                type = types.attrsOf (types.nullOr jsonValue);
                default = { };
              };

              resources = mkOption {
                type = types.listOf resource;
                default = [ ];
              };

              metadata = mkOption {
                type = metadata;
                default = { };
                apply = filterAttrs (n: v: v != null);
              };
            };
          };

          default = { };

          description = "PowerShell DSC v3 configuration document.";
        };

        options.rendered = mkOption {
          type = types.path;
          readOnly = true;
        };

        config.rendered = toFile "config.json" (toJSON config.dsc);
      })
    ]
    ++ baseModules
    ++ modules;
  };
in
eval.config.rendered
