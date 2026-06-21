#!/usr/bin/env bash
# tunnel — Cloudflare Clean IP Toolkit installer
#
# Two installation modes:
#   1. Release tarball (binaries already in bin/)  — quick setup only
#   2. From source (binary missing)                — auto-download or compile
#
# Usage:
#   ./install.sh              # interactive (prompts for PATH)
#   ./install.sh --yes        # non-interactive, auto-approve PATH
#   ./install.sh --no-path    # skip PATH setup
set -euo pipefail

PROJECT="tunnel"
PROJECT_VERSION="$(cat "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/VERSION" 2>/dev/null || echo "1.0.0")"

# --- GitHub (for downloading pre-compiled releases) ---
# Change these if you fork the project.
GITHUB_USER="${GITHUB_USER:-mrsase}"  # set to your GitHub org/username for release downloads
RELEASE_BASE="https://github.com/${GITHUB_USER}/${PROJECT}/releases/download/v${PROJECT_VERSION}"

# --- Upstream repos (for source compilation) ---
CFST_VERSION="v2.3.5"
CFST_REPO="XIU2/CloudflareSpeedTest"
SENPAI_VERSION="v0.5.0"
SENPAI_REPO="MatinSenPai/SenPaiScanner"

# --- Colors ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { printf "${GREEN}[INFO]${NC}  %s\n" "$*"; }
warn()  { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$*"; }
header(){ printf "\n${CYAN}== %s ==${NC}\n" "$*"; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$ROOT/bin"
SCRIPTS_DIR="$ROOT/scripts"

# --- Architecture detection ---
detect_os() {
    case "$(uname -s)" in
        Darwin)  echo "darwin"  ;;
        Linux)   echo "linux"   ;;
        CYGWIN*|MINGW*|MSYS*) echo "windows" ;;
        *)       echo "unknown" ;;
    esac
}

detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64)    echo "amd64"  ;;
        aarch64|arm64)    echo "arm64"  ;;
        i386|i686)        echo "386"    ;;
        armv5*)           echo "armv5"  ;;
        armv6*)           echo "armv6"  ;;
        armv7*)           echo "armv7"  ;;
        mips)             echo "mips"   ;;
        mips64)           echo "mips64" ;;
        mips64le)         echo "mips64le" ;;
        mipsle)           echo "mipsle" ;;
        *)                echo "unknown" ;;
    esac
}

OS="$(detect_os)"
ARCH="$(detect_arch)"
LABEL="${OS}-${ARCH}"

# --- Helpers ---
download() {
    local url="$1" out="$2"
    info "Downloading $(basename "$out")..."
    if command -v curl &>/dev/null; then
        curl -fsSL "$url" -o "$out"
    elif command -v wget &>/dev/null; then
        wget -q "$url" -O "$out"
    else
        error "Neither curl nor wget found."
        return 1
    fi
}

check_deps() {
    local missing=()
    for cmd in python3 sqlite3; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    command -v curl &>/dev/null || command -v wget &>/dev/null || missing+=("curl or wget")
    command -v unzip &>/dev/null || command -v tar &>/dev/null || missing+=("unzip or tar")
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing dependencies: ${missing[*]}"
        exit 1
    fi
}

binary_works() {
    local bin="$1"
    [[ -x "$bin" ]] && "$bin" -v &>/dev/null
}

# --- Install strategy ---
ensure_binaries() {
    header "Scanner binaries"

    mkdir -p "$BIN_DIR"

    if binary_works "$BIN_DIR/cfst" && binary_works "$BIN_DIR/senpaiscanner"; then
        info "Already present and working — skipping download"
        return
    fi

    # Strategy A: download a pre-built release tarball from GitHub
    local tarball_url="${RELEASE_BASE}/tunnel-${LABEL}.tar.gz"
    local tmpdir
    tmpdir="$(mktemp -d)"
    local fetched=0

    if [[ -n "$GITHUB_USER" ]] && download "$tarball_url" "$tmpdir/release.tar.gz" 2>/dev/null; then
        info "Downloaded pre-built release for ${LABEL}"
        tar -xzf "$tmpdir/release.tar.gz" -C "$tmpdir"
        cp "$tmpdir/tunnel-${LABEL}/bin/cfst" "$BIN_DIR/" 2>/dev/null || true
        cp "$tmpdir/tunnel-${LABEL}/bin/senpaiscanner" "$BIN_DIR/" 2>/dev/null || true
        chmod +x "$BIN_DIR/cfst" "$BIN_DIR/senpaiscanner" 2>/dev/null || true
        if binary_works "$BIN_DIR/cfst" && binary_works "$BIN_DIR/senpaiscanner"; then
            fetched=1
        fi
    fi
    rm -rf "$tmpdir"

    if [[ "$fetched" == 1 ]]; then
        info "cfst    : $("$BIN_DIR/cfst" -v 2>&1 | head -1)"
        info "senpai  : ready"
        return
    fi

    # Strategy B: compile from upstream source
    info "No pre-built release for ${LABEL} — compiling from source"

    if ! command -v go &>/dev/null; then
        error "Go is required to compile from source."
        info "Install Go: https://go.dev/doc/install"
        info "Or set GITHUB_USER to enable pre-built downloads."
        exit 1
    fi

    "$SCRIPTS_DIR/build-scanners.sh" --os "$OS" --arch "$ARCH" --dest "$BIN_DIR"

    if binary_works "$BIN_DIR/cfst" && binary_works "$BIN_DIR/senpaiscanner"; then
        info "cfst    : $("$BIN_DIR/cfst" -v 2>&1 | head -1)"
        info "senpai  : ready"
    else
        error "Source compilation failed"
        exit 1
    fi
}

