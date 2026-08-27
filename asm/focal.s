; A subset of FOCAL for the 18-bit machine.
;
; Commands: SET, TYPE, ASK, IF, GOTO, DO, RETURN, FOR, WRITE, ERASE, QUIT and
; comment lines.  Several commands may share a line, separated by semicolons.
; Functions: FABS, FSGN, FITR, FSQT.
; Arithmetic is 18-bit integer, not FOCAL's floating point: the machine has
; no floating unit and the point here is the interpreter, not the numerics.
;
; A stored line is a key word, its length in words, a body, and a newline.  The
; length counts the whole line, so the next one starts at start+length and
; walking the lines costs an add rather than a scan.
;
; A line number is fixed point, gg.sss: two digits of group and three of step,
; held in one word as group*1000 + step.  That ordering is the numeric one, so
; the line index and the insertion search compare words.  Written without a
; point it is a group, which is what DO takes: DO 2 runs every 02.sss line in
; turn.  A step is padded on the right, so 2.1 and 02.100 are one line.
;
; The program text sits in memory as one blob, lines separated by newline,
; terminated by a zero word:
;
;     01.010 SET A=7
;     01.020 SET B=A*(A+1)/2
;     01.030 TYPE "SUM ", B, !
;     01.040 IF (B-28) 01.060, 01.050, 01.060
;     01.050 TYPE "OK", !
;     01.060 QUIT
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
LNUM:   .dd    0               ; number of the line being filed away
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
SCRP:   .dd    0x800            ; the framebuffer, clear of the arena
C512:   .dd    512
C480:   .dd    480
C32:    .dd    32
SPC:    .dd    32
NLC:    .dd    10
LIT:    .dd    0
LNV:    .dd    0                ; a line number, gg.sss packed as gg*1000+sss
LSOR:   .dd    0                ; the step's digits summed: zero for a group
LFD:    .dd    0                ; digits of step read so far
LIB:    .dd    0                ; lower bound handed to LIGE
LIGV:   .dd    0                ; the number LIGE settled on
LIGP:   .dd    0                ; and its position
LIGN:   .dd    0
LIGQ:   .dd    0
DOGL:   .dd    0                ; last number the group under DO can hold
DOGF:   .dd    0                ; the DO names a group, not a line
DORF:   .dd    0                ; RETURN seen: unwind the DO
C3:     .dd    3
C999:   .dd    999
M999:   .dd   -999
M100:   .dd   -100
MTWO:   .dd   -2
DOT:    .dd    46               ; '.'
ITEMB:  .dd    0x10000          ; set on a tagged word, never on a character
LNMASK: .dd    0x1E000          ; the tag field of an item word
LNTAG:  .dd    0x12000          ; ... and the pattern that means a line number
LNMK:   .dd    0                ; the marker just read
C1000:  .dd    1000
C100:   .dd    100
C2:     .dd    2
ZEROC:  .dd    48               ; '0'
WKEY:   .dd    0
WSTEP:  .dd    0
WCH:    .dd    0
WN:     .dd    0
WCH2:   .dd    0
CBUFP:  .dd    CBUF
CDOTB:  .dd    0x100            ; in a command word: a trailing point
CNAMP:  .dd    CNAMES
CNL:    .dd    0
CNLI:   .dd    0
CO:     .dd    0                ; where the next compiled word goes
CKEY:   .dd    0                ; key of the line compiled, zero when none
CPQ:    .dd    0                ; inside a quoted string
CPW:    .dd    0                ; letters in the command word, zero for none
CK:     .dd    0
CPT:    .dd    0
CEMT:   .dd    0                ; CEMIT's own, so it stomps no caller's temp
CN:     .dd    0
CLTR:   .dd    0                ; the command letter as typed
CNAME:  .dd    0
CTGT:   .dd    0                ; line numbers still expected
CDEP:   .dd    0
CSAVE:  .dd    0
CDCH:   .dd    68               ; 'D'
GRPBIT: .dd    1                ; in a marker: the number named a group
ERRL:   .dd    76               ; ?L bad, absent or unreachable line number
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
ERRS:   .dd    83              ; ?S no room left for the program
HALLOC: .dd    0                ; the block HALLOC just carved
SADDR:  .dd    0
SADDR2: .dd    0
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
HEAPTOP: .dd   0x1F000          ; the arena ends where the interpreter begins
HEAP:   .dd    0x1F000          ; and the heap grows down from there
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
CBUF:   .dd    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .dd    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
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

