#!/bin/zsh
# ─── terminal-setup: Zsh config ─────────────────────────────────────
# Powered by: Starship + zsh-autosuggestions + zsh-syntax-highlighting + fzf + fnm

# ─── Homebrew ────────────────────────────────────────────────────────
if [[ -d /opt/homebrew ]]; then
    export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
    BREW_PREFIX="/opt/homebrew"
elif [[ -d /usr/local ]]; then
    export PATH="/usr/local/bin:/usr/local/sbin:$PATH"
    BREW_PREFIX="/usr/local"
else
    BREW_PREFIX=""
fi

if [[ "$OSTYPE" != darwin* ]]; then
    export PATH="$HOME/.local/bin:$PATH"
fi

# ─── Completions ─────────────────────────────────────────────────────
# Add completion definitions to fpath before running compinit.
if [[ -n "$BREW_PREFIX" && -d "$BREW_PREFIX/share/zsh-completions" ]]; then
    fpath=("$BREW_PREFIX/share/zsh-completions" $fpath)
elif [[ -d /usr/share/zsh-completions ]]; then
    fpath=(/usr/share/zsh-completions $fpath)
fi
autoload -Uz compinit
ZSH_COMPDUMP="${ZDOTDIR:-$HOME}/.zcompdump"
if [[ -f "$ZSH_COMPDUMP" && -n "$(find "$ZSH_COMPDUMP" -mtime -1 -print -quit 2>/dev/null)" ]]; then
    compinit -C -d "$ZSH_COMPDUMP"
else
    compinit -d "$ZSH_COMPDUMP"
fi

# Substring + case-insensitive completion
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|=*' 'l:|=*'

# ─── History ─────────────────────────────────────────────────────────
HISTSIZE=50000
SAVEHIST=50000
HISTFILE=~/.zsh_history
setopt EXTENDED_HISTORY
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt SHARE_HISTORY
setopt INC_APPEND_HISTORY

# ─── Zsh plugins (via Homebrew) ──────────────────────────────────────
# Autosuggestions can make use of the completion system, so load it
# after compinit. Keep synta34x highlighting for the end of the file.
if [[ -n "$BREW_PREFIX" && -f "$BREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
    source "$BREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
elif [[ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
    source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
fi
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'
ZSH_AUTOSUGGEST_STRATEGY=(history completion)

# ─── fzf ─────────────────────────────────────────────────────────────
if [[ -f ~/.fzf.zsh ]]; then
    source ~/.fzf.zsh
elif command -v fzf &>/dev/null; then
    eval "$(fzf --zsh 2>/dev/null)"
fi
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'
# Use fd for fzf if available
if command -v fd &>/dev/null; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
fi

# ─── Zoxide (smart cd) ──────────────────────────────────────────────
if command -v zoxide &>/dev/null; then
    eval "$(zoxide init zsh)"
fi

# ─── fnm (Node version manager) ─────────────────────────────────────
if [[ "$OSTYPE" != darwin* && -d "$HOME/.local/share/fnm" ]]; then
    export PATH="$HOME/.local/share/fnm:$PATH"
fi
if command -v fnm &>/dev/null; then
    eval "$(fnm env --use-on-cd --shell zsh)"
fi

# ─── History prefix search (↑/↓) ─────────────────────────────────────
# Keep these bindings after plugin/tool setup so later init code is less
# likely to override them.
autoload -U up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search
bindkey '^[[B' down-line-or-beginning-search
bindkey '^[[1;3D' backward-word
bindkey '^[[1;3C' forward-word

# ─── Starship prompt ────────────────────────────────────────────────
if command -v starship &>/dev/null; then
    export STARSHIP_CONFIG="$HOME/.config/terminal-setup/starship.toml"
    eval "$(starship init zsh)"
fi

# ─── SSH key switcher (fallback for multi-account setups) ────────────
# Usage: set-ssh-key work-github
#        set-ssh-key --append work-github
# Prefer ~/.ssh/config Host aliases for automatic matching.
# This is a fallback for edge cases where you need to force a specific key.
function set-ssh-key() {
    local append=0
    if [[ "$1" == "--append" ]]; then
        append=1
        shift
    fi

    if [[ -z "$1" ]]; then
        echo "Usage: set-ssh-key [--append] <key-name>" >&2
        echo "Available keys:" >&2
        ls ~/.ssh/*.pub 2>/dev/null | sed 's/.*\//  /; s/\.pub$//' >&2
        return 1
    fi

    local key="$HOME/.ssh/$1"
    if [[ ! -f "$key" ]]; then
        echo "Key not found: $key" >&2
        echo "Available keys:" >&2
        ls ~/.ssh/*.pub 2>/dev/null | sed 's/.*\//  /; s/\.pub$//' >&2
        return 1
    fi
    if (( ! append )); then
        echo "Clearing existing SSH agent identities. Use --append to keep them." >&2
        ssh-add -D 2>/dev/null
    fi
    ssh-add "$key"
    echo "Active SSH key: $1"
}

# ─── Aliases ─────────────────────────────────────────────────────────
if command -v eza &>/dev/null; then
    alias ls='eza --icons --group-directories-first'
    alias ll='eza -la --icons --group-directories-first'
    alias lt='eza --tree --icons --level=2'
else
    alias ll='ls -la'
fi
command -v bat &>/dev/null && alias cat='bat'
command -v fd &>/dev/null && alias find='fd'
command -v rg &>/dev/null && alias grep='rg'
command -v btop &>/dev/null && alias top='btop'
command -v lazygit &>/dev/null && alias lg='lazygit'

# ─── pnpm ────────────────────────────────────────────────────────────
if [[ "$OSTYPE" == darwin* ]]; then
    export PNPM_HOME="$HOME/Library/pnpm"
else
    export PNPM_HOME="$HOME/.local/share/pnpm"
fi
case ":$PATH:" in
    *":$PNPM_HOME:"*) ;;
    *) export PATH="$PNPM_HOME:$PATH" ;;
esac

# ─── Syntax Highlighting ─────────────────────────────────────────────
# Load zsh-syntax-highlighting last so its ZLE hooks see the final set
# of widgets and key bindings.
if [[ -n "$BREW_PREFIX" && -f "$BREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
    source "$BREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
elif [[ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
    source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi
