#!/bin/bash
#
# terminal-setup — One-script terminal environment setup
#
# Platforms: macOS, Debian/Ubuntu, Windows (via WSL)
#
# Stack: Ghostty + Zsh + Starship + Nerd Font (MesloLGS)
# Tools: bat, eza, fd, ripgrep, btop, zoxide, jq, tldr, delta, lazygit, fzf
# Node:  fnm (Fast Node Manager)
# Theme: Catppuccin Mocha (Starship)
#
# Usage:
#   ./setup.sh
#

set -euo pipefail

# ─── Colors ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# run_cmd: execute a command
run_cmd() {
    "$@"
}

# ─── Arguments ──────────────────────────────────────────────────────
if [[ "$#" -ne 0 ]]; then
    error "This script does not accept any arguments.\n  Usage: ./setup.sh"
fi

# ─── OS Detection ───────────────────────────────────────────────────
# Possible values: macos, debian, wsl, unsupported
detect_os() {
    local uname_out
    uname_out="$(uname -s)"

    case "$uname_out" in
        Darwin)
            echo "macos"
            ;;
        Linux)
            # Check if running inside WSL
            if grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null; then
                echo "wsl"
            elif [[ -f /etc/debian_version ]] || grep -qi 'debian\|ubuntu' /etc/os-release 2>/dev/null; then
                echo "debian"
            else
                echo "unsupported"
            fi
            ;;
        MINGW*|MSYS*|CYGWIN*)
            echo "windows-native"
            ;;
        *)
            echo "unsupported"
            ;;
    esac
}

OS="$(detect_os)"

case "$OS" in
    macos)
        info "Detected ${BOLD}macOS${NC}"
        ;;
    debian)
        info "Detected ${BOLD}Debian/Ubuntu Linux${NC}"
        ;;
    wsl)
        info "Detected ${BOLD}Windows WSL${NC} (Debian/Ubuntu layer)"
        ;;
    windows-native)
        error "Native Windows (MINGW/MSYS/Cygwin) is not supported.\n  Please install WSL: https://learn.microsoft.com/en-us/windows/wsl/install\n  Then run this script inside WSL."
        ;;
    *)
        error "Unsupported OS: $(uname -s)\n  This script supports macOS, Debian/Ubuntu, and Windows WSL."
        ;;
esac

echo ""
info "Setting up with ${BOLD}zsh${NC} on ${BOLD}${OS}${NC}"

# ─── Config Directory ───────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS_DIR="$SCRIPT_DIR/configs"

# If running via curl pipe (no local configs dir), clone the repo first
if [[ ! -d "$CONFIGS_DIR" ]]; then
    info "Config files not found locally, cloning repo..."
    TMPDIR_CLONE="$(mktemp -d)"
    git clone --depth 1 https://github.com/lewislulu/terminal-setup.git "$TMPDIR_CLONE/terminal-setup"
    SCRIPT_DIR="$TMPDIR_CLONE/terminal-setup"
    CONFIGS_DIR="$SCRIPT_DIR/configs"
fi

# ═══════════════════════════════════════════════════════════════════════
# Helper Functions (cross-platform)
# ═══════════════════════════════════════════════════════════════════════

# Install a package using the appropriate package manager
pkg_install() {
    local pkg="$1"
    case "$OS" in
        macos)
            if brew list "$pkg" &>/dev/null; then
                success "$pkg already installed"
                return 0
            fi
            info "Installing $pkg..."
            run_cmd brew install "$pkg"
            ;;
        debian|wsl)
            if dpkg -s "$pkg" &>/dev/null 2>&1; then
                success "$pkg already installed"
                return 0
            fi
            info "Installing $pkg..."
            run_cmd sudo apt-get install -y "$pkg"
            ;;
    esac
    success "$pkg installed"
}

# Check if a command exists
has_cmd() {
    command -v "$1" &>/dev/null
}

linux_arch() {
    case "$(uname -m)" in
        x86_64|amd64) echo "x86_64" ;;
        aarch64|arm64) echo "aarch64" ;;
        armv7l|armv7) echo "armv7" ;;
        armv6l|armv6) echo "armv6" ;;
        *)
            error "Unsupported Linux architecture: $(uname -m)"
            ;;
    esac
}

