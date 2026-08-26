; A subset of FOCAL for the 18-bit machine.
;
; Commands: SET, TYPE, ASK, IF, GOTO, DO, RETURN, FOR, WRITE, ERASE, QUIT and
; comment lines.  Several commands may share a line, separated by semicolons.
; Functions: FABS, FSGN, FITR, FSQT.
; Arithmetic is 18-bit integer, not FOCAL's floating point: the machine has
; no floating unit and the point here is the interpreter, not the numerics.
;
; The program text sits in memory as one blob, lines separated by newline,
; terminated by a zero word:
;
;     10 SET A=7
;     20 SET B=A*(A+1)/2
;     30 TYPE "SUM ", B, !
;     40 IF (B-28) 60, 50, 60
;     50 TYPE "OK", !
;     60 QUIT
;
; The evaluator is recursive descent, which the machine supports directly
; because CAL and RET use the hardware stack:
;     EXPR := TERM { (+|-) TERM }
;     TERM := FACT { (*|/) FACT }
;     FACT := number | letter | '(' EXPR ')' | '-' FACT

        .dd     RESET   ; 0 reset
        .dd     STOP    ; 1 blitter
        .dd     STOP    ; 2 timer
        .dd     KBDISR  ; 3 keyboard
        .dd     STOP    ; 4 leds
        .dd     STOP    ; 5 spare
        .dd     STOP    ; 6 spare
        .dd     STOP    ; 7 spare

; ---- interpreter state ----
LNUM:   .dd    0               ; line number just parsed
NUM:    .dd    0               ; number under construction
DIGIT:  .dd    0
TMPV:   .dd    0
CURS:   .dd    0               ; console cursor, 0..511
TARG:   .dd    0               ; GOTO target
ARGN:   .dd    0
IFV:    .dd    0
SVAR:   .dd    0               ; SET target, must survive the expression
TPSAVE: .dd    0               ; text pointer parked across the dispatch
T10:    .dd    0
KNEG:   .dd    0
KCH:    .dd    0
KCH2:   .dd    0
CTABP:  .dd    CTAB

; ---- constants ----
TXTP:   .dd    TEXT            ; the text being read, program or typed line
TXTB:   .dd    TEXT            ; the stored program, always
LBUFA:  .dd    LBUF
SCRP:   .dd    0x4000
C512:   .dd    512
C480:   .dd    480
C32:    .dd    32
SPC:    .dd    32
NLC:    .dd    10
LIROOT: .dd    0                ; first chunk, zero when not built
LICUR:  .dd    0
LICNT:  .dd    0
LIN:    .dd    0
LIP:    .dd    0
LIT:    .dd    0
C254:   .dd    254
C255:   .dd    255
C256:   .dd    256
C127:   .dd    127
LIRA:   .dd    0
LIRD:   .dd    0
LIRT:   .dd    0
QUOTE:  .dd    34
COMMA:  .dd    44
LPAR:   .dd    40
RPAR:   .dd    41
PLUSC:  .dd    43
MINC:   .dd    45
STAR:   .dd    42
SLASH:  .dd    47
EQ:     .dd    61
BANG:   .dd    33
MACHR:  .dd   -65              ; -'A'
M0C:    .dd   -48              ; -'0'
M10:    .dd   -10
CS:     .dd    83              ; 'S'
CT:     .dd    84              ; 'T'
CI:     .dd    73              ; 'I'
CG:     .dd    71              ; 'G'
CQ:     .dd    81              ; 'Q'
CW:     .dd    87              ; 'W'
CE:     .dd    69              ; 'E'
CF:     .dd    70              ; 'F'
CA:     .dd    65              ; 'A'
FSEL:   .dd    0
FSEL2:  .dd    0
FARG:   .dd    0
MORE:   .dd    0
SEMI:   .dd    59              ; ';'
FVARI:  .dd    0
FCUR:   .dd    0
FSTEP:  .dd    0
FLIM:   .dd    0
FBODY:  .dd    0
FDIFF:  .dd    0
KRAWV:  .dd    0
KMODV:  .dd    0
KBUF:   .dd    0
KCHR:   .dd    0
KQI:    .dd    0
KQO:    .dd    0
C7:     .dd    7
KQN:    .dd    0
KBIT:   .dd    8               ; the keyboard is device 3
QMARK:  .dd    63              ; '?'
ERRT:   .dd    84              ; ?T unknown type
ERRB:   .dd    66              ; ?B subscript outside the array
AVB:    .dd    0
ERRF:   .dd    70              ; ?F float not implemented
SADDR:  .dd    0
SADDR2: .dd    0
SAT:    .dd    0
SOFF:   .dd    0
SCH:    .dd    0
SLM1:   .dd    19              ; last usable slot in a string
SNEG:   .dd    0
SLNV:   .dd    0
SSRC:   .dd    0
CL:     .dd    76              ; 'L'
ACH:    .dd    0               ; the high half of the value the evaluator carries
EOPL:   .dd    0
EOPH:   .dd    0
ETMP:   .dd    0
FNTL:   .dd    0
NUMH:   .dd    0
T10H:   .dd    0
FNCY:   .dd    0
SXTV:   .dd    0
IFVH:   .dd    0
ECY:    .dd    0
CRR:    .dd    82              ; 'R'
MZCHR:  .dd    -91             ; -('Z'+1)
VPTRB:  .dd    VPTR
TPTRB:  .dd    TPTR
SPTRB:  .dd    SPTR
APTRB:  .dd    APTR
VLPT:   .dd    0
VLSZ:   .dd    0
VLB:    .dd    0
VLT:    .dd    0
VADR:   .dd    0
VVAL:   .dd    0
C26:    .dd    26
C520:   .dd    520
C104:   .dd    104
C20:    .dd    20
C16:    .dd    16
C5:     .dd    5
C4:     .dd    4
FL8:    .dd    0                ; head of the free list of small bodies
FL256:  .dd    0                ; and of large ones
SASZ:   .dd    0
SAP:    .dd    0
SAT:    .dd    0
C8:     .dd    8
C255:   .dd    255
C256:   .dd    256
SGOLD:  .dd    0
SGNEW:  .dd    0
SDLEN:  .dd    0
SGKEEP: .dd    0
VLN:    .dd    0
C63:    .dd    63
C37:    .dd    37
HEAPBV: .dd    HEAPB
HEAP:   .dd    HEAPB
VPTR:   .dd    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .dd    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .dd    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
TPTR:   .dd    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .dd    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .dd    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
SPTR:   .dd    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .dd    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .dd    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
APTR:   .dd    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .dd    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .dd    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
C27:    .dd    27
VN1:    .dd    0
VN2:    .dd    0
VNT:    .dd    0
RSEED:  .dd    12345
RMUL:   .dd    1229
RINC:   .dd    1
RMASK:  .dd    4095
SCH2:   .dd    0
CARET:  .dd    94              ; '^'
COLON:  .dd    58
CACHR:  .dd    65              ; 'A'
CETX:   .dd    3               ; control C
ERRC:   .dd    67              ; ?C interrupted
BRK:    .dd    0
PBASE:  .dd    0
PEXP:   .dd    0
PRES:   .dd    0
AADDR:  .dd    0
SVARI:  .dd    0
ASUB:   .dd    0
AVAL:   .dd    0
INPROG: .dd    0
BATCH:  .dd    0
STARC:  .dd    42              ; '*'
LOFF:   .dd    0
LBMAX:  .dd    62
LBLEN:  .dd    0
TEND:   .dd    0
TPOS:   .dd    0
TNEXT:  .dd    0
TVAL:   .dd    0
TMATCH: .dd    0
TGAP:   .dd    0
TSRC:   .dd    0
TDST:   .dd    0
TCH:    .dd    0
LBUF:   .dd    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .dd    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .dd    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .dd    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
KQ:     .dd    0
        .dd    0
        .dd    0
        .dd    0
        .dd    0
        .dd    0
        .dd    0
        .dd    0
KSHIFT: .dd    1
KCTRL:  .dd    2
MLCA:   .dd    -97             ; -'a'
MLCZ:   .dd    -123            ; -('z'+1)
M32:    .dd    -32
CC:     .dd    67              ; 'C'
C31:    .dd    31
C26:    .dd    26

        .include "arithlib.s"

        .advance 0x2400

; =====================================================================
; console: write only framebuffer, one character per 8 cycles, scroll by
; command with SKRDY as the completion test
; =====================================================================
PUTC:   PSH     IX
        SAD     NLC             ; skip when it is not a newline
        JMP     PNL
        LIX     CURS
        DAC     (SCRP) , X
        ISZ     CURS
        NOP
        LAC     CURS
        SAD     C512
        CAL     SCRL
        POP     IX
        RET
PNL:    LIX     CURS
        LAC     SPC
PNL1:   DAC     (SCRP) , X
        IXC
        DIX     CURS
        LAC     CURS
        SAD     C512
        JMP     PNLS
        LAC     CURS
        AND     C31
        SKNZ
        JMP     PNLD
        LAC     SPC
        JMP     PNL1
PNLS:   CAL     SCRL
PNLD:   POP     IX
        RET

SCRL:   SCROLL
SCRLW:  SKRDY                   ; the blitter answers for itself
        JMP     SCRLW
        LIX     C480
        LAC     SPC
SCRLF:  DAC     (SCRP) , X
        IXC
        SXD     C512
        JMP     SCRLD
        JMP     SCRLF
SCRLD:  LAC     C480
        DAC     CURS
        RET

; print AC as a decimal number
; the same as PNUM, over the thirty-six bit pair in MDH and MDL
PNUM36: PSH     IX
        CAL     DEC36
        LIX     DPOS
.loop:  SXD     DBEND
        JMP     .done
        LAC     (DBUFP) , X
        CAL     PUTC
        IXC
        JMP     .loop
.done:  POP     IX
        RET

PNUM:   PSH     IX              ; IX is the text pointer
        DAC     DVAL
        CAL     DEC
        LIX     DPOS
PNUML:  SXD     DBEND           ; skip while characters remain
        JMP     PNUMX
        LAC     (DBUFP) , X
        CAL     PUTC            ; PUTC saves IX for itself
        IXC
        JMP     PNUML
PNUMX:  POP     IX
        RET