; The interpreter lives in the last 4K page, and so does the arithmetic runtime
; it calls: a direct CAL or JMP is PC-page relative over twelve bits, so code
; and the code it calls have to share a page.  Nothing up here is ever written
; -- bench.py fails the run if anything is -- so all of it can be ROM.
        .org    0x1F400

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
; String variables.  Declared, not spelled: SET A AS STRING, because in FOCAL
; the BASIC suffixes are taken -- % is TYPE's format control, and so are ! and
; #.  So A is one variable whose type sits in a table beside it, not two
; variables called A and A$.
;
; A name holds a pointer and the body is carved from the heap on first use, in
; one of two sizes.  SADDR holds the address of the body being worked on and
; SLM1 its real capacity, which is why nothing here knows a stride.
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
        DAC     DORF
        DAC     INPROG
        LAC     STARC
        CAL     PUTC
        CAL     RDLINE          ; GETK has already echoed the newline
        LAC     LBUFA
        DAC     TXTP
        LIX     NIL
        CAL     SKSP
        LAC     (TXTP) , X
        SKNZ
        JMP     CMDL            ; nothing typed
        CAL     COMP            ; the interpreter runs words, not characters,
        LAC     CKEY            ; so a typed line is compiled either way
        SKNZ
        JMP     CMDEX           ; no number, so run it now
        CAL     STORE
        JMP     CMDL
CMDEX:  LAC     CBUFP
        DAC     TXTP
        LIX     NIL
        CAL     BODY
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
        LAC     (TXTB) , X      ; the key heads the line, so there is no parse
        DAC     TVAL
        IXC
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
STORE:          LAC     CKEY            ; COMP has already read it
        DAC     LNUM
        CAL     TLEN
        CAL     LFIND
        LAC     TMATCH
        SKNZ
        JMP     STNOD
        CAL     TDEL
STNOD:  CAL     STBODY          ; a bare number deletes and nothing more
        SKNZ
        RET
        LAC     CO
        DAC     TGAP            ; the compiled line, newline and all
        TAD     TEND            ; the text would end here
        TAD     TXTB
        CIA
        TAD     HEAP            ; and the heap begins here
        AND     BIT17
                SKNZ                    ; skip when the two would collide
        JMP     STROOM
        LAC     ERRS
        JMP     ERROR
STROOM: CAL     TINS
        CLA
        DAC     TSRC
        LAC     TPOS
        DAC     TDST
STCL:   LAC     TSRC
        SAD     CO              ; skip while words remain
        RET
        PSH     IX
        LIX     TSRC
        LAC     (CBUFP) , X
        DAC     TCH
        LIX     TDST
        LAC     TCH
        DAC     (TXTB) , X
        POP     IX
        ISZ     TSRC
        NOP
        ISZ     TDST
        NOP
        JMP     STCL

; STBODY: nonzero when the compiled line holds anything but its key, spaces
; and the newline.  A number with nothing after it deletes its line, which is
; how FOCAL does it, and asking the compiled form is simpler than re-scanning
; the characters that produced it.
STBODY: PSH     IX
        LAC     MTWO            ; past the key and the length
        CIA
        DAC     CK
STBL:   LAC     CK
        SAD     CO              ; skip while words remain
        JMP     STBNO
        LIX     CK
        LAC     (CBUFP) , X
        DAC     CPT
        SAD     SPC             ; skip when it is not a space
        JMP     STBN
        LAC     CPT
        SAD     NLC             ; skip when it is not the newline
        JMP     STBN
        JMP     STBYES          ; anything else is a body
STBN:   ISZ     CK
        NOP
        JMP     STBL
STBYES: POP     IX
        CLA
        IAC
        RET
STBNO:  POP     IX
        CLA
        RET
; HCARVE: the words wanted in AC -> the base of a fresh block.  The heap grows
; down from the top of the arena while the program text grows up from the
; bottom, so the two need one test between them rather than a ceiling each: a
; block that would reach below the end of the text is refused with ?S.
HCARVE: CIA
        TAD     HEAP
        DAC     HALLOC          ; where the block would start
        LAC     TEND            ; the text's end, as an address
        TAD     TXTB
        CIA
        TAD     HALLOC
        AND     BIT17
                SKNZ                    ; skip when it would reach the text
        JMP     HCOK
        LAC     ERRS
        JMP     ERROR
HCOK:   LAC     HALLOC
        DAC     HEAP
        RET

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
VLNEW:  LAC     VLSZ
        CAL     HCARVE
        DAC     VLB
        DAC     (VLPT) , X
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
SALNEW: LAC     SASZ
        CAL     HCARVE
        DAC     SAP
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

