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

# ------------------------------------------------------- AI assistant (ии)
# ии как установить телеграм  |  команда 2>&1 | ии  |  ии объясни (previous command)
ии() { HUILO_AI_LAST_CMD="$(fc -ln -2 -2 2>/dev/null | sed 's/^[[:space:]]*//')" huilo-ai "$@"; }
alias ai='ии'
# a mistyped command gets a hint instead of a bare "command not found"
command_not_found_handle() {
	printf 'bash: %s: команда не найдена\n' "$1" >&2
	if [[ -t 2 && -z "${HUILO_AI_HINTED:-}" ]] && command -v huilo-ai >/dev/null; then
		HUILO_AI_HINTED=1
		printf '  \e[38;2;138;145;165mНе знаете, как сделать? Спросите помощника: ии как …\e[0m\n' >&2
	fi
	return 127
}

# ------------------------------------------------------------ completion
[[ -r /usr/share/bash-completion/bash_completion ]] && . /usr/share/bash-completion/bash_completion
if [[ -r /usr/share/fzf/key-bindings.bash ]]; then
	. /usr/share/fzf/key-bindings.bash
	. /usr/share/fzf/completion.bash 2>/dev/null
	# colours: /etc/profile.d/huilo-theme.sh (theme/palette.toml)
	: "${FZF_DEFAULT_OPTS:=--height=40% --layout=reverse --border=rounded}"
	export FZF_DEFAULT_OPTS
fi

# ---------------------------------------------------------------- prompt
# starship needs a Nerd Font: use it in graphical terminals, keep a plain
# coloured prompt on the text console (TERM=linux)
if [[ "$TERM" != linux ]] && command -v starship >/dev/null; then
	eval "$(starship init bash)"
else
	PS1='\[\e[1;33m\]\u\[\e[0m\]@\[\e[1;31m\]\h\[\e[0m\] \[\e[1;37m\]\w\[\e[0m\] \[\e[33m\]❯\[\e[0m\] '
fi

# --------------------------------------------------------------- welcome
# system summary once per new terminal window (not on the text console, not in
# tmux/screen or VS Code, not in nested shells); disable: touch ~/.config/huilo/no-fastfetch
if [[ "$TERM" != linux && -z "${TMUX:-}${STY:-}" && "${TERM_PROGRAM:-}" != vscode && -z "${HUILO_FETCHED:-}" \
	&& ! -e ~/.config/huilo/no-fastfetch ]] && command -v fastfetch >/dev/null; then
	export HUILO_FETCHED=1
	fastfetch
fi
