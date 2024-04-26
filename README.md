# Work in progress NixOS module for running solo5

Building the [example](example/configuration.nix):

```sh
nixos-rebuild build-vm -I nixos-config=example/configuration.nix
QEMU_NET_OPTS="hostfwd=tcp::2222-:22,hostfwd=tcp::8080-:8080" QEMU_OPTS="-display none -enable-kvm" ./result/bin/run-nixos-vm
```

The [unipi](https://github.com/robur-coop/unipi/) unikernel serves a website on
`http://localhost:8080` and the VM can be inspected with `ssh localhost:2222`.
