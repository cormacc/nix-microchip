{ lib
, alsa-lib
, at-spi2-atk
, buildFHSEnv
, cairo
, coreutils
, corefonts
, cups
, dbus
, execline
, fuse-overlayfs
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

  # Runs its arguments as a command inside the MPLAB-X root filesystem. The compilers must run
  # unmodified in this environment: an autoPatchelf'd compiler detects the change and drops to
  # Free mode, and a default buildFHSEnv sandbox makes xclm fail ("UID 0 not supported").
  stage2 = writeShellApplication {
    name = "mplab-x-stage2";
    runtimeInputs = [ execline fuse-overlayfs rsync ];
    text = ''
      # Make the rt directory, isolated from the host filesystem. The tmpfs is private to this
      # mount namespace, so concurrent invocations (e.g. make -j) do not interfere.
      # CI runners and other non-login shells can have no XDG_RUNTIME_DIR.
      rt="''${XDG_RUNTIME_DIR:-/tmp}/mplab-x"
      mkdir -p "$rt"
      mount -t tmpfs mplab-x-wrapper "$rt"

      # Make and populate the overlay subdirectory.
      mkdir -p "$rt/overlay/opt/microchip"
      rsync -rlp ${fhsEnv.fhsenv}/             "$rt/overlay/"
      rsync -rlp ${mplab-x-unwrapped}/etc/     "$rt/overlay/etc/"
      # FIXME: This line has started causing issues, but is likely required for programmer support
      # mkdir -p "$rt/overlay/lib/udev"
      # rsync -rlp ${mplab-x-unwrapped}/lib/udev/ "$rt/overlay/lib/udev/"
      ln -s "$HOME"                            "$rt/overlay/root"
      for f in ${mplab-x-unwrapped}/opt/microchip/*; do
        ln -s "$f" "$rt/overlay/opt/microchip/"
      done


      ${lib.concatMapStrings (c: ''
        mkdir -p "$rt/overlay/opt/microchip/${c.pname}"
        ln -s ${c} "$rt/overlay${compilerDir c}"
      '') allCompilers}

      # Make and mount (with FUSE) the newroot subdirectory.
      mkdir "$rt/newroot"
      fuse-overlayfs -o lowerdir="$rt/overlay":/ "$rt/newroot"
      trap 'fusermount -zu "$rt/newroot"' EXIT

      # Bind mount some subtrees we want to make mutable.
      mount --rbind /dev  "$rt/newroot/dev"
      mount --rbind /home "$rt/newroot/home"
      # fuse-overlayfs gives files inode numbers above 2^32. 32-bit programs (XC16 before 1.50)
      # then fail stat() with EOVERFLOW: e.g. the driver does not find cc1. The bind mount also
      # keeps the compilers' file access out of FUSE.
      mount --rbind /nix  "$rt/newroot/nix"
      mount --rbind /proc "$rt/newroot/proc"
      mount --rbind /run  "$rt/newroot/run"
      # N.B. /sys must be a real sysfs mount: fuse-overlayfs cannot traverse it as
      # a lower layer, and without it libusb enumerates no USB devices, so MPLAB
      # never sees programmers/debuggers (PICkit, ICD, ...).
      mount --rbind /sys  "$rt/newroot/sys"
      mount --rbind /tmp  "$rt/newroot/tmp"
      mount --rbind /var  "$rt/newroot/var"
      # Without this bind, the overlay makes a working directory outside the trees above
      # (e.g. a CI checkout under /builds) read-only.
      case "$PWD" in
        /|/dev|/dev/*|/home|/home/*|/proc|/proc/*|/run|/run/*|/sys|/sys/*|/tmp|/tmp/*|/var|/var/*) ;;
        *) mount --rbind "$PWD" "$rt/newroot$PWD" ;;
      esac

      # Chroot into the new rootfs and run the command.
      export MPLAB_X_ENV=1
      # The 32-bit loader does not search /lib32 by itself (sim30 needs libstdc++ from there).
      # 64-bit programs skip the 32-bit libraries in it.
      export LD_LIBRARY_PATH="/lib32''${LD_LIBRARY_PATH:+:}''${LD_LIBRARY_PATH:-}"
      chroot "$rt/newroot" execline-cd "$PWD" "$@"
    '';

    inherit (mplab-x-unwrapped) meta;
  };

  run = writeShellApplication {
    name = "mplab-x-run";
    text = ''
      if [ "$#" -eq 0 ]; then
        echo "usage: mplab-x-run <command> [args...]" >&2
        exit 2
      fi
      # The kernel refuses a new user namespace inside a chroot, so a nested call (e.g. a
      # Makefile run with mplab-x-run that calls a CLI wrapper) runs the command directly.
      if [ -n "''${MPLAB_X_ENV:-}" ]; then
        exec "$@"
      fi
      exec unshare -mUr -- ${lib.getExe stage2} "$@"
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
