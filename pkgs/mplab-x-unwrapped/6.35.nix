{ callPackage, runCommand, unzip }:

let
  unwrapped = callPackage (import ./common.nix {
    version = "6.35";
    hash = "sha256-THRzY9z7MVcmQ5+WjQ4lsLFyFLubpdL9Sn87qyjFZwU=";
  }) { };

  commandLineSubset = runCommand "mplab-x-command-line-subset-${unwrapped.version}" {
    nativeBuildInputs = [ unzip ];
  } ''
    source=${unwrapped}/opt/microchip/mplabx/v${unwrapped.version}
    inventory=${./6.35-headless-files.txt}
    manifest="$TMPDIR/manifest"

    # The makefile generator and MDB load their classes from the Class-Path of their jar's
    # manifest, so a jar that the traces missed would fail only at run time.
    for main_jar in PrjMakefilesGenerator.jar mdb.jar; do
      main_jar="$source/mplab_platform/lib/$main_jar"
      unzip -p "$main_jar" META-INF/MANIFEST.MF > "$manifest"
      class_path=""
      in_class_path=false
      while IFS= read -r line; do
        line="''${line%$'\r'}"
        if "$in_class_path"; then
          case "$line" in
            ' '*) class_path="$class_path''${line# }" ;;
            *) break ;;
          esac
        else
          case "$line" in
            Class-Path:\ *)
              class_path="''${line#Class-Path: }"
              in_class_path=true
              ;;
          esac
        fi
      done < "$manifest"

      for jar in $class_path; do
        path=$(realpath -m --relative-to="$source" "$(dirname "$main_jar")/$jar")
        if ! grep -Fx -- "$path" "$inventory" > /dev/null; then
          echo "Manifest jar of ''${main_jar##*/} is missing from the inventory: $path" >&2
          exit 1
        fi
      done
    done

    while IFS= read -r path; do
      source_file="$source/$path"
      if ! test -f "$source_file"; then
        echo "Inventory file is missing from MPLAB X: $path" >&2
        exit 1
      fi
      mkdir -p "$out/$(dirname "$path")"
      cp -L --preserve=mode,timestamps -- "$source_file" "$out/$path"
      if test -L "$out/$path"; then
        echo "Inventory file was copied as a symlink: $path" >&2
        exit 1
      fi
    done < "$inventory"

    mkdir -p "$out/mplab_platform/platform" "$out/mplab_platform/mplab_ide/modules"
  '';
in
unwrapped.overrideAttrs (old: {
  passthru = old.passthru // { inherit commandLineSubset; };
})
