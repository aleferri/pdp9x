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
VH:     .dd     VHI
VL:     .dd     VLO

        .include "arithlib.s"

        .advance 0x2400
RESET:  CLA
        DAC     IDX
.loop:  LIX     IDX
        LAC     (VH) , X
        DAC     MDH
        LAC     (VL) , X
        DAC     MDL
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
        .advance 0x2600
VHI:    .dd     0, 0, 0, 1, 262143, 262143, 12345, 131072
VLO:    .dd     0, 5, 12345, 0, 262143, 0, 54321, 0
