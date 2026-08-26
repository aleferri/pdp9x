        .dd     RESET
        .dd     STOP
        .dd     STOP
        .dd     STOP
        .dd     STOP
        .dd     STOP
        .dd     STOP
        .dd     STOP
        .include "arithlib.s"
        .advance 0x2400
RESET:  HTON                    ; arm the harness timer
        WAIT                    ; and stop until it fires
        HOUT                    ; reached only if the wait ended
STOP:   HLT
