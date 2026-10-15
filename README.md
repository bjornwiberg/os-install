# macOS

Follow the steps from "Install Brew" below. For Linux, see [Linux (Debian/Ubuntu)](#linux-debianubuntu) at the bottom.

## Install Brew

```
/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
```

### Git

```
brew install git
```

- Generate SSH-key

```
ssh-keygen -t rsa -b 4096 -C "Key comment" && ssh-add ~/.ssh/id_rsa && pbcopy < ~/.ssh/id_rsa.pub
```

- Git email

```
git config --global user.email "b@bjrn.nu"
```

- nvim as default git commit editor

```
git config --global core.editor nvim
```

## Glone repo

```
cd && git clone --depth=1 git@github.com:bjornwiberg/os-install.git
```

### Brew bundle

```
cd ~/os-install && brew bundle
```

### Osx settings

```
cd ~/os-install && chmod +x .osx && ./.osx
```

### Symlink dotfiles

```
cd
touch ~/.aliases
rm ~/.zshrc
ln -s os-install/dotfiles/.zshrc
ln -s os-install/dotfiles/.shortcuts
ln -s os-install/dotfiles/.functions
ln -s os-install/dotfiles/.tmux.conf
```

### Symlink settings for nvim

```
mkdir -p ~/.config
cd ~/.config
ln -s ~/os-install/dotfiles/nvim
```

### Install pynvim for python3 support in nvim

```
python3 -m pip install --user --upgrade pynvim
```

### Symlink settings for vscode

```
mkdir -p ~/Library/Application\ Support/Code/User
cd ~/Library/Application\ Support/Code/User
rm settings.json
ln -s ~/os-install/vscode/settings.json
```

### Oh My Zsh

```
sh -c "$(curl -fsSL https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"
```

### Install tpm for TMUX

Nothing to do: `.tmux.conf` clones tpm and installs missing plugins on every tmux start (needs `git`).

### Teamocil

https://github.com/remi/teamocil

```
gem install teamocil
cd && ln -s os-install/dotfiles/.teamocil
```

### Nerd Font Patched

```
cd ~/Library/Fonts && curl -fLo "FiraCodeNerdFontMono-Regular.ttf" https://github.com/ryanoasis/nerd-fonts/raw/master/patched-fonts/FiraCode/Regular/FiraCodeNerdFontMono-Regular.ttf
```

---

# Linux (Debian/Ubuntu)

Tested on Debian 12 (bookworm). Run as a normal user with `sudo` (drop `sudo` if you are root).

### System packages

```
sudo apt update
sudo apt install -y git zsh tmux curl unzip xz-utils build-essential \
  ripgrep fd-find python3-venv nodejs npm locales xclip
mkdir -p ~/.local/bin && ln -sf "$(command -v fdfind)" ~/.local/bin/fd
```

### UTF-8 locale (needed for icons in nvim)

```
sudo sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
sudo locale-gen
sudo update-locale LANG=en_US.UTF-8
```

### Neovim (Debian's package is too old)

```
curl -fLO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz
sudo rm -rf /opt/nvim-linux-x86_64
sudo tar -C /opt -xzf nvim-linux-x86_64.tar.gz
rm nvim-linux-x86_64.tar.gz
sudo apt remove -y neovim 2>/dev/null   # avoid the old /usr/bin/nvim shadowing it
```

### tree-sitter CLI (needed by nvim-treesitter)

The prebuilt release binary needs glibc 2.39+, which Debian 12 doesn't have, so build it with Rust:

```
curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal --no-modify-path
~/.cargo/bin/cargo install tree-sitter-cli --locked --force --root ~/.local
```

On distros with glibc 2.39+ (Ubuntu 24.04+, Debian 13) you can use the prebuilt one instead:

```
curl -fsSL https://github.com/tree-sitter/tree-sitter/releases/latest/download/tree-sitter-linux-x64.gz \
  | gunzip > ~/.local/bin/tree-sitter && chmod +x ~/.local/bin/tree-sitter
```

### Git

```
git config --global user.email "b@bjrn.nu"
git config --global core.editor nvim
ssh-keygen -t ed25519 -C "Key comment" && cat ~/.ssh/id_ed25519.pub   # add to GitHub
```

### Clone repo

```
cd && git clone --depth=1 git@github.com:bjornwiberg/os-install.git
```

### Oh My Zsh + zsh-autosuggestions

```
sh -c "$(curl -fsSL https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh)" "" --unattended
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
chsh -s "$(command -v zsh)"
```

### Symlink dotfiles and nvim config

```
cd
touch ~/.aliases
rm -f ~/.zshrc
ln -s os-install/dotfiles/.zshrc
ln -s os-install/dotfiles/.shortcuts
ln -s os-install/dotfiles/.functions
ln -s os-install/dotfiles/.tmux.conf
mkdir -p ~/.config && ln -s ~/os-install/dotfiles/nvim ~/.config/nvim
```

### tmux plugins

Nothing to do: `.tmux.conf` clones tpm and installs missing plugins on every tmux start (needs `git`).

### First nvim start

```
exec zsh
nvim
```

lazy.nvim installs the plugins, and nvim-treesitter compiles its parsers on the first start. Run `:checkhealth` to see what's still missing.

### Nerd Font

Install the font on the machine running your **terminal**, not the server. On a Linux desktop:

```
mkdir -p ~/.local/share/fonts && cd ~/.local/share/fonts \
  && curl -fLo "FiraCodeNerdFontMono-Regular.ttf" https://github.com/ryanoasis/nerd-fonts/raw/master/patched-fonts/FiraCode/Regular/FiraCodeNerdFontMono-Regular.ttf \
  && fc-cache -f
```