# --- Fetch Cloudflare IP ranges ---
install_ranges() {
    header "Cloudflare IP ranges"
    local dir="$ROOT/data"
    mkdir -p "$dir"

    if [[ -s "$dir/ip.txt" && -s "$dir/ipv6.txt" ]]; then
        info "Already cached ($(wc -l < "$dir/ip.txt") v4 / $(wc -l < "$dir/ipv6.txt") v6)"
        return
    fi

    download "https://www.cloudflare.com/ips-v4" "$dir/ip.txt"
    download "https://www.cloudflare.com/ips-v6" "$dir/ipv6.txt"
    info "IPv4: $(wc -l < "$dir/ip.txt") ranges"
    info "IPv6: $(wc -l < "$dir/ipv6.txt") ranges"
}

# --- Initialize database ---
init_db() {
    header "Database"
    mkdir -p "$ROOT/db"
    if [[ -f "$ROOT/db/clean_ips.db" ]]; then
        info "Already exists ($(du -h "$ROOT/db/clean_ips.db" | cut -f1))"
        return
    fi
    sqlite3 "$ROOT/db/clean_ips.db" < "$SCRIPTS_DIR/schema.sql"
    info "Created: $ROOT/db/clean_ips.db"
}

# --- Add to PATH ---
setup_path() {
    header "PATH integration"

    local shell_rc
    if [[ "$SHELL" == */zsh ]]; then
        shell_rc="$HOME/.zshrc"
    elif [[ "$SHELL" == */bash ]]; then
        shell_rc="$([[ "$OS" == "darwin" ]] && echo "$HOME/.bash_profile" || echo "$HOME/.bashrc")"
    else
        shell_rc="$HOME/.profile"
    fi

    local path_line="export PATH=\"\$PATH:$ROOT\""
    grep -qF "$ROOT" "$shell_rc" 2>/dev/null && { info "Already in PATH ($shell_rc)"; return; }

    local answer="y"
    if [[ "${1:-}" != "--yes" ]]; then
        printf "  Add to PATH? This appends to %s [Y/n]: " "$shell_rc"
        read -r answer
    fi

    case "$answer" in
        n|N|no|NO) warn "Skipped. Use './tunnel <cmd>' or add manually." ;;
        *)
            echo "" >> "$shell_rc"
            echo "$path_line" >> "$shell_rc"
            info "Added to $shell_rc — run 'source $shell_rc' then use 'tunnel' from anywhere"
            ;;
    esac
}

# --- Summary ---
print_summary() {
    header "Installation complete"
    echo "  Project   : $ROOT"
    echo "  Version   : $PROJECT_VERSION"
    echo "  Platform  : $OS / $ARCH"
    echo ""
    echo "  Quick start:"
    echo "    ${CYAN}./tunnel scan${NC}                # Run a scan"
    echo "    ${CYAN}./tunnel top${NC}                 # View best IPs"
    echo "    ${CYAN}./tunnel status${NC}              # System overview"
    echo "    ${CYAN}./tunnel help${NC}                # All commands"
    echo ""
    grep -qF "$ROOT" "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile" 2>/dev/null && \
        echo "  PATH: active (restart shell or 'source ~/.<rc>')"
}

# --- Main ---
main() {
    local path_mode="prompt"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --yes|-y)       path_mode="--yes"; shift ;;
            --no-path)      path_mode="--no";  shift ;;
            --help|-h)      echo "Usage: $0 [--yes | --no-path]"; exit 0 ;;
            *)              shift ;;
        esac
    done

    echo ""
    echo "  ${CYAN}██╗  ██╗██╗   ██╗███╗   ██╗███╗   ██╗███████╗██╗${NC}"
    echo "  ${CYAN}██║  ██║██║   ██║████╗  ██║████╗  ██║██╔════╝██║${NC}"
    echo "  ${CYAN}███████║██║   ██║██╔██╗ ██║██╔██╗ ██║█████╗  ██║${NC}"
    echo "  ${CYAN}██╔══██║██║   ██║██║╚██╗██║██║╚██╗██║██╔══╝  ██║${NC}"
    echo "  ${CYAN}██║  ██║╚██████╔╝██║ ╚████║██║ ╚████║███████╗███████╗${NC}"
    echo "  ${CYAN}╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚═╝  ╚═══╝╚══════╝╚══════╝${NC}"
    echo "  ${CYAN}Cloudflare Clean IP Toolkit   v${PROJECT_VERSION}${NC}"
    echo ""

    check_deps
    mkdir -p "$ROOT"/{data,db,exports,logs,results/cfst,results/senpai}
    ensure_binaries
    install_ranges
    init_db
    [[ "$path_mode" != "--no" ]] && setup_path "$path_mode"
    print_summary
}

main "$@"
