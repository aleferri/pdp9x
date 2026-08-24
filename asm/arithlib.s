; Arithmetic runtime shared by the sample programs.
; Variables live at 0x300, code at 0x2000, both fixed so that an including
; program can lay out its own zero page below and its own code above.

        .advance 0x300
M1:     .dd    0               ; multiplicand / dividend
M2:     .dd    0               ; multiplier / divisor
MRES:   .dd    0               ; product / quotient
MREM:   .dd    0               ; remainder
MCNT:   .dd    0
NEG:    .dd    0               ; result sign, 1 = negative
SG1:    .dd    0
SG2:    .dd    0
MASK:   .dd    0
TMP:    .dd    0
NDVR:   .dd    0               ; two's complement of the divisor
N18:    .dd   -18
ONE:    .dd    1
TEN:    .dd    10
BIT17:  .dd    0x20000

; ---- decimal conversion ----
DVAL:   .dd    0
DPOS:   .dd    0
DBUF:   .dd    0               ; DBUF..DBUF+7 hold the digits
        .dd    0
        .dd    0
        .dd    0
        .dd    0
        .dd    0
        .dd    0
        .dd    0
DBUFP:  .dd    DBUF

DBUFP2: .dd    0
MINUS:  .dd    45
MONE:   .dd   -1
MOSTNEG: .dd   0x20000
NIL:    .dd    0
DBEND:  .dd    8               ; one past the last slot of DBUF
NEGF:   .dd    0
MSRC:   .dd    0
SQN:    .dd    0
SQG:    .dd    0
SQT:    .dd    0
ZERO:   .dd    48

MNP:    .dd    MNTXT

MNTXT:  .dd    45
        .dd    49
        .dd    51
        .dd    49
        .dd    48
        .dd    55
        .dd    50
        .dd    0

        .advance 0x2000
; =====================================================================
; ABS1 / ABS2: strip the sign of M1 / M2 without branching.  Only DIV needs
; these: restoring division requires genuinely unsigned operands, while the
; low word of a two's complement product is sign agnostic.
;   RLA puts bit 17 in L, GLK rotates L into a cleared AC, so the sign
;   becomes a 0/1 word.  Negating it gives a mask of all ones or all
;   zeros, and (V xor mask) + sign is the two's complement magnitude.
;   No skip, so there is no polarity to get wrong.
; =====================================================================
ABS1:   LAC     M1
        PSH     AC
        RLA                     ; L <- sign bit
        GLK                     ; AC <- sign bit, L <- 0
        DAC     SG1
        CIA                     ; AC <- -sign: all ones, or all zeros
        DAC     MASK
        POP     AC
        XOR     MASK
        TAD     SG1
        DAC     M1
        RET

ABS2:   LAC     M2
        PSH     AC
        RLA
        GLK
        DAC     SG2
        CIA
        DAC     MASK
        POP     AC
        XOR     MASK
        TAD     SG2
        DAC     M2
        RET

; NEGR: apply the sign in NEG to AC, again without branching
NEGR:   PSH     AC
        LAC     NEG
        CIA
        DAC     MASK
        POP     AC
        XOR     MASK
        TAD     NEG
        RET

; =====================================================================
; MUL:  MRES <- M1 * M2, signed, low 18 bits
; =====================================================================
; The loop runs once per significant bit of the multiplier, not a fixed 18,
; so both operands are reduced to magnitudes first: on the raw pattern a
; negative multiplier has bit 17 set and would never run dry.  The smaller
; magnitude becomes the multiplier, the product accumulates in IX so that
; TADX adds into it in one instruction and AC stays free for the shifting
; multiplier.
MUL:    PSH     IX              ; the caller may be keeping an index here
        CAL     ABS1
        CAL     ABS2
        LAC     SG1
        XOR     SG2             ; negative iff exactly one operand was
        DAC     NEG
        LAC     M2
        CIA
        TAD     M1              ; L = 1 when M1 >= M2.  Note that M2 = 0 gives
        SKL                     ; no carry and swaps needlessly: harmless, and
        CAL     SWAP            ; cheaper than special casing it.
        LIX     NIL
        LAC     M2
MULL:   LSR                     ; L <- bit 0, multiplier >>= 1
        SKNL
        TADX    M1              ; accumulate straight into IX
        SKNZ
        JMP     MULD            ; multiplier exhausted
        PSH     AC
        LAC     M1
        SHA
        DAC     M1
        POP     AC
        JMP     MULL
MULD:   DIX     MRES
        POP     IX
        LAC     MRES
        CAL     NEGR
        DAC     MRES
        RET

SWAP:   LAC     M1
        PSH     AC
        LAC     M2
        DAC     M1
        POP     AC
        DAC     M2
        RET

; =====================================================================
; DIV:  MRES and AC <- M1 / M2, MREM <- M1 mod M2, signed quotient,
;       remainder takes the sign of the dividend.
;       Division by zero returns quotient 0, remainder 0.
; =====================================================================
DIV:    LAC     M2
        SKNZ
        JMP     DIVZ
        CAL     ABS1
        CAL     ABS2
        LAC     SG1
        XOR     SG2
        DAC     NEG
        LAC     M2
        CIA
        DAC     NDVR
        CLA
        DAC     MREM
        LAC     N18
        DAC     MCNT