; Strings and arrays hold a pointer and the body is carved on first use, in one
; of the two sizes SALLOC keeps free lists for.
VSTRA:  LAC     TMPV            ; the name is in TMPV, not in AC
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
; VNAME: read a variable name at the text pointer and step past it.  A letter,
; then optionally a letter or a digit, and only the first two characters are
; significant -- FOCAL's own rule.
;
; The two characters come back as two separate indices, VN1 for the first and
; VN2 for the second, because the lookup is two levels deep: VN2 picks one of
; thirty-seven classes -- nothing, A to Z, 0 to 9 -- and VN1 an entry within
; that class's block.  Nothing is multiplied out, which is the point: a flat
; index into a cross product needed 40n, and 40n is two shift chains and an
; add.
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
; AC*10 = AC*8 + AC*2, three shifts and an add: the general multiplier is far
; too much machinery for a constant, and this is the parser's inner step.
TIMES10: SHA
        DAC     T10
        SHA
        SHA
        TAD     T10
        RET

; the digit at the text pointer, in DIGIT and in AC, or -1 when there is none
LDIG:   LAC     (TXTP) , X
        TAD     M0C
        DAC     DIGIT
                SKNM                    ; skip when not negative
        RET                     ; below '0', so already the answer
        TAD     M10
                SKM                     ; skip when negative, which is a digit
        JMP     LDIGN
        LAC     DIGIT
        RET
LDIGN:  LAC     MONE
        RET
RDLN:   LAC     (TXTP) , X
        DAC     LNMK
        AND     LNMASK
        SAD     LNTAG           ; skip when it is not a line number
        JMP     RDLN1
        JMP     RDLERR
RDLN1:  IXC
        LAC     (TXTP) , X
        DAC     LNV
        IXC
        RET

; ---------------------------------------------------------------------
; Compiling a typed line.
;
; The prompt takes characters and the interpreter runs words, so a typed line
; is compiled before it is filed or run -- even an immediate one, because BODY
; dispatches on a command word.  The rules are mkprog.py's, and bench.py holds
; the two in step by listing every sample back out and diffing it against the
; source.
; ---------------------------------------------------------------------

; CNLOOK: the letter in AC -> the name that begins with it, or zero.  A search
; over twelve entries rather than a table indexed by letter: it runs once per
; command listed and once per command typed, never in execution, and it leaves
; every word of the table area read only, which a table built at reset did not.
CNLOOK: PSH     IX
        AND     C31
        DAC     CNL
        LIX     NIL
CNLL:   LAC     (CNAMP) , X
        SKNZ
        JMP     CNLNO
        DAC     CNAME
        DIX     CNLI
        LIX     NIL
        LAC     (CNAME) , X     ; the name's first character is its letter
        AND     C31
        SAD     CNL             ; skip when it is not this one
        JMP     CNLYES
        LIX     CNLI
        IXC
        JMP     CNLL
CNLYES: POP     IX
        LAC     CNAME
        RET
CNLNO:  POP     IX
        CLA
        DAC     CNAME
        RET

; CEMIT: append AC to the line being compiled
CEMIT:  PSH     IX
        DAC     CEMT
        LIX     CO
        LAC     CEMT
        DAC     (CBUFP) , X
        ISZ     CO
        NOP
        POP     IX
        LAC     CEMT
        RET

; CLET: nonzero when a letter stands at the text pointer
CLET:   LAC     (TXTP) , X
        TAD     MACHR
                SKNM                    ; skip when not negative
        JMP     CLETN
        LAC     (TXTP) , X
        TAD     MZCHR
                SKM                     ; skip when negative, so within A..Z
        JMP     CLETN
        CLA
        IAC
        RET
CLETN:  CLA
        RET

; CLNUM: the line number at the text pointer, emitted as a marker and a value.
; The marker's low bit records that it was written without a point, which is
; how DO tells a group from a line without dividing by a thousand.
CLNUM:  CAL     RDLNT
        DAC     CPT
        SKNZ
        RET
        LAC     LNTAG
        DAC     CN
        LAC     LSOR            ; zero when every digit of the step was
        SKNZ
        JMP     CLNG
        JMP     CLNE
CLNG:   LAC     CN
        TAD     GRPBIT
        DAC     CN
CLNE:   LAC     CN
        CAL     CEMIT
        LAC     CPT
        CAL     CEMIT
        RET

