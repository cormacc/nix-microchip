# The source of a compiler installer: a fixed-output download with the same store path as
# fetchurl for the same name and hash.
#
# Microchip can move an installer behind a login to a Microchip account without notice. Its URLs
# then redirect to www.microchip.com/filehandler/redirect (which returns 403) or to
# login.microchip.com. The file handler also takes URLs that do not exist (measured 2026-11-13),
# so this fetcher reports such a redirect as a possible login gate, with the manual-download
# instructions; other failures get a normal download error. A version file with loginRequired = true gets the
# instructions at once, without a download attempt. See README.org, "Installers that need a
# Microchip login".
{ lib, stdenvNoCC, curl, cacert }:
{ urls, hash, loginRequired ? false }:
let
  name = baseNameOf (builtins.head urls);
in
stdenvNoCC.mkDerivation {
  inherit name;
  outputHashMode = "flat";
  outputHash = hash;

  nativeBuildInputs = [ curl ];
  SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
  impureEnvVars = lib.fetchers.proxyImpureEnvVars;
  preferLocalBuild = true;

  urls = lib.concatStringsSep " " urls;
  loginRequired = lib.boolToString loginRequired;
  loginMessage = ''
    Microchip serves ${name} only after a login to a Microchip account, so Nix cannot
    download it.
  '';
  redirectMessage = ''
    Microchip redirects the URL of ${name} to its file handler or login page. It does
    this for a file that it serves only after a login to a Microchip account, and also for a
    URL that does not exist. If the file is in the MPLAB XC compiler archive:
  '';
  instructions = ''
    Add it to the Nix store:

      1. Log in to your Microchip account, and download ${name}
         from the MPLAB XC compiler archive.
      2. Put the file in installers/ in a nix-microchip checkout, and run there:
           bb installers import
         Or add the file directly:
           nix-store --add-fixed sha256 /path/to/${name}
  '';

  buildCommand = ''
    if [ "$loginRequired" = true ]; then
      echo "$loginMessage$instructions" >&2
      exit 1
    fi
    gated=
    for url in $urls; do
      echo "trying $url" >&2
      # No --fail: the status and final URL are needed to recognise a login redirect.
      result=$(curl --location --silent --show-error --retry 3 --connect-timeout 30 \
        --output "$out" --write-out '%{http_code} %{url_effective}' "$url") || result="000 $url"
      status=''${result%% *}
      final=''${result#* }
      if [ "$status" = 200 ]; then
        exit 0
      fi
      rm -f "$out"
      echo "HTTP $status from $final" >&2
      case "$final" in
        https://www.microchip.com/filehandler/*|https://login.microchip.com/*) gated=1 ;;
      esac
    done
    if [ -n "$gated" ]; then
      echo "$redirectMessage$instructions" >&2
    else
      echo "error: cannot download $name from any of: $urls" >&2
    fi
    exit 1
  '';
}
