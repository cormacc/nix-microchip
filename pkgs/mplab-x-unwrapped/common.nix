{ version, hash }:

{ lib, stdenvNoCC, bubblewrap, buildFHSEnv, fakeroot, fetchurl, glibc, rsync }:

let
  fhsEnv = buildFHSEnv {
    name = "mplab-x-build-fhs-env";
    targetPkgs = pkgs: [ fakeroot glibc ];
  };

  unwrapped = stdenvNoCC.mkDerivation rec {
    pname = "mplab-x-unwrapped";
    inherit version;

    src = fetchurl {
      url =
        "https://ww1.microchip.com/downloads/aemDocuments/documents/DEV/ProductDocuments/SoftwareTools/MPLABX-v${version}-linux-installer.tar";
      inherit hash;
      # The Microchip server requires this Referer to allow the download.
      curlOptsList = [
        "--referer"
        "https://www.microchip.com/en-us/tools-resources/develop/mplab-x-ide"
      ];
    };

    # The bundled packs live in a separate derivation exposed through passthru because Nix builds
    # every output. Disable the MCU groups here; the installer leaves tool packs, which are removed
    # before copying the IDE output.
    outputs = [ "out" ];
    installerFlags = "--8bitmcu 0 --16bitmcu 0 --32bitmcu 0 --othermcu 0";

    nativeBuildInputs = [ bubblewrap rsync ];

    unpackPhase = ''
      runHook preUnpack

      tar xf $src MPLABX-v${version}-linux-installer.sh
      sh MPLABX-v${version}-linux-installer.sh \
        --tar xf ./MPLABX-v${version}-linux-installer.run

      runHook postUnpack
    '';
    buildPhase = ''
      runHook preBuild

      rsync -a ${fhsEnv.fhsenv}/ chroot/
      find chroot -type d -exec chmod 755 {} \;
      echo "root:x:0:0:root:/root:/bin/bash" > chroot/etc/passwd
      echo "root:x:0:root" > chroot/etc/group
      mkdir -p chroot/tmp/home

      bwrap \
        --bind chroot / \
        --ro-bind /nix /nix \
        --ro-bind MPLABX-v${version}-linux-installer.run /installer \
        --setenv HOME /tmp/home \
        -- /bin/fakeroot /installer --mode unattended $installerFlags

      # rm -r chroot/opt/microchip/mplabx/v${version}/sys

      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall

      mkdir -p $out/etc $out/usr/share $out/lib/udev/
      cp -r chroot/etc/.mplab_ide $out/etc/
      cp -r chroot/etc/udev $out/etc/
      cp -r chroot/etc/udev/rules.d $out/lib/udev/
      cp -r chroot/usr/share/applications chroot/usr/share/icons $out/usr/share/
      # cp -r chroot/usr/lib/udev

      # In the mplab-x environment, this symlink resolves to the packs folder that the root
      # filesystem assembles from the selected packs. The pack index (index.idx) is not a pack,
      # so it stays in this output. Remove residual tool packs before copying opt to avoid storing
      # them in the IDE derivation.
      packsDir=chroot/opt/microchip/mplabx/v${version}/packs
      mkdir -p $out/share/mplab-x/packs
      mv $packsDir/index.idx $out/share/mplab-x/packs/
      rm -r $packsDir
      cp -r chroot/opt $out/
      ln -s /opt/microchip/mplabx/v${version}/packs $out/opt/microchip/mplabx/v${version}/packs

      runHook postInstall
    '';
    dontFixup = true;

    passthru = {
      inherit fhsEnv;
      packs = bundledPacks;
      inherit devicePacks toolPacks installerHelp;
    };

    meta = with lib; {
      homepage =
        "https://www.microchip.com/en-us/tools-resources/develop/mplab-x-ide";
      description =
        "An expandable, highly configurable software program that incorporates powerful tools to help you discover, configure, develop, debug and qualify embedded designs for most of Microchip's microcontrollers and digital signal controllers.";
      license = licenses.unfree;
      maintainers = with maintainers; [ remexre nyadiia ];
      platforms = [ "x86_64-linux" ];
    };
  };

  packOptions = [ "8bitmcu" "16bitmcu" "32bitmcu" "othermcu" ];

  filteredPacks = { pname, installerFlags, toolPacksOnly }:
    unwrapped.overrideAttrs (_: {
      inherit pname installerFlags;
      installPhase = ''
        runHook preInstall

        packsDir=chroot/opt/microchip/mplabx/v${version}/packs
        index="$TMPDIR/index.idx"
        if ! grep -F '<pdsc ' "$packsDir/index.idx" > "$index"; then
          echo "No pack entries in $packsDir/index.idx" >&2
          exit 1
        fi

        count=0
        while IFS= read -r entry; do
          case "$entry" in
            *atmel:tool-name=*) isToolPack=true ;;
            *) isToolPack=false ;;
          esac
          if [ "$isToolPack" != ${if toolPacksOnly then "true" else "false"} ]; then
            continue
          fi

          case "$entry" in
            *' name="'*)
              pdsc="''${entry#* name=\"}"
              pdsc="''${pdsc%%\"*}"
              ;;
            *)
              echo "Pack entry has no name: $entry" >&2
              exit 1
              ;;
          esac
          pdscPath=$(find "$packsDir" -type f -name "$pdsc" -print -quit)
          if [ -z "$pdscPath" ]; then
            continue
          fi
          packDir=$(dirname "$pdscPath")
          relativePackDir="''${packDir#"$packsDir"/}"
          mkdir -p "$out/$(dirname "$relativePackDir")"
          mv "$packDir" "$out/$relativePackDir"
          count=$((count + 1))
        done < "$index"

        if [ ${if toolPacksOnly then "$count -eq 0" else "$count -le 1"} ]; then
          echo "Installer produced no ${if toolPacksOnly then "tool" else "device"} packs" >&2
          exit 1
        fi

        runHook postInstall
      '';
      passthru = { };
    });

  bundledPacks = unwrapped.overrideAttrs (_: {
    pname = "mplab-x-bundled-packs";
    installerFlags = "";
    installPhase = ''
      runHook preInstall

      packsDir=chroot/opt/microchip/mplabx/v${version}/packs
      rm $packsDir/index.idx
      mkdir -p $out
      mv $packsDir/* $out/

      runHook postInstall
    '';
    passthru = { };
  });

  devicePacks = { mcuOptions }:
    let
      normalisedOptions = lib.sort builtins.lessThan (lib.unique mcuOptions);
      unknownOptions = lib.filter (option: !(lib.elem option packOptions)) normalisedOptions;
      installerFlags = lib.concatMapStringsSep " " (option:
        "--${option} ${if lib.elem option normalisedOptions then "1" else "0"}") packOptions;
    in
    assert lib.assertMsg (unknownOptions == [ ])
      "Unknown MPLAB X MCU option: ${lib.concatStringsSep ", " unknownOptions}";
    filteredPacks {
      pname = "mplab-x-device-packs-${lib.concatStringsSep "-" normalisedOptions}";
      inherit installerFlags;
      toolPacksOnly = false;
    };

  toolPacks = filteredPacks {
    pname = "mplab-x-tool-packs";
    installerFlags = lib.concatMapStringsSep " " (option: "--${option} 0") packOptions;
    toolPacksOnly = true;
  };

  installerHelp = unwrapped.overrideAttrs (_: {
    pname = "mplab-x-installer-help";
    buildPhase = ''
      runHook preBuild

      rsync -a ${fhsEnv.fhsenv}/ chroot/
      find chroot -type d -exec chmod 755 {} \;
      echo "root:x:0:0:root:/root:/bin/bash" > chroot/etc/passwd
      echo "root:x:0:root" > chroot/etc/group
      mkdir -p chroot/tmp/home $out

      bwrap \
        --bind chroot / \
        --ro-bind /nix /nix \
        --ro-bind MPLABX-v${version}-linux-installer.run /installer \
        --setenv HOME /tmp/home \
        -- /bin/fakeroot /installer --help > $out/help.txt
      bwrap \
        --bind chroot / \
        --ro-bind /nix /nix \
        --ro-bind MPLABX-v${version}-linux-installer.run /installer \
        --setenv HOME /tmp/home \
        -- /bin/fakeroot /installer --version > $out/version.txt

      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      runHook postInstall
    '';
    passthru = { };
  });
in
unwrapped
