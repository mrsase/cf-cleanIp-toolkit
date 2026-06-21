#!/usr/bin/env bash
# tunnel — Cloudflare Clean IP toolkit installer
# Usage: curl -fsSL https://raw.githubusercontent.com/<user>/tunnel/main/install.sh | bash
#        or: ./install.sh [--prefix /usr/local] [--no-path]
set -euo pipefail

PROJECT="tunnel"
PROJECT_VERSION="$(cat "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/VERSION" 2>/dev/null || echo "1.0.0")"

# --- Upstream versions (bump these when new scanner releases come out) ---
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

# --- Project root (support running from anywhere) ---
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$ROOT/bin"
DATA_DIR="$ROOT/data"
DB_DIR="$ROOT/db"
SCRIPTS_DIR="$ROOT/scripts"
RESULTS_DIR="$ROOT/results"
LOGS_DIR="$ROOT/logs"

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
        x86_64|amd64)  echo "amd64"  ;;
        aarch64|arm64)  echo "arm64"  ;;
        i386|i686)      echo "386"    ;;
        armv5*)         echo "armv5"  ;;
        armv6*)         echo "armv6"  ;;
        armv7*)         echo "armv7"  ;;
        mips)           echo "mips"   ;;
        mips64)         echo "mips64" ;;
        mips64le)       echo "mips64le" ;;
        mipsle)         echo "mipsle" ;;
        *)              echo "unknown" ;;
    esac
}

OS="$(detect_os)"
ARCH="$(detect_arch)"
info "Detected: $OS / $ARCH"

# --- Dependency check ---
check_deps() {
    local missing=()
    for cmd in curl python3 sqlite3; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    if ! command -v unzip &>/dev/null && ! command -v tar &>/dev/null; then
        missing+=("unzip or tar")
    fi
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing dependencies: ${missing[*]}"
        info "Install them with your package manager (e.g. 'brew install ...' or 'apt install ...')"
        exit 1
    fi
}

# --- Download helpers ---
download() {
    local url="$1" out="$2"
    info "Downloading $(basename "$out")..."
    if command -v curl &>/dev/null; then
        curl -fsSL "$url" -o "$out"
    elif command -v wget &>/dev/null; then
        wget -q "$url" -O "$out"
    else
        error "Neither curl nor wget found. Install one and retry."
        exit 1
    fi
}

# --- Install cfst ---
install_cfst() {
    header "CloudflareSpeedTest ($CFST_VERSION)"

    local arch_map_asset
    case "$OS" in
        darwin)
            case "$ARCH" in
                amd64) arch_map_asset="darwin_amd64" ;;
                arm64) arch_map_asset="darwin_arm64" ;;
                *) error "Unsupported arch: $ARCH for macOS"; return 1 ;;
            esac
            local filename="cfst_${arch_map_asset}.zip"
            local url="https://github.com/${CFST_REPO}/releases/download/${CFST_VERSION}/${filename}"
            local tmpfile="$(mktemp)"
            download "$url" "$tmpfile"
            unzip -o "$tmpfile" cfst -d "$BIN_DIR" >/dev/null 2>&1
            rm -f "$tmpfile"
            ;;
        linux)
            case "$ARCH" in
                amd64) arch_map_asset="linux_amd64" ;;
                arm64) arch_map_asset="linux_arm64" ;;
                386)   arch_map_asset="linux_386" ;;
                *) error "Unsupported arch: $ARCH for Linux"; return 1 ;;
            esac
            local filename="cfst_${arch_map_asset}.tar.gz"
            local url="https://github.com/${CFST_REPO}/releases/download/${CFST_VERSION}/${filename}"
            local tmpfile="$(mktemp)"
            download "$url" "$tmpfile"
            tar -xzf "$tmpfile" -C "$BIN_DIR" cfst 2>/dev/null
            rm -f "$tmpfile"
            ;;
        *)
            error "Unsupported OS: $OS"
            return 1
            ;;
    esac

    chmod +x "$BIN_DIR/cfst"
    info "cfst installed: $("$BIN_DIR/cfst" -v 2>&1 | head -1)"
}

# --- Install senpaiscanner ---
install_senpai() {
    header "SenPaiScanner ($SENPAI_VERSION)"

    local arch_suffix
    case "$OS" in
        darwin)
            case "$ARCH" in
                amd64) arch_suffix="darwin-amd64" ;;
                arm64) arch_suffix="darwin-arm64" ;;
                *) error "Unsupported arch: $ARCH for macOS"; return 1 ;;
            esac
            ;;
        linux)
            case "$ARCH" in
                amd64) arch_suffix="linux-amd64" ;;
                arm64) arch_suffix="linux-arm64" ;;
                386)   arch_suffix="linux-386" ;;
                *) error "Unsupported arch: $ARCH for Linux"; return 1 ;;
            esac
            ;;
        *)
            error "Unsupported OS: $OS"
            return 1
            ;;
    esac

    local url="https://github.com/${SENPAI_REPO}/releases/download/${SENPAI_VERSION}/senpaiscanner-${arch_suffix}"
    if [[ "$OS" == "windows" ]]; then
        url="${url}.exe"
    fi

    download "$url" "$BIN_DIR/senpaiscanner"
    chmod +x "$BIN_DIR/senpaiscanner"
    info "senpaiscanner installed"
}