; CCMD: the command word at the text pointer.  Pass one counts the letters,
; pass two checks them against the name the letter selects, so G, GO and GOTO
; are commands while GOTOO and XYZ are not.  What is not a command is left for
; the caller to emit as the characters it was: that still dispatches to CUNK
; through the letter, and still lists back out unchanged.
;
; CPW holds the letters emitted, zero when nothing was, and the text pointer is
; then back where it started.  CTGT holds the line numbers the command takes.
CCMD:   CLA
        DAC     CTGT
        DAC     CPW
        DIX     CSAVE
CCMDC:  CAL     CLET
        SKNZ
        JMP     CCMDV
        ISZ     CPW
        NOP
        IXC
        JMP     CCMDC
CCMDV:  LAC     CPW
        SKNZ
        JMP     CCMDNO          ; no letters here at all
        LIX     CSAVE
        LAC     (TXTP) , X
        DAC     CLTR
        CAL     CNLOOK          ; a letter with no command has no name
        SKNZ
        JMP     CCMDNO
        CLA
        DAC     CK
CCMDL:  LAC     CK
        SAD     CPW              ; skip while letters remain to check
        JMP     CCMDOK
        LIX     CK
        LAC     (CNAME) , X
        DAC     CN
        SKNZ
        JMP     CCMDNO          ; typed longer than the name it would be
        LAC     CSAVE
        TAD     CK
        DAC     CPT
        LIX     CPT
        LAC     (TXTP) , X
        SAD     CN              ; skip when the letters differ
        JMP     CCMDM
        JMP     CCMDNO
CCMDM:  ISZ     CK
        NOP
        JMP     CCMDL

CCMDOK: LIX     CK              ; nonzero when the name goes on, so a prefix
        LAC     (CNAME) , X
        DAC     CN
        LAC     CPW             ; letters written, into bits five to seven
        SHA
        SHA
        SHA
        SHA
        SHA
        TAD     ITEMB
        DAC     CPT
        LAC     CLTR
        AND     C31
        TAD     CPT
        DAC     CPT
        LAC     CPW             ; the character just past the letters
        TAD     CSAVE
        DAC     CK
        LIX     CK
        LAC     (TXTP) , X
        SAD     DOT             ; skip when it is not a point
        JMP     CCMDD
        JMP     CCMDF
CCMDD:  LAC     CPT             ; a point, after the whole name or a prefix
        TAD     CDOTB
        DAC     CPT
        IXC
        JMP     CCMDE
CCMDF:  LAC     CN              ; no point, so this must be the whole name
        SKNZ
        JMP     CCMDE
        JMP     CCMDNO          ; an abbreviation without its point
CCMDE:  LAC     CPT
        CAL     CEMIT
        LAC     CLTR            ; how many line numbers this one takes
        SAD     CI              ; skip when it is not IF
        JMP     CCTG3
        SAD     CG              ; skip when it is not GOTO
        JMP     CCTG1
        SAD     CDCH            ; skip when it is not DO
        JMP     CCTG1
        RET
CCTG3:  LAC     C3
        DAC     CTGT
        CAL     CCOND           ; the condition first, so its digits are safe
        RET
CCTG1:  CLA
        IAC
        DAC     CTGT
        RET
CCMDNO: LIX     CSAVE           ; put the pointer back and emit nothing
        CLA
        DAC     CPW
        RET

; CCOND: copy IF's condition through the paren that closes it.  The digits in
; it are operands, not line numbers, and this is what keeps them apart.
CCOND:  CLA
        DAC     CDEP
CCONDL: LAC     (TXTP) , X
        SKNZ
        RET
        SAD     LPAR            ; skip when it is not an open paren
        JMP     CCOPEN
        LAC     (TXTP) , X
        SAD     RPAR            ; skip when it is not a close paren
        JMP     CCCLOS
        JMP     CCCOPY
CCOPEN: ISZ     CDEP
        NOP
        JMP     CCCOPY
CCCLOS: DSZ     CDEP            ; skip when the depth falls to zero
        JMP     CCCOPY
        JMP     CCLAST
CCCOPY: LAC     (TXTP) , X
        CAL     CEMIT
        IXC
        JMP     CCONDL
CCLAST: LAC     (TXTP) , X      ; the closing paren belongs to the condition
        CAL     CEMIT
        IXC
        RET

; COMP: compile the line in LBUF.  The key lands in CKEY, zero when the line
; carried no number, and the length in CO.
COMP:   PSH     IX
        LAC     LBUFA
        DAC     TXTP
        LIX     NIL
        CLA
        DAC     CO
        DAC     CPQ
        CAL     SKSP            ; indentation ahead of the number is not kept
        CAL     RDLNT
        DAC     CKEY
        SKNZ
        JMP     COMPS
        CAL     CEMIT           ; the key heads the line, then its length,
        CLA                     ; which is not known until the end
        CAL     CEMIT
