; Arithmetic runtime shared by the sample programs.
; Variables at 0x300 and code at 0x1F000, each placed with its own .org, so
; the file says where its two regions go and an including program does not
; have to interleave them with its own.

        .org    0x300
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
MDH:    .dd    0               ; high word of a thirty-six bit value
MDL:    .dd    0               ; low word
MDT:    .dd    0
N36:    .dd    -36
DQ36:   .dd    0
D18L:   .dd    0               ; the word being divided, and the quotient
D18R:   .dd    0               ; the running remainder
D18C:   .dd    0
N18:    .dd   -18
ONE:    .dd    1
TEN:    .dd    10
BIT17:  .dd    0x20000

; ---- decimal conversion ----
DVAL:   .dd    0
DPOS:   .dd    0
DBUF:   .dd    0               ; DBUF..DBUF+11: eleven digits and a sign, which
        .dd    0                ; is what a thirty-six bit value spells out to
        .dd    0
        .dd    0
        .dd    0
        .dd    0
        .dd    0
        .dd    0
        .dd    0
        .dd    0
        .dd    0
        .dd    0
DBUFP:  .dd    DBUF
        .dd    0
        .dd    0
        .dd    0

DBUFP2: .dd    0
MINUS:  .dd    45
MONE:   .dd   -1
MOSTNEG: .dd   0x20000
NIL:    .dd    0
DBEND:  .dd    12              ; one past the last slot of DBUF
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

        .org    0x1F000
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
.loop:  LSR                     ; L <- bit 0, multiplier >>= 1
        SKNL
        TADX    M1              ; accumulate straight into IX
        SKNZ
        JMP     .done            ; multiplier exhausted
        PSH     AC
        LAC     M1
        SHA
        DAC     M1
        POP     AC
        JMP     .loop
.done:  DIX     MRES
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
; Thirty-six bit primitives, for fixed point.
;
; DIV already holds the trick that makes these work: it compares by adding the
; two's complement of the divisor and reading the link, so the comparison is
; unsigned and the remainder never has to be nineteen bits.  A sign test would
; need that extra bit; a carry test does not.  Both routines below are DIV's
; loop with the dividend widened to a pair.
; =====================================================================
; MUL36: MDH and MDL <- M1 * M2, unsigned, thirty-six bits.
;        Callers wanting a signed product apply the sign themselves.
MUL36:  PSH     IX
        CLA
        DAC     MDH
        DAC     MDL
        LAC     N18
        DAC     MCNT
.loop:  LAC     MDL             ; the pair doubles, low word's top bit moving up
        RLA
        GLK
        DAC     MDT
        LAC     MDH
        LSL
        TAD     MDT
        DAC     MDH
        LAC     MDL
        LSL
        DAC     MDL
        LAC     M1              ; take the multiplicand's top bit
        RLA
        GLK
        SKNZ
        JMP     .noadd
        CLL                     ; the link must mean this addition alone
        LAC     MDL
        TAD     M2
        DAC     MDL
        SKL
        JMP     .noadd
        LAC     MDH
        IAC
        DAC     MDH
.noadd: LAC     M1
        LSL
        DAC     M1
        ISZ     MCNT
        JMP     .loop
        POP     IX
        RET

; DIV36: MRES and AC <- (MDH,MDL) / M2, MREM <- remainder.  Unsigned.
;        Two constraints, both inherited from the comparison rather than
;        chosen: the divisor must be under 2^17, because the remainder doubles
;        every pass and has to stay inside a word for the carry to mean what it
;        says; and the quotient is the low eighteen bits of the true one, so
;        dividing a thirty-six bit value by something small returns the bottom
;        of the answer rather than an error.
; Dividing thirty-six bits by eighteen is two chained eighteen bit divides, not
; one thirty-six step loop.  The trick is the one the PDP-7's own DIV uses: the
; running remainder and the dividend's high half are the same place, because
; the step requires the remainder to stay below the divisor.  So two words
; suffice where this first used three, and a third of the transport goes.
;
; The high half divides first; its remainder becomes the next high half.
DIV36:  PSH     IX
        LAC     M2
        SKNZ
        JMP     .zero
        LAC     M2
        CIA
        DAC     NDVR
        LAC     MDH             ; the high half, with nothing above it
        DAC     D18L
        CLA
        CAL     D18
        DAC     D18R            ; its remainder carries down
        LAC     D18L
        DAC     MDH             ; the quotient's high half
        LAC     MDL
        DAC     D18L
        LAC     D18R
        CAL     D18
        DAC     MREM
        LAC     D18L
        DAC     MDL
        DAC     MRES            ; the low word, for callers that want one
        POP     IX
        RET
