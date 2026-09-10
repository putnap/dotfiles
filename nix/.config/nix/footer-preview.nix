# Build the production patch set in isolation.
{ check ? true }:
let
  flake = builtins.getFlake (toString ./.);
  pkgs = flake.inputs.nixpkgs.legacyPackages.aarch64-darwin;
in
import ./herdr-package.nix { inherit pkgs check; }