# --- Fetch Cloudflare IP ranges ---
install_ranges() {
    header "Cloudflare IP ranges"
    mkdir -p "$DATA_DIR"

    download "https://www.cloudflare.com/ips-v4" "$DATA_DIR/ip.txt"
    download "https://www.cloudflare.com/ips-v6" "$DATA_DIR/ipv6.txt"

    info "IPv4 ranges: $(wc -l < "$DATA_DIR/ip.txt")"
    info "IPv6 ranges: $(wc -l < "$DATA_DIR/ipv6.txt")"
}

# --- Initialize database ---
init_db() {
    header "Database"
    mkdir -p "$DB_DIR"
    if [[ -f "$DB_DIR/clean_ips.db" ]]; then
        info "Database already exists: $DB_DIR/clean_ips.db ($(du -h "$DB_DIR/clean_ips.db" | cut -f1))"
        return
    fi
    if [[ -f "$SCRIPTS_DIR/schema.sql" ]]; then
        sqlite3 "$DB_DIR/clean_ips.db" < "$SCRIPTS_DIR/schema.sql"
        info "Database created: $DB_DIR/clean_ips.db"
    else
        warn "Schema file not found at $SCRIPTS_DIR/schema.sql — skipping DB init"
    fi
}

# --- Add to PATH ---
setup_path() {
    header "PATH integration"

    local shell_rc
    if [[ "$SHELL" == */zsh ]]; then
        shell_rc="$HOME/.zshrc"
    elif [[ "$SHELL" == */bash ]]; then
        if [[ "$OS" == "darwin" ]]; then
            shell_rc="$HOME/.bash_profile"
        else
            shell_rc="$HOME/.bashrc"
        fi
    else
        shell_rc="$HOME/.profile"
    fi

    local path_line="export PATH=\"\$PATH:$ROOT\""

    if grep -qF "$ROOT" "$shell_rc" 2>/dev/null; then
        info "Already in PATH ($shell_rc)"
        return
    fi

    echo
    info "Add $ROOT to your PATH?"
    printf "  This will append the following line to %s:\n" "$shell_rc"
    printf "    ${CYAN}%s${NC}\n" "$path_line"
    printf "  [Y/n]: "
    read -r answer
    case "$answer" in
        n|N|no|NO)
            warn "Skipped PATH setup. Add manually or use: ./tunnel <command>"
            ;;
        *)
            echo "" >> "$shell_rc"
            echo "$path_line" >> "$shell_rc"
            info "Added to $shell_rc — restart your shell or run: source $shell_rc"
            info "Then you can use 'tunnel <command>' from anywhere"
            ;;
    esac
}

# --- Print summary ---
print_summary() {
    header "Installation complete"
    echo "  Project      : $ROOT"
    echo "  Version      : $PROJECT_VERSION"
    echo "  Platform     : $OS / $ARCH"
    echo "  Binaries     :"
    echo "    cfst       : $(test -x "$BIN_DIR/cfst" && "$BIN_DIR/cfst" -v 2>&1 | head -1 || echo MISSING)"
    echo "    senpai     : $(test -x "$BIN_DIR/senpaiscanner" && echo present || echo MISSING)"
    echo "  Database     : $(test -f "$DB_DIR/clean_ips.db" && echo "$DB_DIR/clean_ips.db ($(du -h "$DB_DIR/clean_ips.db" | cut -f1))" || echo not initialized)"
    echo "  IP ranges    : v4=$(test -f "$DATA_DIR/ip.txt" && wc -l < "$DATA_DIR/ip.txt" || echo ?) / v6=$(test -f "$DATA_DIR/ipv6.txt" && wc -l < "$DATA_DIR/ipv6.txt" || echo ?)"
    echo ""
    echo "  Quick start:"
    echo "    ${CYAN}./tunnel update ranges${NC}       # Refresh IP ranges"
    echo "    ${CYAN}./tunnel scan${NC}                # Run a quick scan"
    echo "    ${CYAN}./tunnel top${NC}                 # View best results"
    echo "    ${CYAN}./tunnel status${NC}              # System overview"
    echo "    ${CYAN}./tunnel help${NC}                # All commands"
    echo ""
    if grep -qF "$ROOT" "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile" 2>/dev/null; then
        echo "  PATH integration: active (restart shell or 'source ~/.<rc>' to use 'tunnel' globally)"
    fi
}

# --- Main ---
main() {
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

    mkdir -p "$BIN_DIR" "$DATA_DIR" "$DB_DIR" "$RESULTS_DIR/cfst" "$RESULTS_DIR/senpai" "$LOGS_DIR" "$ROOT/exports"

    install_cfst
    install_senpai
    install_ranges
    init_db

    if [[ "${1:-}" != "--no-path" ]]; then
        setup_path
    fi

    print_summary
}

main "$@"
