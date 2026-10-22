{ callPackage
, gcc
, glibc
, lib
, makeWrapper
, mplab-x-unwrapped
, runCommand
, runtimeShell
, compilers ? [ ]
, packs ? [ ]
, ideVersion ? mplab-x-unwrapped.version
, withMplabProjects ? false
}:

let
  rootfsBuilder = callPackage ../mplab-x/rootfs.nix { };
  ideDir = "/opt/microchip/mplabx/v${ideVersion}";
  subset = mplab-x-unwrapped.commandLineSubset;
  # sim30 and XC16 before 1.50 are 32-bit, and need libstdc++ and libgcc_s from /lib32.
  fhsMultiPkgs = [ glibc gcc.cc.lib ];
  fhsTargetPkgs = [ glibc ];
  environment = rootfsBuilder {
    name = "xc-cli";
    inherit compilers fhsMultiPkgs fhsTargetPkgs packs;
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
      cp -rs ${subset}/sys $out${ideDir}/sys
      for java in $out${ideDir}/sys/java/*/bin/java; do
        real=$(readlink "$java")
        javaHome=''${java#$out${ideDir}/sys/java/}
        javaHome=${ideDir}/sys/java/''${javaHome%/bin/java}
        chmod u+w "$(dirname "$java")"
        rm "$java"
        printf '#!%s\nexec %s -Djava.home=%s -Dpackslib.packsfolder=%s "$@"\n' \
          ${runtimeShell} "$real" "$javaHome" ${ideDir}/packs > "$java"
        chmod +x "$java"
      done
    '';
  };
  generator = (callPackage ../mplab-x/generator.nix { }) {
    inherit environment compilers ideDir;
  };
in
runCommand "xc-cli" {
  nativeBuildInputs = [ makeWrapper ];
  passthru = {
    inherit compilers fhsMultiPkgs fhsTargetPkgs ideVersion packs withMplabProjects;
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
