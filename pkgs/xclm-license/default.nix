# Microchip's free licence for legacy MPLAB XC PRO compilers.
# The licence text is kept as a plain file so that a reissued licence replaces only microchip.lic.
{ lib, runCommand }:
runCommand "microchip-xclm-license" {
  meta = {
    description = "Microchip free licence for legacy MPLAB XC PRO compilers";
    license = lib.licenses.unfree;
  };
} ''
  mkdir -p $out
  cp ${./microchip.lic} $out/microchip.lic
''
