export ZSH=~/.oh-my-zsh

# Homebrew prefix on macOS (/opt/homebrew on Apple Silicon, /usr/local on Intel)
if [[ "$OSTYPE" == darwin* ]]; then
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$b" ] && eval "$("$b" shellenv)" && break
  done
  unset b
  BREW_PREFIX="$HOMEBREW_PREFIX"
fi

# Neovim tarball install on Linux (macOS gets nvim from Homebrew)
[ -d /opt/nvim-linux-x86_64/bin ] && export PATH="/opt/nvim-linux-x86_64/bin:$PATH"
[ -d "$HOME/.local/bin" ] && export PATH="$HOME/.local/bin:$PATH"

export EDITOR=nvim

# macOS Terminal sends LC_CTYPE=UTF-8 over SSH, which is not a valid locale on Linux
[[ "$OSTYPE" == linux* && "$LC_CTYPE" == UTF-8 ]] && export LC_CTYPE=C.UTF-8

# HIST_IGNORE_SPACE don't store commands prefixed with a space
# HIST_NO_STORE don't store history (fc -l) command
# HIST_NO_FUNCTIONS don't store function definitions
setopt HIST_IGNORE_SPACE
ZSH_THEME="mortalscumbag"
plugins=(git)
# Custom completions (grunden CLI); must be on fpath before oh-my-zsh runs compinit
fpath=(~/os-install/dotfiles/nvim/scripts/completions $fpath)
source $ZSH/oh-my-zsh.sh
. ~/.aliases
. ~/.shortcuts
. ~/.functions

# zsh-autosuggestions: Homebrew on macOS, oh-my-zsh custom plugin dir on Linux
for f in \
  "$BREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh" \
  "${ZSH_CUSTOM:-$ZSH/custom}/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" \
  /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh; do
  [ -f "$f" ] && source "$f" && break
done
unset f

# auto completion for teamocil
compctl -g '~/.teamocil/*(:t:r)' teamocil

export NVM_DIR="$HOME/.nvm"
# nvm: Homebrew install on macOS, git install (~/.nvm) on Linux
NVM_SRC="${BREW_PREFIX:+$BREW_PREFIX/opt/nvm}"
[ -s "$NVM_SRC/nvm.sh" ] || NVM_SRC="$NVM_DIR"
[ -s "$NVM_SRC/nvm.sh" ] && . "$NVM_SRC/nvm.sh"  # This loads nvm
[ -s "$NVM_SRC/etc/bash_completion" ] && . "$NVM_SRC/etc/bash_completion"  # This loads nvm bash_completion
[ -s "$NVM_SRC/bash_completion" ] && . "$NVM_SRC/bash_completion"
unset NVM_SRC
