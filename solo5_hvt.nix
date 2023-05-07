{ pkgs, lib, config, ... }:

with lib;

let

  # solo5 = pkgs.solo5.override { qemu = pkgs.qemu.override { guestAgentSupport = false; }; };
  solo5 = "/nix/store/cv8zazrl26i903abn3j7q6szyjj6xix1-solo5-0.7.4";

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
        description =
          "Ports the unikernel listen to. Each port is mapped to a named network interface inside the unikernel.";
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

  mk_service = { name, bin, ipv4, ports, mem, argv }@u:
    let
      ipv4_args = [
        "--ipv4=${ipv4}/${toString conf.ipv4.subnet}"
        "--ipv4-gateway=${conf.ipv4.gateway}"
      ];
      nets = map ({ intf, ... }@p: [ "--net:${intf}=tap1" ]) ports;
      # TODO: Block devices: --block:$name=$block_file_dev
      # (optional) --block-sector-size:$name=$size
      blocks = [ ];
      args = [ "--mem=${toString mem}" ] ++ nets ++ blocks ++ [ "--" bin ]
        ++ ipv4_args ++ argv;
    in nameValuePair "solo5-${name}" {
      description = "Solo5 Unikernel ${name}";
      after = [ "syslog.target" "sys-subsystem-net-devices-tap1.device" ];
      wantedBy = [ "multi-user.target" ];
      requires = [ "sys-subsystem-net-devices-tap1.device" ];
      # TODO: Assign CPU
      serviceConfig = {
        Type = "simple";
        User = "solo5";
        Group = "solo5";
        ExecStart = ''
          ${solo5}/bin/solo5-hvt ${escapeShellArgs args}
        '';
        # ExecStartPre = "";
        ProtectSystem = "full";
        ProtectHome = true;
      };
    };

  mk_forward_ports = { ipv4, ports, ... }:
    concatMap ({ port, intf, proto, exposed_port }:
      if exposed_port == null then
        [ ]
      else [{
        destination = "${ipv4}:${toString port}";
        sourcePort = exposed_port;
        inherit proto;
      }]) ports;

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

    systemd.services = listToAttrs (map mk_service unikernels);

    # Network interface
    networking.nat = {
      enable = true;
      internalInterfaces = [ "service" ];
      externalInterface = "eth0";
      forwardPorts = concatMap mk_forward_ports unikernels;
    };

    systemd.network.enable = true;

    systemd.network.networks.service = {
      address = [ "${conf.ipv4.gateway}/${toString conf.ipv4.subnet}" ];
      matchConfig = { Name = "service"; };
    };

    systemd.network.networks.tap1 = {
      bridge = [ "service" ];
      matchConfig = { Name = "tap1"; };
    };

    systemd.network.netdevs = {
      service = {
        netdevConfig = {
          Name = "service";
          Kind = "bridge";
        };
      };

      tap1 = {
        netdevConfig = {
          Name = "tap1";
          Kind = "tap";
        };
        tapConfig = {
          User = "solo5";
          Group = "solo5";
        };
      };
    };

    # User and group for the services
    users.users.solo5.isNormalUser = true;
    users.groups.solo5.members = [ "solo5" ];

  };
}
