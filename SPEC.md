# 18-bit accumulator machine — architecture specification

An 18-bit word, accumulator-oriented machine in the PDP-4/7/9/15 line, with a
hardware stack, a single index register and a four-entry interrupt vector.

Status: consistent with `sim.py`, `machine.py` and `pdp9x.casm`. Every claim
about behaviour in this document is exercised by `run.py` or by one of the
sample programs.

---

## 1. Programming model

| Register | Width | Notes |
|---|---|---|
| `AC` | 18 | Accumulator |
| `IX` | 18 | Index register; also a second ALU destination |
| `L` | 1 | Link: carry from `TAD`, overflow from `TAS`, shift input/output |
| `PC` | 17 | Program counter |
| `SP` | 12 | Stack pointer, confined to page 1 |
| `I` | 1 | Interrupt enable |

Internal, not program visible: `IR`, `AR[16:0]`, `DI`, `DO`, `T`.

Memory is 131072 words of 18 bits, word addressed. There is no byte
addressing and no unaligned access.

### Two's complement

Negative numbers are two's complement. `TAD` is an unsigned add that reports
carry out in `L`; `TAS` is the same addition reporting signed overflow in `L`.
The pair gives two different comparison predicates, which matters — see §9.

---

## 2. Instruction formats

Opcodes 0–7 (memory reference with a register selector):

```
17..14  13   12   11    10..0
 op(4)   I    X    r    addr(11)
```

Opcodes 8–11 (control and read-modify-write):

```
17..14  13   12   11..0
 op(4)   I    X    addr(12)
```

Opcode 14 is `IOT`, opcode 15 is `OPR`; both use bits 13..0 as a
device or microinstruction field.

`r` selects the register the operation reads and writes: `r=0` is `AC`,
`r=1` is `IX`. It applies uniformly to all eight opcodes 0–7, not only to the
load/store/compare group.

### Addressing modes

`mm` is the pair `{I, X}` in bits 13 and 12. The two bits are independent, not
an enumerated selector.

| mm | Mode | Effective address |
|---|---|---|
| `00` | direct | `addr` zero extended |
| `01` | indexed | `addr + IX` |
| `10` | indirect | `M[addr]` |
| `11` | indirect indexed | `M[addr] + IX` |

`addr` is 11 bits (zero page 0..2047) for opcodes 0–7 and 12 bits (0..4095)
for opcodes 8–11.

**Exception, `CAL` and `JMP` only.** For those two opcodes `mm = 00` does not
mean direct; it means PC-page relative:

```
EA = { PC[16:12], addr[11:0] }
```

The five high bits come from the page of the **instruction itself**, not from
`PC` after the increment. A `JMP` in the last word of a page therefore targets
its own page, not the next one. `ISZ` and `DSZ` keep plain direct addressing,
so `10xx` decodes as PC-page when bit 1 of the opcode is clear and as zero
page when it is set.

The effective address is always truncated to 17 bits. This is load bearing:
biased pointers rely on the wrap (§9).

---

## 3. Opcode map

| Code | `r=0` | `r=1` | Effect |
|---|---|---|---|
| `0000` | `TAD` | `TADX` | reg ← reg + M; `L` ← carry out |
| `0001` | `TAS` | `TASX` | reg ← reg + M; `L` ← signed overflow |
| `0010` | `AND` | `ANDX` | reg ← reg ∧ M |
| `0011` | `XOR` | `XORX` | reg ← reg ⊕ M |
| `0100` | `DAC` | `DIX` | M ← reg |
| `0101` | `LAC` | `LIX` | reg ← M |
| `0110` | `SAD` | `SXD` | skip if reg ≠ M |
| `0111` | `IOR` | `IORX` | reg ← reg ∨ M |
| `1000` | `CAL` | | push {L, PC}; PC ← EA |
| `1001` | `JMP` | | PC ← EA |
| `1010` | `ISZ` | | M ← M + 1; skip if zero |
| `1011` | `DSZ` | | M ← M − 1; skip if zero |
| `1100` | reserved | | |
| `1101` | reserved | | |
| `1110` | `IOT` | | |
| `1111` | `OPR` | | |

