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
VARSP:  .dd    VARS
SCRP:   .dd    0x4000
C512:   .dd    512
C480:   .dd    480
C32:    .dd    32
SPC:    .dd    32
NLC:    .dd    10
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
FS1:    .dd    0
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
ERRF:   .dd    70              ; ?F float not implemented
STRVB:  .dd    STRV
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
ARRB:   .dd    ARRV
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
VTYPE:  .dd    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .dd    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
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
BIT17:  .dd    0x20000
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
SVADDR: LAC     TMPV
        SHA
        SHA
        DAC     SAT             ; 4n
        SHA
        SHA                     ; 16n
        TAD     SAT             ; 20n
        TAD     STRVB
        DAC     SADDR
        RET

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
        CAL     SGNB
        SKZ
        JMP     CMDEX
        LAC     DIGIT
        TAD     M10
        CAL     SGNB
        SKNZ
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
        CAL     SGNB
        SKZ
        JMP     TNUMD
        LAC     DIGIT
        TAD     M10
        CAL     SGNB
        SKNZ
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
STORE:  CAL     RDLNUM          ; LNUM, and LBODY at the first body character
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
        CAL     SGNB
        SKZ
        JMP     RDLND
        LAC     DIGIT
        TAD     M10
        CAL     SGNB
        SKNZ
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
        CAL     SGNB
        SKZ
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
SGNB:   RLA
        GLK
        RET

; =====================================================================
; expression evaluator
; =====================================================================
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
        CAL     SGNB
        SKZ
        JMP     FNUM
        JMP     FVAR

FPAR:   IXC
        CAL     EXPR
        PSH     AC
        CAL     SKSP
        IXC                 ; consume the ')'
        POP     AC
        RET

FNEG:   IXC
        CAL     FACT
        CIA
        RET

; FABS, FSGN, FITR, FSQT.  The second letter tells them apart except for the
; two beginning with S, where the third settles it.
FFUNC:  IXC
        LAC     (TXTP) , X
        SAD     CL              ; FLEN takes a string, not an expression
        JMP     FFLEN
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
        JMP     FNABS
        LAC     FSEL
        SAD     CI
        JMP     FNITR
        LAC     FSEL2
        SAD     CG
        JMP     FNSGN
        JMP     FNSQT

FFLEN:  IXC
        IXC
        IXC                     ; past LEN
        CAL     SKSP
        IXC                     ; the open parenthesis
        CAL     SKSP
        LAC     (TXTP) , X
        TAD     MACHR
        DAC     TMPV
        IXC
        CAL     SVADDR
        CAL     SLENF
        DAC     SLNV
        CAL     SKSP
        IXC                     ; the close parenthesis
        LAC     SLNV
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
        CAL     SGNB
        SKNZ
        JMP     FNSGP
        CLA
        CMA                     ; negative: -1
        RET
FNSGP:  CLA
        IAC
        RET
FNSQT:  LAC     FARG
        DAC     M1
        CAL     ABS1
        CAL     ISQRT
        LAC     MRES
        RET

FVAR:   LAC     (TXTP) , X
        TAD     MACHR
        DAC     TMPV
        IXC
        LAC     (TXTP) , X
        SAD     LPAR
        JMP     FARR
        PSH     IX              ; IX is the text pointer, borrow it
        LIX     TMPV
        LAC     VTYPE , X
        POP     IX
        SKZ                     ; a string here reads as the number it spells
        JMP     FVARS
        PSH     IX
        LIX     TMPV
        LAC     (VARSP) , X
        POP     IX
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

FVARS:  CAL     SVADDR
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
        CAL     SGNB
        SKZ
        JMP     SVND
        LAC     DIGIT
        TAD     M10
        CAL     SGNB
        SKNZ
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

; AVADDR: address of element TMPV of array SVARI, sixteen elements each
AVADDR: LAC     SVARI
        SHA
        SHA
        SHA
        SHA                     ; 16 per variable
        TAD     TMPV
        TAD     ARRB
        DAC     AADDR
        RET