download_github_asset() {
    local repo="$1"
    local pattern="$2"
    local output="$3"
    local api_url="https://api.github.com/repos/$repo/releases/latest"
    local asset_url

    asset_url="$(curl -fsSL "$api_url" | jq -r --arg pattern "$pattern" '
        .assets[]
        | select(.name | test($pattern))
        | .browser_download_url
        ' | head -n 1)"

    if [[ -z "$asset_url" ]]; then
        error "Could not find a matching release asset for $repo (pattern: $pattern)"
    fi

    run_cmd curl -fsSL "$asset_url" -o "$output"
}

install_tarball_binary_from_github() {
    local repo="$1"
    local pattern="$2"
    local binary_name="$3"
    local tmpdir archive_path

    tmpdir="$(mktemp -d)"
    archive_path="$tmpdir/archive.tar.gz"
    download_github_asset "$repo" "$pattern" "$archive_path"
    run_cmd tar -xzf "$archive_path" -C "$tmpdir"

    local binary_path
    binary_path="$(find "$tmpdir" -type f -name "$binary_name" | head -n 1)"
    if [[ -z "$binary_path" ]]; then
        error "Downloaded archive from $repo did not contain $binary_name"
    fi

    run_cmd sudo install -m 755 "$binary_path" "/usr/local/bin/$binary_name"
    rm -rf "$tmpdir"
}

install_raw_binary_from_github() {
    local repo="$1"
    local pattern="$2"
    local binary_name="$3"
    local tmpdir binary_path

    tmpdir="$(mktemp -d)"
    binary_path="$tmpdir/$binary_name"
    download_github_asset "$repo" "$pattern" "$binary_path"
    run_cmd sudo install -m 755 "$binary_path" "/usr/local/bin/$binary_name"
    rm -rf "$tmpdir"
}

# ─── Step 1: Package Manager ────────────────────────────────────────
echo ""
echo -e "${BOLD}══════════════════════════════════════════${NC}"
echo -e "${BOLD}  📦 Step 1/9: Package Manager${NC}"
echo -e "${BOLD}══════════════════════════════════════════${NC}"

case "$OS" in
    macos)
        if ! has_cmd brew; then
            info "Installing Homebrew..."
            run_cmd /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            # Auto-detect Homebrew prefix (Apple Silicon vs Intel)
            if [[ -d /opt/homebrew ]]; then
                eval "$(/opt/homebrew/bin/brew shellenv)"
            elif [[ -d /usr/local/Homebrew ]]; then
                eval "$(/usr/local/bin/brew shellenv)"
            fi
            success "Homebrew installed"
        else
            success "Homebrew already installed"
        fi
        ;;
    debian|wsl)
        info "Updating apt package index..."
        run_cmd sudo apt-get update
        # Ensure basic build tools are available
        pkg_install "curl"
        pkg_install "git"
        pkg_install "wget"
        pkg_install "unzip"
        pkg_install "build-essential"
        success "apt package manager ready"
        ;;
esac

# Needed before Step 3 for GitHub release asset lookup.
pkg_install "jq"

# ─── Step 2: Terminal Emulator ───────────────────────────────────────
echo ""
echo -e "${BOLD}══════════════════════════════════════════${NC}"
echo -e "${BOLD}  👻 Step 2/9: Terminal Emulator${NC}"
echo -e "${BOLD}══════════════════════════════════════════${NC}"

case "$OS" in
    macos)
        if [[ ! -d "/Applications/Ghostty.app" ]]; then
            info "Installing Ghostty..."
            run_cmd brew install --cask ghostty
            success "Ghostty installed"
        else
            success "Ghostty already installed"
        fi
        ;;
    debian)
        # Ghostty on Linux: check if already installed, otherwise try snap/flatpak or skip
        if has_cmd ghostty; then
            success "Ghostty already installed"
        else
            warn "Ghostty is not easily available on Linux via apt."
            echo -e "  Options to install Ghostty on Linux:"
            echo -e "    • Snap:    ${BOLD}sudo snap install ghostty${NC}"
            echo -e "    • Build:   ${BOLD}https://ghostty.org/docs/install/build${NC}"
            echo -e "    • Or use any other terminal (kitty, alacritty, etc.)"
            echo ""
            info "Skipping Ghostty installation — install it manually if desired."
        fi
        ;;
    wsl)
        info "WSL detected — terminal emulator runs on the Windows side."
        echo -e "  Install Ghostty for Windows: ${BOLD}https://ghostty.org${NC}"
        echo -e "  Or use Windows Terminal, which works great with WSL."
        info "Skipping terminal emulator installation."
        ;;