`ISZ` and `DSZ` do not touch `L`. This is deliberate: loop counters must not
destroy the flag a comparison just produced.

`SAD`/`SXD` skip on **inequality**. There is no skip-on-equality, so the
common "loop while equal" shape costs an extra jump:

```
        SAD     LIMIT           ; skip while different
        JMP     done
        JMP     loop
```

---

## 4. OPR, opcode 1111

Bits 13:12 select the group.

### Group 0 — accumulator and link

| Bit | Mnemonic | Effect |
|---|---|---|
| 11 | `CLA` | `AC` ← 0 |
| 10 | `CLL` | `L` ← 0 |
| 9 | `CMA` | `AC` ← ¬`AC` |
| 8 | `CML` | `L` ← ¬`L` |
| 7 | `RLA` | rotate {`L`,`AC`} left one |
| 6 | `RRA` | rotate {`L`,`AC`} right one |
| 5 | `SHA` | `AC` ← `AC` << 1, zero fill |
| 4 | `SRA` | `AC` ← `AC` >> 1, sign extend |
| 3 | `IAC` | `AC` ← `AC` + 1 |
| 2 | `IXC` | `IX` ← `IX` + 1 |
| 1 | free | |
| 0 | `HLT` | halt |

Execution order when bits are combined: clear, then complement, then
increment, then shift or rotate, then halt. Placing the increment before the
shift makes `CIA` = `CMA` + `IAC` a two's complement negate, and
`CLA IAC RLA` a way to build small constants without touching memory.

`IAC` and `IXC` are `A + 0 + cin=1`, the same ALU path as `ISZ`, so they cost
nothing in the datapath beyond the decode. Like `SHA` and `SRA` they **do not
write `L`**, which keeps them composable with a comparison in flight; if the
carry is wanted, use `TAD` against a constant.

Both are needed, not just `IAC`: measured on the console driver, 800 of 824
explicit increments target `IX`, not `AC`.

**`SHA` and `SRA` leave `L` untouched.** They are pure arithmetic and compose
freely with a comparison in flight. `RLA` and `RRA` are the only path for a
bit to enter or leave `L`, which makes them the tool for multiple precision and
for testing the sign bit.

An all-zero group 0 word is the canonical `NOP`: one cycle, one memory access,
no side effect.

### Group 1 — skips

```
13..12  11   10..3    2    1    0
  01     N    ----    I    L    Z
```

`Z` is `AC = 0`, `L` is the link set, `I` is interrupts enabled. Selected
conditions are OR'd; `N` inverts the result.

With `N` set over more than one condition the result is a NOR, not "neither
condition individually". Follow the DEC convention and give each condition two
mnemonics by polarity — `SKZ`/`SKNZ`, `SKL`/`SKNL`, `SKI`/`SKNI` — so the
assembly programmer never meets the inversion. `N` with an empty mask is an
unconditional skip.

### Group 2 — stack

```
13..12  11   10..9    8..4    3     2     1     0
  10     D   I field  ----   AC    IX   LPC    SP
```

`D = 0` is push, `D = 1` is pop. Bits 3..0 are a register mask, one bit per
architectural register.

`I field`: `00` leave `I` alone, `01` clear it, `10` set it, `11` reserved.
The field is honoured even with an empty mask, so `EI` and `DI` cost no extra
encoding.

`LPC` is the pair {`L`, `PC`}: `L` in bit 17, `PC` in bits 16..0, filling a
word exactly. `SP` is stored zero extended and truncated to 12 bits on the way
back.

**Order.** Push walks the mask from bit 0 up to bit 3; pop walks it from bit 3
down to bit 0. The invariant that follows is the reason for the asymmetry:

```
PSH m ; POP m  ≡  NOP     for every mask m, SP included
```

