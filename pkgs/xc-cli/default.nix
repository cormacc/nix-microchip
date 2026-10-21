{ callPackage
, gcc
, glibc
, makeWrapper
, mplab-x-unwrapped
, runCommand
, compilers ? [ ]
, packs ? [ ]
, ideVersion ? mplab-x-unwrapped.version
}:

let
  rootfsBuilder = callPackage ../mplab-x/rootfs.nix { };
  # sim30 and XC16 before 1.50 are 32-bit, and need libstdc++ and libgcc_s from /lib32.
  fhsMultiPkgs = [ glibc gcc.cc.lib ];
  fhsTargetPkgs = [ glibc ];
  environment = rootfsBuilder {
    name = "xc-cli";
    inherit compilers fhsMultiPkgs fhsTargetPkgs packs;
    packsVersion = ideVersion;
    runName = "xc-run";
    makeName = "xc-make";
  };
in
runCommand "xc-cli" {
  nativeBuildInputs = [ makeWrapper ];
  passthru = {
    inherit compilers fhsMultiPkgs fhsTargetPkgs ideVersion packs;
    rootfs = environment.rootfs;
  };
  meta.mainProgram = "xc-run";
} ''
  mkdir -p $out/bin
  ln -s ${environment.run}/bin/xc-run $out/bin/xc-run
  ln -s ${environment.make}/bin/xc-make $out/bin/xc-make
  ${environment.wrappers "$out"}
''
