-- Deliberately broken config: scripts/check-hyprland-config.py must reject it.
-- Each line below is one kind of mistake the checker has to catch.
hl.config({
    general = { gaps_inn = 4 },                       -- unknown option
    decoration = { rounding = "8" },                  -- Int given a string
    cursor = { no_hardware_cursors = true },          -- Int given a boolean
    misc = { vfr = true },                            -- option removed (now debug:vfr)
})
hl.on("hyprland.started", function() end)            -- unknown event
hl.bind("SUPER + Q", hl.dsp.window.closee())          -- unknown dispatcher
