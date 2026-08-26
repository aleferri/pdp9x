        .dd     RESET
        .dd     STOP
        .dd     STOP
        .dd     STOP
        .dd     STOP
        .dd     STOP
        .dd     STOP
        .dd     STOP
IDX:    .dd     0
NCASE:  .dd     8
VECA:   .dd     VA
VECB:   .dd     VB
VECC:   .dd     VC

        .include "arithlib.s"

        .advance 0x2400
RESET:  CLA
        DAC     IDX
LOOP:   LIX     IDX
        LAC     (VECA) , X
        DAC     M1
        LAC     (VECB) , X
        DAC     M2
        CAL     MUL36
        LAC     MDH
        HOUT
        LAC     MDL
        HOUT
        LIX     IDX
        LAC     (VECC) , X
        DAC     M2
        CAL     DIV36
        HOUT
        LAC     MREM
        HOUT
        ISZ     IDX
        NOP
        LAC     IDX
        SAD     NCASE
        JMP     STOP
        JMP     LOOP
STOP:   HLT
        .advance 0x2600
VA:     .dd     1000, 2897, 2897, 100000, 131071, 262143, 5, 15885
VB:     .dd     1000, 15885, 252, 3, 131071, 262143, 7, 15885
VC:     .dd     1000, 131072, 1024, 7, 131071, 65536, 3, 131072