; length of the string at SADDR
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

FNUM:   CLA
        DAC     NUM
FNUML:  LAC     (TXTP) , X
        TAD     M0C
        DAC     DIGIT
        CAL     SGNB
        SKZ
        JMP     FNUMD           ; below '0'
        LAC     DIGIT
        TAD     M10
        CAL     SGNB
        SKNZ
        JMP     FNUMD           ; above '9'
        LAC     NUM             ; num*10 = num*8 + num*2, three shifts and an
        SHA                     ; add: the general multiplier is far too much
        DAC     T10             ; machinery for a constant
        SHA
        SHA
        TAD     T10
        TAD     DIGIT
        DAC     NUM
        IXC
        JMP     FNUML
FNUMD:  LAC     NUM
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
        CAL     SGNB
        SKZ
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
TERML:  PSH     AC
        CAL     SKSP
        LAC     (TXTP) , X
        SAD     STAR
        JMP     TSTAR
        LAC     (TXTP) , X
        SAD     SLASH
        JMP     TSLASH
        POP     AC
        RET
TSTAR:  IXC
        CAL     POWER
        DAC     M2
        POP     AC
        DAC     M1
        CAL     MUL
        JMP     TERML
TSLASH: IXC
        CAL     POWER
        DAC     M2
        POP     AC
        DAC     M1
        CAL     DIV
        JMP     TERML

EXPR:   CAL     TERM
EXPRL:  PSH     AC
        CAL     SKSP
        LAC     (TXTP) , X
        SAD     PLUSC
        JMP     EPLUS
        LAC     (TXTP) , X
        SAD     MINC
        JMP     EMIN
        POP     AC
        RET
EPLUS:  IXC
        CAL     TERM
        DAC     TMPV
        POP     AC
        TAD     TMPV
        JMP     EXPRL
EMIN:   IXC
        CAL     TERM
        CIA
        DAC     TMPV
        POP     AC
        TAD     TMPV
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
        CAL     SGNB
        SKZ
        JMP     RDND
        LAC     DIGIT
        TAD     M10
        CAL     SGNB
        SKNZ
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
FIND:   LAC     TXTB            ; a jump always lands in the stored program
        DAC     TXTP
        CLA
        IAC
        DAC     INPROG
        LIX     NIL
FINDL:  LAC     (TXTP) , X
        SKNZ
        JMP     FINDX           ; ran off the end: stop the program
        CAL     SKSP
        CAL     RDNUM
        SAD     TARG            ; skip when it is not the wanted line
        RET
        CAL     EOL
        JMP     FINDL
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
        LAC     (TXTP) , X
        TAD     MACHR
        DAC     SVAR            ; not TMPV: the evaluator uses that one
        IXC
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
        SAD     CF
        JMP     DECLF
        LAC     ERRT
        JMP     ERROR
DECLI:  CLA
        JMP     DECLST
DECLS:  CLA
        IAC
        JMP     DECLST
DECLF:  LAC     ERRF            ; float has no implementation to declare
        JMP     ERROR
DECLST: DAC     SCH
        PSH     IX
        LIX     SVAR
        LAC     SCH
        DAC     VTYPE , X
        POP     IX
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
        PSH     IX
        LIX     SVAR
        LAC     VTYPE , X
        POP     IX
        SKZ                     ; skip when the type is integer
        JMP     DOSSTR
        CAL     EXPR            ; integer: the ordinary path
        PSH     IX
        PSH     AC
        LIX     SVAR
        POP     AC
        DAC     (VARSP) , X
        POP     IX
        CAL     EOS
        RET

; the right hand side of a string assignment: a literal, a bare string
; variable, or a number to be spelled out
DOSSTR: LAC     SVAR
        DAC     TMPV
        CAL     SVADDR
        LAC     (TXTP) , X
        SAD     QUOTE
        JMP     SETSL
        LAC     (TXTP) , X
        TAD     MACHR
        CAL     SGNB
        SKZ
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
SETSB:  LAC     (TXTP) , X
        TAD     MACHR
        DAC     SCH2
        PSH     IX
        LIX     SCH2
        LAC     VTYPE , X
        POP     IX
        SKZ                     ; skip when the source is an integer
        JMP     SETSV
        JMP     SETSN
