# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#example' or (legacy) 'nix-build -A example'

pkgs : rec {
   # FIXME: Want to do something like the below, though preferably in a one-liner, without having to 'inherit... ' afterwards...
   #        Revisit if my nix-fu progresses
   # xc16-versions = import ./xc16 { };
   # inherit (xc16-versions) xc16 xc16_1_61 xc16_2_10;
   xc16_2_10 = pkgs.callPackage ./xc16/2.10.nix { };
   xc16_1_61 = pkgs.callPackage ./xc16/1.61.nix { };
   #FIXME: Rework this to pass an xc16 version as a parameter to mplab-x package rather than abusing the default..
   # xc16 = xc16_2_10; #i.e. default to latest version we've bothered to package
   xc16 = xc16_1_61; #i.e. default to the version we're using for current production builds
   mplab-x-unwrapped = pkgs.callPackage ./mplab-x-unwrapped { };
   mplab-x = pkgs.callPackage ./mplab-x { };
}