`run.py` checks this for all sixteen masks. Because `SP` is at the low end,
`POP AC|SP` restores `SP` only after `AC` has been read.

On `POP SP` the popped value wins over the increment.

Transfers between registers fall out of composition, so no `PAX`/`PXA` style
instructions are needed:

| Sequence | Effect |
|---|---|
| `PSH IX ; POP AC` | `AC` ← `IX` |
| `PSH AC ; POP SP` | `SP` ← `AC`, truncated to the stack page |
| `POP LPC` | return, restoring `L` |

Useful aliases: `RET` = `POP LPC`, `RTI` = `POP LPC` with `I field = 10`.

### Group 3

Reserved.

---

## 5. Stack

Full descending, fixed to page 1:

```
address = { 000001, SP[11:0] }
```

`SP` is 12 bits and resets to 0, so the first push lands at `0x1FFF` and the
stack grows down. Push is `SP ← SP−1` then write; pop is read then `SP ← SP+1`.

Two properties follow from the width, and both are the point of choosing 12
bits over 18:

- **No bootstrap.** The reset value is the natural end of the page, not a
  lucky address. There is no chicken-and-egg where setting `SP` requires a
  valid `SP`.
- **It cannot escape.** Overflow wraps inside page 1 and overwrites the stack
  itself; it can never reach ROM, code or device registers. `POP SP` truncates,
  so a corrupted word on the stack cannot aim the pointer outside the page.

Cost: depth is capped at 4096 words and the stack cannot be relocated.

---

## 6. Interrupts

Vector table at words 0..7, entries are **indirect** — each word holds the
address of the handler. **Device *n* takes vector entry *n***, so the IOT
device field and the vector index are the same number.

| Word | Device |
|---|---|
| 0 | the processor: reset |
| 1..7 | peripherals |

Device 0 is the processor itself, which is why entry 0 is reset rather than an
interrupt, and why bit 0 of the interrupt mask is spare. Priority is device
order, lowest number first. Requests are sampled at exactly one point,
the fetch of the next instruction, which makes every instruction atomic with
respect to interrupts — including a multi-register `PSH`, whose mask dispatch
never crosses the decision point.

On acceptance of a request from device *n*:

```
push {L, PC_next}
I ← 0
PC ← M[n]
```

which is `CAL` with the target taken from the vector. Reset does **not** push:
`I ← 0`, `SP ← 0`, `PC ← M[0]`.

`I` is not saved. `L` plus a 17-bit `PC` fill a word exactly, so there is no
room; the handler is responsible for the state of `I` on return. Because `RTI`
restores `PC` and sets `I` in one instruction, there is no window between the
two and no delayed-enable hack is needed.

A routine shared between mainline and handler can decide its own return:

```
        SKNI                    ; skip if interrupts are off
        RET                     ; called from the mainline
        RTI                     ; called from inside a handler
```

The one case this cannot distinguish is a mainline that has executed `DI`,
since `DI` and interrupt entry produce the same observable state. Document it:
critical sections do not call shared routines.

`POP LPC` restores `L`, which makes `L` callee-saved by default — but not
unconditionally. The stacked word is ordinary memory in page 1, and a
subroutine can rewrite it before returning (§9).

---

## 7. IOT, opcode 1110

```
17..14  13..11  10..8   7..4    3     2      1      0
 1110   dev(3)  sub(3)  ----   CLA  IOP4   IOP2   IOP1
```

Eight devices, eight subdevices each.

**Device 7 is the processor itself**, and its only register is the interrupt
mask. The mask is CPU state, not device state: eight bits, **one per device**,
saying whether that peripheral is let through.

Mask and vector line up one for one: eight devices, eight entries, device *n*
at entry *n*. A narrower vector would also work — several devices would share
an entry and the handler would poll their status flags to find the source — but
with the processor occupying device 0 the two fit exactly, so no polling is
needed and there is no mapping table to get wrong.

