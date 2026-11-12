-- ============================================================
--  Huilo — Hyprland configuration (Hyprland 0.57+, Lua)
--  Wiki: https://wiki.hypr.land/configuring/
--  Keys: SUPER+Enter terminal | SUPER+D apps | SUPER+Space Huilo menu
--        SUPER+Q close | SUPER+E files | SUPER+N notifications
--        SUPER+I AI assistant | SUPER+Z zapret | SUPER+F1 cheat sheet
--        SUPER+A Arduino IDE | SUPER+Shift+A Arduino helper | SUPER+Shift+N NanoPi tools
--  Your own settings: ~/.config/hypr/user.lua (loaded at the end)
--  Colours: ~/.config/hypr/theme.lua (generated from theme/palette.toml)
-- ============================================================

---------------------------------------------------------------- monitors ---
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "auto",
})

---------------------------------------------------------------- programs ---
local terminal    = "kitty"
local fileManager = "thunar"
local menu        = "huilo-menu apps"
local browser     = "firefox"

-- inside a virtual machine (VirtualBox, VMware, QEMU ...)
local function in_vm()
    local h = io.popen("systemd-detect-virt --vm 2>/dev/null")
    if not h then return false end
    local v = h:read("*l")
    h:close()
    return v ~= nil and v ~= "" and v ~= "none"
end
local VM = in_vm()

-- colours of the Huilo Dusk theme; built-in fallback if theme.lua is missing
local ok_theme, theme = pcall(require, "theme")
if not ok_theme or type(theme) ~= "table" then
    theme = {
        accent = "rgba(f2a33aff)", accent2 = "rgba(ff6b4aff)", inactive = "rgba(2e3445aa)",
        locked = "rgba(6f8fc7ff)", group = "rgba(b08ad8ff)", shadow = "rgba(0b0d12cc)",
        background = "rgba(0b0d12ff)",
    }
end

--------------------------------------------------------------- autostart ---
hl.on("hyprland.start", function()
    hl.exec_cmd("huilo-theme apply")
    hl.exec_cmd("waybar")
    hl.exec_cmd("swaync")
    hl.exec_cmd("swayosd-server")
    hl.exec_cmd("huilo-wallpaper")
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd("nm-applet --indicator")
    hl.exec_cmd("blueman-applet")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
    hl.exec_cmd("xdg-user-dirs-update")
    hl.exec_cmd("huilo-welcome")
    hl.exec_cmd("huilo-logwatch run")
    hl.exec_cmd("huilo-eq start")
end)

------------------------------------------------------------- environment ---
hl.env("XCURSOR_THEME", "capitaine-cursors-light")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("SDL_VIDEODRIVER", "wayland,x11")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

----------------------------------------------------------- look and feel ---
hl.config({
    general = {
        gaps_in  = 5,
        gaps_out = { top = 8, right = 14, bottom = 14, left = 14 },
        border_size = 2,
        col = {
            active_border   = { colors = { theme.accent, theme.accent2 }, angle = 45 },
            inactive_border = theme.inactive,
            nogroup_border_active = theme.locked,
        },
        resize_on_border = true,
        allow_tearing    = true,
        layout = "dwindle",
        snap = {
            enabled = true,
        },
    },

    decoration = {
        rounding         = 14,
        rounding_power   = 2.6,
        active_opacity   = 1.0,
        inactive_opacity = 0.97,
        dim_special      = 0.35,
        shadow = {
            enabled      = not VM,
            range        = 24,
            render_power = 3,
            color        = theme.shadow,
        },
        -- blur is expensive on virtual GPUs
        blur = {
            enabled   = not VM,
            size      = 7,
            passes    = 3,
            noise     = 0.02,
            contrast  = 0.95,
            vibrancy  = 0.18,
            popups    = true,
            special   = false,
        },
    },

    animations = {
        enabled = true,
    },

    dwindle = {
        preserve_split = true,
    },

    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo   = true,
        disable_splash_rendering = true,
        background_color        = theme.background,
        animate_manual_resizes  = false,
        focus_on_activate       = true,
        font_family             = "Inter",
    },

    -- hardware cursor planes are broken on most virtual GPUs (0 = off, 1 = on, 2 = auto)
    cursor = {
        no_hardware_cursors = VM and 1 or 2,
    },

    -- US + RU, Alt+Shift switches layout
    input = {
        kb_layout    = "us,ru",
        kb_options   = "grp:alt_shift_toggle",
        follow_mouse = 1,
        sensitivity  = 0,
        touchpad = {
            natural_scroll   = true,
            tap_to_click     = true,
        },
    },
})

-- motion: quick and soft, no bounce
hl.curve("huilo",        { type = "bezier", points = { {0.22, 1},   {0.36, 1} } })
hl.curve("huiloOut",     { type = "bezier", points = { {0.4, 0},    {0.2, 1} } })
hl.curve("linear",       { type = "bezier", points = { {0, 0},      {1, 1} } })

