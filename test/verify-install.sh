#!/bin/bash
# Asserts that install.sh installed exactly the files at the top level of
# the release archive, and that each one runs. The expected list comes from
# the archive's own listing, so it follows atc's release.
set -euo pipefail

bin="${INSTALL_DIR:-$HOME/.local/bin}"
fail() { echo "FAIL: $1" >&2; exit 1; }

"$bin/atc" --version
version=$("$bin/atc" --version | awk 'NR == 1 { print $2 }')
os=$(uname -s | tr '[:upper:]' '[:lower:]')
case "$(uname -m)" in
    x86_64|amd64) arch=x64 ;;
    *) arch=arm64 ;;
esac

# Top-level files only (the macOS app bundle is a directory), without the
# `._*` AppleDouble entries of archives packed on macOS.
expected=$(curl -fsSL "https://github.com/gitkb/atc-releases/releases/download/v${version}/atc-${os}-${arch}.tar.gz" \
    | tar -tzf - 2>/dev/null | grep -v -e / -e '^\._' | sort)
installed=$(ls -A "$bin" | sort)
[ "$installed" = "$expected" ] || fail "installed binaries differ from the archive
archive:   ${expected//$'\n'/ }
installed: ${installed//$'\n'/ }"

for binary in $expected; do
    test -x "$bin/$binary" || fail "$binary is not executable"
    # Workers have no --version; atc's release smoke checks them this way.
    [ "$binary" = atc ] || "$bin/$binary" --describe </dev/null >/dev/null || fail "$binary --describe failed"
    echo "ok: $binary"
done
