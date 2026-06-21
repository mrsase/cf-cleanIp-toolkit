#!/usr/bin/env bash
# Download scanner binaries for all (or specific) architectures.
# Used by: make build, make release
set -euo pipefail

PROJECT="tunnel"
CFST_VERSION="v2.3.5"
CFST_REPO="XIU2/CloudflareSpeedTest"
SENPAI_VERSION="v0.5.0"
SENPAI_REPO="MatinSenPai/SenPaiScanner"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$ROOT/bin"
RELEASE_DIR="$ROOT/release"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { printf "${GREEN}[INFO]${NC}  %s\n" "$*"; }
warn()  { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$*"; }

download() {
    local url="$1" out="$2"
    info "Downloading $(basename "$out")..."
    if command -v curl &>/dev/null; then
        curl -fsSL "$url" -o "$out"
    elif command -v wget &>/dev/null; then
        wget -q "$url" -O "$out"
    else
        error "Neither curl nor wget found."
        exit 1
    fi
}

# Supported platforms: os/arch
SUPPORTED=(
    "darwin/amd64"
    "darwin/arm64"
    "linux/amd64"
    "linux/arm64"
    "linux/386"
)

# ---------------------------------------------------------------------------
# Map (os, arch) -> (cfst filename, senpai suffix, extract tool, extract cmd)
# ---------------------------------------------------------------------------
resolve_assets() {
    local os="$1" arch="$2"

    case "$os" in
        darwin)
            case "$arch" in
                amd64) cfst_file="cfst_darwin_amd64.zip" ; senpai_sfx="darwin-amd64" ;;
                arm64) cfst_file="cfst_darwin_arm64.zip" ; senpai_sfx="darwin-arm64" ;;
                *) return 1 ;;
            esac
            cfst_extract="unzip -o \$src \$binary -d \$dest >/dev/null 2>&1"
            cfst_clean="rm -f \$src"
            senpai_extract="cp \$src \$dest/\$binary && chmod +x \$dest/\$binary"
            ;;
        linux)
            case "$arch" in
                amd64) cfst_file="cfst_linux_amd64.tar.gz" ; senpai_sfx="linux-amd64" ;;
                arm64) cfst_file="cfst_linux_arm64.tar.gz" ; senpai_sfx="linux-arm64" ;;
                386)   cfst_file="cfst_linux_386.tar.gz"   ; senpai_sfx="linux-386" ;;
                *) return 1 ;;
            esac
            cfst_extract="tar -xzf \$src -C \$dest cfst 2>/dev/null"
            cfst_clean="rm -f \$src"
            senpai_extract="cp \$src \$dest/\$binary && chmod +x \$dest/\$binary"
            ;;
        *)
            return 1
            ;;
    esac

    cfst_url="https://github.com/${CFST_REPO}/releases/download/${CFST_VERSION}/${cfst_file}"
    senpai_url="https://github.com/${SENPAI_REPO}/releases/download/${SENPAI_VERSION}/senpaiscanner-${senpai_sfx}"

    cat <<EOF
cfst_url=$cfst_url
cfst_file=$cfst_file
senpai_url=$senpai_url
cfst_extract=$cfst_extract
cfst_clean=$cfst_clean
senpai_extract=$senpai_extract
EOF
}

