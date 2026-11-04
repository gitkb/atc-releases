#!/bin/bash
# Asserts that install.sh refuses this system with one error line containing
# the given text, before downloading or installing anything. A system without
# curl gets no stub, so the refusal must also come before the curl check.
# Usage: [INSTALL_DIR=dir] check-refusal.sh <expected text> [fake `uname -s` output]
set -euo pipefail

expected="$1"
fake_uname="${2:-}"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
dir="${INSTALL_DIR:-$work/bin}"
mkdir "$work/stub"
fail() { echo "FAIL: $1" >&2; exit 1; }

# A curl that records any call: a refusal must come before any download.
if command -v curl >/dev/null; then
    printf '#!/bin/sh\necho called >> "%s/curl-calls"\nexit 99\n' "$work" > "$work/stub/curl"
    chmod +x "$work/stub/curl"
fi
if [ -n "$fake_uname" ]; then
    real_uname=$(command -v uname)
    printf '#!/bin/sh\nif [ "$1" = -s ]; then echo "%s"; else exec "%s" "$@"; fi\n' \
        "$fake_uname" "$real_uname" > "$work/stub/uname"
    chmod +x "$work/stub/uname"
fi

status=0
PATH="$work/stub:$PATH" INSTALL_DIR="$dir" \
    bash "$(dirname "$0")/../install.sh" >"$work/out" 2>"$work/err" || status=$?

cat "$work/err"
[ "$status" -eq 1 ] || fail "exit status $status, expected 1"
[ "$(wc -l <"$work/err")" -eq 1 ] || fail "expected one error line"
grep -qF -- "$expected" "$work/err" || fail "error does not mention '$expected'"
[ ! -e "$work/curl-calls" ] || fail "curl was called before the refusal"
if [ -z "${INSTALL_DIR:-}" ]; then
    [ ! -e "$dir" ] || fail "INSTALL_DIR was created"
fi
[ ! -e "$dir/atc" ] || fail "atc was installed"
echo "ok: refused (${fake_uname:-$(uname -s)})"
