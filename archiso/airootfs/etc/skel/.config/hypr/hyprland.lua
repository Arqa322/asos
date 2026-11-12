-- ============================================================
--  ASOS — Hyprland configuration (Hyprland 0.57+, Lua)
--  Wiki: https://wiki.hypr.land/configuring/
--  Keys: SUPER+Enter terminal | SUPER+D launcher | SUPER+Q close
--        SUPER+E files | SUPER+Z zapret menu | SUPER+F1 cheat sheet
--        SUPER+A Arduino IDE | SUPER+Shift+A Arduino helper | SUPER+Shift+N NanoPi tools
--  Your own settings: ~/.config/hypr/user.lua (loaded at the end)
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
local menu        = "wofi --show drun"
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

--------------------------------------------------------------- autostart ---
hl.on("hyprland.start", function()
    hl.exec_cmd("waybar")
    hl.exec_cmd("mako")
    hl.exec_cmd("swaybg -c '#1e1e2e'")
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd("nm-applet --indicator")
    hl.exec_cmd("blueman-applet")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
    hl.exec_cmd("xdg-user-dirs-update")
    hl.exec_cmd("asos-welcome")
end)

------------------------------------------------------------- environment ---
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
        gaps_in  = 4,
        gaps_out = 8,
        border_size = 2,
        col = {
            active_border   = { colors = { "rgba(89b4faee)", "rgba(cba6f7ee)" }, angle = 45 },
            inactive_border = "rgba(45475aaa)",
        },
        resize_on_border = true,
        allow_tearing    = true,
        layout = "dwindle",
    },

    decoration = {
        rounding         = 8,
        active_opacity   = 1.0,
        inactive_opacity = 0.96,
        shadow = {
            enabled      = true,
            range        = 8,
            render_power = 3,
            color        = 0xee1a1a1a,
        },
        -- blur is expensive on virtual GPUs
        blur = {
            enabled  = not VM,
            size     = 5,
            passes   = 2,
            vibrancy = 0.17,
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
            ["tap-to-click"] = true,
        },
    },
})

hl.curve("ease",         { type = "bezier", points = { {0.25, 0.1}, {0.25, 1} } })
hl.curve("easeOutQuint", { type = "bezier", points = { {0.23, 1},   {0.32, 1} } })
hl.curve("almostLinear", { type = "bezier", points = { {0.5, 0.5},  {0.75, 1} } })

hl.animation({ leaf = "global",     enabled = true, speed = 8,   bezier = "default" })
hl.animation({ leaf = "windows",    enabled = true, speed = 4,   bezier = "ease",         style = "popin 85%" })
hl.animation({ leaf = "border",     enabled = true, speed = 8,   bezier = "easeOutQuint" })
hl.animation({ leaf = "fade",       enabled = true, speed = 4,   bezier = "almostLinear" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 4,   bezier = "ease",         style = "slide" })

------------------------------------------------------------ window rules ---
hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
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
hl.bind(mod .. " + C",           hl.dsp.exec_cmd("cliphist list | wofi --dmenu | cliphist decode | wl-copy"))
hl.bind(mod .. " + Z",           hl.dsp.exec_cmd("kitty --title asos-zapret -e asos-zapret menu"))
hl.bind(mod .. " + F1",          hl.dsp.exec_cmd("kitty --title asos-help -e less /usr/share/asos/HOTKEYS.txt"))
hl.bind(mod .. " + O",           hl.dsp.exec_cmd("libreoffice"))
hl.bind(mod .. " + A",           hl.dsp.exec_cmd("arduino-ide"))
hl.bind(mod .. " + SHIFT + A",   hl.dsp.exec_cmd("kitty --title asos-arduino -e asos-arduino menu"))
hl.bind(mod .. " + SHIFT + N",   hl.dsp.exec_cmd("kitty --title asos-nanopi -e asos-nanopi menu"))
hl.bind(mod .. " + SHIFT + S",   hl.dsp.exec_cmd("grim -g \"$(slurp)\" - | swappy -f -"))
hl.bind("Print",                 hl.dsp.exec_cmd("grim - | wl-copy && notify-send 'Скриншот' 'Скопирован в буфер обмена'"))
hl.bind(mod .. " + Escape",      hl.dsp.exec_cmd("kitty --title btop -e btop"))
hl.bind(mod .. " + BackSpace",   hl.dsp.exec_cmd("asos-power"))

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

-- media keys
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl s 10%+"),                           { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl s 10%-"),                           { locked = true, repeating = true })
hl.bind("XF86AudioNext",         hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause",        hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",         hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",         hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

------------------------------------------------------------ user settings ---
-- ~/.config/hypr/user.lua is yours: monitors, extra binds, rules ...
-- It is loaded with pcall so a mistake there does not break this file.
local ok, err = pcall(require, "user")
if not ok and not tostring(err):find("not found", 1, true) then
    print("ASOS: error in user.lua: " .. tostring(err))
end
