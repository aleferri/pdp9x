        .dd     RESET   ; 0 reset
        .dd     STOP    ; 1 blitter
        .dd     STOP    ; 2 timer
        .dd     STOP    ; 3 keyboard
        .dd     STOP    ; 4 leds
        .dd     STOP    ; 5 spare
        .dd     STOP    ; 6 spare
        .dd     STOP    ; 7 spare
BIT17:  .dd    0x20000
M17:    .dd    0x1FFFF
RES:    .dd    0
        .advance 0x100
RESET:  CLL                     ; L = 0 entering the call
        CAL     SETL
        SKL                     ; must come back with L = 1
        HLT
        CLA
        IAC
        DAC     RES             ; 1 = link returned set

        STL                     ; L = 1 entering the call
        CAL     CLRL
        SKNL                    ; must come back with L = 0
        HLT
        LAC     RES
        IAC
        DAC     RES             ; 2 = link returned clear

        CAL     SKIPRET
        HLT                     ; must be skipped
        LAC     RES
        IAC
        DAC     RES             ; 3 = skip return worked
        HLT

SETL:   POP     AC              ; AC = { L_caller, PC_ret }
        IOR     BIT17
        PSH     AC
        RET
CLRL:   POP     AC
        AND     M17
        PSH     AC
        RET
SKIPRET:
        POP     AC
        IAC                     ; bump the packed return address
        PSH     AC
        RET
STOP:   HLT