SETSV:  LAC     (TXTP) , X
        TAD     MACHR
        DAC     TMPV
        IXC
        LAC     SADDR
        PSH     AC
        CAL     SVADDR
        LAC     SADDR
        DAC     SADDR2          ; source
        POP     AC
        DAC     SADDR
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

SETSL:  IXC                     ; past the opening quote
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
        CAL     SGNB            ; operator it is arithmetic on the number the
        SKZ                     ; text spells, so one character is looked at.
        JMP     DOTYN
        LAC     (TXTP) , X
        TAD     MACHR
        DAC     TMPV
        IXC
        LAC     (TXTP) , X
        DAC     SCH
        TADX    MONE
        PSH     IX
        LIX     TMPV
        LAC     VTYPE , X
        POP     IX
        SKNZ
        JMP     DOTYN           ; an integer: evaluate it
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
DOTYSV: LAC     (TXTP) , X
        TAD     MACHR
        DAC     TMPV
        IXC
        CAL     SVADDR
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
        CAL     SKSP
        IXC                 ; consume the ')'
        LAC     IFV
        SKNZ
        JMP     DOIFZ
        CAL     SGNB
        SKNZ                    ; sign set means negative
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
DOERAS: LIX     TPSAVE
        CAL     EOL
        PSH     IX
        LIX     NIL
        CLA
DOER1:  DAC     (VARSP) , X
        IXC
        SXD     C26
        JMP     DOER2
        JMP     DOER1
DOER2:  POP     IX
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
        LAC     (TXTP) , X
        TAD     MACHR
        DAC     SVAR
        IXC
        LAC     SVAR            ; FOCAL prompts with the name and a colon
        TAD     CACHR
        CAL     PUTC
        LAC     COLON
        CAL     PUTC
        PSH     IX
        LIX     SVAR
        LAC     VTYPE , X
        POP     IX
        SKZ                     ; skip when the type is integer
        JMP     ASKSTR
        CAL     RDKEY           ; blocks until a full number arrives
        PSH     IX
        PSH     AC
        LIX     SVAR
        POP     AC
        DAC     (VARSP) , X
        POP     IX
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
        CAL     SVADDR
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
        CAL     SGNB
        SKZ
        JMP     RDKD            ; below '0': the number is finished
        LAC     DIGIT
        TAD     M10
        CAL     SGNB
        SKNZ
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
        CAL     SGNB
        SKZ
        JMP     KPLAIN
        LAC     KRAWV
        TAD     MLCZ
        CAL     SGNB
        SKNZ
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
GETK:   LAC     KQI
        SAD     KQO             ; skip when the queue is not empty
        JMP     GETK
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
        LAC     (TXTP) , X
        TAD     MACHR
        DAC     FVARI
        IXC
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
        CAL     SGNB
        DAC     FS1
        LAC     FSTEP
        CAL     SGNB
        SAD     FS1             ; skip when the signs differ
        JMP     FORGO
        JMP     FORD
FORGO:  LAC     FCUR            ; publish the loop variable, then run the body
        PSH     IX
        LIX     FVARI
        DAC     (VARSP) , X
        POP     IX
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
        CAL     SGNB
        SKZ
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
CLV:    LIX     TMPV            ; clear the 26 variables
        CLA
        DAC     (VARSP) , X
        ISZ     TMPV
        NOP
        LAC     TMPV
        SAD     C26
        JMP     CLVD
        JMP     CLV
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

        .advance 0x2E00
VARS:   .advance 0x2E20

        .advance 0x2E40
        .include "program.s"

        .advance 0x3400
STRV:   .advance 0x3610         ; 26 strings of 20 words

        .advance 0x3800
ARRV:   .advance 0x3A00         ; 26 arrays of 16 words
