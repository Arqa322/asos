# Huilo Dusk for terminal programs (fzf, dialog menus, gum). Login shells read
# this; the graphical session and its terminals inherit the variables.
export DIALOGRC=/usr/share/huilo/theme/dialogrc
export FZF_DEFAULT_OPTS="--height=40% --layout=reverse --border=rounded --info=inline-right --pointer=▌ --marker=+ \
--color=bg+:@{ink3},bg:-1,fg:@{fog},fg+:@{snow},hl:@{amber},hl+:@{honey},info:@{mist},prompt:@{amber} \
--color=pointer:@{amber},marker:@{pine},spinner:@{ember},header:@{glacier},border:@{ink4},gutter:-1"
# gum (huilo-ai and other helpers)
export GUM_CHOOSE_CURSOR_FOREGROUND="@{amber}" GUM_CHOOSE_SELECTED_FOREGROUND="@{honey}" GUM_CHOOSE_HEADER_FOREGROUND="@{mist}"
export GUM_INPUT_CURSOR_FOREGROUND="@{amber}" GUM_INPUT_PROMPT_FOREGROUND="@{amber}" GUM_INPUT_PLACEHOLDER_FOREGROUND="@{mist}"
export GUM_CONFIRM_SELECTED_BACKGROUND="@{amber}" GUM_CONFIRM_SELECTED_FOREGROUND="@{ink0}" GUM_CONFIRM_UNSELECTED_BACKGROUND="@{ink3}"
export GUM_SPIN_SPINNER_FOREGROUND="@{amber}" GUM_FILTER_INDICATOR_FOREGROUND="@{amber}" GUM_FILTER_MATCH_FOREGROUND="@{honey}"