esac

# ─── Step 3: Nerd Font (MesloLGS NF) ────────────────────────────────
echo ""
echo -e "${BOLD}══════════════════════════════════════════${NC}"
echo -e "${BOLD}  🔤 Step 3/9: Nerd Font (MesloLGS NF)${NC}"
echo -e "${BOLD}══════════════════════════════════════════${NC}"

# Determine font directory based on OS
case "$OS" in
    macos)
        FONT_DIR="$HOME/Library/Fonts"
        ;;
    debian|wsl)
        FONT_DIR="$HOME/.local/share/fonts"
        ;;
esac

MESLO_FONTS=(
    "MesloLGS NF Regular.ttf"
    "MesloLGS NF Bold.ttf"
    "MesloLGS NF Italic.ttf"
    "MesloLGS NF Bold Italic.ttf"
)

normalize_font_filename() {
    basename "$1" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]'
}

find_meslo_font_in_archive() {
    local archive_dir="$1"
    local style_key="$2"
    local stems=(
        "meslolgsnerdfont${style_key}"
        "meslolgsnf${style_key}"
    )
    local file normalized stem

    while IFS= read -r -d '' file; do
        normalized="$(normalize_font_filename "$file")"
        for stem in "${stems[@]}"; do
            if [[ "$normalized" == "${stem}ttf" || "$normalized" == "${stem}otf" ]]; then
                printf '%s\n' "$file"
                return 0
            fi
        done
    done < <(find "$archive_dir" -type f \( -iname '*.ttf' -o -iname '*.otf' \) -print0)

    return 1
}

FONT_INSTALLED=true
for font in "${MESLO_FONTS[@]}"; do
    [[ ! -f "$FONT_DIR/$font" ]] && FONT_INSTALLED=false && break
done

if $FONT_INSTALLED; then
    success "MesloLGS NF fonts already installed"
else
    info "Installing MesloLGS NF fonts from Nerd Fonts release..."
    run_cmd mkdir -p "$FONT_DIR"
    FONT_TMPDIR="$(mktemp -d)"
    FONT_ARCHIVE="$FONT_TMPDIR/Meslo.zip"
    download_github_asset "ryanoasis/nerd-fonts" '^Meslo\.zip$' "$FONT_ARCHIVE"
    run_cmd unzip -oq "$FONT_ARCHIVE" -d "$FONT_TMPDIR"

    copied_fonts=0
    font_pairs=(
        "MesloLGS NF Regular.ttf:regular"
        "MesloLGS NF Bold.ttf:bold"
        "MesloLGS NF Italic.ttf:italic"
        "MesloLGS NF Bold Italic.ttf:bolditalic"
    )

    for pair in "${font_pairs[@]}"; do
        IFS=':' read -r font style_key <<< "$pair"
        source_font_path="$(find_meslo_font_in_archive "$FONT_TMPDIR" "$style_key" || true)"
        if [[ -n "$source_font_path" ]]; then
            run_cmd cp "$source_font_path" "$FONT_DIR/$font"
            copied_fonts=$((copied_fonts + 1))
        else
            warn "Font style not found in downloaded archive: $font"
        fi
    done

    rm -rf "$FONT_TMPDIR"
    # Rebuild font cache on Linux
    if [[ "$OS" == "debian" || "$OS" == "wsl" ]]; then
        if has_cmd fc-cache; then
            run_cmd fc-cache -fv "$FONT_DIR"
        fi
    fi
    if [[ "$copied_fonts" -eq "${#MESLO_FONTS[@]}" ]]; then
        success "MesloLGS NF fonts installed"
    elif [[ "$copied_fonts" -gt 0 ]]; then
        warn "Installed $copied_fonts/${#MESLO_FONTS[@]} MesloLGS NF font files"
    else
        error "MesloLGS NF download completed, but no matching font files were found in the archive"
    fi
fi

