#!/bin/bash
set -eu

# ATC (Agent Traffic Control) Installation Script
# Usage: curl -fsSL https://raw.githubusercontent.com/gitkb/atc-releases/main/install.sh | bash
#   or:  curl -fsSL ... | VERSION=0.1.18 bash
#   or:  curl -fsSL ... | INSTALL_DIR=/usr/local/bin bash
#
# Installs every binary in the release archive (`atc` and its worker sidecars)
# into INSTALL_DIR. On macOS the signed "ATC Hotkey.app" goes to
# <prefix>/libexec (the parent of INSTALL_DIR), where `atc` looks for it.

REPO="gitkb/atc-releases"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
VERSION="${VERSION:-latest}"
SKIP_CHECKSUM="${SKIP_CHECKSUM:-0}"  # Set to 1 to bypass checksum verification
HOTKEY_APP="ATC Hotkey.app"

# Colors (disabled when stdout is not a terminal)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    NC=''
fi

info() {
    printf '%b\n' "${GREEN}[INFO]${NC} $1"
}

warn() {
    printf '%b\n' "${YELLOW}[WARN]${NC} $1"
}

# To stderr: errors raised inside $(...) would otherwise be captured silently.
error() {
    printf '%b\n' "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

# The Linux binaries link glibc 2.28+. Refuse musl and older glibc before
# downloading; an unrecognised libc is left to the post-install check.
check_libc() {
    local first version major minor
    first=$(ldd --version 2>&1 | head -n 1) || true
    case "$first" in
        *musl*) error "atc needs glibc 2.28+; this system uses musl (e.g. Alpine). Use a glibc distribution such as Debian or Ubuntu." ;;
        *GLIBC*|*"GNU libc"*) ;;
        *) return 0 ;;
    esac
    version="${first##* }"
    case "$version" in
        [0-9]*.[0-9]*) ;;
        *) return 0 ;;
    esac
    major="${version%%.*}"
    minor="${version#*.}"
    minor="${minor%%[!0-9]*}"
    if [ "$major" -lt 2 ] || { [ "$major" -eq 2 ] && [ "$minor" -lt 28 ]; }; then
        error "atc needs glibc 2.28+; this system has glibc ${version}."
    fi
}

# Refuse an INSTALL_DIR this user can't write before downloading anything.
check_install_dir() {
    local dir="$INSTALL_DIR"
    while [ ! -e "$dir" ]; do
        dir=$(dirname "$dir")
    done
    if [ ! -d "$dir" ] || [ ! -w "$dir" ]; then
        error "Cannot write to ${INSTALL_DIR}. Pick a directory you own (e.g. INSTALL_DIR=\"\$HOME/bin\") or run the installer with sudo."
    fi
}

# Detect platform
detect_platform() {
    local os
    local arch
    os=$(uname -s | tr '[:upper:]' '[:lower:]')
    arch=$(uname -m)

    case "$os" in
        darwin) os="darwin" ;;
        linux) check_libc; os="linux" ;;
        mingw*|msys*|cygwin*) error "atc supports macOS and glibc Linux; on Windows, run this installer inside WSL2." ;;
        *) error "Unsupported operating system: $os" ;;
    esac

    case "$arch" in
        x86_64|amd64) arch="x64" ;;
        arm64|aarch64) arch="arm64" ;;
        *) error "Unsupported architecture: $arch" ;;
    esac

    echo "${os}-${arch}"
}

# Get latest version from GitHub.
# Tries the redirect-based approach first (no API quota), falls back to REST API.
get_latest_version() {
    # Method 1: Follow the /releases/latest redirect — free, no API rate limit
    local redirect_url
    redirect_url=$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/${REPO}/releases/latest" 2>/dev/null) || true
    if [ -n "$redirect_url" ]; then
        # URL looks like https://github.com/…/releases/tag/v0.1.18
        local tag
        tag="${redirect_url##*/}"
        tag="${tag#v}"
        # Without any release the redirect stays on .../releases/latest.
        case "$tag" in
            [0-9]*)
                echo "$tag"
                return
                ;;
        esac
    fi

    # Method 2: GitHub REST API (subject to 60 req/hr unauthenticated rate limit)
    local response
    response=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest") || {
        error "Failed to fetch latest release info from GitHub"
    }
    if command -v jq >/dev/null 2>&1; then
        echo "$response" | jq -r '.tag_name // empty' | sed 's/^v//'
    else
        echo "$response" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | sed 's/^v//'
    fi
}

