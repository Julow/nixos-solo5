{ pkgs, modulesPath, ... }:

{
  imports = [
    "${modulesPath}/profiles/headless.nix"
    "${modulesPath}/profiles/minimal.nix"
    ./solo5_hvt.nix
  ];

  solo5 = {
    enable = true;
    unikernels = {
      unipi = {
        bin = pkgs.fetchurl {
          url =
            "https://builds.robur.coop/job/unipi/build/6ee9ddf7-780c-4fc7-ae5f-f7c98db07ae0/f/bin/unipi.hvt";
          sha256 =
            "bbb1f3f0e44641eb5573b92feb384b20ba0225c34fbd9d6cdb2590202361fa8b";
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

  services.openssh = {
    enable = true;
    permitRootLogin = "yes";
  };

  users.users.root.initialPassword = "test";
  users.mutableUsers = false;

  system.stateVersion = "22.05";
}