# ─── Step 4: Shell ──────────────────────────────────────────────────
echo ""
echo -e "${BOLD}══════════════════════════════════════════${NC}"
echo -e "${BOLD}  🐚 Step 4/9: Zsh + Plugins${NC}"
echo -e "${BOLD}══════════════════════════════════════════${NC}"

install_shell_macos() {
    # Zsh is pre-installed on macOS, just install the plugins
    local plugins=(zsh-autosuggestions zsh-syntax-highlighting zsh-completions)
    for plugin in "${plugins[@]}"; do
        if brew list "$plugin" &>/dev/null; then
            success "$plugin already installed"
        else
            info "Installing $plugin..."
            run_cmd brew install "$plugin"
            success "$plugin installed"
        fi
    done

    ZSH_PATH="$(which zsh)"
    if [[ "$SHELL" != "$ZSH_PATH" ]]; then
        info "Setting Zsh as default shell..."
        run_cmd chsh -s "$ZSH_PATH"
        success "Default shell changed to Zsh"
    else
        success "Zsh is already the default shell"
    fi
}

install_shell_linux() {
    if ! has_cmd zsh; then
        info "Installing Zsh..."
        run_cmd sudo apt-get install -y zsh
        success "Zsh installed"
    else
        success "Zsh already installed"
    fi

    local ZSH_PLUGINS_DIR="/usr/share"

    if [[ -f "$ZSH_PLUGINS_DIR/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
        success "zsh-autosuggestions already installed"
    elif dpkg -s zsh-autosuggestions &>/dev/null 2>&1; then
        success "zsh-autosuggestions already installed"
    else
        info "Installing zsh-autosuggestions..."
        run_cmd sudo apt-get install -y zsh-autosuggestions 2>/dev/null || {
            info "apt package not available, cloning from git..."
            run_cmd sudo git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_PLUGINS_DIR/zsh-autosuggestions"
        }
        success "zsh-autosuggestions installed"
    fi

    if [[ -f "$ZSH_PLUGINS_DIR/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
        success "zsh-syntax-highlighting already installed"
    elif dpkg -s zsh-syntax-highlighting &>/dev/null 2>&1; then
        success "zsh-syntax-highlighting already installed"
    else
        info "Installing zsh-syntax-highlighting..."
        run_cmd sudo apt-get install -y zsh-syntax-highlighting 2>/dev/null || {
            info "apt package not available, cloning from git..."
            run_cmd sudo git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_PLUGINS_DIR/zsh-syntax-highlighting"
        }
        success "zsh-syntax-highlighting installed"
    fi

    ZSH_PATH="$(which zsh)"
    if [[ "$SHELL" != "$ZSH_PATH" ]]; then
        info "Setting Zsh as default shell..."
        run_cmd chsh -s "$ZSH_PATH"
        success "Default shell changed to Zsh"
    else
        success "Zsh is already the default shell"
    fi
}

case "$OS" in
    macos)  install_shell_macos ;;
    debian|wsl) install_shell_linux ;;
esac

# ─── Step 5: CLI Tools ──────────────────────────────────────────────
echo ""
echo -e "${BOLD}══════════════════════════════════════════${NC}"
echo -e "${BOLD}  🛠  Step 5/9: CLI Tools${NC}"
echo -e "${BOLD}══════════════════════════════════════════${NC}"

install_cli_tools_macos() {
    local TOOLS=(bat eza fd ripgrep btop zoxide jq tldr git-delta lazygit fzf)
    for tool in "${TOOLS[@]}"; do
        if brew list "$tool" &>/dev/null; then
            success "$tool already installed"
        else
            info "Installing $tool..."
            run_cmd brew install "$tool"
            success "$tool installed"
        fi
    done
}

install_cli_tools_linux() {
    local arch
    arch="$(linux_arch)"

    # Tools available directly from apt (on modern Debian/Ubuntu)
    local APT_TOOLS=(bat fd-find ripgrep jq fzf)

    for tool in "${APT_TOOLS[@]}"; do
        if dpkg -s "$tool" &>/dev/null 2>&1; then
            success "$tool already installed"
        else
            info "Installing $tool..."
            run_cmd sudo apt-get install -y "$tool"
            success "$tool installed"
        fi
    done

    # btop — not in apt on older Debian/Ubuntu, use snap as fallback
    if has_cmd btop; then
        success "btop already installed"
    else
        info "Installing btop..."
        if run_cmd sudo apt-get install -y btop 2>/dev/null; then
            success "btop installed via apt"
        elif has_cmd snap; then
            info "btop not in apt, trying snap..."
            run_cmd sudo snap install btop
            success "btop installed via snap"
        else
            warn "btop not available via apt or snap — skipping (install manually: https://github.com/aristocratos/btop)"
        fi
    fi

    # zoxide — not in apt on older Debian/Ubuntu, use official installer as fallback
    if has_cmd zoxide; then
        success "zoxide already installed"
    else
        info "Installing zoxide..."
        if run_cmd sudo apt-get install -y zoxide 2>/dev/null; then
            success "zoxide installed via apt"
        elif has_cmd snap && run_cmd sudo snap install zoxide 2>/dev/null; then
            success "zoxide installed via snap"
        else
            info "zoxide not in apt/snap, using official installer..."
            run_cmd sh -c "$(curl -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh)" -- --bin-dir /usr/local/bin
            success "zoxide installed via official installer"
        fi
    fi

    # bat is installed as 'batcat' on Debian/Ubuntu — create symlink
    if has_cmd batcat && ! has_cmd bat; then
        info "Creating symlink: batcat → bat"
        mkdir -p "$HOME/.local/bin"
        run_cmd ln -sf "$(which batcat)" "$HOME/.local/bin/bat"
        success "bat symlink created"
    fi

    # fd is installed as 'fdfind' on Debian/Ubuntu — create symlink
    if has_cmd fdfind && ! has_cmd fd; then
        info "Creating symlink: fdfind → fd"
        mkdir -p "$HOME/.local/bin"
        run_cmd ln -sf "$(which fdfind)" "$HOME/.local/bin/fd"
        success "fd symlink created"
    fi

    # eza — try apt first, then GitHub release
    if has_cmd eza; then
        success "eza already installed"
    else
        info "Installing eza..."
        if run_cmd sudo apt-get install -y eza 2>/dev/null; then
            success "eza installed via apt"
        else
            case "$arch" in
                x86_64) install_tarball_binary_from_github "eza-community/eza" 'eza_x86_64-unknown-linux-gnu\.tar\.gz$' "eza" ;;
                aarch64) install_tarball_binary_from_github "eza-community/eza" 'eza_aarch64-unknown-linux-gnu\.tar\.gz$' "eza" ;;
                *) warn "No remote eza install configured for architecture: $arch" ;;
            esac
            has_cmd eza && success "eza installed from GitHub release"
        fi
    fi

    # tldr (tealdeer) — try apt first, then GitHub release
    if has_cmd tldr; then
        success "tldr already installed"
    else
        info "Installing tldr..."
        if run_cmd sudo apt-get install -y tealdeer 2>/dev/null; then
            success "tldr installed via apt"
        else
            case "$arch" in
                x86_64) install_raw_binary_from_github "tealdeer-rs/tealdeer" '^tealdeer-linux-x86_64-musl$' "tldr" ;;
                aarch64) install_raw_binary_from_github "tealdeer-rs/tealdeer" '^tealdeer-linux-aarch64-musl$' "tldr" ;;
                armv7) install_raw_binary_from_github "tealdeer-rs/tealdeer" '^tealdeer-linux-armv7-musleabihf$' "tldr" ;;
                armv6) install_raw_binary_from_github "tealdeer-rs/tealdeer" '^tealdeer-linux-arm-musleabi$' "tldr" ;;
                *) warn "No remote tldr install configured for architecture: $arch" ;;
            esac
            has_cmd tldr && success "tldr installed from GitHub release"
        fi
    fi

    # git-delta — try apt first, then GitHub release
    if has_cmd delta; then
        success "git-delta already installed"
    else
        info "Installing git-delta..."
        if run_cmd sudo apt-get install -y git-delta 2>/dev/null; then
            success "git-delta installed via apt"
        else
            case "$arch" in
                x86_64) install_tarball_binary_from_github "dandavison/delta" 'delta-[0-9.]+-x86_64-unknown-linux-gnu\.tar\.gz$' "delta" ;;
                aarch64) install_tarball_binary_from_github "dandavison/delta" 'delta-[0-9.]+-aarch64-unknown-linux-gnu\.tar\.gz$' "delta" ;;
                armv7) install_tarball_binary_from_github "dandavison/delta" 'delta-[0-9.]+-arm-unknown-linux-gnueabihf\.tar\.gz$' "delta" ;;
                *) warn "No remote delta install configured for architecture: $arch" ;;
            esac
            has_cmd delta && success "git-delta installed from GitHub release"
        fi
    fi

    # lazygit — try apt first, then GitHub release
    if has_cmd lazygit; then
        success "lazygit already installed"
    else
        info "Installing lazygit..."
        if run_cmd sudo apt-get install -y lazygit 2>/dev/null; then
            success "lazygit installed via apt"
        else
            case "$arch" in
                x86_64) install_tarball_binary_from_github "jesseduffield/lazygit" '^lazygit_[0-9.]+_linux_x86_64\.tar\.gz$' "lazygit" ;;
                aarch64) install_tarball_binary_from_github "jesseduffield/lazygit" '^lazygit_[0-9.]+_linux_arm64\.tar\.gz$' "lazygit" ;;
                armv6) install_tarball_binary_from_github "jesseduffield/lazygit" '^lazygit_[0-9.]+_linux_armv6\.tar\.gz$' "lazygit" ;;
                *) warn "No remote lazygit install configured for architecture: $arch" ;;
            esac
            has_cmd lazygit && success "lazygit installed from GitHub release"
        fi
    fi

    # Ensure ~/.local/bin is in PATH
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        export PATH="$HOME/.local/bin:$PATH"
    fi
}

