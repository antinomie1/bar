-- The panel's lists fill as it opens; wallpaper.luau does the work. The
-- online search starts afresh, as its words are not kept.
state.online_walls = {}
state.wall_status = ""
host.list_wallpapers()

watch("page", function(page)
    if page == "online" and #(state.online_walls or {}) == 0 then
        host.search_wallpapers(state.wall_source, "", 1)
    end
end)
