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
| `DOSRC` | 2 | `DO` input: hold, the register `IR[11]` names, `{L,PC}`, ALU |
| `RDST` | 3 | bus R destination: none, `AC`, `IX`, `SP`, `T`, `PC`, `DO` |
| `LCTL` | 2 | `L`: hold, load `ALU_L`, load `DI[17]` |
| `ARSRC` | 3 | `AR`: hold, ALU, `PC`, `DI`, `{PC[16:12], IR[11:0]}`, stack page |
| `MEM` | 2 | idle, read, write |
| `PCINC` | 1 | increment `PC` |
| `ICTL` | 2 | `I`: hold, clear, set |
| `SEQ` | 3 | next, jump, map, map2, mapmask, branch, fetch |
| `CC` | 3 | which condition the branch tests |
| `NA` | 6 | next microaddress |

Control store **64 × 36**, of which 44 are used. Two small map ROMs, below.
`ucode.py` assembles it, emits the ROM images as the base64 LogicCircuit wants,
and contains an engine that executes them.

The field list is not what it was before the engine existed. Four things
changed, all of them because writing the microprogram made them impossible to
leave vague:

**`DO` has a source select of its own, two bits.** Not a bus tap: during an
indexed effective address bus A carries `IX`, so a store could not capture the
value it means to write. `DAC v,X` would have written the index.

**`PC` loads from the `AR` mux output**, not from bus R. A jump wants the
address it has just formed, and `AR` is on no bus. This is also why a jump
loads `PC` and `AR` in one cycle rather than two.

**The ALU exposes carry and overflow both, and the `FROMIR` decode picks which
one drives `L`.** That is the entire difference between `TAD` and `TAS`, and it
is not expressible in the four-bit function field: the field says "read the
function out of the opcode", and reading it out includes reading which flag.

**The carry-in folded into the function field** and `NA` dropped to six bits,
which is what paid for `DOSRC`.

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

### Checked, not asserted

`ucode.py` runs the control store against a memory and is compared with
`sim.py` instruction by instruction. On the sieve: **194392 instructions, no
divergence, memory identical, both print 1899.**

The comparison has to lag by one instruction, because the fold means the
architectural state of instruction *N* only settles during the fetch of *N+1*.
That is a property of the design, not of the harness.

Five bugs surfaced this way, all of them in the microprogram rather than in
`sim.py`: `FETCH_A` was not driving the register onto bus A, so everything but
`LAC` computed with a zero operand; `JMP` was taking `PC` from `DI`; `TAS` was
reporting carry; `IOT` had no microinstruction; and `DO` had no way to be
loaded at all.

### The cycle counts agree

**514775 microcycles against 514770.** Five cycles of difference over 194392
instructions, which is the reset sequence.

Getting there took undoing a mistake of mine. `FETCH` did not set `AR` itself;
it relied on the terminal microinstruction of the instruction before to leave
`AR` holding `PC`. With that invariant an instruction which never touches `AR`
still has to spend a cycle moving it, so operate cost two cycles and the model
looked optimistic by 16%.

The fix is that **every fetch points `AR` at the word after the one it read**.
Then a fetch is self-sufficient, and anything that needs no operand folds into
the fetch after it:

- `FETCH_G` is the fetch that also applies a group 1 operate. One cycle.
- `FETCH_S` is the fetch that also resolves a group 2 skip. It reads the next
  word speculatively and, when the condition turns out to hold, suppresses the
  `IR` load — the same mechanism the interrupt check already uses. Not taken
  costs nothing, taken costs one.

`AR` is then only needed where an address must survive a cycle: `ISZ` and `DSZ`,
which read, compute, and write back to the same place while the ALU is busy, and
the stack, whose address is `SP` with the page forced. Indirection does not need
it, because `DI` is a source of the `AR` mux in its own right.

The page concatenation takes its five high bits from a latch loaded during the
fetch, before the increment. `PC` has already moved on by the time the address
cycle runs, and at a page boundary it would give the wrong page — the bug this
whole design decision exists to avoid.

### The stack group

Progressive reduction, and nothing more: the dispatch picks a bit of `MSK`,
clears it, runs the two cycles for that register and comes straight back, so
the cost is the population count. The priority encoder takes the lowest set bit
for a push and the highest for a pop, which is where `PSH m ; POP m` becomes
the identity in hardware rather than in the simulator.

**Push is verified on all fifteen masks**: the right words in the right order,
`SP` at the highest address and `AC` at the lowest, and `PSH SP` writing the
value `SP` held when the instruction began rather than the decremented one.
That last point needed the `DO` select to read the register file *before* the
cycle's writes, which is what hardware does anyway and what my engine was
getting wrong.

`CAL` pushes first and forms the target afterwards, so it needs nowhere to keep
it: the four address sequences already load `PC`, and `CAL` reuses them. Four
short sequences, one per addressing mode, because only the exit differs.

