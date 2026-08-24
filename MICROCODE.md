# Microcode

Control design for the 18-bit machine described in `SPEC.md`. The timing model
there — fetch one cycle, a data access two, one more whenever `PC` moves other
than by the plain increment — is not an assumption here: it is the thing this
microprogram has to deliver, and §5 checks that it does.

---

## 1. Microword

Thirty-five signals are needed. Rounding to **36 bits** leaves one spare and
makes a microword exactly two machine words wide, which matters only in that
the control store can be blown from the same tooling as everything else.

| Field | Bits | Values |
|---|---|---|
| `ASRC` | 3 | bus A source: none, `AC`, `IX`, `SP`, `T`, `PC` |
| `BSRC` | 2 | bus B source: `DI`, `IR[11:0]`, zero |
| `ALU` | 4 | add, and, or, xor, pass A, shift left, shift right arithmetic, rotate left, rotate right, complement A |
| `CIN` | 1 | carry in |
| `RDST` | 3 | bus R destination: none, `AC`, `IX`, `SP`, `T`, `PC`, `DO` |
| `LCTL` | 2 | `L`: hold, load `ALU_L`, load `DI[17]` |
| `ARSRC` | 3 | `AR`: hold, ALU, `PC`, `DI`, `{PC[16:12], IR[11:0]}`, stack page |
| `MEM` | 2 | idle, read, write |
| `PCINC` | 1 | increment `PC` |
| `ICTL` | 2 | `I`: hold, clear, set |
| `SEQ` | 3 | next, jump, map, map2, mapmask, branch, fetch |
| `CC` | 3 | which condition the branch tests |
| `NA` | 7 | next microaddress |

Control store **128 × 36**. Two small map ROMs, below.

### How the tail folds, and where it cannot

`BD` connects `IR` and `DI` on the way in and `DO` on the way out, nothing
else. An operand therefore lands in `DI` at a clock edge and the ALU can only
see it the cycle after, so a memory reference looks like four cycles: fetch,
address, read, execute.

It is three because the execute cycle **is** the next instruction's fetch. The
last microword of a memory reference reads memory at `AR`, loads `IR` from
`BD`, increments `PC` and dispatches — while simultaneously driving `DI`
through the ALU into `AC` or `IX`. Nothing collides: the fetch uses `BD`, `IR`
and the `PC` incrementer, the tail uses buses A, B and R.

For that to be one microword rather than one per opcode, the `ALU` field has a
code meaning **take the function from `IR[17:14]`**, and `RDST` a code meaning
**take the register from `IR[11]`**. The old `IR` is still readable during the
cycle that loads the new one.

**The fold fails when the result decides where to go next.** `SAD` and `SXD`
compare in order to skip, and the fetch address is not known until the compare
has happened, so they get a cycle of their own: four either way. `ISZ` and
`DSZ` were already five because they write back, and their skip is decided in
time. Everything that only writes a register — `TAD`, `TAS`, `AND`, `XOR`,
`IOR`, `LAC` — folds.

**`DO` gets its own input mux** from `AC`, `IX` and `{L, PC}`, beside bus R
rather than on it. Otherwise an indexed store could not capture the value
while the ALU is busy computing the address, and `DAC v,X` would cost four
cycles instead of three.

---

## 2. Sequencer

| `SEQ` | Next microaddress |
|---|---|
| `NEXT` | µPC + 1 |
| `JUMP` | `NA` |
| `MAP` | `MAP1[IR[17:12]]` |
| `MAP2` | `MAP2[IR[17:14], IR[11]]` |
| `MAPMASK` | `MAP3[priority(MSK)]`, and the selected bit of `MSK` is cleared |
| `BRANCH` | `NA` if `CC` holds, else µPC + 1 |
| `FETCH` | address 0 |

### MAP1 is where the encoding pays

`MAP1` is indexed by **`IR[17:12]`**, six bits: the four opcode bits plus the
two below them. Those two bits are the addressing mode for opcodes 0 through
11 and the group selector for `OPR`. One dispatch therefore resolves opcode,
addressing mode and operate group at once, in the same cycle as the fetch,
because the ISA put them in the same place.

| `IR[17:12]` | Entry |
|---|---|
| `0000 00` .. `1011 11` | 48 entries: the four effective-address sequences, one per mode |
| `1100 xx`, `1101 xx` | reserved opcodes: trap |
| `1110 xx` | `IOT` |
| `1111 00` .. `1111 11` | the four operate groups |