.zero:  CLA
        DAC     MRES
        DAC     MREM
        POP     IX
        RET

; D18: AC is the running remainder coming in and going out, D18L the word being
;      divided, NDVR the divisor's two's complement.  Eighteen steps, and the
;      quotient replaces D18L as the dividend shifts out of it.
D18:    DAC     D18R
        LAC     N18
        DAC     D18C
.loop:  LAC     D18L            ; the pair shifts as one chain
        LSL
        DAC     D18L
        LAC     D18R
        RLA
        DAC     D18R
        TAD     NDVR            ; L = 1 when the remainder reaches the divisor
        SKL
        JMP     .nofit
        DAC     D18R
        LAC     D18L            ; the quotient bit goes where the shift vacated
        IAC
        DAC     D18L
.nofit: ISZ     D18C
        JMP     .loop
        LAC     D18R
        RET


; =====================================================================
; DIV:  MRES and AC <- M1 / M2, MREM <- M1 mod M2, signed quotient,
;       remainder takes the sign of the dividend.
;       Division by zero returns quotient 0, remainder 0.
; =====================================================================
DIV:    LAC     M2
        SKNZ
        JMP     .zero
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
.loop:  LAC     M1              ; shift the dividend left, top bit into L
        LSL
        DAC     M1
        LAC     MREM            ; and into the remainder from below
        RLA
        DAC     MREM
        TAD     NDVR            ; L = 1 when MREM >= divisor
        SKL
        JMP     .nofit
        DAC     MREM
        LAC     M1
        IAC                     ; set the quotient bit
        DAC     M1
.nofit: ISZ     MCNT
        JMP     .loop
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
.zero:  CLA
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
; Signed wrappers over the thirty-six bit primitives.
;
; MUL36 and DIV36 are unsigned, because restoring division needs unsigned
; operands and the multiply shares its shape.  The evaluator is signed, so the
; magnitudes go in and the sign comes back out, the same arrangement MUL and
; DIV already use for eighteen bits.
; =====================================================================
; MULS36: MDH, MDL <- M1 * M2, signed, exact in thirty-six bits.
MULS36: CAL     ABS1
        CAL     ABS2
        LAC     SG1
        XOR     SG2
        DAC     NEG
        CAL     MUL36
        LAC     NEG
        SKNZ
        RET
        LAC     MDL             ; negate the pair
        CMA
        DAC     MDL
        LAC     MDH
        CMA
        DAC     MDH
        CLL
        LAC     MDL
        TAD     ONE
        DAC     MDL
        SKL
        RET
        LAC     MDH
        IAC
        DAC     MDH
        RET

; DIVS36: MDH, MDL / M2, signed.  Quotient replaces the pair, as DIV36 leaves
;         it, and MRES holds its low word.
DIVS36: CAL     ABS2
        LAC     MDH             ; the dividend's sign lives in the high word
        AND     BIT17
        SKNZ
        JMP     .dpos
        CLA
        IAC
        DAC     SG1
        LAC     MDL
        CMA
        DAC     MDL
        LAC     MDH
        CMA
        DAC     MDH
        CLL
        LAC     MDL
        TAD     ONE
        DAC     MDL
        SKL
        JMP     .dsign
        LAC     MDH
        IAC
        DAC     MDH
        JMP     .dsign
.dpos:  CLA
        DAC     SG1
.dsign: LAC     SG1
        XOR     SG2
        DAC     NEG
        CAL     DIV36
        LAC     NEG
        SKNZ
        JMP     .ddone
        LAC     MDL
        CMA
        DAC     MDL
        LAC     MDH
        CMA
        DAC     MDH
        CLL
        LAC     MDL
        TAD     ONE
        DAC     MDL
        SKL
        JMP     .ddone
        LAC     MDH
        IAC
        DAC     MDH