case "$OS" in
    macos)      install_cli_tools_macos ;;
    debian|wsl) install_cli_tools_linux ;;
esac

# ─── Step 6: Starship Prompt ────────────────────────────────────────
echo ""
echo -e "${BOLD}══════════════════════════════════════════${NC}"
echo -e "${BOLD}  🚀 Step 6/9: Starship Prompt${NC}"
echo -e "${BOLD}══════════════════════════════════════════${NC}"

if has_cmd starship; then
    success "Starship already installed"
else
    case "$OS" in
        macos)
            info "Installing Starship..."
            run_cmd brew install starship
            ;;
        debian|wsl)
            info "Installing Starship..."
            run_cmd sh -c "$(curl -fsSL https://starship.rs/install.sh)" -- --yes
            ;;
    esac
    success "Starship installed"
fi

# ─── Step 7: fnm + Node.js (optional) ───────────────────────────────
echo ""
echo -e "${BOLD}══════════════════════════════════════════${NC}"
echo -e "${BOLD}  🟢 Step 7/9: fnm + Node.js (optional)${NC}"
echo -e "${BOLD}══════════════════════════════════════════${NC}"

if has_cmd fnm; then
    success "fnm already installed"
    # Load fnm in current shell so we can install Node
    eval "$(fnm env --use-on-cd --shell bash)"
    if ! fnm list 2>/dev/null | grep -q lts; then
        info "Installing Node LTS..."
        run_cmd fnm install --lts
        run_cmd fnm default lts-latest
        run_cmd fnm use lts-latest
        success "Node LTS installed and set as default"
    else
        success "Node LTS already installed"
    fi
