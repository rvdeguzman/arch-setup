-- N100 MiniBook X: native portrait DSI panel, rotated into landscape.
-- Explicit output matching avoids rotating external displays.
hl.monitor({
    output = "DSI-1", mode = "preferred", position = "auto",
    scale = 1.67, transform = 3, bitdepth = 8,
})
hl.config({ input = { touchdevice = { transform = 3, output = "DSI-1" } } })
-- Scale is a preference; test fractional scaling on the installed version.
