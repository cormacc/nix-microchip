{ runtimeShell }:

# Root filesystem commands that copy the IDE's sys folder and wrap each java in it.
#
# The IDE and the CLI scripts (e.g. prjMakefilesGenerator.sh) run <ideDir>/sys/java. The pack
# library derives its packs folder from its jar's real path, which is in the store, so the wrapper
# sets the folder with the packslib.packsfolder property
# (com.microchip.packslib.parsers.ConfigParser.getSystemRepoLocation). The makefile generator
# writes MP_JAVA_PATH from java.home, so the wrapper sets java.home to the /opt path of the JRE.
#
# The string has no trailing newline: a caller puts it on its own line.
{ sys, ideDir }: ''
  cp -rs ${sys} $out${ideDir}/sys
  for java in $out${ideDir}/sys/java/*/bin/java; do
    real=$(readlink "$java")
    javaHome=''${java#$out${ideDir}/sys/java/}
    javaHome=${ideDir}/sys/java/''${javaHome%/bin/java}
    chmod u+w "$(dirname "$java")"
    rm "$java"
    printf '#!%s\nexec %s -Djava.home=%s -Dpackslib.packsfolder=%s "$@"\n' \
      ${runtimeShell} "$real" "$javaHome" ${ideDir}/packs > "$java"
    chmod +x "$java"
  done''