| | |
|---|---|
| `IMRD` | `AC` ← mask |
| `IMWR` | mask ← `AC` |
| `IMSET` | let the lines set in `AC` through |
| `IMCLR` | mask the lines set in `AC` |

Masking hides a request, it does not clear it: the gating sits between the
device and the vector, so a peripheral that is holding a transfer keeps holding
it and is delivered the moment the bit reopens. `run.py` checks this, along
with two devices sharing a vector and one of them being masked out.

`I` and the mask answer different questions — `I` is whether to be interrupted
at all, the mask is by whom — and only `I` lives in the operate group, which
does enough already. Without a mask a driver that momentarily cannot accept one
more interrupt from its own device has only `DI`, which silences the whole
machine. Measured on the keyboard driver, whose queue fills during input:
global `DI` left the CPU uninterruptible for 42.6% of the run in one unbroken
window of 3271 instructions, against 33.4% and 2485 with the mask, and the
remainder is now only the inside of handlers.

- `IOP1` tests a device flag and skips. It never moves data.
- `IOP2` moves device → `AC`.
- `IOP4` moves `AC` → device.
- `CLA` clears `AC` before the transfer, so `CLA|IOP2` reads into a clean
  accumulator.

Everything that is a pulse or a flag belongs here rather than in memory, for
three reasons that showed up while writing the console driver:

1. A register where the written value is irrelevant is a command, not memory.
2. A memory-mapped status poll costs two instructions, three memory accesses,
   and destroys `AC`. `IOP1` costs one instruction and touches nothing.
3. A wild pointer cannot issue an `IOT`. It can very easily write a
   memory-mapped command register.

Arrays are the exception and stay in memory: a framebuffer wants indexed
addressing, and putting it behind an address/data register pair would cost an
extra instruction per element.

Current assignment:

| Device | Mnemonics |
|---|---|
| 0 processor | `IMRD`, `IMWR`, `IMSET`, `IMCLR` |
| 1 blitter | `SCROLL`, `SKBSY`, `SKRDY` |
| 2 timer | `TLOAD`, `TARM`, `TACK`, `SKIRQ` |
| 3 keyboard | `KRAW`, `KMOD`, `SKKB`, `KACK` |
| 4 LEDs | `LEDS` |
| 5 test harness | `HTON`, `HTOFF`, `HOUT`, `HACK` |

---

## 8. Datapath and timing

### Buses

| Bus | Sources | Sinks |
|---|---|---|
| `BD[17:0]` | `DO` | `IR`, `DI` |
| A | `AC`, `IX`, `SP`, `T`, `PC` | ALU port A |
| B | `DI`, `IR[11:0]` masked, forced zero | ALU port B |

The forced zero on B is not optional: it is what lets the ALU pass A through
unchanged for register moves, and what makes `IAC`, `IXC` and `SP ± 1` work
through the adder with carry in.
| R | ALU result, `DI`, `IR[11:0]` masked | `AC`, `IX`, `SP`, `T`, `DO`, `PC` |

`AR` has its own four-input mux: ALU result, `PC`, `DI`, and the concatenation
`{PC[16:12], IR[11:0]}`.

`L` is packed into bit 17 whenever `PC` crosses a bus, but it is **loaded
separately** through `mux(ALU_L, DI[17])` with its own enable. The enable is
asserted only when popping `LPC`. Without the separation, `JMP (PTR)` would
load bit 17 of a data word into `L` and silently destroy a comparison in
flight.

The `L` write enable is a function of `CLL | CML | RLA | RRA | TAD | TAS`, not
of group 0 as a whole, because `SHA` and `SRA` do not write it.

`PC + 1` is internal, driven by a `pc_inc` signal shared with the skip logic.

`ISZ` is `A + 0 + cin=1` and `DSZ` is `A + ¬0 + cin=0`, which also covers
`SP ± 1`. No constant injector is needed on bus B, only a force-zero plus the
ALU's invert-B and carry-in.

ALU condition outputs — zero, carry, overflow — go to the control block, which
returns `S[3:0]`.

### Timing

