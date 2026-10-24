{ version, hash, url ? null }:

{ lib, stdenvNoCC, bubblewrap, buildFHSEnv, fakeroot, fetchurl, glibc, rsync, microchip-xclm-license }:

let
  # XC16 1.50 is the first 64-bit release (Microchip MPLAB Ecosystem Downloads Archive). Older
  # installers are 32-bit, so the install environment needs 32-bit glibc.
  is32bit = lib.versionOlder version "1.50";

  fhsEnv = buildFHSEnv ({
    name = "mplab-x-build-fhs-env";
    targetPkgs = pkgs: [ fakeroot glibc ];
  } // lib.optionalAttrs is32bit {
    multiArch = true;
    multiPkgs = pkgs: [ pkgs.glibc ];
  });

in stdenvNoCC.mkDerivation rec {
  # See https://www.microchip.com/en-us/tools-resources/archives/mplab-ecosystem for microchip installer back-catalogue
  # pname = "microchip-xc16-unwrapped";
  pname = "xc16";
  inherit version;
  src = if url != null then fetchurl {
    inherit url hash;
  } else if is32bit then fetchurl {
    # The 32-bit installers are a .run inside a .tar (verified for 1.21).
    url = "https://ww1.microchip.com/downloads/en/DeviceDoc/xc16-v${version}-linux-installer.run.tar";
    inherit hash;
  } else fetchurl {
    # Microchip serves each installer from only one of these locations (2.10: aemDocuments; 1.61: DeviceDoc).
    # fetchurl tries them in order, so one list covers every version.
    urls = [
      "https://ww1.microchip.com/downloads/aemDocuments/documents/DEV/ProductDocuments/SoftwareTools/xc16-v${version}-full-install-linux64-installer.run"
      "https://ww1.microchip.com/downloads/en/DeviceDoc/xc16-v${version}-full-install-linux64-installer.run"
    ];
    # N.B. Nix uses a 32-bit hash encoding. Use 'nix hash path <filename>' to generate
    inherit hash;
  };

  nativeBuildInputs = [ bubblewrap rsync ];

  unpackPhase = ''
    runHook preUnpack

    ${if is32bit then "tar xf $src -O > installer.run && chmod +x installer.run" else "install $src installer.run"}

    runHook postUnpack
  '';
  # The 32-bit installers have no --LicenseType option. The edit keeps the 64-bit installPhase
  # (and so its store paths) unchanged.
  installPhase = (if is32bit then
    lib.replaceStrings [ "  --LicenseType FreeMode \\\n" ] [ "" ]
  else lib.id) ''
    runHook preInstall

    rsync -a ${fhsEnv.fhsenv}/ chroot/
    find chroot -type d -exec chmod 755 {} \;
    echo "root:x:0:0:root:/root:/bin/bash" > chroot/etc/passwd
    echo "root:x:0:root" > chroot/etc/group
    mkdir -p chroot/tmp/home

    echo "$out" >outdir.txt

    bwrap \
      --bind chroot / \
      --bind /nix /nix \
      --ro-bind installer.run /installer \
      --setenv HOME /tmp/home \
      -- /bin/fakeroot /installer \
      --LicenseType FreeMode \
      --mode unattended \
      --netservername localhost \
      --prefix $out

    # Point xclm at the packaged licence instead of the host's /opt/microchip/xclm/license.
    if [ -f "$out/etc/xclm.conf" ]; then
      chmod u+w "$out/etc/xclm.conf"
      substituteInPlace "$out/etc/xclm.conf" \
        --replace-fail 'xclm:path="/opt/microchip/xclm/license' 'xclm:path="${microchip-xclm-license}'
    fi

    runHook postInstall
  '';
  dontFixup = true;

  meta = with lib; {
    homepage =
      "https://www.microchip.com/en-us/tools-resources/develop/mplab-xc-compilers";
    description =
      "Microchip's MPLAB XC16 C compiler toolchain for all 16-bit PIC microcontrollers (MCUs)";
    license = licenses.unfree;
    maintainers = with maintainers; [ remexre nyadiia ];
    platforms = [ "x86_64-linux" ];
  };
}