COMPS:  LAC     (TXTP) , X      ; the spaces ahead of a command are text, and
        SAD     SPC             ; CCMD wants to start on the first letter
        JMP     COMPSP
        JMP     COMPS1
COMPSP: CAL     CEMIT
        IXC
        JMP     COMPS
COMPS1: CAL     CCMD
COMPB:  LAC     (TXTP) , X
        SKNZ
        JMP     COMPD
        SAD     QUOTE           ; skip when it is not a quote
        JMP     COMPQ
        LAC     CPQ
        SKNZ                    ; skip when inside a quoted string
        JMP     COMPX
        JMP     COMPC           ; in a string everything is verbatim
COMPX:  LAC     (TXTP) , X
        SAD     SEMI            ; skip when it is not a semicolon
        JMP     COMPSE
        LAC     CTGT            ; a line number only where one is expected
        SKNZ
        JMP     COMPC
        CAL     LDIG
                SKNM                    ; skip when not negative, so a digit
        JMP     COMPC
        CAL     CLNUM
        DSZ     CTGT
        NOP
        JMP     COMPB
COMPQ:  LAC     CPQ
        XOR     ONE
        DAC     CPQ
        JMP     COMPC
COMPSE: LAC     (TXTP) , X      ; the semicolon, then another command may come
        CAL     CEMIT
        IXC
        JMP     COMPS
COMPC:  LAC     (TXTP) , X
        CAL     CEMIT
        IXC
        JMP     COMPB
COMPD:  LAC     NLC             ; every line ends with one
        CAL     CEMIT
        LAC     CKEY            ; an immediate line is not stored, so it has
        SKNZ                    ; neither key nor length to fill in
        JMP     CMPDX
        PSH     IX
        LIX     ONE
        LAC     CO
        DAC     (CBUFP) , X
        POP     IX
CMPDX:  POP     IX
        LAC     CO
        RET

; ---------------------------------------------------------------------
; RDLNT, the text side of the line number.
;
; The prompt takes characters and the interpreter runs words, so a line typed
; at the prompt is compiled before it is filed or run -- even an immediate one,
; because BODY dispatches on a command word.  The rules are mkprog.py's, and
; the listing WRITE produces from the result is compared against the source in
; bench.py, which is what holds the two in step.
; ---------------------------------------------------------------------
; RDLNT: the fixed point line number in the text at the pointer, as a value.
; One accumulator: the step's digits go into the packed number as they arrive,
; and the padding that makes 2.1 and 02.100 the same line is that same
; times-ten run again.  Nobody asks for the step's value, only whether it is
; zero, so its digits are summed -- the sum is zero exactly when every digit
; was, for an add instead of a second times-ten per digit.
;
; AC holds the value, LSOR zero when the number named a group.  Zero means
; there was no number here, which is not an error.  What is: group zero, a
; group above 99, a fourth digit of step, and a second point.
RDLNT:   CLA
        DAC     LNV
        DAC     LSOR
        DAC     LFD
        CAL     LDIG            ; whether there is a number here at all is a
                SKNM            ; property of the first character, so the loop
        JMP     RDLTZ           ; is entered knowing and carries no flag
RDLTG:  LAC     LNV
        CAL     TIMES10
        TAD     DIGIT
        DAC     LNV
        TAD     M100
                SKM                     ; skip while still below a hundred
        JMP     RDLERR          ; more than two digits of group
        IXC
        CAL     LDIG
                SKNM                    ; skip when not negative, so a digit
        JMP     RDLTP
        JMP     RDLTG
RDLTZ:  CLA
        RET                     ; an unnumbered line, which is not an error
RDLTP:  LAC     LNV             ; only the group has been read so far
        SKNZ
        JMP     RDLERR          ; group zero is not a line
        LAC     (TXTP) , X
        SAD     DOT             ; skip when it is not a point
        JMP     RDLTF
        JMP     RDLTPD
RDLTF:  IXC
RDLTS:  CAL     LDIG
                SKNM                    ; skip when not negative, so a digit
        JMP     RDLTPD
        LAC     LFD
        SAD     C3              ; skip while there is room for another digit
        JMP     RDLERR
        LAC     LNV
        CAL     TIMES10
        TAD     DIGIT
        DAC     LNV
        LAC     LSOR            ; the digits summed: zero exactly when every
        TAD     DIGIT           ; one of them was, which is all anyone asks
        DAC     LSOR
        ISZ     LFD
        NOP
        IXC
        JMP     RDLTS
