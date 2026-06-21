#!/usr/bin/env bash
# Build cfst (CloudflareSpeedTest) and senpaiscanner from upstream source.
#
# Used by:
#   - install.sh   (when no pre-built binary is available)
#   - make build    (compile for current arch)
#   - make release  (compile for all archs and package tarballs)
set -euo pipefail

PROJECT="cf-cleanIp-toolkit"
CFST_VERSION="v2.3.5"
CFST_REPO="XIU2/CloudflareSpeedTest"
SENPAI_VERSION="v0.5.0"
SENPAI_REPO="MatinSenPai/SenPaiScanner"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { printf "${GREEN}[INFO]${NC}  %s\n" "$*"; }
warn()  { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$*"; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SUPPORTED=( "darwin/amd64" "darwin/arm64" "linux/amd64" "linux/arm64" "linux/386" )

# --- Ensure Go cross-compilation env vars ---
set_goenv() {
    local os="$1" arch="$2"
    case "$os" in
        darwin) export GOOS="darwin" ;;
        linux)  export GOOS="linux"  ;;
        *)      return 1 ;;
    esac
    case "$arch" in
        amd64) export GOARCH="amd64" ;;
        arm64) export GOARCH="arm64" ;;
        386)   export GOARCH="386"   ;;
        *)     return 1 ;;
    esac
}

# --- Build scanners from upstream source ---
build_scanners() {
    local dest="$1"

    if ! command -v go &>/dev/null; then
        error "Go is not installed. Install it first: https://go.dev/doc/install"
        return 1
    fi

    local tmpdir
    tmpdir="$(mktemp -d)"
    local gopath="${tmpdir}/gopath"
    export GOPATH="$gopath"
    export PATH="$GOPATH/bin:$PATH"

    # --- cfst ---
    info "Building cfst ${CFST_VERSION}..."
    git clone --depth 1 --branch "$CFST_VERSION" "https://github.com/${CFST_REPO}.git" "$tmpdir/cfst" 2>/dev/null
    (
        cd "$tmpdir/cfst"
        go build -ldflags="-s -w" -o "$dest/cfst" .
    )
    chmod +x "$dest/cfst"

    # --- senpaiscanner ---
    info "Building senpaiscanner ${SENPAI_VERSION}..."
    git clone --depth 1 --branch "$SENPAI_VERSION" "https://github.com/${SENPAI_REPO}.git" "$tmpdir/senpai" 2>/dev/null
    (
        cd "$tmpdir/senpai"
        go build -ldflags="-s -w" -o "$dest/senpaiscanner" .
    )
    chmod +x "$dest/senpaiscanner"

    rm -rf "$tmpdir"
    info "Build complete"
}

# --- Create a release tarball (binaries + project files) ---
package_release() {
    local os="$1" arch="$2" dest_dir="$3"
    local label="${os}-${arch}"
    local pkg_dir="$dest_dir/${PROJECT}-${label}"

    mkdir -p "$pkg_dir/bin"

    # Build binaries into the package dir
    set_goenv "$os" "$arch"
    build_scanners "$pkg_dir/bin"

    # Copy project files
    cp "$ROOT/cf-cleanIp-toolkit" "$pkg_dir/"
    cp "$ROOT/VERSION" "$pkg_dir/"
    cp "$ROOT/LICENSE" "$pkg_dir/"
    cp "$ROOT/install.sh" "$pkg_dir/"
    cp -r "$ROOT/scripts" "$pkg_dir/"
    cp -r "$ROOT/launchd" "$pkg_dir/"
    mkdir -p "$pkg_dir"/{data,db,exports,logs,results/cfst,results/senpai}

    local tarball="$dest_dir/${PROJECT}-${label}.tar.gz"
    tar -czf "$tarball" -C "$dest_dir" "${PROJECT}-${label}" 2>/dev/null
    rm -rf "$pkg_dir"

    echo "$tarball"
}

# --- Main ---
main() {
    local opt_os="" opt_arch="" dest="$ROOT/bin" pkg=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --os)      opt_os="$2";  shift 2 ;;
            --arch)    opt_arch="$2"; shift 2 ;;
            --dest)    dest="$2";    shift 2 ;;
            --package) pkg=1;       shift   ;;
            --all|-a)
                for platform in "${SUPPORTED[@]}"; do
                    os="${platform%/*}"; arch="${platform#*/}"
                    info "=== $os/$arch ==="
                    set_goenv "$os" "$arch"
                    "$0" --os "$os" --arch "$arch" ${pkg:+--package}
                done
                return
                ;;
            --help|-h)
                echo "Build cfst + senpaiscanner from upstream source."
                echo ""
                echo "Usage: $0 [--os <os> --arch <arch>] [--dest <dir>] [--package]"
                echo "       $0 --all [--package]"
                echo ""
                echo "  --os,--arch     Target platform (default: current)"
                echo "  --dest <dir>    Output directory (default: bin/)"
                echo "  --package       Create release tarball in <dest>"
                echo "  --all           Build for all supported platforms"
                echo ""
                echo "Supported: ${SUPPORTED[*]}"
                exit 0
                ;;
            *) error "Unknown: $1"; exit 1 ;;
        esac
    done

    # Detect current platform if not specified
    if [[ -z "$opt_os" || -z "$opt_arch" ]]; then
        case "$(uname -s)" in
            Darwin) opt_os="darwin" ;; Linux) opt_os="linux" ;; *) error "Unknown OS"; exit 1 ;;
        esac
        case "$(uname -m)" in
            x86_64|amd64) opt_arch="amd64" ;;
            aarch64|arm64) opt_arch="arm64" ;;
            i386|i686)     opt_arch="386" ;;
            *) error "Unknown arch"; exit 1 ;;
        esac
    fi

    set_goenv "$opt_os" "$opt_arch" || { error "Unsupported: $opt_os/$opt_arch"; exit 1; }

    if [[ "$pkg" == 1 ]]; then
        local tarball
        tarball="$(package_release "$opt_os" "$opt_arch" "$dest")"
        info "Release tarball: $tarball ($(du -h "$tarball" | cut -f1))"
    else
        build_scanners "$dest"
        info "Binaries installed in $dest"
    fi
}

main "$@"
