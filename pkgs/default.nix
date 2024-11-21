# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#example' or (legacy) 'nix-build -A example'

pkgs : rec {
   # FIXME: Want to do something like the below, though preferably in a one-liner, without having to 'inherit... ' afterwards...
   #        Revisit if my nix-fu progresses
   # xc16-versions = import ./xc16 { };
   # inherit (xc16-versions) xc16 xc16_1_61 xc16_2_10;
   xc16_2_10 = pkgs.callPackage ./xc16/2.10.nix { };
   xc16_1_61 = pkgs.callPackage ./xc16/1.61.nix { };
   # xc16 = xc16_2_10; #i.e. default to latest version we've bothered to package
   xc16 = xc16_1_61; #i.e. default to the version we're using for current production builds
   mplab-x-unwrapped_6_20 = pkgs.callPackage ./mplab-x-unwrapped/6.20.nix { };
   mplab-x-unwrapped_6_15 = pkgs.callPackage ./mplab-x-unwrapped/6.15.nix { };
   mplab-x-unwrapped = mplab-x-unwrapped_6_20;
   #FIXME: Rework this to pass an xc16 version as a parameter to mplab-x package rather than abusing the default..
   mplab-x = pkgs.callPackage ./mplab-x { inherit mplab-x-unwrapped xc16; };

   # mplab-xc16_1_61 = pkgs.callPackage ./mplab-x { inherit mplab-x-unwrapped xc16_1_61; };
   # mplab-xc16_2_10 = pkgs.callPackage ./mplab-x { inherit mplab-x-unwrapped xc16_2_10; };
   # mplab-xc16 = mplab-xc16_2_10;

   #If adding support for additional microchip compilers, could adopt a pattern like the following
   # mplab-xc8 = pkgs.callPackage ./mplab-x { inherit mplab-x-unwrapped xc8; };
   mplab-xc16 = pkgs.callPackage ./mplab-x { inherit mplab-x-unwrapped xc16; };
   # mplab-xc32 = pkgs.callPackage ./mplab-x { inherit mplab-x-unwrapped xc32; };
   # mplab-xc-dsc = pkgs.callPackage ./mplab-x { inherit mplab-x-unwrapped xc-dsc; };

   # Or better yet, pass the full list of required compilers in via inherit...
}