RDLTPD: LAC     LFD             ; pad the step out to three digits
        SAD     C3              ; skip while it is still short
        JMP     RDLTD
        JMP     RDLTPZ
RDLTPZ: LAC     LNV
        CAL     TIMES10
        DAC     LNV
        ISZ     LFD
        NOP
        JMP     RDLTPD
RDLTD:  LAC     (TXTP) , X
        SAD     DOT             ; skip when it is not a point
        JMP     RDLERR          ; two points in one line number
        LAC     LNV
        RET

RDLERR: LAC     ERRL
        JMP     ERROR

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
; =====================================================================
; Finding a line.
;
; A key heads every line and its length follows, so looking one up is a walk:
; read a word, compare, and when it does not match step to start+length.  That
; is a compare and an add per line, which is what the rope index of <key,
; position> pairs used to buy -- back when the walk was over characters and had
; to parse a number at every line.  With the header a pair of words the index,
; its chunks, its build and its invalidation on every edit are unnecessary.
; =====================================================================

; LINEXT: step the text pointer to the line after this one
LINEXT: PSH     IX
        POP     AC
        DAC     LIT
        IXC
        LAC     (TXTP) , X      ; the length counts the whole line
        TAD     LIT
        DAC     LIT
        LIX     LIT
        RET

; LILOOK: TARG -> the head of that line in AC, biased by one so that zero can
;         mean absent
LILOOK: PSH     IX
        LAC     TXTB
        DAC     TXTP
        LIX     NIL
LILL:   LAC     (TXTP) , X
        SKNZ
        JMP     LILMISS
        SAD     TARG            ; skip when this is not the line
        JMP     LILHIT
        CAL     LINEXT
        JMP     LILL
LILHIT: PSH     IX
        POP     AC
        IAC
        DAC     LIT
        POP     IX
        LAC     LIT
        RET
LILMISS: POP    IX
        CLA
        RET

; LIGE: the smallest line number at or above LIB, in AC, with that line's head
;       in LIGP; zero when there is nothing that high.  The lines are held in
;       ascending order, so the first one in range is the answer.
LIGE:   PSH     IX
        LAC     TXTB
        DAC     TXTP
        LIX     NIL
        CLA
        DAC     LIGP
LIGL:   LAC     (TXTP) , X
        SKNZ
        JMP     LIGMISS
        DAC     LIGN
        LAC     LIB
        CIA
        TAD     LIGN
        AND     BIT17
                SKNZ                    ; skip when below the bound
        JMP     LIGHIT
        CAL     LINEXT
        JMP     LIGL
LIGHIT: PSH     IX
        POP     AC
        IAC
        DAC     LIGP
        POP     IX
        LAC     LIGN
        RET
LIGMISS: POP    IX
        CLA
        RET


FIND:   CAL     LILOOK          ; one lookup instead of a walk
        SKNZ
        JMP     FINDX           ; no such line
                                ; and on into FINDP with its position

; FINDP: the head of a line, biased by one so that zero can mean absent, in AC.
; Every caller runs STEP next, and STEP is what steps over the key and the
; length.
FINDP:  TAD     MONE            ; undo the bias
        DAC     LIT
        LAC     TXTB            ; a jump always lands in the stored program
        DAC     TXTP
        CLA
        IAC
        DAC     INPROG
        LIX     LIT
        RET
FINDX:  LAC     ERRL
        JMP     ERROR

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
STEP1:  LAC     (TXTP) , X      ; the key heads the line, its length follows,
        SKNZ                    ; and the body is past the pair
        JMP     ENDRUN
        IXC
        IXC
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
        IXC                     ; past the command word
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
        IXC                     ; past the command word
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
        IXC                     ; past the command word
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
        LAC     ARGN
        SKNZ
        JMP     DOIFR
        LAC     (TXTP) , X      ; not this arm, so step over it: a marker and
        AND     LNMASK          ; its value, two words, no reading required
        SAD     LNTAG           ; skip when it is not a line number
        JMP     DOIFS
        JMP     RDLERR
DOIFS:  IXC
        IXC
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
DOIFR:  CAL     RDLN
        DAC     TARG
DOIFJ:  CAL     FIND
        CLA
        DAC     MORE
        RET

; GOTO n
DOGOTO: LIX     TPSAVE
        IXC                     ; past the command word
        CAL     SKSP
        CAL     RDLN
        DAC     TARG
        CAL     FIND
        CLA
        DAC     MORE
        RET


