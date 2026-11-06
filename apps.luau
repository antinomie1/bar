-- apps.aegle's list. Applications started from it come first, the latest
-- first (kept in ~/.local/state/bar/apps.json), then the rest by name. A
-- search keeps those that have every word typed in their name or desktop
-- id, case ignored: names starting with the first word, then names with a
-- word starting so, then the rest, each in the order above. The arrows move
-- the selection through the grid; Enter starts it.
local FILE = "~/.local/state/bar/apps.json"
-- Tiles per row: apps.aegle's 616 dp inside its padding, 112 dp tiles 8 dp apart.
local COLUMNS = 5

local query = {}
local found = {} -- the matching applications, in order
local selected = 1
-- Desktop ids, the latest started first.
local history = json.decode(read(FILE) or "[]") or {}

-- A shell word; `~/` stays the home directory.
local function q(s)
    if s:sub(1, 2) == "~/" then
        return '"$HOME"' .. q(s:sub(2))
    end
    return "'" .. (s:gsub("'", "'\\''")) .. "'"
end

-- How well `app` matches: 0 for not at all, 3 best.
local function rank(app)
    local name, id = app.name:lower(), app.id:lower()
    for _, word in query do
        if not name:find(word, 1, true) and not id:find(word, 1, true) then
            return 0
        end
    end
    local first = query[1]
    if not first or name:sub(1, #first) == first then
        return 3
    end
    return name:find("[%s%-_.]" .. first:gsub("%p", "%%%0")) and 2 or 1
end

local function publish()
    local view = {}
    for i, app in found do
        -- Entries whose icon is nowhere installed get a generic one.
        local icon = app.icon ~= "" and app.icon or "application-x-executable"
        view[i] = { id = app.id, name = app.name, icon = icon, selected = i == selected }
    end
    state.app_view = view
    state.app_count = tostring(#view)
end

local function search()
    local recent = {}
    for i, id in history do
        recent[id] = i
    end
    local matches = {}
    for i, app in state.applications or {} do
        local r = rank(app)
        if r > 0 then
            -- `applications` comes sorted by name.
            table.insert(matches, { app = app, rank = r, recent = recent[app.id] or math.huge, order = i })
        end
    end
    table.sort(matches, function(a, b)
        if a.rank ~= b.rank then
            return a.rank > b.rank
        elseif a.recent ~= b.recent then
            return a.recent < b.recent
        end
        return a.order < b.order
    end)
    found = {}
    for i, m in matches do
        found[i] = m.app
    end
    selected = 1
    publish()
end

function search_apps(text)
    query = {}
    for word in text:lower():gmatch("%S+") do
        table.insert(query, word)
    end
    search()
end

-- Moves the selection by an arrow key's name, staying in the grid.
function move_app(key)
    local n, to = #found, selected
    if key == "Left" then
        to -= 1
    elseif key == "Right" then
        to += 1
    elseif key == "Up" then
        to -= COLUMNS
    elseif key == "Down" then
        -- Into the last row, which may be short, from the column above its end.
        local row = (selected - 1) // COLUMNS
        if row < (n - 1) // COLUMNS then
            to = math.min(selected + COLUMNS, n)
        end
    end
    if to >= 1 and to <= n and to ~= selected then
        selected = to
        publish()
    end
end

-- Starts `id`, moves it to the front of the history, and closes once that
-- is written: closing stops the script's commands.
function launch_app(id)
    host.launch(id)
    local kept = { id }
    for _, old in history do
        if old ~= id then
            table.insert(kept, old)
        end
    end
    history = kept
    local dir = FILE:match("^(.*)/")
    exec(`mkdir -p {q(dir)} && cat > {q(FILE)}.tmp <<'__APPS__' && mv {q(FILE)}.tmp {q(FILE)}\n{json.encode(history)}\n__APPS__`,
        function()
            host.close("apps.aegle")
        end)
end

function launch_selected()
    local app = found[selected]
    if app then
        launch_app(app.id)
    end
end

watch("applications", search)
-- The panel fills `applications` after this runs, without a change to watch.
after(0.01, search)
