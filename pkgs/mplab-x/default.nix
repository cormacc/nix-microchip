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
, nspr
, nss
, pango
, runCommand
, runtimeShell
, systemdLibs
, writeShellApplication
  # Compilers to install at /opt/microchip/<pname>/v<version>. Two or more versions of one
  # compiler can coexist. The first compiler of each pname is the CLI default: its executables
  # get wrappers in bin/. When null, the xc8/xc16/xc32/xc-dsc arguments supply the list;
  # otherwise the package ignores them.
, compilers ? null
  # Device and tool packs for the packs folder, /opt/microchip/mplabx/v<version>/packs. Each
  # element is a pack from fetchMplabPack, or a folder of packs at <vendor>/<name>/<version>
  # (e.g. mplab-x-unwrapped.packs, all the packs that the installer bundles). When null, the
  # bundled packs are used.
, packs ? null
, xc8 ? null
, xc16 ? null
, xc32 ? null
, xc-dsc ? null
}:

let
  allCompilers = lib.unique (
    if compilers != null then compilers
    else lib.filter (c: c != null) [ xc8 xc16 xc32 xc-dsc ]
  );
  allPacks = if packs != null then packs else [ mplab-x-unwrapped.packs ];
  ideDir = "/opt/microchip/mplabx/v${mplab-x-unwrapped.version}";
  rootfsBuilder = callPackage ./rootfs.nix { };
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
    inherit fhsMultiPkgs fhsTargetPkgs;
    compilers = allCompilers;
    packs = allPacks;
    packsVersion = mplab-x-unwrapped.version;
    runName = "mplab-x-run";
    makeName = "mplab-make";
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
      # The IDE and the CLI scripts (e.g. prjMakefilesGenerator.sh) run ${ideDir}/sys/java. The
      # pack library derives its packs folder from its jar's real path, which is in the store,
      # so a wrapper sets the folder with the packslib.packsfolder property
      # (com.microchip.packslib.parsers.ConfigParser.getSystemRepoLocation).
      cp -rs ${mplab-x-unwrapped}${ideDir}/sys $out${ideDir}/sys
      for java in $out${ideDir}/sys/java/*/bin/java; do
        real=$(readlink "$java")
        chmod u+w "$(dirname "$java")"
        rm "$java"
        printf '#!%s\nexec %s -Dpackslib.packsfolder=%s "$@"\n' \
          ${runtimeShell} "$real" ${ideDir}/packs > "$java"
        chmod +x "$java"
      done
    '';
    extraPackCommands = ''
      ln -s ${mplab-x-unwrapped}/share/mplab-x/packs/index.idx "$packsDir/"
    '';
  };

  ide = writeShellApplication {
    name = "mplab_ide";
    text = ''
      echo "mplab-x-unwrapped: ${mplab-x-unwrapped}" >&2
      # The IDE registers each PATH directory that contains a compiler as a toolchain. The CLI
      # wrappers run the default compiler, so their directory (and that of an earlier mplab-x
      # build) would add one more toolchain with that version and a store path.
      path=
      IFS=: read -ra dirs <<< "''${PATH:-}"
      for d in "''${dirs[@]}"; do
        [ -x "$d/mplab-x-run" ] || path=''${path:+$path:}$d
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
runCommand "mplab-x" {
  nativeBuildInputs = [ makeWrapper ];
  passthru = { compilers = allCompilers; packs = allPacks; };
  meta = mplab-x-unwrapped.meta // { mainProgram = "mplab_ide"; };
} ''
  mkdir -p $out/bin
  ln -s ${lib.getExe ide} $out/bin/mplab_ide
  ln -s ${lib.getExe environment.run} $out/bin/mplab-x-run
  ln -s ${lib.getExe environment.make} $out/bin/mplab-make

  # CLI wrappers for the default compiler of each pname. verifyinst is the installer's
  # manifest check. If two pnames ship the same executable (e.g. xclm), the first one wins.
  ${environment.wrappers "$out"}
''
