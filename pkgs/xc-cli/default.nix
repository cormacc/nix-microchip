{ callPackage
, gcc
, glibc
, lib
, makeWrapper
, mplab-x-unwrapped
, runCommand
, compilers ? [ ]
, packs ? null
, ideVersion ? mplab-x-unwrapped.version
, withMplabProjects ? false
}:

let
  rootfsBuilder = callPackage ../mplab-x/rootfs.nix { };
  javaWrapper = callPackage ../mplab-x/java-wrapper.nix { };
  ideDir = "/opt/microchip/mplabx/v${ideVersion}";
  subset = mplab-x-unwrapped.commandLineSubset;
  mcuOptionByCompiler = {
    xc8 = "8bitmcu";
    xc16 = "16bitmcu";
    xc-dsc = "16bitmcu";
    xc32 = "32bitmcu";
  };
  selectedMcuOptions = map (compiler:
    mcuOptionByCompiler.${compiler.pname} or (throw "Unknown compiler pname: ${compiler.pname}")
  ) compilers;
  resolvedPacks = if packs == null then
    lib.optional (compilers != [ ]) (mplab-x-unwrapped.devicePacks {
      mcuOptions = selectedMcuOptions ++ [ "othermcu" ];
    })
  else packs;
  # sim30 and XC16 before 1.50 are 32-bit, and need libstdc++ and libgcc_s from /lib32.
  fhsMultiPkgs = [ glibc gcc.cc.lib ];
  fhsTargetPkgs = [ glibc ];
  environment = rootfsBuilder {
    name = "xc-cli";
    inherit compilers fhsMultiPkgs fhsTargetPkgs;
    packs = resolvedPacks;
    packsVersion = ideVersion;
    runName = "xc-run";
    makeName = "xc-make";
    generatorRunName = if withMplabProjects then "mplab-gen-run" else null;
    generatorBindSource = if withMplabProjects then subset else null;
    extraRootfsCommands = lib.optionalString withMplabProjects ''
      mkdir -p $out${ideDir}
      for f in ${subset}/*; do
        [ "''${f##*/}" = sys ] || ln -s "$f" $out${ideDir}/
      done
      ${javaWrapper { sys = "${subset}/sys"; inherit ideDir; }}
    '';
  };
  generator = (callPackage ../mplab-x/generator.nix { }) {
    inherit environment compilers ideDir;
  };
in
runCommand "xc-cli" {
  nativeBuildInputs = [ makeWrapper ];
  passthru = {
    inherit compilers fhsMultiPkgs fhsTargetPkgs ideVersion withMplabProjects;
    packs = resolvedPacks;
    rootfs = environment.rootfs;
  };
  meta.mainProgram = "xc-run";
} ''
  mkdir -p $out/bin
  ln -s ${environment.run}/bin/xc-run $out/bin/xc-run
  ln -s ${environment.make}/bin/xc-make $out/bin/xc-make
  ${lib.optionalString withMplabProjects ''
    ln -s ${lib.getExe generator} $out/bin/mplab-gen
  ''}
  ${environment.wrappers "$out"}
''