else
    echo ""
    echo -e "  ${YELLOW}⚠ WARNING: fnm manages its own Node.js versions.${NC}"
    echo -e "  ${YELLOW}  If you already have Node.js installed (e.g. via nvm, Homebrew, or system),${NC}"
    echo -e "  ${YELLOW}  fnm may shadow your existing Node/npm and tools installed globally${NC}"
    echo -e "  ${YELLOW}  (e.g. Claude Code, Codex CLI, pnpm global packages).${NC}"
    echo -e "  ${YELLOW}  Only install fnm if you need to manage multiple Node versions.${NC}"
    echo ""
    printf "  Install fnm + Node.js? (y/N, default: N): "
    read -r INSTALL_FNM
    if [[ "$INSTALL_FNM" =~ ^[Yy]$ ]]; then
        case "$OS" in
            macos)
                info "Installing fnm (Fast Node Manager)..."
                run_cmd brew install fnm
                ;;
            debian|wsl)
                info "Installing fnm via official installer..."
                run_cmd bash -c "$(curl -fsSL https://fnm.vercel.app/install)" -- --skip-shell
                export PATH="$HOME/.local/share/fnm:$PATH"
                ;;
        esac
        success "fnm installed"

        # Load fnm in current shell so we can install Node
        if has_cmd fnm; then
            eval "$(fnm env --use-on-cd --shell bash)"
            info "Installing Node LTS..."
            run_cmd fnm install --lts
            run_cmd fnm default lts-latest
            run_cmd fnm use lts-latest
            success "Node LTS installed and set as default"
        fi
    else
        info "Skipping fnm + Node.js"
    fi
