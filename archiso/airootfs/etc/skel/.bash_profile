# ~/.bash_profile (ASOS)
[[ -f ~/.bashrc ]] && . ~/.bashrc

# Start Hyprland automatically on tty1 (skip with kernel option "asos.nogui")
if [[ -z "${WAYLAND_DISPLAY:-}" && "${XDG_VTNR:-}" == 1 ]] && ! grep -qw asos.nogui /proc/cmdline; then
	if command -v start-hyprland >/dev/null 2>&1; then
		exec start-hyprland
	else
		exec Hyprland
	fi
fi