# ---------------------------------------------------------------------------
# Build for a single (os, arch)
# ---------------------------------------------------------------------------
build_for() {
    local os="$1" arch="$2"
    local label="${os}-${arch}"

    eval "$(resolve_assets "$os" "$arch")" || {
        warn "Skipping unsupported: $label"
        return
    }

    info "--- $label ---"

    local tmp_dir
    tmp_dir="$(mktemp -d)"

    # Download cfst
    local cfst_tmp="$tmp_dir/cfst_download"
    download "$cfst_url" "$cfst_tmp"

    # Download senpaiscanner
    local senpai_tmp="$tmp_dir/senpai_download"
    download "$senpai_url" "$senpai_tmp"

    # --- Place in bin/ (for local use) ---
    local binary="cfst"
    src="$cfst_tmp" dest="$BIN_DIR"
    eval "$cfst_extract"
    eval "$cfst_clean"

    binary="senpaiscanner"
    src="$senpai_tmp" dest="$BIN_DIR"
    eval "$senpai_extract"

    # --- Package for release ---
    mkdir -p "$RELEASE_DIR"
    local pkg_dir="$RELEASE_DIR/${PROJECT}-${label}"
    mkdir -p "$pkg_dir/bin"

    # Re-extract/place into package dir
    local cfst_pkg="$tmp_dir/cfst_pkg"
    download "$cfst_url" "$cfst_pkg"
    src="$cfst_pkg" dest="$pkg_dir/bin"
    eval "$cfst_extract"
    eval "$cfst_clean"

    local senpai_pkg="$tmp_dir/senpai_pkg"
    download "$senpai_url" "$senpai_pkg"
    src="$senpai_pkg" dest="$pkg_dir/bin"
    eval "$senpai_extract"

    # Copy project files
    cp "$ROOT/tunnel" "$pkg_dir/"
    cp "$ROOT/VERSION" "$pkg_dir/"
    cp "$ROOT/LICENSE" "$pkg_dir/"
    cp -r "$ROOT/scripts" "$pkg_dir/"
    cp -r "$ROOT/launchd" "$pkg_dir/"
    mkdir -p "$pkg_dir/data" "$pkg_dir/db" "$pkg_dir/exports" "$pkg_dir/results/cfst" "$pkg_dir/results/senpai" "$pkg_dir/logs"
    cp "$ROOT/install.sh" "$pkg_dir/"

    # Create tarball
    local tarball="$RELEASE_DIR/${PROJECT}-${label}.tar.gz"
    tar -czf "$tarball" -C "$RELEASE_DIR" "$(basename "$pkg_dir")"
    rm -rf "$pkg_dir"

    info "Release tarball: $tarball ($(du -h "$tarball" | cut -f1))"
    rm -rf "$tmp_dir"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    mkdir -p "$BIN_DIR" "$RELEASE_DIR"

    local opt_os="" opt_arch=""
    local all=0 current_only=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --os)        opt_os="$2"; shift 2 ;;
            --arch)      opt_arch="$2"; shift 2 ;;
            --all|-a)    all=1; shift ;;
            --current-only|-c) current_only=1; shift ;;
            --help|-h)   echo "Usage: $0 [--os <os> --arch <arch> | --all | --current-only]"; exit 0 ;;
            *)           error "Unknown option: $1"; exit 1 ;;
        esac
    done

    if [[ -n "$opt_os" && -n "$opt_arch" ]]; then
        build_for "$opt_os" "$opt_arch"
    elif [[ "$all" == 1 ]]; then
        for platform in "${SUPPORTED[@]}"; do
            os="${platform%/*}"
            arch="${platform#*/}"
            build_for "$os" "$arch"
        done
    elif [[ "$current_only" == 1 ]]; then
        local os arch
        case "$(uname -s)" in
            Darwin) os="darwin" ;; Linux) os="linux" ;; *) os="unknown" ;;
        esac
        case "$(uname -m)" in
            x86_64|amd64) arch="amd64" ;;
            aarch64|arm64) arch="arm64" ;;
            i386|i686)     arch="386" ;;
            *) arch="unknown" ;;
        esac
        build_for "$os" "$arch"
    else
        echo "Usage: $0 [--os <os> --arch <arch> | --all | --current-only]"
        echo ""
        echo "  --current-only   Build for the current machine (default)"
        echo "  --all            Build for all supported platforms"
        echo "  --os --arch      Build for a specific os/arch pair"
        echo ""
        echo "Supported platforms:"
        for p in "${SUPPORTED[@]}"; do
            echo "  - $p"
        done
        exit 1
    fi
}

main "$@"
