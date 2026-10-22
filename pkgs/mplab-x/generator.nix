{ lib, coreutils, writeShellApplication }:

{ environment, compilers, ideDir }:

let
  compilerDir = c: "/opt/microchip/${c.pname}/v${c.version}";
  compilerArgs = lib.concatMapStringsSep " " (c: "-compilers=${compilerDir c}/bin") compilers;
in
writeShellApplication {
  name = "mplab-gen";
  text = ''
    if [ "$#" -eq 0 ]; then
      echo "usage: mplab-gen <project>@<configuration>..." >&2
      exit 2
    fi
    compilerCount=${toString (builtins.length compilers)}
    if [ "$compilerCount" -eq 0 ]; then
      echo "mplab-gen: no compiler is selected in xc-cli" >&2
      exit 2
    fi
    userdir=$(${coreutils}/bin/mktemp -d /tmp/mplabx-userdir.XXXXXXXX)
    trap '${coreutils}/bin/rm -rf "$userdir"' EXIT
    ${lib.getExe environment.generatorRun} ${ideDir}/mplab_platform/bin/prjMakefilesGenerator.sh -f ${compilerArgs} -mplabx-userdir="$userdir" "$@"
  '';
}