# Download and install
install_atc() {
    local platform="$1"
    local version="$VERSION"
    version="${version#v}"  # Strip leading v if user passed VERSION=v0.1.18

    # Detect existing installation
    if command -v atc >/dev/null 2>&1; then
        local current
        current=$(atc --version 2>/dev/null | head -n 1 || echo "unknown")
        info "Existing installation detected: $current ($(command -v atc))"
    fi

    if [ "$version" = "latest" ]; then
        info "Fetching latest version..."
        version=$(get_latest_version)
        if [ -z "$version" ]; then
            error "Could not determine latest version"
        fi
    fi

    info "Installing atc v${version} for ${platform}..."

    local download_url="https://github.com/${REPO}/releases/download/v${version}/atc-${platform}.tar.gz"
    local checksum_url="https://github.com/${REPO}/releases/download/v${version}/atc-${platform}.tar.gz.sha256"
    tmp_dir=$(mktemp -d)
    trap 'rm -rf "$tmp_dir"' EXIT INT TERM

    info "Downloading from ${download_url}..."
    if ! curl -fsSL "$download_url" -o "${tmp_dir}/atc.tar.gz"; then
        error "Failed to download atc (check that version '${version}' exists)"
    fi

    if [ "$SKIP_CHECKSUM" = "1" ]; then
        warn "Skipping checksum verification (SKIP_CHECKSUM=1)"
    elif curl -fsSL "$checksum_url" -o "${tmp_dir}/atc.tar.gz.sha256" 2>/dev/null; then
        info "Verifying checksum..."
        local expected
        expected=$(awk '{print $1}' "${tmp_dir}/atc.tar.gz.sha256")
        local actual
        if command -v sha256sum >/dev/null 2>&1; then
            actual=$(sha256sum "${tmp_dir}/atc.tar.gz" | awk '{print $1}')
        elif command -v shasum >/dev/null 2>&1; then
            actual=$(shasum -a 256 "${tmp_dir}/atc.tar.gz" | awk '{print $1}')
        else
            error "Cannot verify checksum: neither sha256sum nor shasum found. Install one and retry."
        fi

        if [ "$expected" != "$actual" ]; then
            error "Checksum verification failed!\n  Expected: ${expected}\n  Actual:   ${actual}"
        fi
        info "Checksum verified."
    else
        error "Could not download checksum file. Set SKIP_CHECKSUM=1 to bypass verification."
    fi

    info "Extracting..."
    mkdir -p "${tmp_dir}/archive"
    # Archives packed on macOS carry LIBARCHIVE.xattr.* headers that GNU tar
    # warns about; the files extract the same either way.
    if tar --version 2>/dev/null | grep -q 'GNU tar'; then
        tar --warning=no-unknown-keyword -xzf "${tmp_dir}/atc.tar.gz" -C "${tmp_dir}/archive"
    else
        tar -xzf "${tmp_dir}/atc.tar.gz" -C "${tmp_dir}/archive"
    fi

    if [ ! -f "${tmp_dir}/archive/atc" ]; then
        error "Binary atc not found in archive"
    fi

    # Create install directory if needed
    mkdir -p "$INSTALL_DIR"

    # Install every file at the archive's top level, so the list follows atc's
    # release. The `*` glob skips dotfiles such as the `._*` AppleDouble
    # entries of archives packed on macOS. The sidecars must sit beside atc:
    # atc resolves them from its own directory without configuration.
    info "Installing to ${INSTALL_DIR}..."
    local path
    for path in "${tmp_dir}/archive"/*; do
        if [ -f "$path" ]; then
            cp "$path" "$INSTALL_DIR/"
            chmod +x "$INSTALL_DIR/${path##*/}"
            info "Installed ${path##*/}"
        fi
    done

    # Install the signed hotkey app on macOS. Keep the bundle intact (ditto
    # preserves its signature); macOS attributes Accessibility consent to it.
    if [ -d "${tmp_dir}/archive/${HOTKEY_APP}" ]; then
        local libexec_dir
        libexec_dir="$(cd "$INSTALL_DIR/.." && pwd)/libexec"
        mkdir -p "$libexec_dir"
        rm -rf "${libexec_dir:?}/${HOTKEY_APP}"
        if command -v ditto >/dev/null 2>&1; then
            ditto "${tmp_dir}/archive/${HOTKEY_APP}" "${libexec_dir}/${HOTKEY_APP}"
        else
            cp -R "${tmp_dir}/archive/${HOTKEY_APP}" "${libexec_dir}/"
        fi
        info "Installed ${HOTKEY_APP} to ${libexec_dir}"
    fi

    # Verify the binary runs
    local installed_version
    if installed_version=$("$INSTALL_DIR/atc" --version 2>&1); then
        info "Verified: $(printf '%s\n' "$installed_version" | head -n 1)"
    else
        error "Installed binary failed to run: ${installed_version}"
    fi

    # Check if INSTALL_DIR is in PATH (POSIX-compatible)
    case ":$PATH:" in
        *":$INSTALL_DIR:"*) ;;
        *)
            warn "$INSTALL_DIR is not in this shell's PATH"
            echo ""
            echo "To use atc in this terminal now, run:"
            echo ""
            echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
            echo ""
            # Debian and Ubuntu's ~/.profile adds "$HOME/bin" and
            # "$HOME/.local/bin" at login once they exist.
            local rel="${INSTALL_DIR#"$HOME"/}"
            if [ "$rel" != "$INSTALL_DIR" ] && grep -qsF "\"\$HOME/$rel\"" "$HOME/.profile"; then
                echo "Your ~/.profile adds it to PATH from your next login on; nothing else is needed."
            else
                echo "To keep it, add that line to your shell's startup file (~/.bashrc, ~/.zshrc),"
                echo "or for fish run: fish_add_path $INSTALL_DIR"
            fi
            echo ""
            ;;
    esac

    info "Installation complete!"
    echo ""
    echo "Run 'atc --help' to get started."
}

# Main
main() {
    echo "ATC Installer"
    echo "============="
    echo ""

    # Refusals that installing curl or tar wouldn't fix come first.
    local platform
    platform=$(detect_platform)
    check_install_dir

    # Check for curl
    if ! command -v curl >/dev/null 2>&1; then
        error "curl is required but not installed"
    fi

    # Check for tar
    if ! command -v tar >/dev/null 2>&1; then
        error "tar is required but not installed"
    fi

    install_atc "$platform"
}

main "$@"
