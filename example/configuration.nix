{ pkgs, modulesPath, ... }:

let
  solo5_hvt = ../.;
  # builtins.fetchGit {
  #   url = "https://github.com/Julow/nixos-solo5";
  #   rev = "fa5c9503fb32a136a7d72743db166edfd15bfaef";
  # };

in {
  imports = [
    "${modulesPath}/profiles/headless.nix"
    "${modulesPath}/profiles/minimal.nix"
    "${solo5_hvt}/solo5_hvt.nix"
  ];

  solo5 = {
    enable = true;
    unikernels = {
      # Creates a systemd user service named 'solo5-unipi'.
      unipi = {
        bin = pkgs.fetchurl {
          url =
            "https://builds.robur.coop/job/unipi/build/d80b2ffe-dd64-4fcb-bec2-4004c7ac6c8d/f/bin/unipi.hvt";
          sha256 =
            "d58d3bd992b2cc1bb7b1a862937e7bae414103c0eaf6374a1c30572b57ec336e";
        };
        argv = [ "--remote=https://github.com/mirage/ocaml-dns.git#gh-pages" ];
        ipv4 = "10.0.0.2";
        ports = [{
          port = 80;
          intf = "service";
          exposed_port = 8080;
        }];
      };
    };
  };

  # Unsafe setup for example purposes
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };
  networking.useNetworkd = true;

  users.users.root.initialPassword = "test";
  users.mutableUsers = false;

  # Allow KVM
  boot.kernelModules = [ "kvm-intel" ];

  system.stateVersion = "22.05";
}