; =====================================================================
; String variables.  A$ through Z$, twenty words each, NUL terminated, in a
; table of their own: A and A$ are different variables, exactly as in BASIC.
; SADDR holds the address of the one being worked on, computed as
; base + 20*index with shifts, since 20 = 16 + 4.
; =====================================================================

; print the string at SADDR
SPRINT: PSH     IX
        LIX     NIL
SPRNL:  LAC     (SADDR) , X
        SKNZ
        JMP     SPRND
        CAL     PUTC            ; PUTC saves IX for itself
        IXC
        JMP     SPRNL
SPRND:  POP     IX
        RET

; copy the string at SADDR2 to SADDR, truncating at the buffer size
SCOPY:  PSH     IX
        LIX     NIL
SCOPL:  SXD     SLM1            ; skip while there is room for one more
        JMP     SCOPT
        LAC     (SADDR2) , X
        DAC     (SADDR) , X
        SKNZ
        JMP     SCOPD
        IXC
        JMP     SCOPL
SCOPT:  CLA
        DAC     (SADDR) , X
SCOPD:  POP     IX
        RET


; =====================================================================
; Command level.  A line that starts with a number is filed away, anything
; else runs at once.  This is what separates an interpreter you converse with
; from one that is handed a program: the same BODY runs both, only the text
; pointer differs.
; =====================================================================
CMDL:   CLA
        DAC     BRK
        DAC     INPROG
        LAC     STARC
        CAL     PUTC
        CAL     RDLINE          ; GETK has already echoed the newline
        LAC     LBUFA           ; read from the typed line
        DAC     TXTP
        LIX     NIL
        CAL     SKSP
        LAC     (TXTP) , X
        SKNZ
        JMP     CMDL            ; nothing typed
        TAD     M0C
        DAC     DIGIT
                SKNM                    ; skip when not negative
        JMP     CMDEX
        LAC     DIGIT
        TAD     M10
                SKM                     ; skip when negative
        JMP     CMDEX           ; not a digit, so run it now
        CAL     STORE
        JMP     CMDL
CMDEX:  CAL     BODY
        LAC     INPROG          ; a GOTO moves us into the stored program
        SKNZ
        JMP     CMDL
RUNL:   CAL     STEP
        LAC     INPROG
        SKNZ
        JMP     CMDL
        JMP     RUNL

; read a line from the keyboard into LBUF
RDLINE: PSH     IX
        CLA
        DAC     LOFF
RDLL:   CAL     GETK
        SAD     NLC
        JMP     RDLD
        DAC     TCH
        LAC     LOFF
        SAD     LBMAX
        JMP     RDLL            ; full: the rest of the line is dropped
        LIX     LOFF
        LAC     TCH
        DAC     LBUF , X
        ISZ     LOFF
        NOP
        JMP     RDLL
RDLD:   LIX     LOFF
        CLA
        DAC     LBUF , X
        POP     IX
        RET

; index of the terminating zero of the stored program
TLEN:   PSH     IX
        LIX     NIL
TLENL:  LAC     (TXTB) , X
        SKNZ
        JMP     TLEND
        IXC
        JMP     TLENL
TLEND:  PSH     IX
        POP     AC
        DAC     TEND
        POP     IX
        RET

; number of the line at TPOS into TVAL, and TNEXT past its end
TNUM:   PSH     IX
        LIX     TPOS
        CLA
        DAC     TVAL
TNUML:  LAC     (TXTB) , X
        TAD     M0C
        DAC     DIGIT
                SKNM                    ; skip when not negative
        JMP     TNUMD
        LAC     DIGIT
        TAD     M10
                SKM                     ; skip when negative
        JMP     TNUMD
        LAC     TVAL
        SHA
        DAC     T10
        SHA
        SHA
        TAD     T10
        TAD     DIGIT
        DAC     TVAL
        IXC
        JMP     TNUML
TNUMD:  LAC     (TXTB) , X
        SKNZ
        JMP     TNUMF
        SAD     NLC
        JMP     TNUMG
        IXC
        JMP     TNUMD
TNUMG:  IXC
TNUMF:  PSH     IX
        POP     AC
        DAC     TNEXT
        POP     IX
        RET

; where line LNUM belongs: TPOS, and TMATCH when the number is already there
LFIND:  CLA
        DAC     TPOS
        DAC     TMATCH
LFL:    LAC     TPOS
        SAD     TEND
        JMP     LFDONE
        CAL     TNUM
        LAC     TVAL
        CIA
        TAD     LNUM
        SKNZ
        JMP     LFEQ
        AND     BIT17
        SKNZ
        JMP     LFNEXT          ; the new number is larger: keep looking
        JMP     LFDONE
LFEQ:   CLA
        IAC
        DAC     TMATCH
LFDONE: RET
LFNEXT: LAC     TNEXT
        DAC     TPOS
        JMP     LFL

; delete the line at TPOS, closing the gap
TDEL:   LAC     TNEXT
        CIA
        TAD     TPOS
        CIA
        DAC     TGAP
        LAC     TPOS
        DAC     TDST
        LAC     TNEXT
        DAC     TSRC
TDELL:  PSH     IX
        LIX     TSRC
        LAC     (TXTB) , X
        DAC     TCH
        LIX     TDST
        LAC     TCH
        DAC     (TXTB) , X
        POP     IX
        LAC     TCH
        SKNZ
        JMP     TDELD
        ISZ     TSRC
        NOP
        ISZ     TDST
        NOP
        JMP     TDELL
TDELD:  LAC     TEND
        CIA
        TAD     TGAP
        CIA
        DAC     TEND
        RET

; open a hole of TGAP words at TPOS, working from the top down
TINS:   LAC     TEND
        DAC     TSRC
        LAC     TEND
        TAD     TGAP
        DAC     TDST
TINSL:  PSH     IX
        LIX     TSRC
        LAC     (TXTB) , X
        DAC     TCH
        LIX     TDST
        LAC     TCH
        DAC     (TXTB) , X
        POP     IX
        LAC     TSRC
        SAD     TPOS
        JMP     TINSD
        LAC     TSRC
        TAD     MONE
        DAC     TSRC
        LAC     TDST
        TAD     MONE
        DAC     TDST
        JMP     TINSL
TINSD:  LAC     TEND
        TAD     TGAP
        DAC     TEND
        RET

; file the typed line away, replacing any line with the same number.  A bare
; number deletes that line, which is how FOCAL does it too.
STORE:  CAL     LIDROP          ; an edit moves text: every position after the
                                ; insertion point changes, so drop the index
                                ; and let the next jump rebuild it
        CAL     RDLNUM          ; LNUM, and LBODY at the first body character
        CAL     TLEN
        CAL     LFIND
        LAC     TMATCH
        SKNZ
        JMP     STNOD
        CAL     TDEL
STNOD:  CAL     LBLENF
        LAC     LBLEN
        SKNZ
        RET                     ; nothing but a number: the deletion is all
        TAD     ONE             ; room for the trailing newline too
        DAC     TGAP
        CAL     TINS
        CLA
        DAC     TSRC
        LAC     TPOS
        DAC     TDST
STCL:   PSH     IX
        LIX     TSRC
        LAC     LBUF , X
        DAC     TCH
        LIX     TDST
        LAC     TCH
        DAC     (TXTB) , X
        POP     IX
        LAC     TCH
        SKNZ
        JMP     STCD
        ISZ     TSRC
        NOP
        ISZ     TDST
        NOP
        JMP     STCL
STCD:   PSH     IX
        LIX     TDST
        LAC     NLC             ; the copied terminator becomes a newline
        DAC     (TXTB) , X
        POP     IX
        RET

; the number the typed line begins with
RDLNUM: PSH     IX
        LIX     NIL
        CLA
        DAC     LNUM
RDLNL:  LAC     LBUF , X
        TAD     M0C
        DAC     DIGIT
                SKNM                    ; skip when not negative
        JMP     RDLND
        LAC     DIGIT
        TAD     M10
                SKM                     ; skip when negative
        JMP     RDLND
        LAC     LNUM
        SHA
        DAC     T10
        SHA
        SHA
        TAD     T10
        TAD     DIGIT
        DAC     LNUM
        IXC
        JMP     RDLNL
RDLND:  POP     IX
        RET

; length of the typed line, zero when it is only a number and spaces
LBLENF: PSH     IX
        LIX     NIL
        CLA
        DAC     LBLEN
LBLL:   LAC     LBUF , X
        SKNZ
        JMP     LBLD
        IXC
        JMP     LBLL
LBLD:   PSH     IX
        POP     AC
        DAC     LBLEN
        POP     IX
        LAC     LBLEN
        SKNZ
        RET
        CAL     LBODYQ          ; a number with nothing after it deletes
        RET

; is there anything past the number and the spaces?
LBODYQ: PSH     IX
        LIX     NIL
LBQL:   LAC     LBUF , X
        TAD     M0C
                SKNM                    ; skip when not negative
        JMP     LBQ1
        IXC
        JMP     LBQL
LBQ1:   LAC     LBUF , X
        SAD     SPC
        JMP     LBQ2
        JMP     LBQ3
LBQ2:   IXC
        JMP     LBQ1
LBQ3:   LAC     LBUF , X
        SKNZ
        JMP     LBQE
        POP     IX
        RET
LBQE:   CLA
        DAC     LBLEN
        POP     IX
        RET

; =====================================================================
; Variables, two levels deep and allocated on demand.
;
; The second character of a name picks one of thirty-seven classes -- none, a
; letter, a digit -- and each class owns a block of twenty-six entries, one per
; first letter.  The class pointers live in the zero page and start empty; a
; block is carved off the heap the first time a name in that class is used.  A
; program that only writes A through Z therefore pays for twenty-six entries,
; not for the whole cross product, and no name has to be multiplied out: two
; indexed reads replace the stride arithmetic entirely.
;
; The four kinds are allocated separately, so a program with no strings never
; pays for the twenty words per letter that strings would want.
; =====================================================================
; VLOOK: VLPT names a pointer table, VLSZ the size of one block.  Returns the
; block base in AC, carving and clearing it if this class is new.
VLOOK:  PSH     IX
        LIX     VN2
        LAC     (VLPT) , X
        SKNZ
        JMP     VLNEW
        DAC     VLB
        POP     IX
        LAC     VLB
        RET
