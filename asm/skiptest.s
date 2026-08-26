        .dd     RESET
        .dd     STOP
        .dd     STOP
        .dd     STOP
        .dd     STOP
        .dd     STOP
        .dd     STOP
        .dd     STOP
NEG:    .dd     -7
POS:    .dd     7
ZERO:   .dd     0
ONE:    .dd     1
        .advance 0x2400
RESET:  LAC     NEG             ; 1: SMA su negativo deve saltare
        SMA
        JMP     BAD
        LAC     POS             ; 2: SMA su positivo non deve saltare
        SMA
        JMP     OK1
        JMP     BAD
OK1:    LAC     POS             ; 3: SPA su positivo deve saltare
        SPA
        JMP     BAD
        LAC     NEG             ; 4: SPA su negativo non deve
        SPA
        JMP     OK2
        JMP     BAD
OK2:    LAC     ZERO            ; 5: SKLE = minore o uguale a zero
        SKLE
        JMP     BAD
        LAC     NEG             ; 6: anche su negativo
        SKLE
        JMP     BAD
        LAC     POS             ; 7: e non su positivo
        SKLE
        JMP     OK3
        JMP     BAD
OK3A:   LAC     POS             ; 7b: SKGT = maggiore di zero
        SKGT
        JMP     BAD
        LAC     ZERO
        SKGT
        JMP     OK3
        JMP     BAD
OK3:    JMP     OK3B
OK3B:   EI                      ; 8: SKI con interrupt attivi
        SKI
        JMP     BAD
        DI                      ; 9: SKNI con interrupt spenti
        SKNI
        JMP     BAD
        LAC     ONE
        HOUT                    ; tutto passato
        JMP     STOP
BAD:    CLA
        HOUT
STOP:   HLT