DIVL:   LAC     M1              ; shift the dividend left, top bit into L
        LSL
        DAC     M1
        LAC     MREM            ; and into the remainder from below
        RLA
        DAC     MREM
        TAD     NDVR            ; L = 1 when MREM >= divisor
        SKL
        JMP     DIVNO
        DAC     MREM
        LAC     M1
        IAC                     ; set the quotient bit
        DAC     M1
DIVNO:  ISZ     MCNT
        JMP     DIVL
        LAC     M1
        CAL     NEGR
        DAC     MRES
        LAC     MREM            ; the remainder follows the dividend's sign
        PSH     AC
        LAC     SG1
        DAC     NEG
        POP     AC
        CAL     NEGR
        DAC     MREM
        LAC     MRES            ; the quotient is the return value
        RET
DIVZ:   CLA
        DAC     MRES
        DAC     MREM
        RET

; =====================================================================
; ISQRT:  MRES <- floor(sqrt(M1)) for M1 >= 0, by Newton from above.
;         The guess only ever falls, so the first value that fails to fall is
;         the answer.  Halving uses LSR, which is safe because everything here
;         is non negative.
; =====================================================================
ISQRT:  LAC     M1
        SKNZ
        JMP     SQZ
        DAC     SQN
        DAC     SQG
SQL:    LAC     SQN
        DAC     M1
        LAC     SQG
        DAC     M2
        CAL     DIV             ; n / g
        TAD     SQG
        LSR                     ; ( g + n/g ) / 2
        DAC     SQT
        LAC     SQG
        CIA
        TAD     SQT             ; new - old
        SKNZ                    ; skip while the guess is still falling
        JMP     SQD
        AND     BIT17
        SKNZ
        JMP     SQD             ; stopped falling: converged
        LAC     SQT
        DAC     SQG
        JMP     SQL
SQD:    LAC     SQG
        DAC     MRES
        RET
SQZ:    CLA
        DAC     MRES
        RET

; =====================================================================
; DEC:  convert DVAL to decimal digits in DBUF, DPOS = digit count.
;       A negative value emits a leading minus as character code 45.
; =====================================================================
; =====================================================================
; ISQRT:  MRES <- floor(sqrt(M1)) for M1 >= 0, by Newton from above.
;         The guess only ever falls, so the first value that fails to fall is
;         the answer.  Halving uses LSR, which is safe because everything here
;         is non negative.
; =====================================================================
ISQRT:  LAC     M1
        SKNZ
        JMP     SQZ
        DAC     SQN
        DAC     SQG
SQL:    LAC     SQN
        DAC     M1
        LAC     SQG
        DAC     M2
        CAL     DIV             ; n / g
        TAD     SQG
        LSR                     ; ( g + n/g ) / 2
        DAC     SQT
        LAC     SQG
        CIA
        TAD     SQT             ; new - old
        SKNZ                    ; skip while the guess is still falling
        JMP     SQD
        AND     BIT17
        SKNZ
        JMP     SQD             ; stopped falling: converged
        LAC     SQT
        DAC     SQG
        JMP     SQL
SQD:    LAC     SQG
        DAC     MRES
        RET
SQZ:    CLA
        DAC     MRES
        RET

; =====================================================================
; DEC:  convert DVAL to decimal characters in DBUF.  DPOS is the index of the
;       first character; the last one is always DBUF[7].
;
;       Digits come out least significant first, so they are written backwards
;       into the tail of the buffer and land in order: no reversal pass, and
;       IX carries the write index throughout.  TADX steps it back by one
;       without touching AC.
; =====================================================================
DEC:    PSH     IX              ; the write index lives in IX, so callers that
        LAC     DVAL            ; keep something there must not lose it
        SAD     MOSTNEG
        JMP     DECMN
        CLA
        DAC     NEGF
        LAC     DVAL
        AND     BIT17
        SKNZ                    ; skip only when the sign bit is set
        JMP     DECP
        LAC     DVAL
        CIA
        DAC     DVAL
        CLA
        IAC
        DAC     NEGF
DECP:   LIX     DBEND
        LAC     DVAL
        SKNZ
        JMP     DECZ
DECL:   LAC     DVAL
        SKNZ
        JMP     DECS
        DAC     M1
        LAC     TEN
        DAC     M2
        CAL     DIV             ; quotient in AC, remainder in MREM
        DAC     DVAL
        LAC     MREM
        TAD     ZERO
        TADX    MONE            ; back up one slot, AC untouched
        DAC     (DBUFP) , X
        JMP     DECL
DECZ:   LAC     ZERO
        TADX    MONE
        DAC     (DBUFP) , X
DECS:   LAC     NEGF
        SKNZ
        JMP     DECF
        LAC     MINUS
        TADX    MONE
        DAC     (DBUFP) , X
DECF:   DIX     DPOS
        POP     IX
        RET

; -131072 has no positive counterpart in 18 bits, so CIA cannot reach it
DECMN:  LAC     ONE
        DAC     DPOS
        CLA
        DAC     MSRC
        LIX     DPOS
DECMNL: PSH     IX
        LIX     MSRC
        LAC     (MNP) , X
        POP     IX
        SKNZ
        JMP     DECMND
        JMP     DECMNC
DECMND: POP     IX
        RET
DECMNC:
        DAC     (DBUFP) , X
        IXC
        ISZ     MSRC
        NOP
        JMP     DECMNL
