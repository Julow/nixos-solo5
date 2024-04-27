{ pkgs, lib, config, ... }:

with lib;

let

  solo5 = (pkgs.solo5.override { qemu = pkgs.qemu_kvm; }).overrideAttrs (o:
    o // rec {
      version = "0.7.5";
      src = pkgs.fetchurl {
        url =
          "https://github.com/Solo5/solo5/releases/download/v${version}/solo5-v${version}.tar.gz";
        sha256 = "sha256-viwrS9lnaU8sTGuzK/+L/PlMM/xRRtgVuK5pixVeDEw=";
      };
      doCheck = false;
    });

  ports_module = { ... }: {
    options = with types; {
      port = mkOption {
        type = int;
        description = "Bound port on the local network.";
      };

      intf = mkOption {
        type = str;
        description = "Name of the interface inside the unikernel.";
      };

      proto = mkOption {
        type = str;
        default = "tcp";
      };

      exposed_port = mkOption {
        type = nullOr int;
        default = null;
        description = "Forwared port open to the internet.";
      };
    };
  };

  blocks_module = {
    options = with types; {
      name = mkOption {
        type = str;
        description = "Name of the block device inside the unikernel.";
      };

      path = mkOption {
        type = str;
        description =
          "Path to the block device or file to attach. Make sure this is not a Nix path. A file is created at this location if it doesn't exist.";
      };

      sector_size = mkOption {
        type = int;
        default = 16384;
        description =
          "Sector size in byte. Must be a power of two greater than or equal to 512.";
      };

      initial_size = mkOption {
        type = nullOr int;
        default = null;
        description = ''
          Specify whether the file at 'path' should be created automatically
          and its initial size. If set to 'null' (the default), the file is not
          created automatically. No attempt is made to resize an existing
          file.
        '';
      };
    };
  };

  unikernel_module = {
    options = with types; {
      name = mkOption {
        type = nullOr str;
        default = null;
        defaultText = "<name of the attribute>";
        description = "Unikernel name. Used to name the systemd service.";
      };

      bin = mkOption {
        type = path;
        description = "Unikernel binary in HVT format.";
      };

      # TODO: Make ipv4 optionnal and starts a dhcp server
      ipv4 = mkOption {
        type = str;
        description = "Local network address for the unikernel.";
      };

      ports = mkOption {
        type = listOf (submodule [ ports_module ]);
        default = [ ];
        description =
          "Ports the unikernel listen to. Each port is mapped to a named network interface inside the unikernel.";
      };

      blocks = mkOption {
        type = listOf (submodule [ blocks_module ]);
        default = [ ];
        description = "Block devices mounted into the unikernel.";
      };

      mem = mkOption {
        type = int;
        default = 128;
      };

      argv = mkOption {
        type = listOf string;
        default = [ ];
      };
    };
  };

  # Shell commands run at ExecStart that create block files if they don't exist
  block_initial_create = ({ path, initial_size, ... }:
    let p = escapeShellArg path;
    in if initial_size == null then
      [ ]
    else
      [
        "if ! [[ -e ${p} ]]; then dd conv=excl bs=1M count=${
          toString initial_size
        } if=/dev/null of=${p}; fi"
      ]);

  services = listToAttrs (map_unikernels (i:
    { name, bin, ipv4, ports, blocks, mem, argv }@u:
    let
      ipv4_args = [
        "--ipv4=${ipv4}/${toString conf.ipv4.subnet}"
        "--ipv4-gateway=${conf.ipv4.gateway}"
      ];
      net_args = map ({ intf, ... }@p: "--net:${intf}=${tap i}") ports;
      block_args = concatMap ({ name, path, sector_size, ... }: [
        "--block:${name}=${toString path}"
        "--block-sector-size:${name}=${toString sector_size}"
      ]) blocks;
      # TODO: Block devices: --block:$name=$block_file_dev
      # (optional) --block-sector-size:$name=$size
      args = [ "--mem=${toString mem}" ] ++ net_args ++ block_args
        ++ [ "--" bin ] ++ ipv4_args ++ argv;

    in nameValuePair "solo5-${name}" {
      description = "Solo5 Unikernel ${name}";
      after = [ "sys-subsystem-net-devices-tap1.device" ];
      wantedBy = [ "multi-user.target" ];
      requires = [ "sys-subsystem-net-devices-tap1.device" ];
      # TODO: Assign CPU
      serviceConfig = {
        Type = "simple";
        User = "solo5";
        Group = "solo5";
        ExecStart = pkgs.writeShellScript "solo5-${name}-start" ''
          ${concatStringsSep "\n" (concatMap block_initial_create blocks)}
          ${solo5}/bin/solo5-hvt ${escapeShellArgs args}
        '';
        # ExecStartPre = "";
        ProtectSystem = "full";
        ProtectHome = true;
      };
    }));

  # Name of the tap device for a unikernel ID.
  tap = i: "tap${toString i}";

  # Apply [f] for every unikernels passing the implicit unikernel id.
  map_unikernels = f: imap1 f unikernels;

  port_forwards = concatLists (map_unikernels (_:
    { ipv4, ports, ... }:
    concatMap ({ port, intf, proto, exposed_port }:
      if exposed_port == null then
        [ ]
      else [{
        destination = "${ipv4}:${toString port}";
        sourcePort = exposed_port;
        inherit proto;
      }]) ports));

  tap_devices = listToAttrs (map_unikernels (i: _:
    let name = tap i;
    in nameValuePair name {
      netdevConfig = {
        Name = name;
        Kind = "tap";
      };
      tapConfig = {
        User = "solo5";
        Group = "solo5";
      };
    }));

  tap_networks = listToAttrs (map_unikernels (i: _:
    let name = tap i;
    in nameValuePair name {
      bridge = [ "service" ];
      matchConfig = { Name = name; };
    }));

  conf = config.solo5;

  unikernels = mapAttrsToList (attr_name:
    { name, ... }@u:
    u // {
      # Use the attribute name if no name is specified
      name = if name == null then attr_name else name;
    }) conf.unikernels;

in {
  options = with types; {
    solo5 = {
      enable = mkEnableOption "solo5";

      unikernels = mkOption {
        description = "Description of the unikernels to launch.";
        default = { };
        type = attrsOf (submodule [ unikernel_module ]);
      };

      ipv4.gateway = mkOption {
        type = str;
        default = "10.0.0.1";
        description = "Gateway for the unikernel to connect to the internet.";
      };

      ipv4.subnet = mkOption {
        type = int;
        default = 24;
        description = "Subnet mask for every unikernels.";
      };
    };
  };

  config = mkIf conf.enable {

    # TODO: Assert that each ip adress is unique
    # TODO: Assert that each ports of each unikernel is uniquely named

    systemd.services = services;

    # Network interface
    networking.nat = {
      enable = true;
      internalInterfaces = [ "service" ];
      externalInterface = "eth0";
      forwardPorts = port_forwards;
    };

    systemd.network.enable = true;

    systemd.network.networks = tap_networks // {
      service = {
        address = [ "${conf.ipv4.gateway}/${toString conf.ipv4.subnet}" ];
        matchConfig = { Name = "service"; };
      };
    };

    systemd.network.netdevs = tap_devices // {
      service = {
        netdevConfig = {
          Name = "service";
          Kind = "bridge";
        };
      };
    };

    # User and group for the services
    users.users.solo5.isNormalUser = true;
    users.groups.solo5.members = [ "solo5" ];

  };
}