.ddone: LAC     MDL
        DAC     MRES
        RET

; =====================================================================
; DEC36: the decimal spelling of the thirty-six bit value in MDH and MDL.
;        Same contract as DEC: the digits end up in DBUF, and DPOS through
;        DBEND brackets them.
;
; Repeated division by ten is the whole of decimal conversion, which is why
; this could not exist before DIV36: an eighteen bit divide cannot take a
; thirty-six bit dividend.
;
; Every label here is local, so the routine cannot collide with DIV36 below
; it -- which is exactly what went wrong the first time this was written.
; =====================================================================
DEC36:  PSH     IX
        CLA
        DAC     NEGF
        LAC     MDH             ; the sign lives in the high word
        AND     BIT17
        SKNZ                    ; skip when the value is negative
        JMP     .pos
        CLA
        IAC
        DAC     NEGF
        LAC     MDL             ; negate the pair: complement both, add one to
        CMA                     ; the low word, carry into the high
        DAC     MDL
        LAC     MDH
        CMA
        DAC     MDH
        CLL
        LAC     MDL
        TAD     ONE             ; not IAC: IAC leaves the link alone, and the
        DAC     MDL             ; carry into the high word is the whole point
        SKL                     ; skip when the low word carried out
        JMP     .pos
        LAC     MDH
        IAC
        DAC     MDH
.pos:   LIX     DBEND           ; fill backwards from the end, as DEC does
.loop:  LAC     MDL             ; the zero test goes at the top, like DEC's:
        SKNZ                    ; testing after the write spells a spurious
        JMP     .high           ; extra digit
        JMP     .div
.high:  LAC     MDH
        SKNZ
        JMP     .maybez
        JMP     .div
.maybez: SXD    DBEND           ; zero divides away before the loop writes a
        JMP     .zerod          ; digit, so it needs one of its own -- the same
        JMP     .sign           ; special case DEC carries.  The index having
.zerod: LAC     ZERO            ; moved is what says a digit was written.
        TADX    MONE
        DAC     (DBUFP) , X
        JMP     .sign
.div:   LAC     TEN
        DAC     M2
        CAL     DIV36           ; the quotient replaces the pair in place, so
        LAC     MREM            ; the next round divides it without reloading
        TAD     ZERO
        TADX    MONE            ; back up one slot, AC untouched
        DAC     (DBUFP) , X
        JMP     .loop
.sign:  LAC     NEGF
        SKZ                     ; skip when there is no sign to write
        JMP     .neg
        JMP     .done
.neg:   LAC     MINUS
        TADX    MONE
        DAC     (DBUFP) , X
.done:  DIX     DPOS            ; where the digits begin
        POP     IX
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
        JMP     .mostneg
        CLA
        DAC     NEGF
        LAC     DVAL
        AND     BIT17
        SKNZ                    ; skip only when the sign bit is set
        JMP     .pos
        LAC     DVAL
        CIA
        DAC     DVAL
        CLA
        IAC
        DAC     NEGF
.pos:   LIX     DBEND
        LAC     DVAL
        SKNZ
        JMP     .zero
.loop:  LAC     DVAL
        SKNZ
        JMP     .sign
        DAC     M1
        LAC     TEN
        DAC     M2
        CAL     DIV             ; quotient in AC, remainder in MREM
        DAC     DVAL
        LAC     MREM
        TAD     ZERO
        TADX    MONE            ; back up one slot, AC untouched
        DAC     (DBUFP) , X
        JMP     .loop
.zero:  LAC     ZERO
        TADX    MONE
        DAC     (DBUFP) , X
.sign:  LAC     NEGF
        SKNZ
        JMP     .fin
        LAC     MINUS
        TADX    MONE
        DAC     (DBUFP) , X
.fin:   DIX     DPOS
        POP     IX
        RET

; -131072 has no positive counterpart in 18 bits, so CIA cannot reach it
.mostneg: LAC     ONE
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
