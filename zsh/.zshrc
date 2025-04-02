# zmodload zsh/zprof

# Download and install ZINIT
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"

if [ ! -d $ZINIT_HOME ]; then
  mkdir -p "$(dirname $ZINIT_HOME)"
  git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi
source "${ZINIT_HOME}/zinit.zsh"

# Prompt
if [ "$TERM_PROGRAM" != "Apple_Terminal" ]; then
  eval "$(oh-my-posh init zsh --config $HOME/.config/ohmyposh/zen.toml)"
fi

# Plugins
zinit light zsh-users/zsh-syntax-highlighting
zinit light zsh-users/zsh-completions
zinit light zsh-users/zsh-autosuggestions
# zinit light trapd00r/LS_COLORS
zinit light Aloxaf/fzf-tab

# Snippets
zinit snippet OMZL::git.zsh
zinit snippet OMZP::git
zinit snippet OMZP::sudo
zinit snippet OMZP::archlinux
zinit snippet OMZP::docker
zinit snippet OMZP::docker-compose
zinit snippet OMZP::kubectl
zinit snippet OMZP::kubectx
zinit snippet OMZP::command-not-found

# Loading completions
autoload -Uz compinit
for dump in ~/.zcompdump(N.mh+24); do
  compinit
done
compinit -C

# Enable hidden files completion
_comp_options+=(globdots)

zinit cdreplay -q

export EDITOR='nvim'
# Keybindings
bindkey -e
bindkey '^p' history-search-backward
bindkey '^n' history-search-forward

# History
HISTSIZE=10000
HISTFILE=~/.zsh_history
SAVEHIST=$HISTSIZE
HISTDUP=erase
setopt appendhistory
setopt sharehistory
setopt hist_ignore_space
setopt hist_ignore_all_dups
setopt hist_save_no_dups
setopt hist_ignore_dups
setopt hist_find_no_dups

# Completion styling
export LS_COLORS="di=34:fi=0:ln=36:pi=33:so=32:bd=34;46:cd=34;43:su=37;41:sg=30;43:tw=30;42:ow=34;42"

zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path ~/.zsh/cache
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}' # case insensitive match
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':fzf-tab:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no #disable default menu in favor of fzf
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls --color $realpath'
zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'ls --color $realpath'
# zstyle ':fzf-tab:*' fzf-preview 'cat $realpath'

# Aliases
alias l='ls -al --color'
alias ls='ls -al --color'
alias vim='nvim'
alias v='nvim'
alias c='clear'
alias lg='lazygit'
alias as='aerospace'
alias d='docker'

# git aliases
alias gaa="git add --all"
alias gap="git add -p"
alias gb="git branch"
alias gcb="git checkout -b"
alias gc="git checkout"
alias gcm="git checkout main"
alias gf="git fetch"
alias gm="git merge"
alias gp="git push"
alias gpf="git push -f"
alias gss="git status"
alias gs="git status -s"
alias glogg="git log --graph --pretty=oneline --decorate --abbrev-commit"
alias glog="git log --pretty=oneline --decorate --abbrev-commit -n 10"
alias gk="git commit -m"
alias gwa="git-worktree-add"

# Shell integrations
eval "$(fzf --zsh)"
eval "$(zoxide init --cmd cd zsh)"

# carapace shell integration
export CARAPACE_BRIDGES='zsh,fish,bash,inshellisense' # optional
zstyle ':completion:*' format $'\e[2;37mCompleting %d\e[m'
source <(carapace _carapace)

# shell integrations
source <(COMPLETE=zsh tms)

# Paths
export GOPATH=$HOME/go
export PATH="$PATH:$HOME/.local/bin:$GOPATH/bin:/usr/local/share/dotnet"

# yazi helper function
function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	yazi "$@" --cwd-file="$tmp"
	if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
		builtin cd -- "$cwd"
	fi
	rm -f -- "$tmp"
}

function ff() {
    aerospace list-windows --all | fzf --bind 'enter:execute(bash -c "aerospace focus --window-id {1}")+abort'
}

# zprof