`MAP2` runs after the effective address exists and picks the operation:
sixteen opcodes by the `r` bit, thirty-two entries. `MAP3` turns the priority
encoding of the stack mask into one of eight sequences, push and pop for each
of the four registers.

### The interrupt check costs nothing

At `FETCH`, when a request is pending and `I` is set, the sequencer forces the
microaddress to `IRQ` **and suppresses `PCINC` and the `IR` load**. The
instruction just read is discarded and `PC` still points at it, which is
exactly what has to be pushed. No cycle is spent looking.

`MSK[3:0]` is loaded from `BD[3:0]` during every fetch. It only means anything
for group 2 of `OPR`, and loading it unconditionally is cheaper than deciding
not to.

---

## 3. Microprogram

Written as `destination ← source`, one line per cycle.

### Fetch

```
00 FETCH:  MEM=read, IR←BD, MSK←BD[3:0], PCINC, SEQ=MAP
01 FETCH_A:MEM=read, IR←BD, MSK←BD[3:0], PCINC, SEQ=MAP,
           A=reg per old IR[11], B=DI, ALU=per old IR[17:14],
           R→reg per old IR[11], L←ALU_L if the opcode writes it
```

`FETCH_A` is the fetch that also finishes the instruction before it. There is
one of them, not one per opcode, because the `ALU` and `RDST` fields can say
"read it out of `IR`".

`AR` already holds `PC`: every terminal microinstruction leaves it that way,
which is what makes the fetch a single cycle. It also means no terminal
microinstruction may use the `PC→AR` path for anything else.

### Effective address, one sequence per mode

```
10 EA_PG:  AR←{PC[16:12],IR[11:0]}, SEQ=MAP2      ; CAL and JMP, mm=00
11 EA_ZP:  AR←IR[11:0],             SEQ=MAP2      ; everything else, mm=00
12 EA_IDX: A=IX, B=IR[11:0], ALU=add, AR←ALU, SEQ=MAP2
13 EA_IN1: AR←IR[11:0], SEQ=NEXT
14 EA_IN2: MEM=read, DI←BD, SEQ=NEXT
15 EA_IN3: AR←DI, SEQ=MAP2
16 EA_IX1: AR←IR[11:0], SEQ=NEXT                  ; mm=11
17 EA_IX2: MEM=read, DI←BD, SEQ=NEXT
18 EA_IX3: A=IX, B=DI, ALU=add, AR←ALU, SEQ=MAP2
```

### Operations

```
20 OP_RD:  MEM=read, DI←BD, AR←PC, SEQ=JUMP FETCH_A  ; TAD TAS AND XOR IOR LAC
23 OP_DAC: MEM=write, AR←PC, SEQ=FETCH               ; DO was loaded during EA
24 OP_SAD: MEM=read, DI←BD, SEQ=NEXT                 ; cannot fold: see above
25         A=reg, B=DI, ALU=sub, SEQ=BRANCH CC=NZ NA=SKIP
26         AR←PC, SEQ=FETCH
27 SKIP:   PCINC, AR←PC+1, SEQ=FETCH

30 OP_JMP: PC←AR, AR←ALU(=AR), SEQ=FETCH
31 OP_CAL: T←AR, SEQ=NEXT
32         A=SP, ALU=dec, R→SP, AR←stack, SEQ=NEXT
33         A=PC with L in bit 17, MEM=write, SEQ=NEXT
34         A=T, ALU=pass A, R→PC, AR←ALU, SEQ=FETCH

38 OP_ISZ: B=BD, ALU=pass B, CIN=1, R→DO, MEM=read, SEQ=NEXT
39         MEM=write, SEQ=BRANCH CC=Z NA=SKIP
3A         AR←PC, SEQ=FETCH
```

`DSZ` is the same pair with `ALU=add ¬0, CIN=0`, which is the subtraction the
adder already does.

### Operate