fi

# ─── Step 8: Zellij (optional) ──────────────────────────────────────
echo ""
echo -e "${BOLD}══════════════════════════════════════════${NC}"
echo -e "${BOLD}  🪟 Step 8/9: Zellij (optional)${NC}"
echo -e "${BOLD}══════════════════════════════════════════${NC}"

if has_cmd zellij; then
    success "Zellij already installed"
else
    echo ""
    echo -e "  Zellij is a modern terminal multiplexer (like tmux, but better UX)."
    printf "  Install Zellij? (y/N): "
    read -r INSTALL_ZELLIJ
    if [[ "$INSTALL_ZELLIJ" =~ ^[Yy]$ ]]; then
        case "$OS" in
            macos)
                info "Installing Zellij..."
                run_cmd brew install zellij
                ;;
            debian|wsl)
                local arch
                arch="$(linux_arch)"
                info "Installing Zellij..."
                case "$arch" in
                    x86_64) install_tarball_binary_from_github "zellij-org/zellij" '^zellij-x86_64-unknown-linux-musl\.tar\.gz$' "zellij" ;;
                    aarch64) install_tarball_binary_from_github "zellij-org/zellij" '^zellij-aarch64-unknown-linux-musl\.tar\.gz$' "zellij" ;;
                    *) warn "No remote zellij install configured for architecture: $arch" ;;
                esac
                ;;
        esac
        success "Zellij installed"
    else
        info "Skipping Zellij"
    fi
fi

# ─── Step 9: Config Files ───────────────────────────────────────────
echo ""
echo -e "${BOLD}══════════════════════════════════════════${NC}"
echo -e "${BOLD}  📦 Step 9/9: Deploying Configs${NC}"
echo -e "${BOLD}══════════════════════════════════════════${NC}"

# --- Ghostty config ---
deploy_ghostty_config() {
    local ghostty_config_dir
    case "$OS" in
        macos)
            ghostty_config_dir="$HOME/Library/Application Support/com.mitchellh.ghostty"
            ;;
        debian)
            ghostty_config_dir="$HOME/.config/ghostty"
            ;;
        wsl)
            info "Ghostty config: configure on the Windows side if using Ghostty for Windows."
            info "Deploying Linux-side config to ~/.config/ghostty/ for reference."
            ghostty_config_dir="$HOME/.config/ghostty"
            ;;
    esac

    mkdir -p "$ghostty_config_dir"
    if [[ -f "$ghostty_config_dir/config" ]] || [[ -f "$ghostty_config_dir/config.ghostty" ]]; then
        local existing
        existing="$(ls "$ghostty_config_dir"/config* 2>/dev/null | head -1)"
        run_cmd cp "$existing" "${existing}.bak.$(date +%s)"
        warn "Backed up existing Ghostty config"
    fi

    # macOS uses config.ghostty, Linux uses config
    case "$OS" in
        macos)
            run_cmd cp "$CONFIGS_DIR/ghostty.config" "$ghostty_config_dir/config.ghostty"
            ;;
        debian|wsl)
            run_cmd cp "$CONFIGS_DIR/ghostty.config" "$ghostty_config_dir/config"
            ;;
    esac
    success "Ghostty config deployed"
}

deploy_ghostty_config

# --- Starship config ---
MANAGED_CONFIG_DIR="$HOME/.config/terminal-setup"
MANAGED_STARSHIP_CONFIG="$MANAGED_CONFIG_DIR/starship.toml"
run_cmd mkdir -p "$MANAGED_CONFIG_DIR"
run_cmd cp "$CONFIGS_DIR/starship.toml" "$MANAGED_STARSHIP_CONFIG"
success "Starship managed config deployed"

