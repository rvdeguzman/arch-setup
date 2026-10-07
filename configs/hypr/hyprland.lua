-- Standalone Hyprland >= 0.55 Lua configuration. No Omarchy sources.
-- API reference: installed /usr/share/hypr/hyprland.lua and matching wiki.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

hl.config({
    general = {
        gaps_in = 4, gaps_out = 8, border_size = 2, layout = "dwindle",
        col = { active_border = "rgb(c9a554)", inactive_border = "rgb(444444)" },
    },
    decoration = {
        rounding = 4,
        blur = { enabled = false },
        shadow = { enabled = false },
    },
    animations = { enabled = false },
    dwindle = { preserve_split = true },
    input = {
        kb_layout = "us", kb_options = "ctrl:nocaps",
        repeat_rate = 32, repeat_delay = 250,
        touchpad = { natural_scroll = true, scroll_factor = 0.4 },
    },
    misc = { disable_hyprland_logo = true, force_default_wallpaper = 0 },
})

local config_home = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
dofile(config_home .. "/hypr/host.lua")

hl.on("hyprland.start", function()
    -- This profile is launched through the UWSM session in Ly.
    hl.exec_cmd("uwsm finalize")
    for _, cmd in ipairs({
        "hypridle", "mako", "waybar",
        "/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1",
    }) do
        hl.exec_cmd("uwsm-app -- " .. cmd)
    end
    hl.exec_cmd("uwsm-app -- ghostty")
end)

local function launch(keys, command, description)
    hl.bind(keys, hl.dsp.exec_cmd("uwsm-app -- " .. command), { description = description })
end
launch("SUPER + Return", "ghostty", "Terminal")
launch("SUPER + SHIFT + Return", "ghostty -e tmux new-session", "Tmux")
launch("SUPER + D", "fuzzel", "Applications")
launch("SUPER + B", "brave", "Brave")
launch("SUPER + E", "emacs", "Emacs")
launch("SUPER + N", "ghostty -e nvim", "Neovim")
launch("SUPER + P", "sioyek", "Sioyek")
launch("SUPER + W", "ghostty -e impala", "Wi-Fi")
launch("SUPER + SHIFT + W", "ghostty -e bluetui", "Bluetooth")
launch("SUPER + A", "1password", "1Password")
hl.bind("SUPER + Q", hl.dsp.window.close())
hl.bind("SUPER + Space", hl.dsp.window.float({ action = "toggle" }))
hl.bind("SUPER + F", hl.dsp.window.fullscreen())
hl.bind("SUPER + S", hl.dsp.layout("togglesplit"))
hl.bind("SUPER + SHIFT + Escape", hl.dsp.exec_cmd("uwsm stop"))

-- Keep hjkl navigation; lock is SUPER+CTRL+L to avoid a conflict.
hl.bind("SUPER + CTRL + L", hl.dsp.exec_cmd("loginctl lock-session"))
for key, direction in pairs({ H = "left", J = "down", K = "up", L = "right" }) do
    hl.bind("SUPER + " .. key, hl.dsp.focus({ direction = direction }))
    hl.bind("SUPER + SHIFT + " .. key, hl.dsp.window.move({ direction = direction }))
end
for i = 1, 10 do
    local key = tostring(i % 10)
    hl.bind("SUPER + " .. key, hl.dsp.focus({ workspace = i }))
    hl.bind("SUPER + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })

local media = { locked = true, repeating = true }
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), media)
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), media)
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl set +5%"), media)
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl --min-value=1 set 5%-"), media)
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })
hl.bind("Print", hl.dsp.exec_cmd('selection=$(slurp) && grim -g "$selection" - | wl-copy'))
-- Keyboard backlight is not exposed through sysfs on the audited MiniBook.
-- Keep the firmware Fn shortcut; do not invent a software device binding.
