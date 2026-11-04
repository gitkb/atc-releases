#!/bin/bash
# Asserts that a successful install wrote nothing to stderr, and that its PATH
# hint works: the printed export line puts atc on PATH in this shell, and no
# startup-file edit is suggested when ~/.profile already adds ~/.local/bin.
# Usage: check-install-output.sh <stdout log> <stderr log>
set -euo pipefail

out="$1"
err="$2"
fail() { echo "FAIL: $1" >&2; exit 1; }

[ ! -s "$err" ] || { cat "$err" >&2; fail "install.sh wrote to stderr"; }

if ! command -v atc >/dev/null; then
    line=$(grep '^  export PATH=' "$out") || fail "atc is not on PATH and no export line was printed"
    eval "$line"
    command -v atc >/dev/null || fail "the printed export line does not put atc on PATH"
    if grep -qs '\.local/bin' "$HOME/.profile" && grep -q 'bashrc' "$out"; then
        fail "\$HOME/.profile already adds .local/bin, but the hint asks for a startup-file edit"
    fi
fi
echo "ok: clean stderr, working PATH hint"
