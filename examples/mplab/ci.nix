{ microchip }:

let
  dfp = microchip.fetchMplabPack {
    name = "dsPIC33E-GM-GP-MC-GU-MU_DFP";
    version = "1.7.401";
    hash = "sha256-NSLRbSv/UQcvVhFLhqc+eQixQupAA5aFuCwdoHyVEyc=";
  };
  xc-cli = microchip.xc-cli.override {
    compilers = [ microchip.xc16_1_61 ];
    packs = [ dfp ];
    withMplabProjects = true;
  };
  image = microchip.mkCiImage {
    inherit xc-cli;
    name = "ghcr.io/cormacc/nix-microchip-ci";
  };
in
{
  inherit xc-cli;
  # GHCR uses this label to associate a locally published image with its source repository.
  image = image.override (old: {
    config = old.config // {
      Labels."org.opencontainers.image.source" = "https://github.com/cormacc/nix-microchip";
    };
  });
}
