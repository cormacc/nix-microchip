# The source of an installer that Microchip serves only after a login to a Microchip account.
#
# requireFile gives the same fixed-output path as fetchurl for the same name and hash, so the
# installer in the store serves both. When it is not in the store, the build fails with
# instructions instead of an HTTP 403 retry log. See README.org, "Installers that need a
# Microchip login".
{ requireFile }:
{ name, hash }:
requireFile {
  inherit name hash;
  message = ''
    Microchip serves ${name} only after a login to a Microchip account, so Nix cannot
    download it. Add it to the Nix store:

      1. Log in to your Microchip account, and download ${name}
         from the MPLAB XC compiler archive.
      2. Put the file in installers/ in a nix-microchip checkout, and run there:
           bb installers import
         Or add the file directly:
           nix-store --add-fixed sha256 /path/to/${name}
  '';
}
