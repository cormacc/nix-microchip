{
  description = "Microchip devtools overlay";

  # Flake layout (substantially) adapted from here:
  # https://github.com/Misterio77/nix-starter-configs/blob/main/standard/flake.nix

  # Microchip packages (minimally) adapted from original work by https://github.com/nyadiia in a nixpkgs pull request
  # https://github.com/NixOS/nixpkgs/pull/301317
  # She did the hard work, including some fhsEnv stuff for mplab-x this isn't taking advantage of yet...

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";
  };

  outputs = inputs@{ nixpkgs, self, ... }:
    let
      # Supported systems for your flake packages, shell, etc.
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      # systems = [
      #   "x86_64-linux"
      #   # I'm guessing that the currently supported MacOS architecture is aarch64, but have no hardware to test on....
      #   "aarch64-darwin"
      #   "x86_64-darwin"
      # ];
      # This is a function that generates an attribute by calling a function you
      # pass to it, with each system as an argument
      # forAllSystems = nixpkgs.lib.genAttrs systems;
      # pkgsForSystem = system:
      #   import nixpkgs {
      #     inherit system;
      #     config.allowUnfree = true;
      #   };
    in {
      # Your custom packages
      # Accessible through 'nix build', 'nix shell', etc
      # packages = forAllSystems (system: import ./pkgs { pkgs = pkgsForSystem system; });
      packages.${system} = import ./pkgs pkgs;

      # Your custom packages and modifications, exported as overlays
      # overlays.default = import ./overlays {inherit inputs;};
      overlays.default = self: super: import ./pkgs super.pkgs;
    };
}
