# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#example' or (legacy) 'nix-build -A example'

pkgs : rec {
   # A function, not a package: flake.nix exports it in legacyPackages and the overlay only.
   fetchMplabPack = pkgs.callPackage ./fetch-mplab-pack { };
   microchip-xclm-license = pkgs.callPackage ./xclm-license { };
   xc16_2_10 = pkgs.callPackage ./xc16/2.10.nix { inherit microchip-xclm-license; };
   xc16_1_61 = pkgs.callPackage ./xc16/1.61.nix { inherit microchip-xclm-license; };
   xc16_1_21 = pkgs.callPackage ./xc16/1.21.nix { inherit microchip-xclm-license; };
   # xc16 = xc16_2_10; #i.e. default to latest version we've bothered to package
   xc16 = xc16_1_61; #i.e. default to the version we're using for current production builds
   xc8_4_00 = pkgs.callPackage ./xc8/4.00.nix { inherit microchip-xclm-license; };
   xc8_3_10 = pkgs.callPackage ./xc8/3.10.nix { inherit microchip-xclm-license; };
   xc8_2_50 = pkgs.callPackage ./xc8/2.50.nix { inherit microchip-xclm-license; };
   xc8 = xc8_4_00; #i.e. default to latest version we've bothered to package
   xc32_6_00 = pkgs.callPackage ./xc32/6.00.nix { inherit microchip-xclm-license; };
   xc32_5_19 = pkgs.callPackage ./xc32/5.19.nix { inherit microchip-xclm-license; };
   xc32_5_10 = pkgs.callPackage ./xc32/5.10.nix { inherit microchip-xclm-license; };
   xc32 = xc32_6_00; #i.e. default to latest version we've bothered to package
   xc-dsc_4_00 = pkgs.callPackage ./xc-dsc/4.00.nix { inherit microchip-xclm-license; };
   xc-dsc_3_31 = pkgs.callPackage ./xc-dsc/3.31.nix { inherit microchip-xclm-license; };
   xc-dsc = xc-dsc_4_00; #i.e. default to latest version we've bothered to package
   mplab-x-unwrapped_6_35 = pkgs.callPackage ./mplab-x-unwrapped/6.35.nix { };
   mplab-x-unwrapped = mplab-x-unwrapped_6_35;
   # Projects choose compilers with e.g. mplab-x.override { compilers = [ xc16_1_61 xc16_2_10 ]; },
   # and packs with e.g. mplab-x.override { packs = [ (fetchMplabPack { ... }) ]; }.
   # The single-compiler arguments stay so that existing overrides such as { xc16 = ...; } still work.
   mplab-x = pkgs.callPackage ./mplab-x { inherit mplab-x-unwrapped xc16; };
   mplab-xc8 = pkgs.callPackage ./mplab-x { inherit mplab-x-unwrapped xc8; };
   mplab-xc16 = pkgs.callPackage ./mplab-x { inherit mplab-x-unwrapped xc16; };
   mplab-xc32 = pkgs.callPackage ./mplab-x { inherit mplab-x-unwrapped xc32; };
   mplab-xc-dsc = pkgs.callPackage ./mplab-x { inherit mplab-x-unwrapped xc-dsc; };
}
