{ lib, fetchzip }:

# Fetches one device family pack (DFP) or tool pack (TP) from Microchip's pack repository.
# The output is the pack root, the same tree that the MPLAB-X installer puts at
# packs/<vendor>/<name>/<version>, so `nix hash path` of an installed copy gives the hash.
{ vendor ? "Microchip", name, version, hash }:

fetchzip {
  name = "mplab-pack-${name}-${version}";
  url = "https://packs.download.microchip.com/${vendor}.${name}.${version}.atpack";
  # An .atpack is a zip archive with the pack files at its top level.
  extension = "zip";
  stripRoot = false;
  # The archive manifest. Installed packs do not have it; without it the hash matches theirs.
  postFetch = ''
    rm -f $out/package.content
  '';
  inherit hash;
  passthru = {
    inherit vendor version;
    packName = name;
    # The location of the pack in a packs folder.
    mplabPackPath = "${vendor}/${name}/${version}";
  };
  meta = {
    homepage = "https://packs.download.microchip.com/";
    license = lib.licenses.unfree;
  };
}
