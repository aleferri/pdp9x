        .dd     RESET
        .dd     STOP
        .dd     STOP
        .dd     STOP
        .dd     STOP
        .dd     STOP
        .dd     STOP
        .dd     STOP
        .include "arithlib.s"
        .org    0x1F400
RESET:  HTON                    ; arm the harness timer
        WAIT                    ; and stop until it fires
        HOUT                    ; reached only if the wait ended
STOP:   HLT