VLNEW:  LAC     HEAP
        DAC     VLB
        DAC     (VLPT) , X
        LAC     HEAP
        TAD     VLSZ
        DAC     HEAP
        LIX     NIL             ; a fresh block reads as zero
        CLA
VLCLR:  DAC     (VLB) , X
        IXC
        SXD     VLSZ
        JMP     VLCD
        JMP     VLCLR
VLCD:   POP     IX
        LAC     VLB
        RET

; the four kinds.  Each leaves an address, and only the strings and arrays need
; a stride, because a value and a type are one word each.
; =====================================================================
; String bodies come in two sizes, and nothing in between.
;
; Eight words holds seven characters and a terminator, which covers just over
; half the strings our programs actually write; 256 holds 255.  Two fixed sizes
; rather than a fit-anything allocator means the free lists are stacks -- the
; first word of a free block points at the next -- so releasing is two writes
; and there is no fragmentation, because there are no intermediate shapes to
; leave behind.
;
; Growing past a small body promotes it: take a large one, copy, give the small
; one back.  That is why a loop appending to a string does not exhaust the heap
; the way a bump allocator alone would.
; =====================================================================

; SALLOC: size in AC -> a cleared body in AC, off the free list when there is
;         one, off the heap when there is not
SALLOC: DAC     SASZ
        SAD     C8
        JMP     SAL8
        LAC     FL256
        JMP     SALT
SAL8:   LAC     FL8
SALT:   SKNZ
        JMP     SALNEW
        DAC     SAP             ; unlink the head
        PSH     IX
        LIX     NIL
        LAC     (SAP) , X
        POP     IX
        DAC     SAT
        LAC     SASZ
        SAD     C8
        JMP     SALU8
        LAC     SAT
        DAC     FL256
        JMP     SALCL
SALU8:  LAC     SAT
        DAC     FL8
        JMP     SALCL
SALNEW: LAC     HEAP
        DAC     SAP
        TAD     SASZ
        DAC     HEAP
SALCL:  PSH     IX              ; a body always starts empty
        LIX     NIL
        CLA
SALCLL: DAC     (SAP) , X
        IXC
        SXD     SASZ
        JMP     SALCD
        JMP     SALCLL
SALCD:  POP     IX
        LAC     SAP
        RET

; SFREE: body in SAP, its size in SASZ -> onto the matching list
SFREE:  LAC     SASZ
        SAD     C8
        JMP     SFR8
        LAC     FL256
        JMP     SFRL
SFR8:   LAC     FL8
SFRL:   PSH     IX
        LIX     NIL
        DAC     (SAP) , X       ; the old head becomes the next
        POP     IX
        LAC     SASZ
        SAD     C8
        JMP     SFRU8
        LAC     SAP
        DAC     FL256
        RET
SFRU8:  LAC     SAP
        DAC     FL8
        RET

; SGROW: the descriptor in VLB wants room for the length in AC.  Promotes a
;        small body to a large one when it no longer fits, and answers with the
;        capacity either way.
SGROW:  DAC     SAT
        LAC     VLB
        TAD     ONE
        TAD     ONE
        DAC     VADR            ; wh, the capacity
        PSH     IX
        LIX     NIL
        LAC     (VADR) , X
        POP     IX
        DAC     SASZ
        LAC     SAT
        IAC                     ; room for the terminator
        CIA
        TAD     SASZ
                SKM                    ; skip when it still fits
        JMP     SGRD
        LAC     SASZ            ; it does not: promote
        SAD     C256
        JMP     SGRD            ; already large, nothing bigger to go to
        LAC     VLB
        TAD     ONE
        DAC     SAP
        PSH     IX
        LIX     NIL
        LAC     (SAP) , X
        POP     IX
        DAC     SGOLD
        LAC     C256
        CAL     SALLOC
        DAC     SGNEW
        LAC     SADDR2          ; the caller's source has to survive the move
        DAC     SGKEEP
        LAC     SGOLD           ; carry the text across
        DAC     SADDR2
        LAC     SGNEW
        DAC     SADDR
        LAC     C255
        DAC     SLM1
        CAL     SCOPY
        LAC     SGOLD           ; and give the small body back
        DAC     SAP
        LAC     C8
        DAC     SASZ
        CAL     SFREE
        PSH     IX              ; publish the new body and capacity
        LIX     NIL
        LAC     VLB
        TAD     ONE
        DAC     VADR
        LAC     SGNEW
        DAC     (VADR) , X
        LAC     VLB
        TAD     ONE
        TAD     ONE
        DAC     VADR
        LAC     C256
        DAC     (VADR) , X
        POP     IX
        LAC     C256
        DAC     SASZ
        LAC     SGKEEP          ; and be handed back untouched
        DAC     SADDR2
SGRD:   LAC     SASZ
        TAD     MONE
        DAC     SLM1            ; the copy limit follows the real capacity
        LAC     SASZ
        RET

; SDEST: the destination name in SVAR, the length it must hold in AC.  Leaves
;        SADDR at a body big enough and SLM1 at its real capacity, promoting
;        the body first if the length no longer fits.  The three places that
;        write a string all come through here, so the growth rule lives once.
SDEST:  DAC     SDLEN
        LAC     SVAR
        DAC     TMPV
        CAL     VSTRA           ; VLB is the descriptor, SADDR its body
        LAC     SDLEN
        CAL     SGROW           ; may publish a new body
        LAC     SVAR
        DAC     TMPV
        CAL     VSTRA           ; refresh SADDR in case it moved
        RET

; A thirty-six bit variable lives in wl and wh, which the descriptor already
; puts side by side.  These two are the only places that know that.
VGETL:  CAL     VDESC
        DAC     VLB
        TAD     ONE
        DAC     VADR
        PSH     IX
        LIX     NIL
        LAC     (VADR) , X
        DAC     MDL
        POP     IX
        LAC     VLB
        TAD     ONE
        TAD     ONE
        DAC     VADR
        PSH     IX
        LIX     NIL
        LAC     (VADR) , X
        DAC     MDH
        POP     IX
        RET

VPUTL:  CAL     VDESC
        DAC     VLB
        TAD     ONE
        DAC     VADR
        PSH     IX
        LIX     NIL
        LAC     MDL
        DAC     (VADR) , X
        POP     IX
        LAC     VLB
        TAD     ONE
        TAD     ONE
        DAC     VADR
        PSH     IX
        LIX     NIL
        LAC     MDH
        DAC     (VADR) , X
        POP     IX
        RET

; WIDEN: the eighteen bit value in AC becomes a thirty-six bit pair, sign
;        extended, because a negative number stored as a bare low word would
;        read back as a large positive one.
WIDEN:  DAC     MDL
        AND     BIT17
        SKNZ
        JMP     .plus
        LAC     MONE            ; all ones in the high word
        DAC     MDH
        RET
.plus:  CLA
        DAC     MDH
        RET

; =====================================================================
; VDESC: the packed name in AC becomes the address of its descriptor.
;
; A variable is four words -- type, low, high, length -- and which types exist
; is our own list, so the type field holds a small number rather than anything
; structural:
;
;   0  integer, eighteen bits          wl = value
;   1  integer, thirty-six bits        wl, wh = value
;   2  float, eighteen bits            reserved
;   3  float, thirty-six bits          reserved
;   4  string                          wl = pointer, wh = capacity, len = length
;   5  array                           wl = pointer, wh = capacity, len = length
;
; Four words rather than three because 4n is two shifts while 3n needs a shift
; and an add, and the wasted word costs less than the arithmetic.
;
; The block for a class of second character is 26 descriptors, 104 words, and
; it is carved on first use like everything else here.  Type and value now sit
; one word apart, so a dispatch that used to walk two pointer tables and two
; blocks walks one of each -- which matters because nearly every site in the
; evaluator dispatches on the type before touching the value.
; =====================================================================
VDESC:  CAL     VUNP
        LAC     VPTRB
        DAC     VLPT
        LAC     C104
        DAC     VLSZ
        CAL     VLOOK
        DAC     VLB
        LAC     VN1
        SHA
        SHA                     ; four words each
        TAD     VLB
        RET

; The six calls the rest of the interpreter makes, now all four words apart
; from one descriptor rather than spread over four tables.
VGET:   CAL     VDESC
        TAD     ONE
        DAC     VADR
        PSH     IX
        LIX     NIL
        LAC     (VADR) , X
        POP     IX
        RET

VPUTV:  CAL     VDESC
        TAD     ONE
        DAC     VADR
        PSH     IX
        LIX     NIL
        LAC     VVAL
        DAC     (VADR) , X
        POP     IX
        RET

VTGET:  CAL     VDESC
        DAC     VADR
        PSH     IX
        LIX     NIL
        LAC     (VADR) , X
        POP     IX
        RET

VTPUTV: CAL     VDESC
        DAC     VADR
        PSH     IX
        LIX     NIL
        LAC     VVAL
        DAC     (VADR) , X
        POP     IX
        RET

; Strings and arrays hold a pointer now instead of living at a fixed stride, so
; the body is carved on first use.  The sizes are the ones they had before, so
; nothing observable changes yet; two size classes are the next step.
VSTRA:  LAC     TMPV            ; SVADDR's old contract: the name is in TMPV
        CAL     VBODY
        DAC     SADDR
        RET

; Arrays had no type field at all before, because they lived in a table of
; their own.  VARRA sets it, so a name used as an array is marked as one and
; VBODY can size the body from the type rather than guessing.
VARRA:  DAC     VLN
        CAL     VDESC
        DAC     VADR
        PSH     IX
        LIX     NIL
        LAC     (VADR) , X
        POP     IX
        SKNZ
        JMP     VARST
        JMP     VARGO
VARST:  PSH     IX
        LIX     NIL
        LAC     C5
        DAC     (VADR) , X
        POP     IX
VARGO:  LAC     VLN
        CAL     VBODY
        DAC     AADDR
        RET

; VBODY: the pointer at wl, allocated the first time it is asked for.  The size
; comes from the type, which VSTRA and VARRA have already set.
VBODY:  CAL     VDESC
        DAC     VLB
        TAD     ONE
        DAC     VADR
        PSH     IX
        LIX     NIL
        LAC     (VADR) , X
        POP     IX
        SKNZ
        JMP     VBNEW
        RET
