#include <xc.h>

// Toggles RA0. The program exists to give the CI examples a project that builds to a hex file.
int main(void)
{
    TRISAbits.TRISA0 = 0;
    for (;;) {
        LATAbits.LATA0 ^= 1;
    }
    return 0;
}
