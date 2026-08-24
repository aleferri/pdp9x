# pdp9x — 18-bit accumulator machine

Simulator, assembler definition and sample programs for an 18-bit machine in
the PDP-4/7/9/15 line, with a hardware stack, one index register and a
four-entry interrupt vector.

`SPEC.md` is the architecture document. Everything asserted in it is exercised
by the code here.

## Running

The `bin/` directory ships pre-assembled, so nothing needs building to run:

```
python3 bench.py            # CPU invariants, then every sample program
python3 bench.py checks     # just the 32 CPU unit tests
python3 bench.py sieve      # just the sieve variants
python3 bench.py sieve 10   # sieve, ten iterations
python3 bench.py console    # console driver, spacing test, link return
```

Python 3.8 or later, no dependencies.

## Rebuilding

Assembly is done with [casmeleon](https://github.com/aleferri/casmeleon), a
retargetable assembler in Go by aleferri:

Two patches in `patches/` are required; both are small and upstreamable.

```
git clone --depth 1 https://github.com/aleferri/casmeleon
cd casmeleon
patch -p1 < ../patches/casmeleon-string-escapes.patch
patch -p1 < ../patches/casmeleon-dd-directive.patch
GOPROXY=direct GOSUMDB=off GOFLAGS=-mod=mod go get github.com/aleferri/casmvm@v0.2.9
GOPROXY=direct GOSUMDB=off go build -o casmeleon ./cmd/casmeleon
```

The `go get` matters. `casmeleon` pins `casmvm v0.2.8`, in which `Enter.Apply`
discards the error returned by an inline in order to check the return count
first. An inline aborted by `.error` never reaches its `.return`, so the count
necessarily disagrees and that generic complaint replaces the real message:
every range check in `pdp9x.casm` used to surface as `len of formal returns and
effective returns diffs, expected 1 returns, received 0 instead`. Upstream
fixed it in `63c8d7d`, released as `v0.2.9`. With it, a range check says what it
means:

```
memory reference address outside the 11 bit zero page, value 16384
CAL/JMP direct is PC-page relative: target is in another 4K page, value 16384
```

`casmeleon-dd-directive.patch` adds `.dd`, which deposits at the width the
target actually uses. `.db` and `.dw` are fixed at 8 and 16 bits regardless of
`-byteSize`, so an 18-bit machine previously had to route every data word
through a pseudo opcode. `.dd` takes numbers, negatives, labels and quoted
strings, so `WORD` and `NWORD` are gone.

`casmeleon-string-escapes.patch` adds backslash escapes to quoted literals.
The scanner had none: a `"` opened a literal and the next `"` closed it, so a
string could never contain one. It now honours `\\`, `\"`, `\n`, `\r`, `\t`
and `\0`, with an unknown escape yielding the character itself so a stray
backslash is never silently dropped.

Then, from this directory:

```
CASM=/path/to/casmeleon ./build.sh
```

`build.sh` regenerates `pdp9x.casm` from `gen_casm.py` and assembles every
`asm/*.s` into `bin/`. The instruction set definition is generated rather than
hand-written because the memory-reference opcodes are 64 near-identical
patterns (8 opcodes by 2 register selectors by 4 addressing modes).

Three casmeleon constraints shaped the definition, and are worth knowing before
editing it:

- Opcode arguments are **single tokens**. No expressions, no negative
  literals — hence the `NWORD` pseudo-opcode for negative constants.
- `.db` and `.dw` stay 8 and 16 bits wide even at `-byteSize=32`; `.dd`, added
  by the patch, follows the byte size.
- Every `.set` member needs a trailing `;`, **including the last one**.
  Omitting it reports only `Unexpected Error`, with no line number.
- `.include` resolves relative to the **including file**, not the working
  directory.

A memory reference operand above 2047 is rejected, which is easy to trigger by
declaring a constant next to the code that uses it instead of in the zero page.

A forward label reads as 0 on the first pass, which would make the PC-page
range check in `JPC` fire spuriously; since `.error` is fatal and blocks
re-evaluation, the check is guarded with `a != 0`.

## Files

| | |
|---|---|
| `SPEC.md` | architecture specification |
| `sim.py` | CPU core: decode, execute, cycle accounting |
| `machine.py` | blitter and timer on IOT, framebuffer at `0x4000` |
| `model.py` | Python model of the console algorithm, used to debug it |
| `run.py` | CPU invariant tests |
| `bench.py` | runs everything and reports |
| `gen_casm.py` | generates `pdp9x.casm` |
| `mkprog.py` | turns a FOCAL `.fc` source into WORD directives |
| `pdp9x.casm` | casmeleon instruction set definition |
| `build.sh` | regenerate and assemble |

## Sample programs

### Sieve

The Byte magazine sieve, 8190 flags, one word per flag, answer 1899. Four
versions showing where the instruction set costs and pays:

| | |
|---|---|
| `sieve.s` | baseline: loop variable in memory, bound checked with `TAD` against a negative constant |
| `sieve2.s` | loop variable lives in `IX`, incremented with `TADX`, bound checked with `SXD` |
| `sieve3.s` | index biased so the limit sits on the sign boundary, `TASX` reports the crossing as overflow |
| `sieve4.s` | `IAC`/`IXC` replace the explicit `TAD ONE` |

Measured: 912398 cycles down to 514769, **−43.6%**, with the answer unchanged
throughout.

The step from `sieve2` to `sieve3` is the interesting one. There is no skip on
sign, and `SXD` only compares for inequality, so the marking loop — which
advances by a variable stride and overshoots the limit — cannot terminate on
equality. Biasing the index by `2^17 − (limit+1)` moves the limit onto the sign
boundary, and the bias is absorbed by the base pointer because the effective
address is masked to 17 bits. The ordering test then costs nothing.

### Console

`driver.s` and `driver2.s` drive a 16×32 character blitter and a 16-bit timer,
both on IOT. The blitter is deaf for 7680 cycles during a scroll, and needs 8
cycles between consecutive framebuffer writes.

Output is queued during a scroll with the newlines kept inline; on scroll-done
the queue is replayed through the normal `putc`/`newline` path rather than
copied, so a queued newline issues the next scroll by itself. The timer times
the scroll, so its interrupt *is* the completion signal.

Busy-waiting instead would serialise computation and scrolling. Buffering
overlaps them: cost per line goes from `t_compute + 7680` to
`max(t_compute, 7680)`, worth up to 2× when the two are comparable.

### spacing.s

Writes to the framebuffer four times in a row, 5 cycles apart against a floor
of 8. Loses 587 writes with no error of any kind. Unrolling a fill loop is
exactly this mistake, which is why the simulator counts the violations rather
than letting them pass.

### FOCAL

`asm/focal.s` is a subset of DEC's FOCAL: `SET`, `TYPE`, `ASK`, `IF`, `GOTO`,
`DO`, `RETURN`, `FOR`, `WRITE`, `ERASE`, `QUIT` and comment lines, several to a
line separated by semicolons, over an expression evaluator with `+ - * / ^`,
parentheses, unary minus, subscripted variables `A(i)` and the functions
`FABS`, `FSGN`, `FITR`, `FSQT`, `FLEN`. `IF` takes one, two or three targets
and falls through when the arm it wants is not there. `ASK` prompts with the
variable name and a colon. Control C stops a running program with `?C`.

### Command level

`bin/focal_int.bin` is the same interpreter with no program assembled in, so it
converses. A line beginning with a number is filed away, anything else runs at
once, and a bare number deletes that line:

```
*10 TYPE "ONE", !
*30 TYPE "THREE", !
*20 TYPE "TWO", !          filed in numeric order, not typing order
*40 QUIT
*20 TYPE "TWO BIS", !      replaces line 20
*30                        deletes line 30
*WRITE
10 TYPE "ONE", !
20 TYPE "TWO BIS", !
40 QUIT
*GOTO 10
ONE
TWO BIS
```

The same `BODY` runs both modes; only the text pointer differs, aiming at the
stored program or at the line just typed. `RESET` looks at the first word of
the program area: assembled in, it runs and stops; empty, it prompts. So every
batch program above still works unchanged.

An error abandons the stack and returns to the prompt — the stack lives in a
fixed page precisely so that this costs two instructions — but in a batch image
there is nobody to return to, so it stops instead.

What is left is **floating point**, which is the substrate of the real language
and was replaced on purpose, and with it the fractional line numbers that make
`DO 1` mean "the whole of group 1". `LIBRARY` and `MODIFY` sit behind mass
storage.

`FOR v=start,step,limit; body` re-runs the rest of its own line, so the loop
just rewinds the text pointer and calls the body again; the loop variable lives
in the ordinary variable table, as FOCAL specifies, so the body can read it.
`FSQT` is Newton from above in `arithlib.s`: the guess only ever falls, so the
first value that fails to fall is the answer.

```
10 COMMENT TRIANGULAR NUMBERS AND A THREE WAY TEST
20 SET A=7
30 SET B=A*(A+1)/2
40 TYPE "SUM TO ", A, " IS ", B, !
50 IF (B-28) 80, 60, 80
60 TYPE "TWENTY EIGHT, AS EXPECTED", !
```

`DO n` runs line *n* as a subroutine and then carries on after the `DO`. The
main loop calls a `STEP` subroutine that executes exactly one line, so a line
can be run from inside another line and the nesting rides entirely on the
hardware stack — two words per level, no interpreter state to save. `DO` inside
`DO` therefore works without a single line of extra code, which is the one
place where this machine's stack earns its keep over the PDP-8 it descends
from.

`ASK` reads decimal numbers from the keyboard, which has four registers: the
raw code, the modifiers held with it, a status flag and an acknowledge. A
keystroke latches code and modifiers and raises `irq1` on release, and scanning
stops until the CPU acknowledges. **Reconstructing the character is the CPU's
job**: control masks to the low five bits, shift folds letters to upper case.
The symbol half of the shift map is left alone because it depends on the
physical layout.

The handler reconstructs into an eight-entry queue, and the queue-full case is
where the handshake earns its place: the handler simply does not acknowledge,
so the device keeps the keystroke and stops scanning. It then masks **that one
device** in the processor's interrupt mask and returns with interrupts still on,
because a keyboard queue that is momentarily full is no reason to stop
listening to the rest of the machine. `GETK` unmasks once it has taken a
character and the held keystroke is delivered again. Nothing is dropped, no
keystroke is duplicated, and the buffer never has to grow.

The evaluator is plain recursive descent, which the machine supports directly
because `CAL` and `RET` use the hardware stack and intermediate values ride on
it via `PSH AC`.

`IX` is the text pointer for the whole interpreter, not a variable in the zero
page. Reading the current character is then a single `LAC (TXTP), X` and
advancing is a single `IXC`, both inline. As subroutines they cost a `CAL`, a
`LIX`, an indirect load and a `RET` each, and the scanner calls them about
1600 times in a 24 line program: moving the pointer into the register cut the
whole run from 69788 cycles to 51510, **26 percent**. A routine that needs `IX`
for its own indexing saves it first, which is `FVAR`, `PNUM`, `PUTC`, the store
side of `SET`, and `MUL` in the library. FOCAL's three-way `IF` needs the sign of a value, and the
`RLA` then `GLK` idiom hands it over as a 0 or 1 word without a branch.

Two things dominated the interpreter before they were fixed, and neither was
the evaluator. Reading the current character was a subroutine call: moving the
text pointer into `IX` made it one inline instruction and cut a quarter of the
run. Then `num*10` in the number parser was calling the general multiplier,
which turned out to be **half** of a loop-heavy program; `10x = 8x + 2x` is
three `SHA` and an add.

Command dispatch goes through a 32-entry table of jumps indexed by the low five
bits of the command letter, which needs no range check because `A`..`Z` map onto
1..26 and anything else lands on an entry that skips the line. The table holds
jumps rather than addresses because the machine indirects once, not twice.

Measured against the chain of comparisons it replaced: a failed comparison
costs two instructions (`LAC`, then `SAD` skipping the `JMP`), so the chain
costs `2(k-1)` for the command in position *k* while the table is flat and four
instructions worse than position one. **They cross at position three.** With
seven commands and uniform use it is still close to a wash; the table pulls
ahead where the chain is long or the hit is late — on a loop of comment lines,
which fall past every comparison, it wins 2.3% of cycles.

The interesting part is that it took two wrong guesses to find this out. The
dispatch chain looked like the obvious waste in an instruction-coverage census
because it left the indexed indirect jump unused, but coverage says nothing
about cost. The actual waste was `CAL MUL` for a constant, which the census
could never flag because multiplying is perfectly normal code — it was only in
the wrong place. A call profile found it in one measurement.

### Two types

FOCAL has exactly one type, floating point: variables hold it, expressions
evaluate to it, and line numbers *are* it, which is why `1.10` works and why
`DO 1` can mean "the whole of group 1". Replacing that single type with 18-bit
integers is therefore not a missing feature, it is a different language.

A second type is added by **declaration** rather than by a suffix. BASIC put the
type in the spelling of the name — `A$` for a string, `A%` for an integer — but
in FOCAL `%` is already the `TYPE` format control, as are `!` and `#`, the other
two BASIC suffixes. Declaring instead puts the type in a table beside the
variables, so `A` stays `A` and a further type costs a table entry rather than a
new sigil.

```
10 SET A AS STRING
20 SET N AS INT
30 SET C AS STRING = N       declare and assign in one breath
40 SET A="HELLO"
50 SET N=1234
60 TYPE A, " ", N, " ", FLEN(A), !
70 SET D AS STRING
80 SET D="-56XYZ"
90 TYPE "SUM ", D+N, !       1178: the text read as the number it spells
```

Undeclared means integer, so every program written before declarations existed
still runs. `SET X AS FLOAT` is refused with `?F` rather than silently accepted:
there is no floating point to declare, and a declaration that quietly does
nothing is worse than one that fails.

Conversions run in both directions instead of raising a type error, which suits
a language that never had one, and they reuse the decimal machinery already
there for `TYPE` and `ASK`. Twenty-six strings of nineteen characters,
truncated silently on overflow.

One ambiguity survives the move from suffix to declaration, though it shrinks.
`A` alone, where `A` is a string, prints as text; `A+B` is arithmetic on the
numbers the two strings spell. The parser looks one character past the name — a
separator means the value, anything else means an expression — and a bare name
on the right of `SET` is resolved by **the source's** declared type, not the
destination's.

Arithmetic is 18-bit integer rather than FOCAL's floating point: the machine
has no floating unit, and the interesting part here is the interpreter.

Program text is generated from a `.fc` source:

```
python3 mkprog.py focal/diag.fc asm/program.s
FOCAL=focal/diag.fc ./build.sh
```

Decimal conversion writes its digits **backwards** into the tail of the
buffer. Division yields them least significant first, so filling from the end
leaves them in order and the reversal pass disappears entirely, along with its
four temporaries; `IX` carries the write index throughout, stepped back by
`TADX MONE`, which does not disturb `AC`.

`asm/arithlib.s` holds multiply, divide and decimal conversion at fixed
addresses (variables at `0x300`, code at `0x2000`) so both `arith.s` and
`focal.s` can include it and lay out their own zero page below and code above.

### return_link.s

Shows that a subroutine can return `L` after all, by editing the packed
`{L, PC}` word on the stack before returning, and that the same handle gives a
skip return.

## Caveats

The cycle model is an interpretation, not silicon. If the control logic
diverges, the three places to check first are the execution order of combined
group 0 microinstructions, the cost of an indirection, and whether indexing is
really free.

`machine.py` models the specific devices attached in LogicCircuit — the
8-cycle spacing, the write-only framebuffer, the 7680-cycle scroll. Those are
device properties, not architecture, which is why they are not in `SPEC.md`.
