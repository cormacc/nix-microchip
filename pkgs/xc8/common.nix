{ version, hash }:

{ lib, stdenvNoCC, bubblewrap, buildFHSEnv, fakeroot, fetchurl, glibc, rsync }:

let
  fhsEnv = buildFHSEnv {
    name = "mplab-x-build-fhs-env";
    targetPkgs = pkgs: [ fakeroot glibc ];
  };

in stdenvNoCC.mkDerivation rec {
  # See https://www.microchip.com/en-us/tools-resources/archives/mplab-ecosystem for microchip installer back-catalogue
  pname = "xc8";
  inherit version;
  src = fetchurl {
    url =
      "https://ww1.microchip.com/downloads/aemDocuments/documents/DEV/ProductDocuments/SoftwareTools/xc8-v${version}-full-install-linux-x64-installer.run";
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

    # N.B. --proc is required: the xc8 installer runs a manifest check (bin/verifyinst)
    # that crashes without /proc, which the installer misreports as corrupted files.
    bwrap \
      --bind chroot / \
      --bind /nix /nix \
      --proc /proc \
      --ro-bind installer.run /installer \
      --setenv HOME /tmp/home \
      -- /bin/fakeroot /installer \
      ${lib.optionalString (lib.versionOlder version "4.00")
        "--LicenseType FreeMode --netservername localhost"} \
      --mode unattended \
      --prefix $out

    runHook postInstall
  '';
  dontFixup = true;

  meta = with lib; {
    homepage =
      "https://www.microchip.com/en-us/tools-resources/develop/mplab-xc-compilers";
    description =
      "Microchip's MPLAB XC8 C compiler toolchain for 8-bit PIC and AVR microcontrollers (MCUs)";
    license = licenses.unfree;
    maintainers = with maintainers; [ remexre nyadiia ];
    platforms = [ "x86_64-linux" ];
  };
}
