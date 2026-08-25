# Historical

These two patches are no longer needed. Both were merged upstream in
casmeleon `6af03b3`, "add quote escapes, introduce .dd", and neither applies
to a current checkout — `git apply --check` fails on both because the code
they add is already there.

They are kept because they record *why* casmeleon can assemble an 18-bit
machine at all:

- `casmeleon-dd-directive.patch` — `.dd` deposits at the width the target
  actually uses. `.db` and `.dw` are fixed at 8 and 16 bits regardless of
  `-byteSize`, so before this every data word on an 18-bit machine had to go
  through a pseudo opcode.
- `casmeleon-string-escapes.patch` — backslash escapes in quoted literals.
  Without them a string could never contain a `"`, which makes it impossible
  to embed a FOCAL program, since `TYPE "..."` is its most common statement.