VBNEW:  PSH     IX
        LIX     NIL
        LAC     (VLB) , X       ; the type says how big the body is
        POP     IX
        SAD     C5
        JMP     VBARR
        LAC     C8              ; strings start small and grow if they must
        JMP     VBALL
VBARR:  LAC     C16
        JMP     VBALL
VBALL:  DAC     VLSZ
        CAL     SALLOC
        DAC     VLT
        PSH     IX              ; publish the pointer and the capacity
        LIX     NIL
        LAC     VLT
        DAC     (VADR) , X
        POP     IX
        LAC     VLB
        TAD     ONE
        TAD     ONE             ; wh, the capacity
        DAC     VADR
        PSH     IX
        LIX     NIL
        LAC     VLSZ
        DAC     (VADR) , X
        POP     IX
        LAC     VLT
        RET

; =====================================================================
; VNAME: read a variable name at the text pointer, step past it, return its
; index.  A letter, then optionally a letter or a digit, and only the first two
; characters are significant -- FOCAL's own rule.  The second position takes
; thirty-seven values: nothing, A to Z, 0 to 9.  The stride is forty rather
; than thirty-seven because 40n is two shift chains and an add, while 37n needs
; three.  The three wasted slots per letter cost less than the multiply.
; =====================================================================
VNAME:  LAC     (TXTP) , X
        TAD     MACHR
        DAC     VN1
        IXC
        CLA
        DAC     VN2
        LAC     (TXTP) , X
        TAD     MACHR
                SKNM                     ; skip when the character is at least 'A'
        JMP     VNDIG
        LAC     (TXTP) , X
        TAD     MZCHR
                SKM                    ; skip when it is at most 'Z'
        JMP     VNDONE
        LAC     (TXTP) , X
        TAD     MACHR
        IAC                     ; letters occupy 1 to 26
        DAC     VN2
        IXC
        JMP     VNDONE
VNDIG:  LAC     (TXTP) , X
        TAD     M0C
                SKNM                    ; skip when not negative
        JMP     VNDONE
        LAC     (TXTP) , X
        TAD     M0C
        TAD     M10
                SKM                     ; skip when negative
        JMP     VNDONE
        LAC     (TXTP) , X
        TAD     M0C
        TAD     C27             ; digits occupy 27 to 36
        DAC     VN2
        IXC
VNDONE: LAC     VN2             ; packed as class*32 + letter, so the call
        SHA                     ; sites can go on holding a single word
        SHA
        SHA
        SHA
        SHA
        TAD     VN1
        RET

; unpack what VNAME made
VUNP:   DAC     VLT
        AND     C31
        DAC     VN1
        LAC     VLT
        SRA
        SRA
        SRA
        SRA
        SRA
        AND     C63
        DAC     VN2
        RET

; =====================================================================
; text access.  IX is the text pointer for the whole interpreter: reading the
; current character is one instruction and advancing is one more, so the two
; hottest operations in the scanner cost no call at all.  A routine that needs
; IX for its own indexing saves it first.
; =====================================================================
SKSP:   LAC     (TXTP) , X
        SAD     SPC             ; the next instruction runs when they match
        JMP     SKSP1
        RET
SKSP1:  IXC
        JMP     SKSP

; AC -> sign bit of AC, 0 or 1
; =====================================================================
; expression evaluator
; =====================================================================
; SEXT: fill ACH from AC's sign, leaving AC alone.  Every eighteen bit producer
;       in FACT ends here, so a word-sized value entering a thirty-six bit
;       expression behaves as the number it is rather than as a large positive.
SEXT:   DAC     SXTV            ; the value has to survive the masking
        AND     BIT17
        SKNZ
        JMP     .plus
        LAC     MONE
        DAC     ACH
        LAC     SXTV
        RET
.plus:  CLA
        DAC     ACH
        LAC     SXTV
        RET

FACT:   CAL     SKSP
        LAC     (TXTP) , X
        SAD     LPAR
        JMP     FPAR
        LAC     (TXTP) , X
        SAD     MINC
        JMP     FNEG
        LAC     (TXTP) , X
        SAD     CF              ; F starts a function, so F is not a variable
        JMP     FFUNC
        LAC     (TXTP) , X
        TAD     MACHR           ; below 'A' means a digit
                SKNM                    ; skip when not negative
        JMP     FNUM
        JMP     FVAR

FPAR:   IXC
        CAL     EXPR            ; the nested expression set ACH already; the
        PSH     AC              ; round trip through the stack must not lose it
        LAC     ACH
        PSH     AC
        CAL     SKSP
        IXC                 ; consume the ')'
        POP     AC
        DAC     ACH
        POP     AC
        RET

FNEG:   IXC
        CAL     FACT            ; negate the pair, not just the low word
        CMA
        DAC     FNTL
        LAC     ACH
        CMA
        DAC     ACH
        CLL
        LAC     FNTL
        TAD     ONE
        DAC     FNTL
        SKL
        JMP     .nc
        LAC     ACH
        IAC
        DAC     ACH
.nc:    LAC     FNTL
        RET

; FABS, FSGN, FITR, FSQT.  The second letter tells them apart except for the
; two beginning with S, where the third settles it.
FFUNC:  IXC
        LAC     (TXTP) , X
        SAD     CL              ; FLEN takes a string, not an expression
        JMP     FCLEN
        PSH     AC              ; the selector letters ride on the stack: the
        IXC                     ; argument may contain another function call,
        LAC     (TXTP) , X      ; and a global would be overwritten by it
        PSH     AC
        IXC
        IXC                     ; step over the fourth letter
        CAL     SKSP
        IXC                     ; and the open parenthesis
        CAL     EXPR
        DAC     FARG
        POP     AC
        DAC     FSEL2
        POP     AC
        DAC     FSEL
        CAL     SKSP
        IXC                     ; and the close parenthesis
        LAC     FSEL
        SAD     CA
        JMP     FCABS
        LAC     FSEL
        SAD     CI
        JMP     FCITR
        LAC     FSEL
        SAD     CRR
        JMP     FCRAN
        LAC     FSEL2
        SAD     CG
        JMP     FCSGN
        JMP     FCSQT

FFLEN:  IXC
        IXC
        IXC                     ; past LEN
        CAL     SKSP
        IXC                     ; the open parenthesis
        CAL     SKSP
        CAL     VNAME
        DAC     TMPV
        CAL     VSTRA
        CAL     SLENF
        DAC     SLNV
        CAL     SKSP
        IXC                     ; the close parenthesis
        LAC     SLNV
        RET

FCLEN:  CAL     FFLEN
        JMP     FCW
FCABS:  CAL     FNABS
        JMP     FCW
FCITR:  CAL     FNITR
        JMP     FCW
FCRAN:  CAL     FNRAN
        JMP     FCW
FCSGN:  CAL     FNSGN
        JMP     FCW
FCSQT:  CAL     FNSQT
; every function returns a word, so one widening here serves them all: without
; it the high half kept whatever the previous operand left behind, and FABS of
; a negative came back negative
FCW:    CAL     SEXT
        RET

FNABS:  LAC     FARG
        DAC     M1
        CAL     ABS1
        LAC     M1
        RET
FNITR:  LAC     FARG           ; already an integer
        RET
FNSGN:  LAC     FARG
        SKNZ
        RET
                SKM                     ; skip when negative
        JMP     FNSGP
        CLA
        CMA                     ; negative: -1
        RET
FNSGP:  CLA
        IAC
        RET
; FRAN(n) is a random value in 0..n-1.  FOCAL's FRAN returns a fraction, which
; an integer machine has no way to represent, so the argument gives the range
; instead: a deliberate change, not an approximation of the original.
FNRAN:  LAC     RSEED
        DAC     M1
        LAC     RMUL
        DAC     M2
        CAL     MUL
        TAD     RINC
        DAC     RSEED
        SRA                     ; the low bits of an LCG are the weak ones
        SRA
        SRA
        SRA
        SRA
        SRA
        AND     RMASK
        DAC     M1
        LAC     FARG
        SKNZ
        RET                     ; FRAN(0) is zero, not a division by zero
        DAC     M2
        CAL     DIV
        LAC     MREM
        RET

FNSQT:  LAC     FARG
        DAC     M1
        CAL     ABS1
        CAL     ISQRT
        LAC     MRES
        RET

FVAR:   CAL     VNAME
        DAC     TMPV
        LAC     (TXTP) , X
        SAD     LPAR
        JMP     FARR
        LAC     TMPV
        CAL     VTGET
        SKZ                     ; a string here reads as the number it spells
        JMP     FVNZ
        LAC     TMPV
        CAL     VGET
        CAL     SEXT
        RET
FVNZ:   SAD     ONE             ; type 1 brings its own high word
        JMP     FVLONG
        JMP     FVARS
FVLONG: LAC     TMPV
        CAL     VGETL
        LAC     MDH
        DAC     ACH
        LAC     MDL
        RET
FARR:   LAC     TMPV
        DAC     SVARI
        IXC                     ; the open parenthesis
        CAL     EXPR
        DAC     TMPV
        CAL     SKSP
        IXC                     ; the close parenthesis
        CAL     AVADDR
        PSH     IX
        LIX     NIL
        LAC     (AADDR) , X
        POP     IX
        RET

FVARS:  CAL     VSTRA
        CAL     SVNUM
        RET

; the leading signed integer of the string at SADDR
SVNUM:  PSH     IX
        LIX     NIL
        CLA
        DAC     NUM
        DAC     SNEG
        LAC     (SADDR) , X
        SAD     MINC
        JMP     SVNM
        JMP     SVNL
SVNM:   CLA
        IAC
        DAC     SNEG
        IXC
SVNL:   LAC     (SADDR) , X
        TAD     M0C
        DAC     DIGIT
                SKNM                    ; skip when not negative
        JMP     SVND
        LAC     DIGIT
        TAD     M10
                SKM                     ; skip when negative
        JMP     SVND
        LAC     NUM
        SHA
        DAC     T10
        SHA
        SHA
        TAD     T10
        TAD     DIGIT
        DAC     NUM
        IXC
        JMP     SVNL
SVND:   POP     IX
        LAC     SNEG
        SKNZ
        JMP     SVNP
        LAC     NUM
        CIA
        RET
SVNP:   LAC     NUM
        RET

