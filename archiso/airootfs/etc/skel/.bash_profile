# ~/.bash_profile (ASOS)
[[ -f ~/.bashrc ]] && . ~/.bashrc

# Start the graphical session on tty1 (skip with kernel option "asos.nogui").
# asos-session tries Hyprland and falls back to safer graphics modes if it
# cannot start; if nothing works it leaves you in this console with a hint.
if [[ -z "${WAYLAND_DISPLAY:-}" && "${XDG_VTNR:-}" == 1 ]] && ! grep -qw asos.nogui /proc/cmdline; then
	if asos-session; then
		exit 0   # session ended normally (log out)
	fi
fi
