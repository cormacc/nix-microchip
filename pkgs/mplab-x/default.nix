{ lib
, alsa-lib
, at-spi2-atk
, cairo
, callPackage
, coreutils
, corefonts
, cups
, dbus
, expat
, glib
, glibc
, gtk2
, gtk3
, libdrm
, libx11
, libxcb
, libxcomposite
, libxdamage
, libxext
, libxfixes
, libxi
, libxkbcommon
, libxrandr
, libxrender
, libxtst
, libusb1
, libxslt
, makeWrapper
, mesa
, mplab-x-unwrapped
, xc-cli ? (callPackage ../xc-cli { inherit mplab-x-unwrapped; })
, nspr
, nss
, pango
, runCommand
, systemdLibs
, writeShellApplication
  # IDE-only packs for the packs folder, /opt/microchip/mplabx/v<version>/packs. Each element
  # is a pack from fetchMplabPack, or a folder of packs at <vendor>/<name>/<version>.
, packs ? [ ]
}:

let
  allPacks = xc-cli.packs ++ packs;
  ideDir = "/opt/microchip/mplabx/v${mplab-x-unwrapped.version}";
  rootfsBuilder = callPackage ./rootfs.nix { };
  javaWrapper = callPackage ./java-wrapper.nix { };
  fhsMultiPkgs = [ glibc ];
  fhsTargetPkgs = [
    alsa-lib
    at-spi2-atk
    cairo
    corefonts
    cups
    dbus
    expat
    glib
    glibc
    gtk2
    gtk3
    libdrm
    libxkbcommon
    libxslt
    libusb1
    mesa
    nspr
    nss
    pango
    systemdLibs
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxi
    libxrandr
    libxrender
    libxtst
  ];
  environment = rootfsBuilder {
    name = "mplab-x";
    # Keep the GUI list first so buildFHSEnv resolves collisions as the pre-xc-cli root did.
    fhsMultiPkgs = fhsMultiPkgs ++ xc-cli.fhsMultiPkgs;
    fhsTargetPkgs = fhsTargetPkgs ++ xc-cli.fhsTargetPkgs;
    compilers = xc-cli.compilers;
    packs = allPacks;
    packsVersion = mplab-x-unwrapped.version;
    extraEnvironmentIdentities = [ xc-cli.rootfs ];
    runName = "mplab-x-run";
    makeName = "mplab-make";
    generatorRunName = "mplab-gen-run";
    generatorBindSource = "${mplab-x-unwrapped}${ideDir}";
    extraRootfsCommands = ''
      rsync -rlp --chmod=Du+w ${mplab-x-unwrapped}/etc/ $out/etc/
      # FIXME: This line has started causing issues, but is likely required for programmer support
      # mkdir -p $out/lib/udev
      # rsync -rlp ${mplab-x-unwrapped}/lib/udev/ $out/lib/udev/
      for f in ${mplab-x-unwrapped}/opt/microchip/*; do
        [ "''${f##*/}" = mplabx ] || ln -s "$f" $out/opt/microchip/
      done
      # A real directory, so that the packs folder can differ from the IDE installation. The
      # installation's packs symlink resolves to this packs folder.
      mkdir -p $out${ideDir}
      for f in ${mplab-x-unwrapped}${ideDir}/*; do
        case ''${f##*/} in packs|sys) ;; *) ln -s "$f" $out${ideDir}/ ;; esac
      done
      ${javaWrapper { sys = "${mplab-x-unwrapped}${ideDir}/sys"; inherit ideDir; }}
    '';
    extraPackCommands = ''
      ln -s ${mplab-x-unwrapped}/share/mplab-x/packs/index.idx "$packsDir/"
    '';
  };

  generator = (callPackage ./generator.nix { }) {
    inherit environment ideDir;
    compilers = xc-cli.compilers;
  };

  ide = writeShellApplication {
    name = "mplab_ide";
    text = ''
      echo "mplab-x-unwrapped: ${mplab-x-unwrapped}" >&2
      # The IDE registers each PATH directory that contains a compiler wrapper as a toolchain.
      # Exclude earlier mplab-x and xc-cli package directories to avoid duplicate registrations.
      path=
      IFS=: read -ra dirs <<< "''${PATH:-}"
      for d in "''${dirs[@]}"; do
        [ -x "$d/mplab-x-run" ] || [ -x "$d/xc-run" ] || path=''${path:+$path:}$d
      done
      export PATH=$path
      # Only the IDE gets /lib on LD_LIBRARY_PATH. The compilers do not need it, and it makes
      # host programs (e.g. a script run with mplab-x-run) load the FHS glibc instead of their own.
      exec ${lib.getExe environment.run} ${coreutils}/bin/env \
        LD_LIBRARY_PATH="/lib''${LD_LIBRARY_PATH:+:}''${LD_LIBRARY_PATH:-}" \
        ${mplab-x-unwrapped}/opt/microchip/mplabx/v${mplab-x-unwrapped.version}/mplab_platform/bin/mplab_ide "$@"
    '';
  };

in
assert xc-cli.ideVersion == mplab-x-unwrapped.version || throw "mplab-x: xc-cli.ideVersion (${xc-cli.ideVersion}) must match mplab-x-unwrapped.version (${mplab-x-unwrapped.version})";
runCommand "mplab-x" {
  nativeBuildInputs = [ makeWrapper ];
  passthru = { inherit xc-cli; packs = allPacks; };
  meta = mplab-x-unwrapped.meta // { mainProgram = "mplab_ide"; };
} ''
  mkdir -p $out/bin
  ln -s ${lib.getExe ide} $out/bin/mplab_ide
  ln -s ${lib.getExe environment.run} $out/bin/mplab-x-run
  ln -s ${lib.getExe environment.make} $out/bin/mplab-make
  ln -s ${lib.getExe generator} $out/bin/mplab-gen

''