Address is registered in cycle N, the access happens in cycle N+1.

| Component | Cycles |
|---|---|
| opcode fetch | 1 |
| data read or write | 2 |
| indirection (an extra access) | 2 |
| PC loaded other than by increment | +1 |

Execute normally folds into the fetch of the following instruction, because
`AR ← PC` has already happened. It cannot fold whenever `PC` moves other than
by the plain increment: `CAL`, `JMP`, a taken skip, `POP LPC`, interrupt entry.
`ISZ` and `DSZ` pay the penalty only when they actually skip.

Measured on the samples: CPI 2.7 to 2.8.

### Control

Roughly 30 states, five to six bits. Group 2 is the largest block in state
count and the smallest in cycles: dispatch jumps straight to the state for the
highest priority set bit, each state clears its own bit and re-dispatches on
the residue, so the cost is `popcount(mask)`, not four.

`CAL` and interrupt entry reuse the `PSH LPC` states and add only the `PC`
load.

---

## 9. Idioms worth knowing

**Ordering comparisons.** There is no skip on sign. Two idioms cover it:

`TAD` against a precomputed negative constant gives an unsigned comparison
against an arbitrary limit, at the cost of one zero-page read:

```
        LAC     K
        TAD     MSIZE1          ; MSIZE1 = -(limit+1)
        SKL                     ; L = 1 when K > limit
```

`TAS` against a bias constant moves the limit onto the sign boundary and gives
the comparison for free, composed with indexing:

```
BIAS  = 2^17 - (limit+1)
base' = (array_base - BIAS) mod 2^17

        CLA
loop:   DAC     (base') , X
        TASX    STEP            ; L = 1 exactly when the index passes the limit
        SKL
        JMP     loop
```

The bias is absorbed by the base pointer because the effective address is
masked to 17 bits. On the sieve this replaced a ten instruction inner loop with
four and cut total cycles by 40 percent. It costs one extra zero-page word for
the biased pointer.

**The index register can hold the loop variable.** `TADX` increments it in
place and `SXD` compares it without going through `AC`, so the reload before
each array access disappears.

**Reading `IX` into `AC`** is `PSH IX ; POP AC`, two instructions, no temporary
in memory.

**Rewriting the return word.** `POP LPC` restores `L` from the stacked word,
so the default is callee-saved. But the word can be edited first, because
`POP AC` reads it as data:

```
SETL:   POP     AC              ; AC = { L_caller, PC_ret }
        IOR     BIT17           ; BIT17 = 0x20000
        PSH     AC
        RET                     ; returns with L = 1
```

`AND` against `0x1FFFF` clears it instead. Four instructions and one constant
per polarity — awkward enough that passing the flag in `AC` is usually better,
but it is available when the caller's calling convention wants `L`.

The same handle gives a **skip return**, the classic PDP idiom for signalling
success out of band:

```
SKIPRET:
        POP     AC
        IAC                     ; bump the packed return address
        PSH     AC
        RET                     ; returns to caller+1
```

The caller places the failure path immediately after the `CAL` and the success
path after that. Note that `IAC` on the packed word carries into bit 17 if
`PC_ret` is `0x1FFFF`, which would corrupt `L`; harmless in practice, but it is
a real edge.

**Shared temporaries need saving.** `PSH AC , IX` saves the registers, not the
zero-page scratch a routine uses. A routine called from both the mainline and
a handler must have its scratch saved explicitly by the handler.

---

## 10. Known gaps

- **No skip on equality.** `SAD`/`SXD` are inequality only; every "loop while
  equal" pays an extra jump. There are free bits in group 1.
- **No skip on sign.** Worked around by §9; the alternative, `RLA` + `SKL` +
  `RRA`, costs three instructions and disturbs `AC`.
- **Opcodes `1100` and `1101` are unassigned.**
- **Returning `L` from a subroutine is awkward, not impossible** (§9). A
  keep-link bit on pop would make it free, at the cost of one bit and of the
  transparency that makes interrupts invisible.
