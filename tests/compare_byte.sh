#!/bin/bash
# Byte-by-byte comparison of dtran disassembly output against golden files.
# Does NOT require dubna: works with pre-assembled object modules.
#
# Usage:
#   ./compare_byte.sh                     run all tests (object.o must exist)
#   ./compare_byte.sh bss bss2            run named tests only
#   ./compare_byte.sh --update             regenerate .expected from current output
#   ./compare_byte.sh --bin FILE          disassemble a single binary file
#
# Prerequisite: object.o (DMS object module) in this directory.

cd "$(dirname "$0")" || exit 2
DTRAN="$(cd .. && pwd)/dtran"
[ -x "$DTRAN" ] || { echo 'ERROR: dtran not found; run make first'; exit 2; }

update=0; single_bin=""
case "$1" in
    --update)  update=1; shift ;;
    --bin)     single_bin="$2"; shift 2 ;;
esac

# Single-file mode: disassemble any binary file.
if [ -n "$single_bin" ]; then
    [ -f "$single_bin" ] || { echo "ERROR: file not found: $single_bin"; exit 2; }
    $DTRAN -F dms "$single_bin"
    exit 0
fi

# Test-suite mode
if [ "$#" -gt 0 ]; then
    names="$@"
else
    names="")
    for f in *.asm; do
        [ -f "$f" ] && names="$names $(basename $f .asm)"
    done
fi

pass=0; fail=0; skip=0
for name in $names; do
    exp="$name.expected"
    obj="object.o"

    if [ ! -f "$obj" ]; then
        echo "SKIP $name (no object.o — run asm.sh first)"
        skip=$((skip+1))
        continue
    fi

    got="/tmp/dtran-cmp-${name}.txt"
    $DTRAN -F dms "$obj" >"$got" 2>/dev/null
    rc=$?
    if [ $rc -ne 0 ]; then
        echo "FAIL $name (dtran exited with $rc)"
        fail=$((fail+1))
        continue
    fi

    if [ "$update" -eq 1 ]; then
        cp "$got" "$exp"
        echo "updated $exp"
        continue
    fi

    if [ -f "$exp" ] && diff -q "$exp" "$got" >/dev/null 2>&1; then
        echo "PASS $name"
        pass=$((pass+1))
    else
        echo "FAIL $name"
        diff "$exp" "$got" 2>&1 | sed 's/^/    /'
        fail=$((fail+1))
    fi
done

[ "$update" -eq 1 ] && exit 0
echo "----"
echo "$pass passed, $fail failed, $skip skipped"
[ "$fail" -eq 0 ]