# --- Shell-specific config ---
MANAGED_ZSHRC="$MANAGED_CONFIG_DIR/zshrc.managed"
ZSHRC_LOADER_START='# >>> terminal-setup >>>'
ZSHRC_LOADER_END='# <<< terminal-setup <<<'
ZSHRC_LOADER='[[ -f "$HOME/.config/terminal-setup/zshrc.managed" ]] && source "$HOME/.config/terminal-setup/zshrc.managed"'
ZSHRC_BLOCK="$ZSHRC_LOADER_START"$'\n'"$ZSHRC_LOADER"$'\n'"$ZSHRC_LOADER_END"
ZSHRC_TARGET="$HOME/.zshrc"

run_cmd mkdir -p "$MANAGED_CONFIG_DIR"
run_cmd cp "$CONFIGS_DIR/.zshrc" "$MANAGED_ZSHRC"

if [[ ! -f "$ZSHRC_TARGET" ]]; then
    printf '%s\n' "$ZSHRC_BLOCK" > "$ZSHRC_TARGET"
    success "Created .zshrc loader"
elif grep -qF "$ZSHRC_LOADER_START" "$ZSHRC_TARGET" 2>/dev/null; then
    success "terminal-setup loader already present in .zshrc"
else
    run_cmd cp "$ZSHRC_TARGET" "$ZSHRC_TARGET.bak.$(date +%s)"
    warn "Backed up existing .zshrc before inserting loader"
    TMP_ZSHRC="$(mktemp)"
    printf '%s\n\n' "$ZSHRC_BLOCK" > "$TMP_ZSHRC"
    cat "$ZSHRC_TARGET" >> "$TMP_ZSHRC"
    mv "$TMP_ZSHRC" "$ZSHRC_TARGET"
    success "Inserted terminal-setup loader at top of .zshrc"
fi

success "Zsh managed config deployed"

# ─── Git config for delta ────────────────────────────────────────────
if has_cmd delta; then
    info "Configuring git-delta as git pager..."
    run_cmd git config --global core.pager delta
    run_cmd git config --global interactive.diffFilter "delta --color-only"
    run_cmd git config --global delta.navigate true
    run_cmd git config --global delta.dark true
    run_cmd git config --global delta.line-numbers true
    run_cmd git config --global delta.side-by-side true
    run_cmd git config --global merge.conflictstyle diff3
    run_cmd git config --global diff.colorMoved default
    success "git-delta configured"
fi

# ─── Done! ───────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}══════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  ✅ All done!${NC}"
echo -e "${BOLD}══════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BOLD}Platform:${NC} $OS"
echo -e ""
echo -e "  ${BOLD}Your terminal stack:${NC}"
case "$OS" in
    macos)
        echo -e "    👻 Ghostty              — terminal emulator"
        ;;
    debian)
        echo -e "    👻 Ghostty              — terminal (install separately on Linux)"
        ;;
    wsl)
        echo -e "    💻 Windows Terminal      — recommended for WSL"
        ;;
esac
echo -e "    🐚 Zsh                  — shell (POSIX-compatible)"
echo -e "    ✨ zsh-autosuggestions   — inline suggestions"
echo -e "    🎨 zsh-syntax-highlight — syntax highlighting"
echo -e "    🚀 Starship             — prompt (Catppuccin Mocha)"
echo -e "    🔤 MesloLGS NF          — nerd font"
echo -e "    🟢 fnm                  — Node version manager (fast!)"
echo -e "    📦 bat eza fd rg        — modern coreutils"
echo -e "    📊 btop                 — system monitor"
echo -e "    🔀 lazygit + delta      — git tools"
echo -e "    📁 zoxide               — smart cd"
echo -e "    🔍 fzf                  — fuzzy finder"
if has_cmd zellij; then
    echo -e "    🪟 zellij               — terminal multiplexer"
fi
echo ""
echo -e "  ${YELLOW}Next steps:${NC}"
echo -e "    1. Restart your terminal (or open ${BOLD}Ghostty${NC})"
echo -e "    2. Node is ready: ${BOLD}node --version${NC}"
echo -e "    3. Pin a project: ${BOLD}echo 22 > .node-version${NC} (fnm auto-switches)"
echo -e "    4. Try: ${BOLD}Ctrl+R${NC} (fzf history) / ${BOLD}Ctrl+T${NC} (fzf files)"
echo ""