; The address of element TMPV of the array named by SVARI.  The descriptor
; carries the capacity now, so a subscript past the end is detectable where it
; used to run silently into whatever followed.
AVADDR: LAC     SVARI
        CAL     VARRA
        DAC     AVB
        LAC     VLB             ; wh, the capacity the body was given
        TAD     ONE
        TAD     ONE
        DAC     VADR
        PSH     IX
        LIX     NIL
        LAC     (VADR) , X
        POP     IX
        CIA
        TAD     TMPV            ; subscript - capacity
                SKM                    ; skip when the subscript is below it
        JMP     AVERR
        LAC     AVB
        TAD     TMPV
        DAC     AADDR
        RET
AVERR:  LAC     ERRB
        JMP     ERROR

; length of the string at SADDR
SLENF2: PSH     IX              ; the same count, over SADDR2
        LIX     NIL
SLEN2L: LAC     (SADDR2) , X
        SKNZ
        JMP     SLEN2D
        IXC
        JMP     SLEN2L
SLEN2D: PSH     IX
        POP     AC
        DAC     SLNV
        POP     IX
        LAC     SLNV
        RET

SLENF:  PSH     IX
        LIX     NIL
SLENL:  LAC     (SADDR) , X
        SKNZ
        JMP     SLEND
        IXC
        JMP     SLENL
SLEND:  PSH     IX
        POP     AC
        DAC     SLNV
        POP     IX
        LAC     SLNV
        RET

; The literal accumulates in a pair, not a word.  Two reasons: a constant
; larger than a word can then be written down at all, and 131072 stops being
; read as its own negative -- as a bare low word its sign bit is set, so
; widening turned it into -131072 and the unary minus gave +131072 back.
;
; Times ten is still three doublings and an add, only over the pair: doubling
; chains LSL into RLA, so the low word's top bit arrives at the high word's
; bottom.
FNUM:   CLA
        DAC     NUM
        DAC     NUMH
FNUML:  LAC     (TXTP) , X
        TAD     M0C
        DAC     DIGIT
                SKNM                    ; skip when not negative
        JMP     FNUMD           ; below '0'
        LAC     DIGIT
        TAD     M10
                SKM                     ; skip when negative
        JMP     FNUMD           ; above '9'
        CAL     FNDBL           ; times two, kept aside
        LAC     NUM
        DAC     T10
        LAC     NUMH
        DAC     T10H
        CAL     FNDBL           ; times four
        CAL     FNDBL           ; times eight
        CLL                     ; plus the two, giving ten.  The carry out of
        LAC     NUM             ; the low add has to be taken before the high
        TAD     T10             ; add overwrites the link with its own
        DAC     NUM
        GLK
        DAC     FNCY
        LAC     NUMH
        TAD     T10H
        TAD     FNCY
        DAC     NUMH
FN10:   CLL                     ; plus the digit
        LAC     NUM
        TAD     DIGIT
        DAC     NUM
        GLK
        DAC     FNCY
        LAC     NUMH
        TAD     FNCY
        DAC     NUMH
FN11:   IXC
        JMP     FNUML

; double the pair in NUMH and NUM
FNDBL:  LAC     NUM
        LSL
        DAC     NUM
        LAC     NUMH
        RLA
        DAC     NUMH
        RET

FNUMD:  LAC     NUMH
        DAC     ACH
        LAC     NUM
        RET

; POWER := FACT { ^ FACT }, so the exponent binds tighter than * and /
POWER:  CAL     FACT
POWL:   PSH     AC
        CAL     SKSP
        LAC     (TXTP) , X
        SAD     CARET
        JMP     POWC
        POP     AC
        RET
POWC:   IXC
        CAL     FACT
        DAC     PEXP
        POP     AC
        DAC     PBASE
        CLA
        IAC
        DAC     PRES
        LAC     PEXP            ; a negative exponent is zero in integers
                SKNM                    ; skip when not negative
        JMP     POWZ
POWLP:  LAC     PEXP
        SKNZ
        JMP     POWD
        LAC     PRES
        DAC     M1
        LAC     PBASE
        DAC     M2
        CAL     MUL
        DAC     PRES
        LAC     PEXP
        TAD     MONE
        DAC     PEXP
        JMP     POWLP
POWZ:   CLA
        DAC     PRES
POWD:   LAC     PRES
        JMP     POWL

TERM:   CAL     POWER
TERML:  PSH     AC              ; the pair, low word first
        LAC     ACH
        PSH     AC
        CAL     SKSP
        LAC     (TXTP) , X
        SAD     STAR
        JMP     TSTAR
        LAC     (TXTP) , X
        SAD     SLASH
        JMP     TSLASH
        POP     AC
        DAC     ACH
        POP     AC
        RET
; A product of two words needs thirty-six bits to be exact, which is the whole
; reason the channel exists: MUL kept the low half and threw the rest away.
TSTAR:  IXC
        CAL     POWER
        DAC     M2
        POP     AC              ; the left operand's high half is discarded:
        POP     AC              ; the product of two words is exact in the pair
        DAC     M1
        CAL     MULS36
        LAC     MDH
        DAC     ACH
        LAC     MDL
        JMP     TERML
; Division takes the whole thirty-six bits of the left operand, so a quotient
; that fits a word comes out right even when the dividend did not.
TSLASH: IXC
        CAL     POWER
        DAC     M2
        POP     AC
        DAC     MDH
        POP     AC
        DAC     MDL
        CAL     DIVS36
        LAC     MDH
        DAC     ACH
        LAC     MDL
        JMP     TERML

; The evaluator carries thirty-six bits: AC is the low half and ACH the high.
; Callers that only want a word read AC and ignore ACH, which is every caller
; that existed before this -- the widening is invisible to them.  Intermediates
; go on the stack as a pair, low first so the high pops off the top.
EXPR:   CAL     TERM
EXPRL:  PSH     AC              ; the pair, low word first
        LAC     ACH
        PSH     AC
        CAL     SKSP
        LAC     (TXTP) , X
        SAD     PLUSC
        JMP     EPLUS
        LAC     (TXTP) , X
        SAD     MINC
        JMP     EMIN
        POP     AC              ; nothing to combine: unwind the pair
        DAC     ACH
        POP     AC
        RET
EPLUS:  IXC
        CAL     TERM
        DAC     EOPL            ; the right operand
        LAC     ACH
        DAC     EOPH
        POP     AC              ; the left operand back off the stack
        DAC     ACH
        POP     AC
        CLL                     ; low halves first, and the carry out has to be
        TAD     EOPL            ; taken before the high add overwrites the link
        DAC     ETMP
        GLK
        DAC     ECY
        LAC     ACH
        TAD     EOPH
        TAD     ECY
        DAC     ACH
EPNC:   LAC     ETMP
        JMP     EXPRL
EMIN:   IXC
        CAL     TERM
        DAC     EOPL            ; negate the right operand, then add
        LAC     ACH
        DAC     EOPH
        LAC     EOPL
        CMA
        DAC     EOPL
        LAC     EOPH
        CMA
        DAC     EOPH
        CLL
        LAC     EOPL
        TAD     ONE
        DAC     EOPL
        GLK
        DAC     ECY
        LAC     EOPH
        TAD     ECY
        DAC     EOPH
EMNC:   POP     AC
        DAC     ACH
        POP     AC
        CLL
        TAD     EOPL
        DAC     ETMP
        GLK
        DAC     ECY
        LAC     ACH
        TAD     EOPH
        TAD     ECY
        DAC     ACH
EMNC2:  LAC     ETMP
        JMP     EXPRL

; =====================================================================
; line handling
; =====================================================================
; parse an unsigned integer at the text pointer into AC, no sign, no expression
RDNUM:  CLA
        DAC     NUM
RDNL:   LAC     (TXTP) , X
        TAD     M0C
        DAC     DIGIT
                SKNM                    ; skip when not negative
        JMP     RDND
        LAC     DIGIT
        TAD     M10
                SKM                     ; skip when negative
        JMP     RDND
        LAC     NUM             ; num*10 = num*8 + num*2, three shifts and an
        SHA                     ; add: the general multiplier is far too much
        DAC     T10             ; machinery for a constant
        SHA
        SHA
        TAD     T10
        TAD     DIGIT
        DAC     NUM
        IXC
        JMP     RDNL
RDND:   LAC     NUM
        RET

; step the text pointer past the end of the current line
EOL:    LAC     (TXTP) , X
        SKNZ
        RET                     ; end of text
        SAD     NLC             ; skip when not a newline
        JMP     EOL1
        IXC
        JMP     EOL
EOL1:   IXC
        RET

; position the text pointer at the body of the line numbered TARG
; =====================================================================
; The line index, a rope.
;
; FINDL used to walk the program text a character at a time, and since every
; GOTO, IF and DO starts that walk from the beginning, the cost was quadratic
; in the text: on an eighty line program a third of all cycles went into EOL.
;
; The index holds one pair per line, <number, position>, in chunks of 256
; words: 127 pairs, then the count, then a link to the next chunk.  Chunks come
; off the same bump allocator as everything else, so a short program pays for
; one chunk and a long one grows a chain -- there is no worst case reserved up
; front.  Lines are stored in ascending order, so the pairs are sorted and the
; search could be halved further; it is linear for now because linear over a
; hundred words already replaces a walk over thousands of characters.
;
; Any edit moves text and invalidates every position after it, so STORE and
; ERASE just drop the index and the next search rebuilds it.  That trades one
; scan per edit for none per jump.
; =====================================================================

; LIDROP: forget the index
LIDROP: CLA
        DAC     LIROOT
        RET

; LINEW: carve a chunk, clear its count and link, return its base in AC
LINEW:  LAC     HEAP
        DAC     LIT
        TAD     C256
        DAC     HEAP
        PSH     IX
        LIX     C254
        CLA
        DAC     (LIT) , X       ; the count
        IXC
        DAC     (LIT) , X       ; the link
        POP     IX
        LAC     LIT
        RET

; LIADD: append the pair in LIN and LIP to the chunk in LICUR, chaining on
LIADD:  PSH     IX
        LIX     C254
        LAC     (LICUR) , X
        DAC     LICNT
        SAD     C127
        JMP     LIFULL
        JMP     LIROOM
LIFULL: POP     IX
        CAL     LINEW           ; the chunk is full: link a fresh one
        DAC     LIT
        PSH     IX
        LIX     C255
        LAC     LIT
        DAC     (LICUR) , X
        POP     IX
        LAC     LIT
        DAC     LICUR
        CLA
        DAC     LICNT
        PSH     IX
LIROOM: LAC     LICNT           ; the pair goes at twice the count
        SHA
        DAC     LIT
        LIX     LIT
        LAC     LIN
        DAC     (LICUR) , X
        IXC
        LAC     LIP
        DAC     (LICUR) , X
        LIX     C254
        LAC     LICNT
        IAC
        DAC     (LICUR) , X
        POP     IX
        RET

; LIBUILD: one pass over the text, appending a pair per line
LIBUILD: CAL    LINEW
        DAC     LIROOT
        DAC     LICUR
        PSH     IX
        LIX     NIL
LIBL:   LAC     (TXTB) , X
        SKNZ
        JMP     LIBD
        SXD     NIL             ; remember where this line starts
        JMP     LIBP
LIBP:   PSH     IX
        POP     AC
        IAC                     ; stored one past, so that zero can mean absent
        DAC     LIP
        CAL     LISKSP
        CAL     LIRDN           ; the line number
        DAC     LIN
        CAL     LIEOL
        LAC     LIN
        SKNZ
        JMP     LIBL            ; a line with no number cannot be jumped to
        PSH     IX
        CAL     LIADD
        POP     IX
        JMP     LIBL
LIBD:   POP     IX
        RET

; the three scanners above, reading TXTB rather than TXTP
LISKSP: LAC     (TXTB) , X
        SAD     SPC
        JMP     LISK1
        RET
LISK1:  IXC
        JMP     LISKSP

LIRDN:  CLA                     ; its own scratch: LIP holds the position the
        DAC     LIRA            ; caller saved before calling in here
LIRDL:  LAC     (TXTB) , X
        TAD     M0C
        DAC     LIRD
                SKNM                    ; skip when not negative
        JMP     LIRDD
        LAC     LIRD
        TAD     M10
                SKM                     ; skip when negative
        JMP     LIRDD
        LAC     LIRA            ; times ten, three shifts and an add
        SHA
        DAC     LIRT
        SHA
        SHA
        TAD     LIRT
        TAD     LIRD
        DAC     LIRA
        IXC
        JMP     LIRDL
LIRDD:  LAC     LIRA
        RET

LIEOL:  LAC     (TXTB) , X
        SKNZ
        RET
        SAD     NLC
        JMP     LIEO1
        IXC
        JMP     LIEOL
LIEO1:  IXC
        RET

; LILOOK: TARG -> the position of that line in AC, or zero when absent
LILOOK: LAC     LIROOT
        SKNZ
        JMP     LILB
        JMP     LILGO
LILB:   CAL     LIBUILD
LILGO:  LAC     LIROOT
        DAC     LICUR
LILC:   PSH     IX
        LIX     C254
        LAC     (LICUR) , X
        DAC     LICNT
        POP     IX
        CLA
        DAC     LIT
LILE:   LAC     LIT
        SAD     LICNT
        JMP     LILNX
        LAC     LIT
        SHA
        DAC     LIN
        PSH     IX
        LIX     LIN
        LAC     (LICUR) , X
        SAD     TARG
        JMP     LILHIT
        POP     IX
        ISZ     LIT
        NOP
        JMP     LILE
LILHIT: IXC
        LAC     (LICUR) , X
        POP     IX
        RET
LILNX:  PSH     IX
        LIX     C255
        LAC     (LICUR) , X
        POP     IX
        SKNZ
        JMP     LILMISS
        DAC     LICUR
        JMP     LILC
LILMISS: CLA
        RET

FIND:   LAC     TXTB            ; a jump always lands in the stored program
        DAC     TXTP
        CLA
        IAC
        DAC     INPROG
        LIX     NIL
FINDL:  CAL     LILOOK          ; one lookup instead of a walk
        SKNZ
        JMP     FINDX           ; no such line: stop the program
        TAD     MONE            ; undo the bias the index stores
        DAC     LIT
        LIX     LIT
        CAL     SKSP
        CAL     RDNUM           ; leave IX past the number, as the walk did
        RET
FINDX:  JMP     STOP

; =====================================================================
; commands
; =====================================================================
RUN:    LIX     NIL             ; IX is the text pointer from here on
NEXT:   CAL     STEP
        LAC     INPROG          ; QUIT or the end of the text clears it
        SKNZ
        JMP     STOP
        JMP     NEXT

; STEP executes exactly one line and returns.  Making it a subroutine is what
; lets DO run a line from inside another line: the nesting rides on the
; hardware stack, with no interpreter state to save.
STEP:   LAC     BRK
        SKNZ
        JMP     STEP1
        LAC     ERRC
        JMP     ERROR
STEP1:  CAL     SKSP
        LAC     (TXTP) , X
        SKNZ
        JMP     ENDRUN
        CAL     RDNUM
        DAC     LNUM
BODY:   CAL     SKSP
; Dispatch through a table instead of a chain of comparisons.  Indexing by
; the low five bits of the command letter needs no range check: 'A'..'Z' map
; onto 1..26 and anything else lands on an entry that skips the line.  The
; table holds jumps rather than addresses, because the machine indirects once,
; not twice.
        LAC     (TXTP) , X
        AND     C31
        DAC     TMPV
        DIX     TPSAVE          ; park the text pointer, IX becomes the index
        LIX     TMPV
        CAL     (CTABP) , X     ; the table holds jumps, so a CAL through it
        LAC     MORE            ; lands in the handler and returns here
        SKNZ
        RET
        JMP     BODY

; SET v = expression
DOSET:  LIX     TPSAVE
        CAL     SKIPW
        CAL     SKSP
        CAL     VNAME
        DAC     SVAR            ; not TMPV: the evaluator uses that one
        LAC     (TXTP) , X
        SAD     LPAR
        JMP     DOSARR
        CAL     SKSP
        LAC     (TXTP) , X
        SAD     EQ
        JMP     DOSASN
        CAL     DECLAR          ; no equals sign, so it must be AS <type>
        CAL     SKSP
        LAC     (TXTP) , X
        SAD     EQ              ; a declaration may assign in the same breath
        JMP     DOSASN
        CAL     EOS
        RET

; SET v(i) = expression
DOSARR: LAC     SVAR
        DAC     SVARI
        IXC
        CAL     EXPR
        DAC     ASUB
        CAL     SKSP
        IXC                     ; the close parenthesis
        CAL     SKSP
        IXC                     ; the equals sign
        CAL     EXPR
        DAC     AVAL
        LAC     ASUB
        DAC     TMPV
        CAL     AVADDR
        PSH     IX
        LIX     NIL
        LAC     AVAL
        DAC     (AADDR) , X
        POP     IX
        CAL     EOS
        RET

; SET v AS INT | STRING | FLOAT.  The type lives in a table beside the
; variables rather than in the spelling of the name, so a new type costs a
; table entry instead of a new sigil.
DECLAR: IXC
        IXC                     ; past AS
        CAL     SKSP
        LAC     (TXTP) , X
        DAC     TMPV            ; the initial tells the types apart
        CAL     SKIPT
        LAC     TMPV
        SAD     CI
        JMP     DECLI
        LAC     TMPV
        SAD     CS
        JMP     DECLS
        LAC     TMPV
        SAD     CL              ; LONG: the thirty-six bit integer, type 1
        JMP     DECLL
        LAC     TMPV
        SAD     CF
        JMP     DECLF
        LAC     ERRT
        JMP     ERROR
DECLI:  CLA
        JMP     DECLST
DECLL:  CLA
        IAC                     ; 1 is the thirty-six bit integer
        JMP     DECLST
DECLS:  LAC     C4              ; 4 is string in the descriptor's numbering
        JMP     DECLST
DECLF:  LAC     ERRF            ; float has no implementation to declare
        JMP     ERROR
DECLST: DAC     SCH
        LAC     SCH
        DAC     VVAL
        LAC     SVAR
        CAL     VTPUTV
        RET

; ?x and stop, because a wrong declaration cannot be shrugged off the way an
; unrecognised command can
ERROR:  DAC     SCH
        LAC     QMARK
        CAL     PUTC
        LAC     SCH
        CAL     PUTC
        LAC     NLC
        CAL     PUTC
        LAC     BATCH           ; with no operator to talk to there is nowhere
        SKZ                     ; to return: stop
        JMP     STOP
        CLA                     ; abandon whatever was on the stack and go
        PSH     AC              ; back to command level
        POP     SP
        JMP     CMDL

DOSASN: IXC                     ; the equals sign
        CAL     SKSP
        LAC     SVAR
        CAL     VTGET
        SKZ                     ; skip when the type is integer
        JMP     DOSNZ
        JMP     DOSINT
DOSNZ:  SAD     ONE             ; type 1 is the thirty-six bit integer
        JMP     DOSLNG
        JMP     DOSSTR
DOSLNG: CAL     EXPR            ; the evaluator already carries both halves, so
        DAC     MDL             ; widening here would throw the high one away
        LAC     ACH
        DAC     MDH
        LAC     SVAR
        CAL     VPUTL
        CAL     EOS
        RET
DOSINT: CAL     EXPR            ; integer: the ordinary path
        DAC     VVAL
        LAC     SVAR
        CAL     VPUTV
        CAL     EOS
        RET

; the right hand side of a string assignment: a literal, a bare string
; variable, or a number to be spelled out
DOSSTR: LAC     SVAR
        DAC     TMPV
        CAL     VSTRA
        LAC     (TXTP) , X
        SAD     QUOTE
        JMP     SETSL
        LAC     (TXTP) , X
        TAD     MACHR
                SKNM                    ; skip when not negative
        JMP     SETSN
        IXC                     ; a letter: bare, or the start of a sum?
        LAC     (TXTP) , X
        DAC     SCH
        TADX    MONE
        LAC     SCH
        SKNZ
        JMP     SETSB
        LAC     SCH
        SAD     NLC
        JMP     SETSB
        LAC     SCH
        SAD     SEMI
        JMP     SETSB
        JMP     SETSN

; A bare variable on the right: copy it when it is itself a string, spell it
; out when it is an integer.  The source's declared type decides, not the
; destination's.
SETSB:  PSH     IX
        CAL     VNAME
        DAC     SCH2
        POP     IX
        LAC     SCH2
        CAL     VTGET
        SKZ                     ; skip when the source is an integer
        JMP     SETSV
        JMP     SETSN
