        .dd     RESET
        .dd     STOP
        .dd     STOP
        .dd     STOP
        .dd     STOP
        .dd     STOP
        .dd     STOP
        .dd     STOP
IDX:    .dd     0
NC:     .dd     8
VA:     .dd     TA
VB:     .dd     TB

        .include "arithlib.s"

        .org    0x1F400
RESET:  CLA
        DAC     IDX
.loop:  LIX     IDX
        LAC     (VA) , X
        DAC     M1
        LAC     (VB) , X
        DAC     M2
        CAL     MULS36
        CAL     DEC36
        LIX     DPOS
.out:   SXD     DBEND
        JMP     .next
        LAC     (DBUFP) , X
        HOUT
        IXC
        JMP     .out
.next:  CLA
        HOUT
        ISZ     IDX
        NOP
        LAC     IDX
        SAD     NC
        JMP     STOP
        JMP     .loop
STOP:   HLT
        .org    0x1F600
TA:     .dd     1000, -1000, 1000, -1000, 131071, -131072, 0, 12345
TB:     .dd     1000, 1000, -1000, -1000, 131071, 131071, 5, -6789
