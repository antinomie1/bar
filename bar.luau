-- Colors follow Pastel through IPC (`compositor_colors`), live on every config
-- save, or the wallpaper (`wall_scheme`), as the settings choose, and become
-- the palette tokens the bar and its popups paint with:
--   palette.1  normbg: the background, `glass` opaque over the blur
--   palette.2  normfg: text on it
--   palette.3  selbg:  [window] active-color
--   palette.4  selfg:  text on the accent
--   palette.5  dimmed text: [window] inactive-color, lifted to be readable
-- Pastel's defaults, for other compositors (they report no colors).
local DEFAULTS = { background = "#1e2028", active = "#a6c8ff", inactive = "#4a4f5c" }

local function rgb(text)
    local h = text and text:match("^#(%x+)$")
    if not h or (#h ~= 6 and #h ~= 8) then
        return nil
    end
    return { tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16) }
end

local function hex(c, alpha)
    return string.format("#%02x%02x%02x%02x", c[1], c[2], c[3], math.floor((alpha or 1) * 255 + 0.5))
end

local function mix(a, b, t)
    local out = {}
    for i = 1, 3 do
        out[i] = math.floor(a[i] + (b[i] - a[i]) * t + 0.5)
    end
    return out
end

-- Readable text on `c`, tinted by it.
local function on(c)
    local light = 0.2126 * c[1] + 0.7152 * c[2] + 0.0722 * c[3] > 140
    return mix(c, light and { 0, 0, 0 } or { 255, 255, 255 }, 0.85)
end

local function colors(c)
    c = c or {}
    local function pick(key)
        return rgb(c[key]) or rgb(DEFAULTS[key])
    end
    local bg, active, inactive = pick("background"), pick("active"), pick("inactive")
    local fg = on(bg)
    palette({ hex(bg, state.glass or 0.72), hex(fg), hex(active), hex(on(active)), hex(mix(inactive, fg, 0.45)) })
end

-- Labels markup can't build without conditionals.
local function network(n)
    n = n or {}
    -- Dimmed without full connectivity.
    state.net_off = not n.connected
    if n.kind == "wifi" then
        state.net_name, state.net_label = "wifi", `{n.name} {n.strength}%`
    elseif n.kind and n.kind ~= "" then
        state.net_name, state.net_label = n.kind == "ethernet" and "eth" or n.kind, n.name ~= "" and n.name or "up"
    elseif n.wifi_available and not n.wifi then
        state.net_name, state.net_label = "wifi", "off"
    else
        state.net_name, state.net_label = "net", "down"
    end
end

-- dwm's layout symbol, from the shown workspace's layout as the compositor
-- reports it: Pastel's scrolling columns show which of how many has the
-- focus, as dwm's monocle shows its count.
--   [2/5]  second of five columns    [M]  the column fills the screen
--   [><>]  a floating window         [ ]  no windows
--   [name] a layout it doesn't know  [?] the compositor doesn't say
local function layout()
    local shown
    for _, ws in ipairs(state.output_workspaces or {}) do
        if ws.active then
            shown = ws
            break
        end
    end
    local window = state.output_window or {}
    if not shown or shown.layout == "" then
        state.layout_symbol = "[?]"
    elseif window.id ~= 0 and window.floating then
        -- Bracketed like the rest: bare, its low glyphs look smaller.
        state.layout_symbol = "[><>]"
    elseif shown.layout ~= "scrolling" then
        state.layout_symbol = `[{shown.layout}]`
    elseif shown.column == 0 then
        state.layout_symbol = "[ ]"
    elseif shown.maximized then
        state.layout_symbol = "[M]"
    else
        state.layout_symbol = `[{shown.column}/{shown.columns}]`
    end
end

local function sound()
    state.vol_label = state.muted and "mute" or `{math.floor((state.volume or 0) * 100 + 0.5)}%`
end

local function bluetooth()
    local adapter = state.bluetooth or {}
    if not adapter.powered then
        state.bt_label = "off"
        return
    end
    local first = (state.bluetooth_devices or {})[1]
    state.bt_label = first and first.connected and first.name or "on"
end

-- The scheme the settings pick; Pastel's until the wallpaper's is sampled.
local function scheme()
    local wall = state.wall_scheme
    local c = state.colors_from == "wallpaper" and wall and wall.background ~= "" and wall or state.compositor_colors
    colors(c)
end

-- The wallpaper and the settings it keeps (wallpaper.luau); opened once the
-- bar is, since documents can't open while one is loading.
after(0.01, function()
    host.open("wallpaper.aegle")
end)

for _, name in { "compositor_colors", "wall_scheme", "colors_from", "glass" } do
    watch(name, scheme)
end
watch("output_workspaces", layout)
watch("output_window", layout)
watch("network", network)
watch("volume", sound)
watch("muted", sound)
watch("bluetooth", bluetooth)
watch("bluetooth_devices", bluetooth)
scheme()
layout()
network(state.network)
sound()
bluetooth()
