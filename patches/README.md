# casmeleon patches

One patch, and it is required: `asm/focal.s` cannot be assembled without it.

## `casmeleon-org-places-by-address.patch`

`.org` was parsed, implemented, and did nothing useful. Two defects.

The fatal one is in the assembly driver. It skips items whose bytes cannot have
changed since the previous pass and recomputes the address after them as
`here + len(bytes)`. That holds for anything which emits what it spans —
`.advance` pads, so it is fine — but `.org` moves the address and emits nothing,
so the moment it was skipped it became a silent no-op. `.org 16` left the
address where it was. Fixed by remembering the next address instead of deriving
it from the byte count.

The second is in how the image is built: the items' bytes were concatenated in
source order, so a byte's file offset came from where it was written rather than
from the address it was assembled at. `.advance` gets away with that because its
padding keeps the two equal. Fixed by placing each item's bytes at its own
address.

That second change is what makes a backwards `.org` legal, which is the point of
the directive: it places what follows at an address instead of padding up to
one. The restriction stays on `.advance`, where padding backwards means nothing.

What it buys here: a file states where its regions go and stops caring what
order they appear in. `asm/focal.s` needs two `.org` — the interpreter at
`0x1F400`, its tables at `0x1FF00` — and puts the program text at `0x2000` last,
where it reads best. `asm/arithlib.s` places its variables and its code with one
`.org` each; before the fix it had to be split into two files so an including
program could interleave them with its own regions.

Worth sending upstream: `.org` is broken for anyone, not just for an 18-bit
machine, and the fix is six lines.

## Removed

`casmeleon-dd-directive.patch` and `casmeleon-string-escapes.patch` are gone.
Both were merged upstream in `6af03b3`, "add quote escapes, introduce .dd", and
neither applied to a current checkout any more — `git apply --check` failed on
both, and the features are demonstrably there: `.dd` in `AssemblyParser.go`,
backslash handling in `pkg/scanner/Scanner.go`. A patch that cannot be applied
and describes code that already exists is not documentation, it is something to
mistake for work still to do.

What they recorded is worth keeping, so it is in the main `README.md` instead:
`.dd` deposits at the width the target uses, where `.db` and `.dw` stay 8 and 16
bits regardless of `-byteSize`; and without escapes in quoted literals a string
could never contain a `"`, which makes embedding a FOCAL program impossible,
`TYPE "..."` being its commonest statement.
