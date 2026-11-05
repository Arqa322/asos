# ~/.bashrc (ASOS)
[[ $- != *i* ]] && return

alias ls='eza --group-directories-first --icons=auto'
alias ll='eza -la --group-directories-first --icons=auto --git'
alias cat='bat --paging=never --style=plain'
alias grep='grep --color=auto'
alias ip='ip -color=auto'
alias z='asos-zapret'
alias update='sudo pacman -Syu'

export EDITOR=nano
export VISUAL=nano
HISTSIZE=10000
HISTFILESIZE=20000
HISTCONTROL=ignoreboth:erasedups
shopt -s histappend checkwinsize

[[ -r /usr/share/bash-completion/bash_completion ]] && . /usr/share/bash-completion/bash_completion
[[ -r /usr/share/fzf/key-bindings.bash ]] && . /usr/share/fzf/key-bindings.bash

PS1='\[\e[1;36m\]\u@\h\[\e[0m\] \[\e[1;34m\]\w\[\e[0m\] \$ '
