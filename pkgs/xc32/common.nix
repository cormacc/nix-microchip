{ version, hash, url ? null }:

{ lib, stdenvNoCC, bubblewrap, buildFHSEnv, fakeroot, fetchurl, glibc, rsync, microchip-xclm-license }:

let
  fhsEnv = buildFHSEnv {
    name = "mplab-x-build-fhs-env";
    targetPkgs = pkgs: [ fakeroot glibc ];
  };

  # Measured: 5.10 installs xclm and etc/xclm.conf and enforces licensing; 5.19 and 6.00 do neither
  # and their installers have no licence options. The 6.00 release notes list no release between them.
  needsLicense = lib.versionOlder version "5.19";

in stdenvNoCC.mkDerivation rec {
  # See https://www.microchip.com/en-us/tools-resources/archives/mplab-ecosystem for microchip installer back-catalogue
  pname = "xc32";
  inherit version;
  src = if url != null then fetchurl {
    inherit url hash;
  } else fetchurl {
    url =
      "https://ww1.microchip.com/downloads/aemDocuments/documents/DEV/ProductDocuments/SoftwareTools/xc32-v${version}-full-install-linux-x64-installer.run";
    # N.B. Nix uses a 32-bit hash encoding. Use 'nix hash path <filename>' to generate
    inherit hash;
  };

  nativeBuildInputs = [ bubblewrap rsync ];

  unpackPhase = ''
    runHook preUnpack

    install $src installer.run

    runHook postUnpack
  '';
  installPhase = ''
    runHook preInstall

    rsync -a ${fhsEnv.fhsenv}/ chroot/
    find chroot -type d -exec chmod 755 {} \;
    echo "root:x:0:0:root:/root:/bin/bash" > chroot/etc/passwd
    echo "root:x:0:root" > chroot/etc/group
    mkdir -p chroot/tmp/home

    echo "$out" >outdir.txt

    # N.B. --proc is required: the installer runs a manifest check (bin/verifyinst)
    # that crashes without /proc, which the installer misreports as corrupted files.
    bwrap \
      --bind chroot / \
      --bind /nix /nix \
      --proc /proc \
      --ro-bind installer.run /installer \
      --setenv HOME /tmp/home \
      -- /bin/fakeroot /installer \
      ${lib.optionalString needsLicense
        "--LicenseType FreeMode --netservername localhost"} \
      --mode unattended \
      --prefix $out
  '' + lib.optionalString needsLicense ''

    # Point xclm at the packaged licence instead of the host's /opt/microchip/xclm/license.
    chmod u+w "$out/etc/xclm.conf"
    substituteInPlace "$out/etc/xclm.conf" \
      --replace-fail 'xclm:path="/opt/microchip/xclm/license' 'xclm:path="${microchip-xclm-license}'
  '' + ''

    runHook postInstall
  '';
  dontFixup = true;

  meta = with lib; {
    homepage =
      "https://www.microchip.com/en-us/tools-resources/develop/mplab-xc-compilers";
    description =
      "Microchip's MPLAB XC32 C/C++ compiler toolchain for 32-bit PIC32 and SAM microcontrollers (MCUs)";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
  };
}