SETSV:  CAL     VNAME
        DAC     TMPV
        CAL     VSTRA
        LAC     SADDR
        DAC     SADDR2          ; source
        CAL     SLENF2          ; how much has to fit
        CAL     SDEST
        CAL     SCOPY
        CAL     EOS
        RET

; a number on the right hand side becomes its decimal spelling
SETSN:  LAC     SADDR
        PSH     AC              ; the expression may itself read a string
        CAL     EXPR
        DAC     DVAL
        CAL     DEC
        POP     AC
        DAC     SADDR
        CLA
        DAC     SOFF
        LAC     DPOS
        DAC     SSRC
SETSNL: LAC     SSRC
        SAD     DBEND
        JMP     SETSND
        PSH     IX
        LIX     SSRC
        LAC     (DBUFP) , X
        DAC     SCH
        LIX     SOFF
        LAC     SCH
        DAC     (SADDR) , X
        POP     IX
        ISZ     SSRC
        NOP
        ISZ     SOFF
        NOP
        JMP     SETSNL
SETSND: PSH     IX
        LIX     SOFF
        CLA
        DAC     (SADDR) , X
        POP     IX
        CAL     EOS
        RET

; The literal's length is known before a character is copied -- scan to the
; closing quote and count -- so the destination can be grown once rather than
; truncated.  Without this a literal longer than a small body would be cut at
; eight characters instead of promoting.
SETSL:  IXC                     ; past the opening quote
        PSH     IX
        CLA
        DAC     SOFF
SETSLM: LAC     (TXTP) , X
        SKNZ
        JMP     SETSLE
        SAD     QUOTE
        JMP     SETSLE
        ISZ     SOFF
        NOP
        IXC
        JMP     SETSLM
SETSLE: POP     IX
        LAC     SOFF
        CAL     SDEST
        CLA
        DAC     SOFF
SETSL1: LAC     (TXTP) , X
        SKNZ
        JMP     SETSLD
        SAD     QUOTE
        JMP     SETSLQ
        DAC     SCH
        PSH     IX
        LIX     SOFF
        LAC     SCH
        DAC     (SADDR) , X
        POP     IX
        ISZ     SOFF
        NOP
        IXC
        LAC     SOFF
        SAD     SLM1
        JMP     SETSLD
        JMP     SETSL1
SETSLQ: IXC
SETSLD: PSH     IX
        LIX     SOFF
        CLA
        DAC     (SADDR) , X
        POP     IX
        CAL     EOS
        RET


; TYPE item {, item}   where item is "string" or ! or an expression
DOTYPE: LIX     TPSAVE
        CAL     SKIPW
DOTYL:  CAL     SKSP
        LAC     (TXTP) , X
        SKNZ
        JMP     DOTYD
        SAD     NLC
        JMP     DOTYD
        LAC     (TXTP) , X
        SAD     QUOTE
        JMP     DOTYS
        LAC     (TXTP) , X
        SAD     BANG
        JMP     DOTYB
        LAC     (TXTP) , X      ; A variable declared as a string prints as
        TAD     MACHR           ; text when it stands alone.  Followed by an
                SKNM                     ; text spells.  A name is one or two characters,
        JMP     DOTYN           ; so the only way back is to remember where it
        PSH     IX              ; began rather than to step back by one.
        CAL     VNAME
        DAC     TMPV
        LAC     (TXTP) , X
        DAC     SCH
        POP     IX
        LAC     TMPV
        CAL     VTGET
        SKNZ
        JMP     DOTYN           ; an integer: evaluate it
        SAD     ONE             ; type 1 prints as thirty-six bits, which the
        JMP     DOTYLG          ; eighteen bit evaluator cannot carry
        LAC     SCH
        SAD     COMMA
        JMP     DOTYSV
        LAC     SCH
        SAD     NLC
        JMP     DOTYSV
        LAC     SCH
        SAD     SEMI
        JMP     DOTYSV
        LAC     SCH
        SKNZ
        JMP     DOTYSV
        JMP     DOTYN
DOTYN:  CAL     EXPR
        CAL     PNUM
        JMP     DOTYC
; A thirty-six bit variable standing alone prints in full; used inside an
; expression it would have to be truncated, so it is only taken alone.
DOTYLG: CAL     VNAME
        CAL     VGETL
        CAL     PNUM36
        JMP     DOTYC

DOTYSV: CAL     VNAME
        DAC     TMPV
        CAL     VSTRA
        CAL     SPRINT
        JMP     DOTYC
DOTYB:  IXC
        LAC     NLC
        CAL     PUTC
        JMP     DOTYC
DOTYS:  IXC
DOTYS1: LAC     (TXTP) , X
        SKNZ
        JMP     DOTYD
        SAD     QUOTE
        JMP     DOTYS2
        CAL     PUTC
        IXC
        JMP     DOTYS1
DOTYS2: IXC
DOTYC:  CAL     SKSP
        LAC     (TXTP) , X
        SAD     COMMA
        JMP     DOTYM           ; a comma: another item follows
        JMP     DOTYD
DOTYM:  IXC
        JMP     DOTYL
DOTYD:  CAL     EOS
        RET

; IF (expression) neg, zero, pos
DOIF: LIX     TPSAVE
        CAL     SKIPW
        CAL     SKSP
        IXC                 ; consume the '('
        CAL     EXPR
        DAC     IFV
        LAC     ACH             ; the sign of a thirty-six bit value lives in
        DAC     IFVH            ; the high word, and a low word that happens to
        CAL     SKSP            ; look negative would send the test the wrong way
        IXC                 ; consume the ')'
        LAC     IFV
        SKNZ
        JMP     DOIFHZ
        JMP     DOIFNZ
DOIFHZ: LAC     IFVH            ; low word zero: the high one decides
        SKNZ
        JMP     DOIFZ
DOIFNZ: LAC     IFVH
                SKM                    ; sign set means negative
        JMP     DOIFP
        CLA                     ; negative: first target
        DAC     ARGN
        JMP     DOIFG
DOIFZ:  CLA
        IAC
        DAC     ARGN
        JMP     DOIFG
DOIFP:  CLA
        IAC
        IAC
        DAC     ARGN
DOIFG:  CAL     SKSP            ; walk to the selected target
        CAL     RDNUM
        DAC     TARG
        LAC     ARGN
        SKNZ
        JMP     DOIFJ
        DSZ     ARGN
        NOP
        CAL     SKSP
        LAC     (TXTP) , X
        SAD     COMMA           ; fewer targets than arms: fall through to
        JMP     DOIFN           ; the next line, which is what FOCAL does
        CAL     EOS
        RET
DOIFN:  IXC
        JMP     DOIFG
DOIFJ:  CAL     FIND
        CLA
        DAC     MORE
        RET

; GOTO n
DOGOTO: LIX     TPSAVE
        CAL     SKIPW
        CAL     SKSP
        CAL     RDNUM
        DAC     TARG
        CAL     FIND
        CLA
        DAC     MORE
        RET


; WRITE: list the stored program
DOWRIT: LIX     TPSAVE
        CAL     EOL
        PSH     IX
        LIX     NIL
DOWR1:  LAC     (TXTB) , X      ; the stored program, not the line just typed
        SKNZ
        JMP     DOWR2
        CAL     PUTC
        IXC
        JMP     DOWR1
DOWR2:  POP     IX
        RET

; ERASE: clear every variable
; ERASE drops every block instead of walking every variable: the class
; pointers go empty and the heap rewinds, which is the whole of it.
DOERAS: CAL     LIDROP
        LIX     TPSAVE
        CAL     EOL
        PSH     IX
        LIX     NIL
        CLA
DOER1:  DAC     (VPTRB) , X
        DAC     (TPTRB) , X
        DAC     (SPTRB) , X
        DAC     (APTRB) , X
        IXC
        SXD     C37
        JMP     DOER2
        JMP     DOER1
DOER2:  LAC     HEAPBV
        DAC     HEAP
        POP     IX
        RET

; DO n: run line n as a subroutine, then carry on after the DO.
; The nesting lives on the hardware stack, so DO inside DO costs nothing
; beyond two words per level and needs no interpreter state at all.
DODO:   LIX     TPSAVE
        CAL     SKIPW
        CAL     SKSP
        CAL     RDNUM
        DAC     TARG
        CAL     EOL             ; IX now points at the line after this one
        PSH     IX
        CAL     FIND            ; IX at the body of line TARG
        CAL     STEP            ; run it
        POP     IX
        CLA
        DAC     MORE
        RET

; ASK v {, v}: read a decimal number from the keyboard into each variable.
; KSF tests the device flag and skips in one instruction without touching AC,
; which is the whole point of putting status behind IOT rather than in memory.
DOASK:  LIX     TPSAVE
        CAL     SKIPW
DOASKL: CAL     SKSP
        CAL     VNAME
        DAC     SVAR
        LAC     SVAR            ; FOCAL prompts with the name and a colon
        TAD     CACHR
        CAL     PUTC
        LAC     COLON
        CAL     PUTC
        LAC     SVAR
        CAL     VTGET
        SKZ                     ; skip when the type is integer
        JMP     ASKSTR
        CAL     RDKEY           ; blocks until a full number arrives
        DAC     VVAL
        LAC     SVAR
        CAL     VPUTV
DOASKC: CAL     SKSP
        LAC     (TXTP) , X
        SAD     COMMA
        JMP     DOASKM
        CAL     EOS
        RET
DOASKM: IXC
        JMP     DOASKL

; ASK v$ reads a whole line of text, not a number
ASKSTR: LAC     SVAR
        DAC     TMPV
        CAL     VSTRA
        CLA
        DAC     SOFF
ASKSL:  CAL     GETK
        SAD     NLC
        JMP     ASKSD
        DAC     SCH
        LAC     SOFF
        SAD     SLM1            ; full: keep reading, drop the rest
        JMP     ASKSL
        PSH     IX
        LIX     SOFF
        LAC     SCH
        DAC     (SADDR) , X
        POP     IX
        ISZ     SOFF
        NOP
        JMP     ASKSL
ASKSD:  PSH     IX
        LIX     SOFF
        CLA
        DAC     (SADDR) , X
        POP     IX
        JMP     DOASKC

