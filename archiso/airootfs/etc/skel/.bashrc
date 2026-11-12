# ~/.bashrc (Huilo)
[[ $- != *i* ]] && return

# ---------------------------------------------------------------- history
HISTSIZE=50000
HISTFILESIZE=100000
HISTCONTROL=ignoreboth:erasedups
HISTTIMEFORMAT='%F %T  '
shopt -s histappend checkwinsize cmdhist autocd cdspell globstar 2>/dev/null
PROMPT_COMMAND="history -a${PROMPT_COMMAND:+; $PROMPT_COMMAND}"

export EDITOR=nano
export VISUAL=nano
export PAGER=less
export LESS='-R --mouse --wheel-lines=3 -i'
export MANPAGER="sh -c 'col -bx | bat -l man -p'"
export MANROFFOPT='-c'
export BAT_THEME=ansi

# ---------------------------------------------------------------- aliases
if command -v eza >/dev/null; then
	alias ls='eza --group-directories-first --icons=auto'
	alias ll='eza -la --group-directories-first --icons=auto --git --time-style=long-iso'
	alias lt='eza --tree --level=2 --icons=auto'
fi
command -v bat >/dev/null && alias cat='bat --paging=never --style=plain'
alias grep='grep --color=auto'
alias diff='diff --color=auto'
alias ip='ip -color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias z='huilo-zapret'
alias update='sudo pacman -Syu'
alias ff='fastfetch'
alias wall='huilo-wallpaper pick'

# ------------------------------------------------------------ completion
[[ -r /usr/share/bash-completion/bash_completion ]] && . /usr/share/bash-completion/bash_completion
if [[ -r /usr/share/fzf/key-bindings.bash ]]; then
	. /usr/share/fzf/key-bindings.bash
	. /usr/share/fzf/completion.bash 2>/dev/null
	export FZF_DEFAULT_OPTS="--height=40% --layout=reverse --border=rounded \
--color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8,fg:#cdd6f4,header:#f38ba8 \
--color=info:#cba6f7,pointer:#f5e0dc,marker:#b4befe,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8"
fi

# ---------------------------------------------------------------- prompt
# starship needs a Nerd Font: use it in graphical terminals, keep a plain
# coloured prompt on the text console (TERM=linux)
if [[ "$TERM" != linux ]] && command -v starship >/dev/null; then
	eval "$(starship init bash)"
else
	PS1='\[\e[1;34m\]\u\[\e[0m\]@\[\e[1;35m\]\h\[\e[0m\] \[\e[1;36m\]\w\[\e[0m\] \$ '
fi

# --------------------------------------------------------------- welcome
# system summary once per new terminal window (not on the text console, not in
# tmux/screen or VS Code, not in nested shells); disable: touch ~/.config/huilo/no-fastfetch
if [[ "$TERM" != linux && -z "${TMUX:-}${STY:-}" && "${TERM_PROGRAM:-}" != vscode && -z "${HUILO_FETCHED:-}" \
	&& ! -e ~/.config/huilo/no-fastfetch ]] && command -v fastfetch >/dev/null; then
	export HUILO_FETCHED=1
	fastfetch
fi