```
40 G1:     A=AC, ALU=per the microinstruction bits, R→AC, L←ALU_L if enabled,
           AR←PC, SEQ=FETCH
44 G2:     SEQ=BRANCH CC=G2 NA=SKIP
45         AR←PC, SEQ=FETCH
48 G3:     SEQ=MAPMASK
50 PSH_SP: A=SP, ALU=dec, R→SP, AR←stack, SEQ=NEXT
51         A=SP, ALU=pass A, MEM=write, SEQ=MAPMASK
52 PSH_LPC:A=SP, ALU=dec, R→SP, AR←stack, SEQ=NEXT
53         A=PC with L, MEM=write, SEQ=MAPMASK
   ... IX and AC the same shape ...
60 POP_AC: AR←stack, SEQ=NEXT
61         B=BD, ALU=pass B, R→AC, A=SP, ALU=inc, R→SP, MEM=read, SEQ=MAPMASK
   ... and so on, LPC additionally doing L←DI[17] ...
68 G3_END: ICTL per IR[10:9], AR←PC, SEQ=FETCH
```

`MAPMASK` returns to `G3_END` once `MSK` is empty. Push walks the mask upward
and pop downward, which is the whole reason `PSH m ; POP m` is the identity:
the priority encoder is wired to select the lowest set bit for push and the
highest for pop, off the same `MSK` register.

### Interrupt entry

```
70 IRQ:    A=SP, ALU=dec, R→SP, AR←stack, SEQ=NEXT
71         A=PC with L, MEM=write, ICTL=clear, SEQ=NEXT
72         AR←device number, SEQ=NEXT
73         MEM=read, B=BD, ALU=pass B, R→PC, SEQ=NEXT
74         AR←PC, SEQ=FETCH
```

Five cycles, and it reuses nothing from `CAL` because the vector fetch is an
extra indirection `CAL` does not have.

---

## 4. Conditions

| `CC` | Tested |
|---|---|
| `Z` | ALU result is zero |
| `NZ` | ALU result is not zero |
| `G2` | the group 2 expression: selected of `Z`, `L`, `I` OR'd, then inverted by `IR[11]` |
| `IRQ` | a request is pending and `I` is set |
| `MSK0` | the stack mask is empty |

The group 2 expression is evaluated in the condition logic, not in the
microprogram: one microinstruction, one cycle, whatever the mask holds.

---

## 5. Cycle counts against the model

| Instruction | Microcycles | `sim.py` charges |
|---|---|---|
| `TAD` direct | fetch 1 + EA 1 + read 1 = **3** | 1 + 2 = 3 |
| `DAC` direct | 1 + 1 + 1 = **3** | 1 + 2 = 3 |
| `TAD` indexed | 1 + 1 + 1 = **3** | 1 + 2 = 3 |
| `TAD` indirect | 1 + 3 + 1 = **5** | 1 + 2 + 2 = 5 |
| `JMP` direct | 1 + 1 = **2** | 1 + 1 = 2 |
| `ISZ` no skip | 1 + 1 + 2 + 1 = **5** | 1 + 2 + 2 = 5 |
| `ISZ` skipping | **6** | 6 |
| `PSH AC,IX` | 1 + 2 + 2 = **5** | 1 + 2 + 2 = 5 |
| `IAC` | 1 + 1 = **2** | 1 + 1 = 2 |
| `SKL` taken | 1 + 1 + 1 = **3** | 1 + 1 + 1 = 3 |
| `SKL` not taken | 1 + 1 = **2** | 1 + 1 = 2 |
| `SAD` either way | 1 + 1 + 1 + 1 = **4** | 4, after the correction below |
| interrupt entry | **5** | 4 + 1 = 5 |

They agree everywhere except `SAD` and `SXD`, where writing the microcode
showed the simulator was charging three cycles for something that cannot be
done in three. `sim.py` now charges the fourth, which costs 1.6% of the sieve,
0.8% of the console driver and 4.2% of FOCAL — the last because its scanner
compares constantly.

That correction is the whole point of writing the microprogram before the
hardware. Everything else in the model survived contact with it.

---

## 6. Open

**Indexing is assumed free.** `EA_IDX` puts the adder in the address path and
still claims one cycle. If the adder cannot make it inside a cycle that also
loads `AR`, indexed mode costs two and the sieve figures move.

**The write cycle drives `BD` from bus R through the ALU.** That means the ALU
is in the store path as well as the load path; if that is too slow, `DO` goes
back to being a register and `DAC` becomes four cycles.

**`MSK` is four bits of state that only group 2 of `OPR` uses.** Loading it on
every fetch is the cheap way; the alternative is decoding the group during the
fetch, which puts more logic in the critical path than the register costs.

**The reserved opcodes trap.** Where to is undecided: there is no trap vector
in `SPEC.md`, and reusing the reset entry would make a stray opcode look like a
power-on.
