{ coreutils, lib, writeShellApplication }:

# The mdb command: runs the MPLAB-X debugger command line (mplab_platform/bin/mdb.sh) in an
# environment, with the output and exit status of mdb.sh.
#
# mdb.sh puts $mplab_user_dir/modules on its class path; USER_DIR sets that folder (common-vars.sh),
# so a private empty folder keeps modules of an IDE user folder off the class path. The pack library
# creates ~/.mchp_packs and exits if it cannot, so a HOME that is not writable (e.g. in the Nix build
# sandbox) is replaced. The folders are in /tmp because the bwrap environment binds the host /tmp,
# not TMPDIR. mdb.sh passes its arguments unquoted, so an argument with a space breaks.
{ run, ideDir }:

writeShellApplication {
  name = "mdb";
  text = ''
    tmp=()
    trap '${coreutils}/bin/rm -rf "''${tmp[@]}"' EXIT
    userdir=$(${coreutils}/bin/mktemp -d /tmp/mdb-userdir.XXXXXXXX)
    tmp+=("$userdir")
    if [ -z "''${HOME:-}" ] || [ ! -d "$HOME" ] || [ ! -w "$HOME" ]; then
      HOME=$(${coreutils}/bin/mktemp -d /tmp/mdb-home.XXXXXXXX)
      tmp+=("$HOME")
      export HOME
    fi
    status=0
    USER_DIR=$userdir ${lib.getExe run} ${ideDir}/mplab_platform/bin/mdb.sh "$@" || status=$?
    exit "$status"
  '';
}
