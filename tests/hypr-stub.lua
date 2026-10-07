-- Evaluate configuration without Hyprland, input/display changes, or processes.
local monitors, binds = {}, {}
local api = setmetatable({}, {
    __index = function(_, key)
        if key == "window" then return setmetatable({}, { __index = function() return function(...) return {...} end end }) end
        return function(...) return {...} end
    end,
})
hl = {
    dsp = api,
    monitor = function(spec) table.insert(monitors, spec) end,
    env = function() end,
    config = function() end,
    on = function(event, callback)
        assert(event == "hyprland.start")
        assert(type(callback) == "function")
        -- Never invoke startup callbacks in tests.
    end,
    exec_cmd = function() error("Unexpected application launch in test") end,
    bind = function(key, _, flags)
        assert(not binds[key], "Duplicate key: " .. key)
        binds[key] = flags or {}
    end,
}
dofile(arg[1])
assert(#monitors == 2)
assert(monitors[1].output == "" and monitors[1].scale == 1)
assert(monitors[2].output == "DSI-1" and monitors[2].transform == 3)
assert(monitors[2].mode == "preferred")
assert(binds["SUPER + B"] and binds["SUPER + A"])
assert(binds["SUPER + CTRL + L"] and binds["SUPER + L"])
assert(binds["XF86MonBrightnessUp"].locked)
