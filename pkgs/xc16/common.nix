{ version, hash }:

{ lib, stdenvNoCC, bubblewrap, buildFHSEnv, fakeroot, fetchurl, glibc, rsync }:

let
  fhsEnv = buildFHSEnv {
    name = "mplab-x-build-fhs-env";
    targetPkgs = pkgs: [ fakeroot glibc ];
  };

in stdenvNoCC.mkDerivation rec {
  # See https://www.microchip.com/en-us/tools-resources/archives/mplab-ecosystem for microchip installer back-catalogue
  # pname = "microchip-xc16-unwrapped";
  pname = "xc16";
  inherit version;
  src = fetchurl {
    url =
      "https://ww1.microchip.com/downloads/en/DeviceDoc/xc16-v${version}-full-install-linux64-installer.run";
    # N.B. Nix uses a 32-bit hash encoding. Use 'nix hash path <filename>' to generate
    inherit hash;
    # v1.61
    # hash = "sha256-Wi0vhJWt+WiNq41daf7e7tJeJmt3/M3t2TJbkJQTNEg=";
    # v2.10
    # hash = "sha256-1k1ec5Hshi1N0Wk2G2aAtyX4lgQ1EhcJtF6xpK/hXcg=";
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
