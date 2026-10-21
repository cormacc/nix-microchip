{ lib
, alsa-lib
, at-spi2-atk
, bubblewrap
, buildFHSEnv
, cairo
, coreutils
, corefonts
, cups
, dbus
, expat
, glib
, glibc
, gnumake
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
, rsync
, runCommand
, systemdLibs
, writeShellApplication
  # Compilers to install at /opt/microchip/<pname>/v<version>. Two or more versions of one
  # compiler can coexist. The first compiler of each pname is the CLI default: its executables
  # get wrappers in bin/. When null, the xc8/xc16/xc32/xc-dsc arguments supply the list;
  # otherwise the package ignores them.
, compilers ? null
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
  compilerDir = c: "/opt/microchip/${c.pname}/v${c.version}";
  defaultCompilers = lib.attrValues (lib.foldl'
    (acc: c: if acc ? ${c.pname} then acc else acc // { ${c.pname} = c; })
    { }
    allCompilers);

  fhsEnv = buildFHSEnv {
    name = "mplab-x-fhs-env";
    # 32-bit libraries for compilers before XC16 1.50 and for sim30, which is 32-bit in every XC16.
    multiArch = true;
    multiPkgs = pkgs: [ pkgs.glibc ];
    targetPkgs = pkgs: [
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
  };

  # The root filesystem of the environment. mplab-x-run merges it with the host at each call.
  rootfs = runCommand "mplab-x-rootfs" { nativeBuildInputs = [ rsync ]; } ''
    mkdir -p $out
    rsync -rlp --chmod=Du+w ${fhsEnv.fhsenv}/ $out/
    rm -rf $out/nix-support
    rsync -rlp --chmod=Du+w ${mplab-x-unwrapped}/etc/ $out/etc/
    # FIXME: This line has started causing issues, but is likely required for programmer support
    # mkdir -p $out/lib/udev
    # rsync -rlp ${mplab-x-unwrapped}/lib/udev/ $out/lib/udev/
    mkdir -p $out/opt/microchip
    for f in ${mplab-x-unwrapped}/opt/microchip/*; do
      ln -s "$f" $out/opt/microchip/
    done
    ${lib.concatMapStrings (c: ''
      mkdir -p $out/opt/microchip/${c.pname}
      ln -s ${c} $out${compilerDir c}
    '') allCompilers}
  '';

  run = writeShellApplication {
    name = "mplab-x-run";
    text = ''
      root=${rootfs}
      bwrap=${lib.getExe bubblewrap}
    '' + builtins.readFile ./run.sh;
  };

  make = writeShellApplication {
    name = "mplab-make";
    text = ''
      exec ${lib.getExe run} ${lib.getExe gnumake} "$@"
    '';
  };

  ide = writeShellApplication {
    name = "mplab_ide";
    text = ''
      echo "mplab-x-unwrapped: ${mplab-x-unwrapped}" >&2
      # Only the IDE gets /lib on LD_LIBRARY_PATH. The compilers do not need it, and it makes
      # host programs (e.g. a script run with mplab-x-run) load the FHS glibc instead of their own.
      exec ${lib.getExe run} ${coreutils}/bin/env \
        LD_LIBRARY_PATH="/lib''${LD_LIBRARY_PATH:+:}''${LD_LIBRARY_PATH:-}" \
        ${mplab-x-unwrapped}/opt/microchip/mplabx/v${mplab-x-unwrapped.version}/mplab_platform/bin/mplab_ide "$@"
    '';
  };

in
runCommand "mplab-x" {
  nativeBuildInputs = [ makeWrapper ];
  passthru = { compilers = allCompilers; };
  meta = mplab-x-unwrapped.meta // { mainProgram = "mplab_ide"; };
} ''
  mkdir -p $out/bin
  ln -s ${lib.getExe ide} $out/bin/mplab_ide
  ln -s ${lib.getExe run} $out/bin/mplab-x-run
  ln -s ${lib.getExe make} $out/bin/mplab-make

  # CLI wrappers for the default compiler of each pname. verifyinst is the installer's
  # manifest check. If two pnames ship the same executable (e.g. xclm), the first one wins.
  ${lib.concatMapStrings (c: ''
    for f in ${c}/bin/*; do
      name=$(basename "$f")
      if [ -f "$f" ] && [ -x "$f" ] && [ "$name" != verifyinst ] && [ ! -e "$out/bin/$name" ]; then
        makeWrapper ${lib.getExe run} "$out/bin/$name" --add-flags "${compilerDir c}/bin/$name"
      fi
    done
  '') defaultCompilers}
''
