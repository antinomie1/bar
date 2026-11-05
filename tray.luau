-- tray.aegle shows one level of the menu at a time: a submenu opens in place
-- of its parent's entries, and the back entry returns. `tray_menu` holds the
-- whole menu flattened, each submenu's entries one deeper right after it;
-- this picks out one level as `tray_view`.
local path = {} -- ids of the submenus entered, outermost first

-- The entries directly in submenu `id` (the top level for nil), its label,
-- and whether it is still there.
local function level(entries, id)
    local out, title, depth, inside = {}, "", 0, id == nil
    for _, e in ipairs(entries) do
        if inside then
            if e.depth < depth then
                break -- past the submenu's last entry
            elseif e.depth == depth then
                table.insert(out, e)
            end
        elseif e.id == id then
            inside, depth, title = true, e.depth + 1, e.label
        end
    end
    return out, title, inside
end

-- Shows the innermost entered submenu that the menu still has: an
-- application may rebuild its menu while it is open.
local function show()
    local entries = state.tray_menu or {}
    while true do
        local items, title, found = level(entries, path[#path])
        if found then
            state.tray_view, state.tray_title, state.tray_nested = items, title, #path > 0
            return
        end
        table.remove(path)
    end
end

-- Whether `id` is an enabled entry of the shown level.
local function enabled(id)
    for _, e in ipairs(state.tray_view or {}) do
        if e.id == id then
            return e.enabled
        end
    end
    return false
end

function tray_enter(id)
    if enabled(id) then
        table.insert(path, id)
        show()
    end
end

-- Chooses an entry, which closes the menu.
function tray_pick(id)
    if enabled(id) then
        host.tray_select(id)
        host.close("tray.aegle")
    end
end

function tray_back()
    table.remove(path)
    show()
end

watch("tray_menu", show)
show()