**Pop costs three cycles per register, not two.** The address, the read, and
the transfer: a word read from memory reaches `DI` at the clock edge, so it can
only leave for a register the cycle after. `sim.py` was charging two and has
been corrected; the cost is 833 cycles on FOCAL and 8834 on the loop
benchmark, both in interrupt prologues, and nothing at all on the sieve, which
never touches the stack.

Forming the stack address had to come off the ALU for this to work at all —
`{00001, SP}` is a concatenation, and computing it through the adder left
nothing free for the transfer. `ARSRC` gained a second stack source: the
decremented `SP` from the ALU for a push, the register as it stands for a pop.

**Push is two cycles per register and matches the model**, and the two cycles
of fixed overhead the group used to carry are gone. The dispatch is answered by
the priority encoder in the fetch's own cycle rather than by a microinstruction
of its own, and the `I` field rides on every stack cycle instead of needing an
epilogue — it is idempotent, so applying it four times costs nothing.

This is the third time the same constraint has shaped the design: it made `SAD`
cost four, it forced the operate group to fold into the fetch, and now it makes
a pop longer than a push. **A value read from memory is available one cycle
later, and the only way to hide that is to overlap with the next fetch.** Where
there is a next fetch to overlap with, it is free; where there is not, it costs.

`CAL` and `RET` are exercised: the call returns to the word after itself with
`L` and `SP` restored, and `PSH m ; POP m` is the identity on all eight masks
that do not contain `LPC` — the two that do reload `PC`, so the pair is not a
no-op by construction.

### The RTL, and what it caught

`rtl/` is a Verilog 2005 model for iverilog. The field positions and every
symbolic value come from `ufields.vh`, which `ucode.py hex` generates alongside
the ROM images, so the RTL never writes a bit offset by hand and cannot drift
away from the microassembler: change a field width and the Verilog recompiles
against the new one.

```
make        build and run the sieve
make trace  dump cycles for comparison with the Python engine
make hex    regenerate the ROMs
```

It prints `OUT 1899` and halts in 514776 cycles, against 514775 for the Python
engine and 514770 for `sim.py`.

Writing it caught two bugs in the Verilog itself — `SEQ_SKIPC` translated as a
sequencer jump without the conditional `PC` step, so `SAD` never skipped, and
the datapath registers left unreset, so `L` started undefined and poisoned
`TAS`.

It also caught one in the microprogram, which matters more because both engines
shared it. **`ISZ` never skipped.** When the `PCINC` field was removed in favour
of deriving the increment from `ARSRC=PCNEXT`, the substitution stripped
`PCINC` from the `SKIP` microinstruction too, leaving it to move `AR` without
stepping `PC`. The sieve ran correctly and then looped: its outer `ISZ ITER`
never fell through, so the whole sieve ran six times and never reached the
`HLT`.

The comparison that found it was not the instruction-by-instruction one, which
had been passing all along while comparing three registers out of five and
skipping `PC` because the fold makes `PC` an instruction ahead by construction.
It was **the list of memory writes in order**: 35903 of them from `sim.py`,
matching the first 35903 of 211174 from the microcode. Same writes, six times
over. A comparison that is independent of the pipeline shape found in one run
what a state comparison had hidden for several.

### Interrupt entry

Five cycles, matching `sim.py`, and traced through: the fetch that detects the
request suppresses the `IR` load and the increment, so `PC` still names the
instruction thrown away and that is what gets pushed. `I` is cleared on the
same cycle the stack address is formed. The vector entry is the device number,
which comes from the priority encoder and so needed a bus source of its own —
`BSRC` had one slot free.

`RTI` restores `PC`, `L`, `SP` and `I`, and the machine re-enters the handler
immediately afterwards, which is correct: the test never acknowledges, so the
request is still up. That is the interrupt storm from earlier in the project,
reproduced by the microcode for the same reason.

`EI` and `DI` needed a fix that is worth recording, because it came from an
optimisation. The `I` field had been moved onto the stack cycles so the group
would not need an epilogue — but `EI` and `DI` are exactly the empty-mask case,
where there are no stack cycles. The answer was the same shape as everything
else here: **`FETCH_I` is the fetch that also applies the `I` field**, so an
empty mask costs one cycle and the epilogue disappears for good.

A fuller test — save context, acknowledge, restore, return — does **not** pass
yet. The entry and the return are each verified in isolation; the combination
of a two-register push and pop pair inside a handler leaves `SP` one short. Not
isolated.

### Width

The stack group pushed the microword from 36 bits to **37**: `DOSRC` needs three
bits once it selects `AC`, `IX`, `SP`, `{L,PC}` and the ALU separately, and `NA`
needs seven for 74 microinstructions. Two ROMs of 128 × 24 hold it with eleven
bits spare, and 24 is the width the project already uses for its microcode.

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
