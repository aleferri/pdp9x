; Byte Sieve of Eratosthenes, 8190 flags, word per flag.
; Expected result: 1899 primes.

        .dd     RESET   ; 0 reset
        .dd     IRQ2    ; 1 blitter
        .dd     IRQ0    ; 2 timer
        .dd     IRQ1    ; 3 keyboard
        .dd     IRQ2    ; 4 leds
        .dd     IRQ2    ; 5 spare
        .dd     IRQ2    ; 6 spare
        .dd     IRQ2    ; 7 spare

; ---- zero page ----
ITER:   .dd    0
COUNT:  .dd    0
IVAR:   .dd    0
PRIME:  .dd    0
KVAR:   .dd    0
TICKS:  .dd    0
FLAGP:  .dd    0x2000          ; base of the flag array (page 1 is the stack)
ONE:    .dd    1
THREE:  .dd    3
MS1:    .dd   -8191            ; -(SIZE+1), SIZE = 8190
NITER:  .dd   -10

        .advance 0x40

; ---- entry ----
RESET:  HTON                 ; timer on; SP is 0 out of reset, stack page is fixed
        EI
        LAC     NITER
        DAC     ITER

ILOOP:  CLA
        DAC     COUNT

; flags[0..SIZE] = 1
        CLA
        DAC     IVAR
FILL:   LIX     IVAR
        LAC     ONE
        DAC     (FLAGP), X
        LAC     IVAR
        TAD     ONE
        DAC     IVAR
        TAD     MS1             ; L = 1 when i+1 > SIZE
        SKL
        JMP     FILL

; main sieve
        CLA
        DAC     IVAR
SLOOP:  LIX     IVAR
        LAC     (FLAGP), X
        SKNZ
        JMP     SNEXT
        LAC     IVAR
        TAD     IVAR
        TAD     THREE
        DAC     PRIME           ; prime = i+i+3
        TAD     IVAR
        DAC     KVAR            ; k = i + prime
MARK:   LAC     KVAR
        TAD     MS1
        SKNL
        JMP     MDONE
        LIX     KVAR
        CLA
        DAC     (FLAGP), X
        LAC     KVAR
        TAD     PRIME
        DAC     KVAR
        JMP     MARK
MDONE:  LAC     COUNT
        TAD     ONE
        DAC     COUNT
SNEXT:  LAC     IVAR
        TAD     ONE
        DAC     IVAR
        TAD     MS1
        SKL
        JMP     SLOOP

        ISZ     ITER
        JMP     ILOOP
        LAC     COUNT
        HOUT                 ; emit result
        HLT

; ---- irq0: deliberately clobbers AC, IX and L ----
IRQ0:   PSH     AC , IX
        HACK  
        LAC     ONE
        TAD     ONE
        LIX     ONE
        ISZ     TICKS
        NOP
        POP     AC , IX
        SKNI
        RET
        RTI

IRQ1:   RTI
IRQ2:   RTI
