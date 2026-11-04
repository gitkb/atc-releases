#!/bin/bash
# Asserts that install.sh refuses this system with one error line containing
# the given text, before downloading or installing anything.
# Usage: check-refusal.sh <expected text> [fake `uname -s` output]
set -euo pipefail

expected="$1"
fake_uname="${2:-}"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/stub"
fail() { echo "FAIL: $1" >&2; exit 1; }

# A curl that records any call: a refusal must come before any download.
printf '#!/bin/sh\necho called >> "%s/curl-calls"\nexit 99\n' "$work" > "$work/stub/curl"
if [ -n "$fake_uname" ]; then
    real_uname=$(command -v uname)
    printf '#!/bin/sh\nif [ "$1" = -s ]; then echo "%s"; else exec "%s" "$@"; fi\n' \
        "$fake_uname" "$real_uname" > "$work/stub/uname"
fi
chmod +x "$work/stub"/*

status=0
PATH="$work/stub:$PATH" INSTALL_DIR="$work/bin" \
    bash "$(dirname "$0")/../install.sh" >"$work/out" 2>"$work/err" || status=$?

cat "$work/err"
[ "$status" -eq 1 ] || fail "exit status $status, expected 1"
[ "$(wc -l <"$work/err")" -eq 1 ] || fail "expected one error line"
grep -qF -- "$expected" "$work/err" || fail "error does not mention '$expected'"
[ ! -e "$work/curl-calls" ] || fail "curl was called before the refusal"
[ ! -e "$work/bin" ] || fail "INSTALL_DIR was created"
echo "ok: refused (${fake_uname:-$(uname -s)})"
