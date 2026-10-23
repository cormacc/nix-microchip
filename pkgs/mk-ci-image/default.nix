{ lib, buildEnv, dockerTools }:

# Builds a Docker image whose root is the root filesystem of an xc-cli package, for CI runners
# that cannot create the user namespace of the bwrap environment (Docker's default seccomp
# profile blocks it). MPLAB_X_ENV names that root filesystem, so the xc-cli commands run
# directly, without bwrap (run.sh). The image streams to stdout: `$(nix build ...) | docker load`.
{ xc-cli
  # Packages whose bin directories the image PATH also contains.
, extraPackages ? [ ]
, name ? "xc-cli"
  # null: Nix derives the tag from the image contents.
, tag ? null
}:

let
  tools = buildEnv {
    name = "${name}-tools";
    paths = [ xc-cli ] ++ extraPackages;
  };
in
dockerTools.streamLayeredImage {
  inherit name tag;
  # fakeNss: the pack library needs a user.home, which Java reads from /etc/passwd.
  contents = [ xc-cli.rootfs dockerTools.fakeNss ];
  # mplab-gen gets real copies of the IDE entries that its bwrap runner binds: the generator
  # derives its paths from the real path of its jar, and a symlink into the store would put
  # store paths into the makefiles.
  extraCommands = ''
    mkdir -p root tmp
    chmod 1777 tmp
  '' + lib.optionalString (xc-cli.generatorBindList != null) ''
    while IFS=$'\t' read -r source target; do
      rm -rf ".$target"
      cp -rL "$source" ".$target"
    done < ${xc-cli.generatorBindList}
  '';
  config = {
    Cmd = [ "/bin/bash" ];
    Env = [
      # PATH (stub first) and LD_LIBRARY_PATH as run.sh sets them for its bwrap environment.
      # MPLAB_X_ENV makes the xc-cli wrappers run their commands directly.
      "PATH=${xc-cli.mountStub}/bin:${tools}/bin:/usr/bin:/usr/sbin"
      "MPLAB_X_ENV=${xc-cli.rootfs}"
      "LD_LIBRARY_PATH=/lib32"
      "HOME=/root"
    ];
  };
}