hl.animation({ leaf = "global",        enabled = true, speed = 6,   bezier = "huilo" })
hl.animation({ leaf = "windowsIn",     enabled = true, speed = 4.5, bezier = "huilo",    style = "popin 88%" })
hl.animation({ leaf = "windowsOut",    enabled = true, speed = 3.5, bezier = "huiloOut", style = "popin 92%" })
hl.animation({ leaf = "windowsMove",   enabled = true, speed = 4,   bezier = "huilo" })
hl.animation({ leaf = "border",        enabled = true, speed = 8,   bezier = "huilo" })
hl.animation({ leaf = "borderangle",   enabled = not VM, speed = 80, bezier = "linear",  style = "loop" })
hl.animation({ leaf = "fade",          enabled = true, speed = 4,   bezier = "huilo" })
hl.animation({ leaf = "layersIn",      enabled = true, speed = 3.5, bezier = "huilo",    style = "popin 94%" })
hl.animation({ leaf = "layersOut",     enabled = true, speed = 2.5, bezier = "huiloOut", style = "fade" })
hl.animation({ leaf = "workspaces",    enabled = true, speed = 4.5, bezier = "huilo",    style = "slidefade 12%" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 4, bezier = "huilo",   style = "slidefadevert 20%" })

-------------------------------------------------------------- layer rules ---
-- frosted glass behind the bar, menus, notifications and OSD
for _, ns in ipairs({ "waybar", "rofi", "swaync-control-center", "swaync-notification-window", "swayosd" }) do
    hl.layer_rule({
        name  = "glass-" .. ns,
        match = { namespace = ns },
        blur  = not VM,
        ignore_alpha = 0.35,
    })
end
hl.layer_rule({ name = "dim-behind-launcher", match = { namespace = "rofi" }, dim_around = true })
hl.layer_rule({ name = "no-anim-selection",   match = { namespace = "selection" }, no_anim = true })

------------------------------------------------------------ window rules ---
hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

-- Huilo helpers (zapret menu, logs, hotkeys, AI assistant ...) and small
-- settings apps open as centred floating windows
hl.window_rule({
    name  = "huilo-float",
    match = { class = "^(huilo-float)$" },
    float = true, center = true, size = { 980, 640 },
})
hl.window_rule({
    name  = "huilo-float-title",
    match = { title = "^(huilo-.*)$" },
    float = true, center = true, size = { 980, 640 },
})
hl.window_rule({
    name  = "settings-float",
    match = { class = "^(org.pulseaudio.pavucontrol|pavucontrol|blueman-manager|nm-connection-editor|nwg-look|qt6ct|com.github.wwmm.easyeffects|xdg-desktop-portal-gtk)$" },
    float = true, center = true, size = { 900, 620 },
})
hl.window_rule({
    name  = "dialogs-float",
    match = { title = "^(Open File|Save File|Open Folder|Select a File|Открыть файл|Сохранить файл|Выбор файла).*" },
    float = true, center = true,
})
hl.window_rule({
    name  = "picture-in-picture",
    match = { title = "^(Picture-in-Picture|Картинка в картинке)$" },
    float = true, pin = true, size = { 480, 270 },
})
hl.window_rule({
    name  = "fix-xwayland-drags",
    match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
    no_focus = true,
})

-------------------------------------------------------------- keybindings ---
local mod = "SUPER"

