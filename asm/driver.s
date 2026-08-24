; Buffered console driver.
;   framebuffer : 0x4000, 512 words, write only, one write per 8 cycles
;   blitter     : IOT dev 0  -- SCROLL, SKBSY, SKRDY
;   timer       : IOT dev 1  -- TLOAD, TARM, TACK, SKIRQ.  Times the scroll.
; During a scroll the framebuffer is deaf, so output is queued in BUF with the
; newlines kept inline; on scroll-done the queue is replayed through the normal
; putc/newline path instead of being memcpy'd, so a queued newline issues the
; next scroll by itself and no need_scroll flag is required.

        .dd     RESET   ; 0 reset
        .dd     STOP    ; 1 blitter
        .dd     DONE    ; 2 timer
        .dd     STOP    ; 3 keyboard
        .dd     STOP    ; 4 leds
        .dd     STOP    ; 5 spare
        .dd     STOP    ; 6 spare
        .dd     STOP    ; 7 spare

; ---- state ----
LINE:   .dd    0               ; 0..15
INDX:   .dd    0               ; 0..511
BUSY:   .dd    0
BUFP:   .dd    0               ; write offset into BUF
CAP:    .dd    64
NPEND:  .dd    0
IDXT:   .dd    0
ENDX:   .dd    0
CHR:    .dd    0
; ---- constants ----
ONE:    .dd    1
C15:    .dd    15
C512:   .dd    512
C32:    .dd    32
C64:    .dd    64
SPACE:  .dd    32
NLCH:   .dd    10
THIV:   .dd    226             ; (256-226)*256 = 7680 counts
SCRP:   .dd    0x4000          ; framebuffer base
; ---- program driven state ----
NLINE:  .dd   -24
CH:     .dd    64
WORK:   .dd    0
WORKV:  .dd   -250             ; simulated per line computation

        .advance 0x400
BUF:    .advance 0x440          ; queue, 64 words
SCR:    .advance 0x480          ; replay scratch, 64 words

        .advance 0x2000

; =====================================================================
RESET:  CLA
        DAC     LINE
        DAC     INDX
        DAC     BUSY
        DAC     BUFP
        LAC     C64
        DAC     CAP
        CAL     CLS
        EI

MAIN:   LAC     CH              ; produce one line: a character, then newline
        TAD     ONE
        DAC     CH
        CAL     PUTC
        LAC     WORKV           ; pretend to compute the next line
        DAC     WORK
BURN:   ISZ     WORK
        JMP     BURN
        LAC     NLCH
        CAL     PUTC
        ISZ     NLINE
        JMP     MAIN
DRAIN:  LAC     BUSY            ; let the last scroll finish
        SKNZ
        JMP     STOP
        JMP     DRAIN
STOP:   HLT

; ---- PUTC: AC = character -------------------------------------------
PUTC:   DAC     CHR
        SAD     NLCH            ; skip when the character is not a newline
        JMP     NEWL
        LAC     BUSY
        SKNZ
        JMP     PCDIR
        LAC     CAP
        SKZ
        JMP     PCBUF
        CAL     WAITRDY
PCDIR:  LIX     INDX
        LAC     CHR
        DAC     (SCRP) , X
        ISZ     INDX
        NOP
        RET
PCBUF:  LIX     BUFP
        LAC     CHR
        DAC     BUF , X
        ISZ     BUFP
        NOP
        DSZ     CAP
        NOP
        RET

; ---- NEWL -----------------------------------------------------------
NEWL:   LAC     BUSY
        SKNZ
        JMP     NLNOW
        LAC     CAP
        SKZ
        JMP     PCBUF           ; queue the newline like any other character
        CAL     WAITRDY
NLNOW:  LAC     LINE
        SAD     C15             ; skip while we are not on the last line
        JMP     NLSCR
        ISZ     LINE
        NOP
        CAL     SETIDX
        RET
NLSCR:  SCROLL
        CAL     TSTART
        LAC     ONE
        DAC     BUSY
        RET

; ---- INDX = 32 * LINE ------------------------------------------------
SETIDX: LAC     LINE
        SHA
        SHA
        SHA
        SHA
        SHA
        DAC     INDX
        RET

; ---- arm the timer for the scroll duration --------------------------
TSTART: LAC     THIV
        TLOAD
        TARM
        RET

; ---- spin until the blitter is free ---------------------------------
WAITRDY:
        LAC     BUSY
        SKNZ
        RET
        JMP     WAITRDY

; ---- clear the screen ------------------------------------------------
CLS:    CLA
        DAC     INDX
        LIX     INDX
        LAC     SPACE
CLS1:   DAC     (SCRP) , X
        TADX    ONE
        SXD     C512
        JMP     CLS2
        JMP     CLS1
CLS2:   RET

; ---- scroll finished -------------------------------------------------
DONE:   PSH     AC , IX
        LAC     CHR             ; the replay calls PUTC, which owns CHR
        PSH     AC
        TACK
        CAL     SETIDX          ; LINE is still 15, cursor to the fresh row
        LAC     INDX
        TAD     C32
        DAC     ENDX
        LIX     INDX
        LAC     SPACE
BLNK:   DAC     (SCRP) , X
        TADX    ONE
        SXD     ENDX
        JMP     BLNKD
        JMP     BLNK
BLNKD:  CLA
        DAC     BUSY

; snapshot the queue, reset it, then replay
        LAC     BUFP
        DAC     NPEND
        SKNZ
        JMP     RPDONE
        CLA
        DAC     IDXT
CPY:    LIX     IDXT
        LAC     BUF , X
        DAC     SCR , X
        ISZ     IDXT
        NOP
        LAC     IDXT
        SAD     NPEND           ; skip while IDXT != NPEND
        JMP     CPYD
        JMP     CPY
CPYD:
        CLA
        DAC     BUFP
        LAC     C64
        DAC     CAP
        CLA
        DAC     IDXT
FEED:   LIX     IDXT
        LAC     SCR , X
        CAL     PUTC
        ISZ     IDXT
        NOP
        LAC     IDXT
        SAD     NPEND           ; skip while IDXT != NPEND
        JMP     RPDONE
        JMP     FEED
RPDONE: POP     AC
        DAC     CHR
        POP     AC , IX
        SKNI
        RET
        RTI