; WRITE: list the stored program.
;
; The stored form is a compression of what was typed, so listing it is the
; decompression: a key, then characters kept verbatim, then the two kinds of
; word the compiler put there.  Only the number's own spelling is lost, and it
; comes back canonical, which is what FOCAL did anyway.
DOWRIT: LIX     TPSAVE
        CAL     EOL
        PSH     IX
        LIX     NIL
DOWR1:  LAC     (TXTB) , X      ; the stored program, not the line just typed
        SKNZ
        JMP     DOWR2
        CAL     WKEYP           ; the key heads every line
        IXC
        IXC                     ; and its length, which is not printed
DOWR3:  LAC     (TXTB) , X
        SKNZ
        JMP     DOWR2
        SAD     NLC             ; skip when it is not the end of the line
        JMP     DOWR4
        AND     ITEMB
        SKNZ
        JMP     DOWR5           ; a character, kept as it was
        LAC     (TXTB) , X
        AND     LNMASK
        SAD     LNTAG           ; skip when it is not a line number
        JMP     DOWR6
        CAL     WCMD            ; a command word
        IXC
        JMP     DOWR3
DOWR6:  IXC                     ; a line number: its value is the next word
        LAC     (TXTB) , X
        CAL     WKEYP
        IXC
        JMP     DOWR3
DOWR5:  LAC     (TXTB) , X
        CAL     PUTC
        IXC
        JMP     DOWR3
DOWR4:  LAC     NLC
        CAL     PUTC
        IXC
        JMP     DOWR1
DOWR2:  POP     IX
        RET

; WCMD: the command word at the text pointer, spelled back out.  The word says
; which letter and how many of its letters were written, so G, GO and GOTO all
; come back as they went in, and a trailing point with them.
WCMD:   PSH     IX
        LAC     (TXTB) , X
        DAC     WCH
        CAL     CNLOOK          ; the letter selects a name
        DAC     WN
        LAC     WCH
        SRA
        SRA
        SRA
        SRA
        SRA
        AND     C7
        DAC     WCH2            ; letters written
        LIX     NIL
WCMDL:  LAC     WCH2
        SKNZ
        JMP     WCMDD
        LAC     (WN) , X
        CAL     PUTC
        IXC
        DSZ     WCH2
        NOP
        JMP     WCMDL
WCMDD:  LAC     WCH
        AND     CDOTB           ; the point, exactly as it was typed
        SKNZ
        JMP     WCMDX
        LAC     DOT
        CAL     PUTC
WCMDX:  POP     IX
        RET

; WKEYP: a line number in AC, printed gg.sss, or gg when the step is zero and
; the number named a group.  WRITE lists a program once, so the general divide
; is the right tool here and splitting the value costs nothing worth saving.
WKEYP:  DAC     M1
        LAC     C1000
        DAC     M2
        CAL     DIV
        DAC     WKEY            ; the group
        LAC     MREM
        DAC     WSTEP
        LAC     WKEY            ; two digits, so a leading zero when it is small
        TAD     M10
                SKM                     ; skip when below ten
        JMP     WK1
        LAC     ZEROC
        CAL     PUTC
WK1:    LAC     WKEY
        CAL     PNUM
        LAC     WSTEP
        SKNZ
        RET                     ; a group is written without a point
        LAC     DOT
        CAL     PUTC
        LAC     WSTEP           ; three digits, zeros in front as needed
        TAD     M100
                SKM                     ; skip when below a hundred
        JMP     WK2
        LAC     ZEROC
        CAL     PUTC
        LAC     WSTEP
        TAD     M10
                SKM                     ; skip when below ten
        JMP     WK2
        LAC     ZEROC
        CAL     PUTC
WK2:    LAC     WSTEP
        CAL     PNUM
        RET

; ERASE: clear every variable
; ERASE drops every block instead of walking every variable: the class
; pointers go empty and the heap rewinds, which is the whole of it.
DOERAS: LIX     TPSAVE
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
DOER2:  LAC     HEAPTOP
        DAC     HEAP
        POP     IX
        RET

; DO gg.sss runs that line as a subroutine, then carries on after the DO.
; DO gg, a group with no step, runs every line of the group in turn, which is
; what the fixed point line numbers are for.
;
; The nesting lives on the hardware stack -- the mode, the text pointer, and
; for a group the cursor and the group's upper end -- so DO inside DO needs no
; interpreter state at all, and a nested DO cannot overwrite the outer walk.
; The mode is saved because FIND moves both the pointer and INPROG into the
; stored program: without it, a DO typed at the prompt would carry on running
; the program from wherever the typed line's offset happened to fall.
DODO:   LIX     TPSAVE
        IXC                     ; past the command word
        CAL     SKSP
        CAL     RDLN
        DAC     TARG
        LAC     LNMK            ; the marker records that the number was
        AND     GRPBIT          ; written without a point, so it names a group
        DAC     DOGF
        LAC     INPROG
        PSH     AC
        LAC     TXTP
        PSH     AC
        PSH     IX              ; the rest of this line, to come back to
        LAC     DOGF
        SKNZ                    ; skip when it named a group
        JMP     DODO1
        JMP     DOGRP