; read one decimal number, echoing as it goes; ends at any non digit
RDKEY:  CLA
        DAC     NUM
        DAC     KNEG
        CAL     GETK
        SAD     MINC            ; a leading minus?
        JMP     RDKN
        JMP     RDK1
RDKN:   CLA
        IAC
        DAC     KNEG
        CAL     GETK
RDK1:   DAC     KCH
        TAD     M0C
        DAC     DIGIT
                SKNM                    ; skip when not negative
        JMP     RDKD            ; below '0': the number is finished
        LAC     DIGIT
        TAD     M10
                SKM                     ; skip when negative
        JMP     RDKD            ; above '9'
        LAC     NUM
        SHA
        DAC     T10
        SHA
        SHA
        TAD     T10
        TAD     DIGIT
        DAC     NUM
        CAL     GETK
        JMP     RDK1
RDKD:   LAC     KNEG        ; GETK already echoed the terminator, including
                            ; the newline, so do not add another one
        SKNZ
        JMP     RDKP
        LAC     NUM
        CIA
        RET
RDKP:   LAC     NUM
        RET

; The keyboard delivers a raw code plus the modifiers that were held with it,
; and reconstructing the character is the CPU's job.  Doing it in the handler
; means the mainline only ever sees finished characters.
KBDISR: PSH     AC , IX
        KRAW
        DAC     KRAWV
        KMOD
        DAC     KMODV
        AND     KCTRL           ; control wins over shift
        SKNZ
        JMP     KNOCTL
        LAC     KRAWV
        AND     C31             ; a control code is the low five bits
        JMP     KDONE
KNOCTL: LAC     KMODV
        AND     KSHIFT
        SKNZ
        JMP     KPLAIN
        LAC     KRAWV           ; shift only folds letters here: the symbol
        TAD     MLCA            ; map depends on the physical layout
                SKNM                    ; skip when not negative
        JMP     KPLAIN
        LAC     KRAWV
        TAD     MLCZ
                SKM                     ; skip when negative
        JMP     KPLAIN
        LAC     KRAWV
        TAD     M32
        JMP     KDONE
KPLAIN: LAC     KRAWV
KDONE:  DAC     KCHR
        SAD     CETX            ; control C does not queue: it asks the
        JMP     KBRK            ; running program to stop
        JMP     KDONE1
KBRK:   CLA
        IAC
        DAC     BRK
        KACK
        POP     AC , IX
        SKNI
        RET
        RTI
KDONE1: LAC     KCHR            ; into the queue: the mainline may be busy, and
        LAC     KQI             ; a single character would be overwritten by
        IAC                     ; the next keystroke before anyone read it
        AND     C7
        DAC     KQN
        SAD     KQO             ; skip when there is still room
        JMP     KFULL
        LIX     KQI
        LAC     KCHR
        DAC     KQ , X
        LAC     KQN
        DAC     KQI
        KACK                    ; collected, scanning may resume
        POP     AC , IX
        SKNI
        RET
        RTI

; No room.  Do not acknowledge: the device holds the keystroke and stops
; scanning, so nothing is lost.  Mask this one line in the processor's mask
; and return with interrupts on, because a keyboard queue that is momentarily
; full is no reason to stop listening to the rest of the machine.
KFULL:  LAC     KBIT
        IMCLR
        POP     AC , IX
        SKNI
        RET
        RTI

; wait for a reconstructed character, echo it
; Waiting for a person to type is unbounded, so spinning on the queue burns the
; machine for as long as they think.  WAIT stops the fetch until a device asks
; for attention -- which for the keyboard is the keystroke itself -- and costs
; cycles without instructions.  The loop stays around it because a wait can end
; for the timer instead.
GETK:   LAC     KQI
        SAD     KQO             ; skip when the queue is not empty
        JMP     GETKW
        JMP     GETKD
GETKW:  WAIT
        JMP     GETK
GETKD:
        PSH     IX
        LIX     KQO
        LAC     KQ , X
        POP     IX
        DAC     KCH2
        LAC     KQO
        IAC
        AND     C7
        DAC     KQO
        LAC     KBIT            ; room again: let the held keystroke through
        IMSET
        LAC     KCH2
        CAL     PUTC
        LAC     KCH2
        RET

; unknown command, or a comment: step over the line
CUNK:   LIX     TPSAVE
        CAL     EOS
        RET

DOQUIT: LAC     INPROG
        SKNZ
        JMP     STOP            ; typed at command level: really stop
ENDRUN: CLA                     ; inside a program: back to command level
        DAC     INPROG
        DAC     MORE
        RET

; step to the end of this command: a semicolon leaves MORE set, so the body
; loop runs the next command on the same line
EOS:    LAC     (TXTP) , X
        SKNZ
        JMP     EOSZ
        SAD     NLC
        JMP     EOSN
        SAD     SEMI
        JMP     EOSS
        IXC
        JMP     EOS
EOSN:   IXC
EOSZ:   CLA
        DAC     MORE
        RET
EOSS:   IXC
        CLA
        IAC
        DAC     MORE
        RET

; FOR v = start, limit ; body        (step defaults to 1)
; FOR v = start, step, limit ; body
; The body is the rest of the line, so the loop just rewinds the text pointer
; and calls BODY again.  The loop variable lives in the ordinary variable
; table, exactly as FOCAL specifies, so the body can read and even change it.
DOFOR:  LIX     TPSAVE
        CAL     SKIPW
        CAL     SKSP
        CAL     VNAME
        DAC     FVARI
        CAL     SKSP
        IXC                     ; the equals sign
        CAL     EXPR
        DAC     FCUR
        CAL     SKSP
        IXC                     ; the first comma
        CAL     EXPR
        DAC     FLIM            ; provisionally the limit
        CLA
        IAC
        DAC     FSTEP           ; provisionally a step of one
        CAL     SKSP
        LAC     (TXTP) , X
        SAD     COMMA           ; a third field means that was the step
        JMP     FOR3
        JMP     FORB
FOR3:   IXC
        LAC     FLIM
        DAC     FSTEP
        CAL     EXPR
        DAC     FLIM
FORB:   CAL     SKSP
        IXC                     ; the semicolon before the body
        DIX     FBODY           ; where the body starts

FORL:   LAC     FLIM            ; continue while limit - current agrees in
        CIA                     ; sign with the step, or is zero
        TAD     FCUR
        CIA
        DAC     FDIFF
        SKNZ
        JMP     FORGO           ; exactly on the limit: run one more time
        XOR     FSTEP           ; two signs agree exactly when their XOR is not
        SKM                     ; negative, so one skip settles it and neither
        JMP     FORGO           ; sign has to be extracted
        JMP     FORD
FORGO:  LAC     FCUR            ; publish the loop variable, then run the body
        DAC     VVAL
        LAC     FVARI
        CAL     VPUTV
        LIX     FBODY
        CAL     BODY
        LAC     FCUR
        TAD     FSTEP
        DAC     FCUR
        JMP     FORL
FORD:   LIX     FBODY
        CAL     EOL
        CLA
        DAC     MORE
        RET

; RETURN: abandon the rest of the line, which is how a DO comes back early
DORET:  LIX     TPSAVE
        CAL     EOL
        CLA
        DAC     MORE
        RET

; step over a word of letters: SKIPW stops at a space, which is not enough
; when the word is the last thing on the line
SKIPT:  LAC     (TXTP) , X
        TAD     MACHR
                SKNM                    ; skip when not negative
        RET
        IXC
        JMP     SKIPT

; skip the rest of the command word
SKIPW:  LAC     (TXTP) , X
        SKNZ
        RET
        SAD     SPC             ; skip when it is not a space
        RET
        IXC
        JMP     SKIPW

; =====================================================================
RESET:  CLA
        DAC     CURS
        LIX     CURS
        LAC     SPC
CLS:    DAC     (SCRP) , X
        IXC
        SXD     C512
        JMP     CLSD
        JMP     CLS
CLSD:   CLA
        DAC     CURS
        DAC     TMPV
; nothing to clear: the class pointers start empty and a block is cleared
; when it is carved, so a fresh variable reads as zero by construction
CLVD:   EI                      ; the keyboard reaches us through irq1
        PSH     IX
        LIX     NIL
        LAC     (TXTB) , X
        POP     IX
        SKNZ
        JMP     CMDL            ; no program was assembled in: converse
        CLA
        IAC
        DAC     INPROG
        DAC     BATCH           ; a program was assembled in: no command level
        CAL     RUN
STOP:   HLT

        .advance 0x2D00
CTAB:
        JMP     CUNK    ; 0  .
        JMP     DOASK   ; 1  A
        JMP     CUNK    ; 2  B
        JMP     CUNK   ; 3  C
        JMP     DODO    ; 4  D
        JMP     DOERAS  ; 5  E
        JMP     DOFOR   ; 6  F
        JMP     DOGOTO  ; 7  G
        JMP     CUNK    ; 8  H
        JMP     DOIF    ; 9  I
        JMP     CUNK    ; 10  J
        JMP     CUNK    ; 11  K
        JMP     CUNK    ; 12  L
        JMP     CUNK    ; 13  M
        JMP     CUNK    ; 14  N
        JMP     CUNK    ; 15  O
        JMP     CUNK    ; 16  P
        JMP     DOQUIT  ; 17  Q
        JMP     DORET   ; 18  R
        JMP     DOSET   ; 19  S
        JMP     DOTYPE  ; 20  T
        JMP     CUNK    ; 21  U
        JMP     CUNK    ; 22  V
        JMP     DOWRIT  ; 23  W
        JMP     CUNK    ; 24  X
        JMP     CUNK    ; 25  Y
        JMP     CUNK    ; 26  Z
        JMP     CUNK    ; 27  .
        JMP     CUNK    ; 28  .
        JMP     CUNK    ; 29  .
        JMP     CUNK    ; 30  .
        JMP     CUNK    ; 31  .


        .advance 0x2E40
        .include "program.s"

; above the framebuffer, which SCRP puts at 0x4000.  The index is now a letter
; times forty plus the second character, so every table has 1040 entries.
; The heap, above the framebuffer at 0x4000.  Blocks are carved off it as
; classes of names appear, so what is used is what is spent.
        .advance 0x4400
HEAPB:  .advance 0x10000