hl.bind(mod .. " + Return",      hl.dsp.exec_cmd(terminal))
hl.bind(mod .. " + Q",           hl.dsp.window.close())
hl.bind(mod .. " + SHIFT + E",   hl.dsp.exit())
hl.bind(mod .. " + E",           hl.dsp.exec_cmd(fileManager))
hl.bind(mod .. " + B",           hl.dsp.exec_cmd(browser))
hl.bind(mod .. " + D",           hl.dsp.exec_cmd(menu))
hl.bind(mod .. " + V",           hl.dsp.window.float({ action = "toggle" }))
hl.bind(mod .. " + F",           hl.dsp.window.fullscreen())
hl.bind(mod .. " + P",           hl.dsp.window.pseudo())
hl.bind(mod .. " + J",           hl.dsp.layout("togglesplit"))
hl.bind(mod .. " + L",           hl.dsp.exec_cmd("hyprlock"))
hl.bind(mod .. " + C",           hl.dsp.exec_cmd("huilo-menu clipboard"))
hl.bind(mod .. " + period",      hl.dsp.exec_cmd("huilo-menu emoji"))
hl.bind(mod .. " + equal",       hl.dsp.exec_cmd("huilo-menu calc"))
hl.bind(mod .. " + space",       hl.dsp.exec_cmd("huilo-menu hub"))
hl.bind(mod .. " + N",           hl.dsp.exec_cmd("swaync-client -t -sw"))
hl.bind(mod .. " + ALT + N",     hl.dsp.exec_cmd("swaync-client -d -sw"))
hl.bind(mod .. " + I",           hl.dsp.exec_cmd("kitty --class huilo-float --title huilo-ai -e huilo-ai"))
hl.bind(mod .. " + Z",           hl.dsp.exec_cmd("kitty --class huilo-float --title huilo-zapret -e huilo-zapret menu"))
hl.bind(mod .. " + F1",          hl.dsp.exec_cmd("kitty --class huilo-float --title huilo-help -e less /usr/share/huilo/HOTKEYS.txt"))
hl.bind(mod .. " + O",           hl.dsp.exec_cmd("libreoffice"))
hl.bind(mod .. " + A",           hl.dsp.exec_cmd("arduino-ide"))
hl.bind(mod .. " + SHIFT + A",   hl.dsp.exec_cmd("kitty --class huilo-float --title huilo-arduino -e huilo-arduino menu"))
hl.bind(mod .. " + SHIFT + N",   hl.dsp.exec_cmd("kitty --class huilo-float --title huilo-nanopi -e huilo-nanopi menu"))
hl.bind(mod .. " + SHIFT + S",   hl.dsp.exec_cmd("grim -g \"$(slurp)\" - | swappy -f -"))
hl.bind("Print",                 hl.dsp.exec_cmd("grim - | wl-copy && notify-send 'Скриншот' 'Скопирован в буфер обмена'"))
hl.bind(mod .. " + Escape",      hl.dsp.exec_cmd("kitty --class huilo-float --title btop -e btop"))
hl.bind(mod .. " + BackSpace",   hl.dsp.exec_cmd("huilo-menu power"))
hl.bind(mod .. " + W",           hl.dsp.exec_cmd("huilo-wallpaper pick"))
hl.bind(mod .. " + SHIFT + W",   hl.dsp.exec_cmd("huilo-wallpaper next"))
hl.bind(mod .. " + SHIFT + M",   hl.dsp.exec_cmd("huilo-eq menu"))
hl.bind(mod .. " + ALT + M",     hl.dsp.exec_cmd("huilo-eq"))
hl.bind(mod .. " + SHIFT + L",   hl.dsp.exec_cmd("kitty --class huilo-float --title huilo-logwatch -e sh -c 'huilo-logwatch show; read -rp Enter _'"))

-- focus / move windows
for _, dir in ipairs({ "left", "right", "up", "down" }) do
    hl.bind(mod .. " + " .. dir,             hl.dsp.focus({ direction = dir }))
    hl.bind(mod .. " + SHIFT + " .. dir,     hl.dsp.window.move({ direction = dir }))
end

-- workspaces 1..10 (key 0 = workspace 10)
for i = 1, 10 do
    local key = i % 10
    hl.bind(mod .. " + " .. key,             hl.dsp.focus({ workspace = i }))
    hl.bind(mod .. " + SHIFT + " .. key,     hl.dsp.window.move({ workspace = i }))
end

-- scratchpad
hl.bind(mod .. " + S",           hl.dsp.workspace.toggle_special("magic"))
hl.bind(mod .. " + ALT + S",     hl.dsp.window.move({ workspace = "special:magic" }))

-- scroll through workspaces, move/resize with the mouse
hl.bind(mod .. " + mouse_down",  hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mod .. " + mouse_up",    hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mod .. " + mouse:272",   hl.dsp.window.drag(),   { mouse = true })
hl.bind(mod .. " + mouse:273",   hl.dsp.window.resize(), { mouse = true })

-- media keys: swayosd shows a pill with the level; wpctl/brightnessctl if it is not running
local function osd(args, fallback)
    return hl.dsp.exec_cmd("swayosd-client " .. args .. " || " .. fallback)
end
local rep = { locked = true, repeating = true }
hl.bind("XF86AudioRaiseVolume",  osd("--output-volume raise",       "wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+"), rep)
hl.bind("XF86AudioLowerVolume",  osd("--output-volume lower",       "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),        rep)
hl.bind("XF86AudioMute",         osd("--output-volume mute-toggle", "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),       { locked = true })
hl.bind("XF86AudioMicMute",      osd("--input-volume mute-toggle",  "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),     { locked = true })
hl.bind("XF86MonBrightnessUp",   osd("--brightness raise",          "brightnessctl s 10%+"),                             rep)
hl.bind("XF86MonBrightnessDown", osd("--brightness lower",          "brightnessctl s 10%-"),                             rep)
hl.bind("Caps_Lock",             hl.dsp.exec_cmd("swayosd-client --caps-lock"), { locked = true, release = true, non_consuming = true })
hl.bind("XF86AudioNext",         hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause",        hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",         hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",         hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

------------------------------------------------------------ user settings ---
-- ~/.config/hypr/user.lua is yours: monitors, extra binds, rules ...
-- It is loaded with pcall so a mistake there does not break this file.
local ok, err = pcall(require, "user")
if not ok and not tostring(err):find("not found", 1, true) then
    print("Huilo: error in user.lua: " .. tostring(err))
end
