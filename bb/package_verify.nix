{ flakeUri, candidate, family, version }:

let
  flake = builtins.getFlake flakeUri;
  pkgs = import flake.inputs.nixpkgs {
    system = "x86_64-linux";
    config.allowUnfree = true;
  };
  microchip = flake.legacyPackages.x86_64-linux;
  compiler = pkgs.callPackage (import (builtins.toPath candidate)) {
    inherit (microchip) microchip-xclm-license;
  };
  profiles = {
    xc16 = {
      command = "xc16-gcc";
      flags = [ "-mcpu=33EP512MU810" ];
      linkFlags = [ "-Wl,-Tp33EP512MU810.gld" ];
    };
    xc8 = {
      command = "xc8-cc";
      flags = [ "-mcpu=18F47K40" ];
      linkFlags = [ ];
      pack = {
        name = "PIC18F-K_DFP";
        version = "1.17.312";
        hash = "sha256-WR6hOWhWLYGvLIThcw9sq+7RhAZ5bgKBjySVWZNCsXQ=";
      };
      packSuffix = "/xc8";
    };
    xc32 = {
      command = "xc32-gcc";
      flags = [ "-mprocessor=32MX795F512L" ];
      linkFlags = [ ];
      pack = {
        name = "PIC32MX_DFP";
        version = "1.7.380";
        hash = "sha256-Fzw/L6o6PtgRpFzvYAjkMI5ej8r58gaRoudkivbuadg=";
      };
      packSuffix = "";
    };
    xc-dsc = {
      command = "xc-dsc-gcc";
      flags = [ "-mcpu=33CK64MP105" ];
      linkFlags = [ "-Wl,-Tp33CK64MP105.gld" ];
      pack = {
        name = "dsPIC33CK-MP_DFP";
        version = "1.16.521";
        hash = "sha256-r7kLDTSUTo1prP9U34j+9LC9vHiExQKXl+23eNY8ArU=";
      };
      packSuffix = "/xc16";
    };
  };
  profile = profiles.${family};
  pack = if profile ? pack then microchip.fetchMplabPack profile.pack else null;
  cli = microchip.xc-cli.override {
    compilers = [ compiler ];
    packs = pkgs.lib.optional (pack != null) pack;
  };
  packDirectory = if pack == null then "" else
    "/opt/microchip/mplabx/v${cli.ideVersion}/packs/${pack.mplabPackPath}";
  flags = profile.flags
    ++ pkgs.lib.optional (pack != null) "-mdfp=${packDirectory}${profile.packSuffix or ""}"
    ++ [ "-O3" "probe.c" ] ++ profile.linkFlags ++ [ "-o" "probe.elf" ];
  # XC-DSC 4.00 reports v4.00.00. Additional zero components do not identify a different release.
  versionPattern = "${family}.*[^0-9]v?${pkgs.lib.replaceStrings [ "." ] [ "[.]" ] version}([.]0+)*([^0-9.]|$)";
in
assert compiler.pname == family;
assert compiler.version == version;
pkgs.runCommand "verify-${family}-${version}" { nativeBuildInputs = [ cli ]; } ''
  xc-run ${compiler}/bin/${profile.command} --version > version.txt 2>&1
  cat version.txt
  if ! grep -Ei ${pkgs.lib.escapeShellArg versionPattern} version.txt; then
    echo 'Compiler version banner does not match the requested family/version' >&2
    exit 1
  fi
  printf '%s\n' 'int main(void) { return 0; }' > probe.c
  xc-run ${compiler}/bin/${profile.command} ${pkgs.lib.escapeShellArgs flags} > compile.log 2>&1 || {
    cat compile.log
    exit 1
  }
  cat compile.log
  # Several licensed compilers return zero even when PRO optimisation is disabled.
  if grep -E 'restricted license|[(]2051[)]|requires the MPLAB XC32 PRO compiler' compile.log; then
    echo 'Compiler reported a restricted licence' >&2
    exit 1
  fi
  test -s probe.elf
  mkdir -p "$out"
  cp probe.elf version.txt compile.log "$out/"
''
