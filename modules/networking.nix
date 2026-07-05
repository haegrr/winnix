{ config, lib, ... }:

with builtins;
with lib;

let
  cfg = config.networking;

  ipv4Pattern = "^([0-9]{1,3}\\.){3}[0-9]{1,3}$";
  ipv6Pattern = "^[0-9A-Fa-f:]+$";

  isIPv4Address = value: isString value && match ipv4Pattern value != null;
  isIPv6Address = value: isString value && match ipv6Pattern value != null && hasInfix ":" value;
  isIPAddress = value: isIPv4Address value || isIPv6Address value;

  ipAddressType = types.addCheck types.str isIPAddress;

  gatewayType = types.submodule {
    options = {
      address = mkOption {
        type = ipAddressType;
        description = "Gateway IP address.";
      };

      interface = mkOption {
        type = types.nonEmptyStr;
        description = "Interface alias for the gateway.";
      };
    };
  };

  addressType = types.submodule {
    options = {
      address = mkOption {
        type = ipAddressType;
        description = "IP address without prefix length.";
      };

      prefixLength = mkOption {
        type = types.ints.between 0 128;
        description = "CIDR prefix length for the address.";
      };
    };
  };

  interfaceType = types.submodule {
    options = {
      ipv4.addresses = mkOption {
        type = types.listOf addressType;
        default = [ ];
        description = "Static IPv4 addresses for the interface.";
      };

      ipv6.addresses = mkOption {
        type = types.listOf addressType;
        default = [ ];
        description = "Static IPv6 addresses for the interface.";
      };

      nameservers = mkOption {
        type = types.listOf ipAddressType;
        default = [ ];
        description = "Static DNS servers for the interface.";
      };
    };
  };

  firewallType = types.submodule {
    options = {
      enable = mkEnableOption "generated Windows firewall rules";

      allowedTCPPorts = mkOption {
        type = types.listOf types.port;
        default = [ ];
        description = "Allowed inbound TCP ports.";
      };

      allowedUDPPorts = mkOption {
        type = types.listOf types.port;
        default = [ ];
        description = "Allowed inbound UDP ports.";
      };
    };
  };

  isAlphaNum = char: match "[A-Za-z0-9]" char != null;

  sanitizeNamePart =
    part: concatStrings (map (char: if isAlphaNum char then char else " ") (stringToCharacters part));

  mkResourceName = parts: concatStringsSep " " (map sanitizeNamePart parts);

  mkResource = nameParts: resourceType: properties: {
    name = mkResourceName nameParts;
    type = "NetworkingDsc/${resourceType}";
    inherit properties;
  };

  mkGatewayResource =
    family: gateway:
    mkResource [ "Networking" "Default Gateway" family gateway.interface ] "DefaultGatewayAddress"
      {
        InterfaceAlias = gateway.interface;
        AddressFamily = family;
        Address = gateway.address;
      };

  mkIPAddressResource =
    interfaceName: family: addresses:
    mkResource [ "Networking" "IPAddress" family interfaceName ] "IPAddress" {
      InterfaceAlias = interfaceName;
      AddressFamily = family;
      IPAddress = map (address: "${address.address}/${toString address.prefixLength}") addresses;
    };

  mkDnsServerResource =
    interfaceName: family: addresses:
    mkResource [ "Networking" "DNS" family interfaceName ] "DnsServerAddress" {
      InterfaceAlias = interfaceName;
      AddressFamily = family;
      Address = addresses;
    };

  mkFirewallResource =
    protocol: port:
    mkResource [ "Networking" "Firewall" protocol (toString port) ] "Firewall" {
      Name = mkResourceName [
        "Networking"
        protocol
        (toString port)
      ];
      Ensure = "Present";
      Enabled = "True";
      Direction = "Inbound";
      Action = "Allow";
      Protocol = protocol;
      LocalPort = [ (toString port) ];
    };

  mkHostsResource =
    ipAddress: hostName:
    mkResource [ "Networking" "Hosts" hostName ] "HostsFile" {
      HostName = hostName;
      IPAddress = ipAddress;
      Ensure = "Present";
    };

  validateGatewayFamily =
    family: gateway:
    if family == "IPv4" && !isIPv4Address gateway.address then
      throw "networking ${family} default gateway address `${gateway.address}` must be an IPv4 address."
    else if family == "IPv6" && !isIPv6Address gateway.address then
      throw "networking ${family} default gateway address `${gateway.address}` must be an IPv6 address."
    else
      gateway;

  validateAddressFamily =
    interfaceName: family: address:
    if family == "IPv4" && !isIPv4Address address.address then
      throw "networking.interfaces.${interfaceName}.${toLower family}.addresses contains non-IPv4 address `${address.address}`."
    else if family == "IPv6" && !isIPv6Address address.address then
      throw "networking.interfaces.${interfaceName}.${toLower family}.addresses contains non-IPv6 address `${address.address}`."
    else if family == "IPv4" && address.prefixLength > 32 then
      throw "networking.interfaces.${interfaceName}.ipv4.addresses prefixLength must be between 0 and 32."
    else
      address;

  interfaceResources = concatLists (
    mapAttrsToList (
      interfaceName: interface:
      let
        ipv4Addresses = map (validateAddressFamily interfaceName "IPv4") interface.ipv4.addresses;
        ipv6Addresses = map (validateAddressFamily interfaceName "IPv6") interface.ipv6.addresses;
        ipv4Nameservers = filter isIPv4Address interface.nameservers;
        ipv6Nameservers = filter isIPv6Address interface.nameservers;
        invalidNameservers = filter (address: !isIPAddress address) interface.nameservers;
      in
      if invalidNameservers != [ ] then
        throw "networking.interfaces.${interfaceName}.nameservers contains invalid IP addresses."
      else
        optional (ipv4Addresses != [ ]) (mkIPAddressResource interfaceName "IPv4" ipv4Addresses)
        ++ optional (ipv6Addresses != [ ]) (mkIPAddressResource interfaceName "IPv6" ipv6Addresses)
        ++ optional (ipv4Nameservers != [ ]) (mkDnsServerResource interfaceName "IPv4" ipv4Nameservers)
        ++ optional (ipv6Nameservers != [ ]) (mkDnsServerResource interfaceName "IPv6" ipv6Nameservers)
    ) cfg.interfaces
  );

  firewallResources =
    if cfg.firewall.enable then
      (map (mkFirewallResource "TCP") cfg.firewall.allowedTCPPorts)
      ++ (map (mkFirewallResource "UDP") cfg.firewall.allowedUDPPorts)
    else
      [ ];

  hostResources = concatLists (
    mapAttrsToList (
      ipAddress: hostNames:
      if !isIPAddress ipAddress then
        throw "networking.hosts key `${ipAddress}` must be an IPv4 or IPv6 address."
      else
        map (mkHostsResource ipAddress) hostNames
    ) cfg.hosts
  );

  networkingResources =
    optional (cfg.defaultGateway != null) (
      mkGatewayResource "IPv4" (validateGatewayFamily "IPv4" cfg.defaultGateway)
    )
    ++ optional (cfg.defaultGateway6 != null) (
      mkGatewayResource "IPv6" (validateGatewayFamily "IPv6" cfg.defaultGateway6)
    )
    ++ interfaceResources
    ++ firewallResources
    ++ hostResources;
in
{
  options.networking = {
    defaultGateway = mkOption {
      type = types.nullOr gatewayType;
      default = null;
      description = "IPv4 default gateway.";
    };

    defaultGateway6 = mkOption {
      type = types.nullOr gatewayType;
      default = null;
      description = "IPv6 default gateway.";
    };

    interfaces = mkOption {
      type = types.attrsOf interfaceType;
      default = { };
      description = "Network interface configuration.";
    };

    firewall = mkOption {
      type = firewallType;
      default = { };
      description = "Generated Windows firewall rules.";
    };

    hosts = mkOption {
      type = types.attrsOf (types.listOf types.nonEmptyStr);
      default = { };
      description = "Hosts file entries keyed by IP address.";
    };
  };

  config.dsc.resources = networkingResources;
}
