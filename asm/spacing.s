; Deliberately violates the blitter's 8 cycle spacing rule, to prove the
; simulator catches it.  Four back-to-back writes land 5 cycles apart, so
; three of every four are swallowed by the cell counter and lost in silence.
; Unrolling a framebuffer fill is exactly this mistake.

        .dd     RESET   ; 0 reset
        .dd     STOP    ; 1 blitter
        .dd     ISR     ; 2 timer
        .dd     STOP    ; 3 keyboard
        .dd     STOP    ; 4 leds
        .dd     STOP    ; 5 spare
        .dd     STOP    ; 6 spare
        .dd     STOP    ; 7 spare
CURS:   .dd    0
CH:     .dd    65
SCRP:   .dd    0x800
THIV:   .dd    255             ; shortest period the timer allows, 256 counts
N:      .dd   -300

        .advance 0x2000
RESET:  LAC     THIV
        TLOAD
        TARM
        EI
        LIX     CURS
        LAC     CH
LOOP:   DAC     (SCRP) , X      ; 5 cycles apart, against a floor of 8
        DAC     (SCRP) , X
        DAC     (SCRP) , X
        DAC     (SCRP) , X
        ISZ     N
        JMP     LOOP
STOP:   HLT

; the handler writes as early as it can; the interrupt prologue alone
; already puts it more than 8 cycles behind the last mainline write
ISR:    PSH     AC , IX
        TACK
        LAC     CH
        LIX     CURS
        DAC     (SCRP) , X
        LAC     THIV
        TLOAD
        TARM
        POP     AC , IX
        SKNI
        RET
        RTI
