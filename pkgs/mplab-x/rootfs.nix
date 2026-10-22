{ lib
, bubblewrap
, buildFHSEnv
, gnumake
, makeWrapper
, rsync
, runCommand
, writeShellApplication
}:

{ name
, fhsMultiPkgs
, fhsTargetPkgs
, compilers
, packs
, packsVersion
, extraEnvironmentIdentities ? [ ]
, extraRootfsCommands ? ""
, extraPackCommands ? ""
, runName
, makeName
, generatorRunName ? null
, generatorBindSource ? null
}:

let
  compilerDir = c: "/opt/microchip/${c.pname}/v${c.version}";
  ideDir = "/opt/microchip/mplabx/v${packsVersion}";

  # Adds each pack as a real directory with symlinks to its files: the pack library finds packs
  # with Files.walkFileTree, which does not follow directory symlinks (packslib.jar,
  # com.microchip.packslib.packutilities.FileLocator).
  linkPack = p: if p ? mplabPackPath then ''
    addPack ${p} ${p.mplabPackPath}
  '' else ''
    for d in ${p}/*/*/*; do
      addPack "$d" "''${d#${p}/}"
    done
  '';

  uniqueCompilers = lib.unique compilers;

  defaultCompilers = lib.attrValues (lib.foldl'
    (acc: c: if acc ? ${c.pname} then acc else acc // { ${c.pname} = c; })
    { }
    uniqueCompilers);

  fhsEnv = buildFHSEnv {
    name = "${name}-fhs-env";
    multiArch = true;
    multiPkgs = _: fhsMultiPkgs;
    targetPkgs = _: fhsTargetPkgs;
  };

  # The root filesystem of the environment. The run command merges it with the host at each call.
  rootfs = runCommand "${name}-rootfs" { nativeBuildInputs = [ rsync ]; } ''
    mkdir -p $out
    rsync -rlp --chmod=Du+w ${fhsEnv.fhsenv}/ $out/
    rm -rf $out/nix-support
    mkdir -p $out/opt/microchip
    ${extraRootfsCommands}
    packsDir=$out${ideDir}/packs
    mkdir -p "$packsDir"
    ${extraPackCommands}
    addPack() {
      if [ -e "$packsDir/$2" ]; then
        echo "Two packs at $2" >&2
        exit 1
      fi
      mkdir -p "$packsDir/$(dirname "$2")"
      cp -rs "$1" "$packsDir/$2"
    }
    ${lib.concatMapStrings linkPack packs}
    ${lib.concatMapStrings (c: ''
      mkdir -p $out/opt/microchip/${c.pname}
      ln -s ${c} $out${compilerDir c}
    '') uniqueCompilers}
  '';

  environmentIds = [ rootfs ] ++ extraEnvironmentIdentities;

  generatorBindList = if generatorBindSource == null then null else runCommand "${name}-generator-binds" { } ''
    for source in ${generatorBindSource}/*; do
      case "''${source##*/}" in packs|sys) continue ;; esac
      printf '%s\t%s/%s\n' "$source" "${ideDir}" "''${source##*/}" >> $out
    done
  '';

  mkRun = { name, generator }: writeShellApplication {
    inherit name;
    text = ''
      root=${rootfs}
      environmentId=${rootfs}
      environmentIdentityList=${lib.concatStringsSep ":" environmentIds}
      generatorBindList=${if generator then generatorBindList else ""}
      mplabxDir=${ideDir}
      bwrap=${lib.getExe bubblewrap}
    '' + builtins.readFile ./run.sh;
  };

  run = mkRun { name = runName; generator = false; };

  generatorRun = if generatorRunName == null then null else mkRun {
    name = generatorRunName;
    generator = true;
  };

  make = writeShellApplication {
    name = makeName;
    text = ''
      exec ${lib.getExe run} ${lib.getExe gnumake} "$@"
    '';
  };

  wrappers = out: lib.concatMapStrings (c: ''
    for f in ${c}/bin/*; do
      name=$(basename "$f")
      if [ -f "$f" ] && [ -x "$f" ] && [ "$name" != verifyinst ] && [ ! -e "${out}/bin/$name" ]; then
        makeWrapper ${lib.getExe run} "${out}/bin/$name" --add-flags "${compilerDir c}/bin/$name"
      fi
    done
  '') defaultCompilers;
in
{
  inherit fhsMultiPkgs fhsTargetPkgs generatorRun make rootfs run wrappers;
}
