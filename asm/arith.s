; Arithmetic runtime for FOCAL: signed multiply, signed divide, and decimal
; conversion.  The machine has neither multiply nor divide, so these are the
; floor everything else stands on.
;
; Multiply is shift-and-add, divide is restoring division, both 18 bit.
; Signs are stripped, the magnitudes are processed unsigned, and the sign is
; reapplied at the end -- restoring division needs unsigned operands.

        .dd     RESET   ; 0 reset
        .dd     STOP    ; 1 blitter
        .dd     STOP    ; 2 timer
        .dd     STOP    ; 3 keyboard
        .dd     STOP    ; 4 leds
        .dd     STOP    ; 5 spare
        .dd     STOP    ; 6 spare
        .dd     STOP    ; 7 spare

; ---- shared scratch ----
; ---- test vectors and results ----
TA:     .dd    0
TB:     .dd    0
RES:    .dd    0
RES2:   .dd    0
FAILS:  .dd    0
VECP:   .dd    0
VECN:   .dd    0
VZERO:  .dd    0
VECBASE: .dd   VECS
NVEC:   .dd   -9


        .include "arithlib.s"

        .advance 0x2400

; =====================================================================
; self test
; =====================================================================
RESET:  CLA
        DAC     FAILS
        LAC     VECBASE
        DAC     VECP
        LAC     NVEC
        DAC     VECN
TLOOP:  LIX     VECP
        LAC     (VZERO) , X     ; a
        DAC     TA
        DAC     M1
        ISZ     VECP
        NOP
        LIX     VECP
        LAC     (VZERO) , X     ; b
        DAC     TB
        DAC     M2
        ISZ     VECP
        NOP
        CAL     MUL
        LAC     MRES
        DAC     RES
        LIX     VECP
        LAC     (VZERO) , X     ; expected product
        ISZ     VECP
        NOP
        SAD     RES             ; skip when they differ
        JMP     TMOK
        ISZ     FAILS
        NOP
TMOK:   LAC     TA
        DAC     M1
        LAC     TB
        DAC     M2
        CAL     DIV
        LAC     MRES
        DAC     RES
        LAC     MREM
        DAC     RES2
        LIX     VECP
        LAC     (VZERO) , X     ; expected quotient
        ISZ     VECP
        NOP
        SAD     RES
        JMP     TDOK
        ISZ     FAILS
        NOP
TDOK:   LIX     VECP
        LAC     (VZERO) , X     ; expected remainder
        ISZ     VECP
        NOP
        SAD     RES2
        JMP     TROK
        ISZ     FAILS
        NOP
TROK:   ISZ     VECN
        JMP     TLOOP
STOP:   HLT

MNTXT:  .dd    45
        .dd    49
        .dd    51
        .dd    49
        .dd    48
        .dd    55
        .dd    50
        .dd    0

        .advance 0x2600
VECS:                           ; a, b, a*b, a/b, a mod b
        .dd    7
        .dd    3
        .dd    21
        .dd    2
        .dd    1

        .dd    100
        .dd    7
        .dd    700
        .dd    14
        .dd    2

        .dd    0
        .dd    5
        .dd    0
        .dd    0
        .dd    0

        .dd    12345
        .dd    1
        .dd    12345
        .dd    12345
        .dd    0

        .dd    131071
        .dd    2
        .dd   -2               ; 131071*2 = 262142, low 18 bits = -2
        .dd    65535
        .dd    1

        .dd   -21
        .dd    3
        .dd   -63
        .dd   -7
        .dd    0

        .dd    21
        .dd   -3
        .dd   -63
        .dd   -7
        .dd    0

        .dd   -21
        .dd   -3
        .dd    63
        .dd    7
        .dd    0

        .dd    9
        .dd    0
        .dd    0
        .dd    0
        .dd    0
