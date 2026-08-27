#!/bin/sh
# Assemble every program in asm/ into bin/.
# Needs casmeleon on PATH; see README.md for how to build it.
set -e
CASM=${CASM:-casmeleon}
mkdir -p bin
python3 gen_casm.py
python3 mkprog.py "${FOCAL:-focal/sum.fc}" asm/program.s
for f in asm/*.s; do
    case "$f" in asm/arithlib.s|asm/program.s) continue;; esac   # included, not standalone
    b=$(basename "$f" .s)
    "$CASM" -lang=pdp9x.casm -byteSize=32 -endian=big -export=bin "$f" >/dev/null
    mv "asm/$b.bin" "bin/$b.bin"
    echo "  $b.bin"
done
rm -f asm/*.export.txt
# extra FOCAL images, one per sample program
for p in loop do ask for func keys types tyerr more arr brk hamurabi lunar rnd twoch grow bounds long exprt fnt fort abbrev comment diag if3 seven erase; do
    python3 mkprog.py "focal/$p.fc" asm/program.s >/dev/null
    "$CASM" -lang=pdp9x.casm -byteSize=32 -endian=big -export=bin asm/focal.s >/dev/null
    mv asm/focal.bin "bin/focal_$p.bin"
done
# an image with no program assembled in: it converses instead
printf '; empty: the operator types the program in\nTEXT:\n        .dd     0\n' > asm/program.s
"$CASM" -lang=pdp9x.casm -byteSize=32 -endian=big -export=bin asm/focal.s >/dev/null
mv asm/focal.bin bin/focal_int.bin

python3 mkprog.py "${FOCAL:-focal/sum.fc}" asm/program.s >/dev/null
"$CASM" -lang=pdp9x.casm -byteSize=32 -endian=big -export=bin asm/focal.s >/dev/null
mv asm/focal.bin bin/focal.bin
rm -f asm/*.export.txt