DODO1:  CAL     FIND            ; the head of line TARG
        CAL     STEP            ; run it
        JMP     DODOD

DOGRP:  LAC     TARG            ; the group's last possible number, parked
        TAD     C999            ; under the cursor for the whole walk
        PSH     AC
        LAC     TARG
        PSH     AC
DOGRPL: POP     AC
        DAC     LIB             ; the cursor
        POP     AC
        DAC     DOGL            ; the upper end
        CAL     LIGE
        SKNZ
        JMP     DOGRPE          ; the index holds nothing that high
        DAC     TARG
        CIA
        TAD     DOGL
        AND     BIT17
                SKNZ                    ; skip when past the group
        JMP     DOGRPI
        JMP     DOGRPE
DOGRPI: LAC     DOGL
        PSH     AC
        LAC     TARG            ; the cursor moves one past the line we run
        IAC
        PSH     AC
        LAC     LIGP            ; the position LIGE already found
        CAL     FINDP
        CAL     STEP
        LAC     DORF            ; RETURN unwinds the group, not just the line
        SKNZ
        JMP     DOGRPL
        POP     AC
        POP     AC
        JMP     DODOD

DOGRPE: LAC     DOGL            ; the cursor never left the group's base, so
        TAD     M999            ; nothing ran: the group does not exist
        SAD     LIB             ; skip when the cursor has moved
        JMP     RDLERR
        JMP     DODOD

DODOD:  POP     IX
        POP     AC
        DAC     TXTP
        POP     AC
        DAC     INPROG
        CLA
        DAC     DORF            ; a RETURN is spent here, not further out
        CAL     EOS             ; and the rest of the line runs, which is what
        RET                     ; FOCAL does: a DO is not the end of a line

; ASK v {, v}: read a decimal number from the keyboard into each variable.
; KSF tests the device flag and skips in one instruction without touching AC,
; which is the whole point of putting status behind IOT rather than in memory.
DOASK:  LIX     TPSAVE
        IXC                     ; past the command word
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
        IXC                     ; past the command word
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

; RETURN: abandon the rest of the line, which is how a DO comes back early.
; Over a group the rest of the group goes too, so a subroutine spread across
; several lines can leave from the middle of the first.
DORET:  LIX     TPSAVE
        CAL     EOL
        CLA
        IAC
        DAC     DORF
        CLA
        DAC     MORE
        RET

; step over a run of letters, stopping on the first character that is not one,
; end of line included
SKIPT:  LAC     (TXTP) , X
        TAD     MACHR
                SKNM                    ; skip when not negative
        RET
        IXC
        JMP     SKIPT
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

        .org    0x1FF00
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

; The command names.  A command's letter is its own first character, so there is
; no second table indexed by letter: CNLOOK searches this list, which keeps
; every word up here read only.  What cannot be derived is the other direction
; -- CTAB holds jumps, and an address carries no letters -- so adding a command
; means a name here and a JMP there, and bench.py checks the two agree.
CNAMES: .dd     NASK, NCOMMENT, NDO, NERASE, NFOR, NGOTO
        .dd     NIF, NQUIT, NRETURN, NSET, NTYPE, NWRITE, 0

NASK:     .dd     "ASK", 0
NCOMMENT: .dd     "COMMENT", 0
NDO:      .dd     "DO", 0
NERASE:   .dd     "ERASE", 0
NFOR:     .dd     "FOR", 0
NGOTO:    .dd     "GOTO", 0
NIF:      .dd     "IF", 0
NQUIT:    .dd     "QUIT", 0
NRETURN:  .dd     "RETURN", 0
NSET:     .dd     "SET", 0
NTYPE:    .dd     "TYPE", 0
NWRITE:   .dd     "WRITE", 0



; The heap grows down from the top of the arena, HCARVE taking blocks off it as
; classes of names appear, so what is used is what is spent -- and the program
; text growing up from the bottom is the only thing it can collide with.

; The bottom of the arena: the text grows up from here while the heap grows down
; from the top of the same span, so the two share one boundary rather than
; having a ceiling each.  It reads best last and .org places it regardless.
        .org    0x2000
        .include "program.s"
