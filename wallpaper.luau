-- The wallpaper and the bar's settings. This script runs as long as the bar
-- (bar.luau opens wallpaper.aegle), so it is the one writer of
-- ~/.config/bar/settings.json, and downloads finish even after the settings
-- panel closes. Its states reach every document declaring them:
--   wall_path, wall_thumb, wall_blur, wall_dir, wall_source  settings; search
--   words are not among them: they belong to the open settings panel
--   colors_from, glass, pastel_colors                       look
--   wall_scheme      colors sampled from the wallpaper (a Colors)
--   local_walls, online_walls, online_page, wall_status     settings panel
-- Actions: set_setting, set_number, pick_wallpaper, list_wallpapers, search_wallpapers,
-- random_wallpaper; `palettes msg random_wallpaper` from a keybinding.
local FILE = "~/.config/bar/settings.json"
local DEFAULTS = {
    wallpaper = "",
    blur = 0,
    dir = "~/Pictures/Wallpapers",
    source = "wallhaven",
    colors = "compositor",
    glass = 0.72,
    pastel = "keep", -- "follow": Pastel's colors follow the wallpaper too
}
local settings = {}
-- Each listed picture's thumbnail, by path.
local thumbs = {}

-- A shell word; `~/` stays the home directory.
local function q(s)
    if s:sub(1, 2) == "~/" then
        return '"$HOME"' .. q(s:sub(2))
    end
    return "'" .. (s:gsub("'", "'\\''")) .. "'"
end

local function encode(s)
    return (s:gsub("[^%w%-_%.~]", function(c)
        return string.format("%%%02X", c:byte())
    end))
end

-- Settings ------------------------------------------------------------------

local function publish()
    state.wall_path = settings.wallpaper
    -- The panel previews the thumbnail: the picture itself may be 8K.
    state.wall_thumb = thumbs[settings.wallpaper] or settings.wallpaper
    state.wall_blur = settings.blur
    state.wall_dir = settings.dir
    state.wall_source = settings.source
    state.colors_from = settings.colors
    state.pastel_colors = settings.pastel
    state.glass = settings.glass
end

-- Sliders change settings many times a second; write once they settle.
local saving
local function save()
    if saving then
        saving:stop()
    end
    saving = after(0.5, function()
        saving = nil
        local dir = FILE:match("^(.*)/")
        exec(`mkdir -p {q(dir)} && cat > {q(FILE)}.tmp <<'__SETTINGS__' && mv {q(FILE)}.tmp {q(FILE)}\n{json.encode(settings)}\n__SETTINGS__`)
    end)
end

-- Colors from the wallpaper -------------------------------------------------

local function mix(a, b, t)
    return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

local function hex(c)
    return string.format("#%02x%02x%02x", math.floor(c[1] + 0.5), math.floor(c[2] + 0.5), math.floor(c[3] + 0.5))
end

local function luma(c)
    return 0.2126 * c[1] + 0.7152 * c[2] + 0.0722 * c[3]
end

-- A dark background tinted by the picture's average, and its most vivid
-- color, brightened enough to read on it, as the accent.
local function scheme(pixels)
    local sum, accent, best = { 0, 0, 0 }, nil, -1
    for _, p in ipairs(pixels) do
        sum = { sum[1] + p[1], sum[2] + p[2], sum[3] + p[3] }
        local hi, lo = math.max(p[1], p[2], p[3]), math.min(p[1], p[2], p[3])
        local vivid = (hi - lo) * (0.4 + hi / 425)
        if vivid > best then
            accent, best = p, vivid
        end
    end
    local avg = { sum[1] / #pixels, sum[2] / #pixels, sum[3] / #pixels }
    local bg = mix(avg, { 0, 0, 0 }, 0.8)
    if best < 40 then -- grey pictures: a light grey accent
        accent = mix(avg, { 255, 255, 255 }, 0.6)
    end
    while luma(accent) < 130 do
        accent = mix(accent, { 255, 255, 255 }, 0.2)
    end
    return { background = hex(bg), active = hex(accent), inactive = hex(mix(bg, accent, 0.55)), shadow = "" }
end

-- Pastel's colors -------------------------------------------------------------

-- Sets $1, $2, $3 as Pastel's background, [window] active-color and
-- inactive-color: only the quoted values change, comments and the rest stay,
-- missing keys are added. Pastel reloads the file once it is written; it is
-- written into, not replaced, so a symlinked config keeps its link, and not
-- at all when nothing changed.
local PASTEL = [=[
f="${XDG_CONFIG_HOME:-$HOME/.config}/pastel/config.toml"
mkdir -p "${f%/*}" && { [ -e "$f" ] || : > "$f"; } || exit 1
t="$(mktemp)" || exit 1
awk -v dq='"' -v bg="$1" -v active="$2" -v inactive="$3" '
function set(line, value) { sub(/"[^"]*"/, dq value dq, line); return line }
function key(k) { return $0 ~ ("^[[:space:]]*" k "[[:space:]]*=") }
function rest() {
    if (section == "window") {
        if (!a) print "active-color = " dq active dq
        if (!i) print "inactive-color = " dq inactive dq
        a = i = 1
    }
}
/^[[:space:]]*\[/ {
    if (section == "" && !b) { print "background = " dq bg dq; b = 1 }
    rest()
    section = $0; sub(/#.*/, "", section); gsub(/[][[:space:]]/, "", section)
    if (section == "window") w = 1
    print; next
}
section == "" && key("background") { print set($0, bg); b = 1; next }
section == "window" && key("active-color") { print set($0, active); a = 1; next }
section == "window" && key("inactive-color") { print set($0, inactive); i = 1; next }
{ print }
END {
    if (section == "" && !b) print "background = " dq bg dq
    rest()
    if (!w) { print ""; print "[window]"; section = "window"; rest() }
}' "$f" > "$t" && { cmp -s "$t" "$f" || cat "$t" > "$f"; }
s=$?; rm -f "$t"; exit $s
]=]

local function sync_pastel()
    local s = state.wall_scheme
    if settings.pastel ~= "follow" or not s or (s.background or "") == "" then
        return
    end
    exec(`sh -c {q(PASTEL)} sh {q(s.background)} {q(s.active)} {q(s.inactive)}`, function(_, status)
        if status ~= 0 then
            state.wall_status = "could not write Pastel's config"
        end
    end)
end

local sampled
local function sample(path)
    if path == sampled then
        return
    end
    sampled = path
    if path == "" then
        state.wall_scheme = {}
        return
    end
    local cmd = `ffmpeg -v error -i {q(path)} -vf scale=8:6 -frames:v 1 -f rawvideo -pix_fmt rgb24 - | od -An -v -tu1`
    exec(cmd, function(out)
        if path ~= sampled then
            return
        end
        local bytes, pixels = {}, {}
        for n in out:gmatch("%d+") do
            table.insert(bytes, tonumber(n))
        end
        for i = 1, #bytes - 2, 3 do
            table.insert(pixels, { bytes[i], bytes[i + 1], bytes[i + 2] })
        end
        state.wall_scheme = #pixels > 0 and scheme(pixels) or {}
        sync_pastel()
    end)
end

function set_setting(key, value)
    if DEFAULTS[key] == nil or type(value) ~= type(DEFAULTS[key]) then
        return `unknown setting or wrong type: {key}`
    end
    settings[key] = value
    publish()
    save()
    if key == "pastel" then
        sync_pastel()
    elseif key == "wallpaper" then
        sample(value)
    end
end

-- Markup fixes an action's argument types by its name: numbers go here.
function set_number(key, value)
    return set_setting(key, value)
end

-- Local wallpapers ------------------------------------------------------------

-- Lists $1's pictures, newest first, each with a small cached thumbnail.
local LIST = [[
cache="$HOME/.cache/bar/thumbs"; mkdir -p "$cache"
find "$1" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
    -printf '%T@\t%p\n' 2>/dev/null | sort -rn | cut -f2- | while IFS= read -r f; do
    t="$cache/$(printf %s "$f" | md5sum | cut -c1-32).jpg"
    [ "$t" -nt "$f" ] || vipsthumbnail "$f" --size 340x192 -o "$t[Q=85]" 2>/dev/null \
        || ffmpeg -v error -y -i "$f" -vf scale=340:-1 -frames:v 1 "$t" 2>/dev/null
    printf '%s\t%s\n' "$f" "$t"
done
]]

local listing = 0
function list_wallpapers()
    listing += 1
    local run = listing
    exec(`sh -c {q(LIST)} sh {q(settings.dir)}`, function(out)
        if run ~= listing then
            return
        end
        local walls = {}
        for path, thumb in out:gmatch("([^\t\n]+)\t([^\n]+)") do
            thumbs[path] = thumb
            table.insert(walls, { key = path, thumb = thumb, url = path, label = "" })
        end
        state.local_walls = walls
        state.wall_thumb = thumbs[settings.wallpaper] or settings.wallpaper
        if #walls == 0 then
            state.wall_status = `no pictures in {settings.dir}`
        end
    end)
end

-- Online wallpapers -----------------------------------------------------------

-- Moebooru boards (Konachan, yande.re) share one API. They filter on the
-- server, so pages stay full: safe, and landscape from 4:3 to beyond 21:9
-- (yande.re is mostly portraits). `shuffles`: `order:random` works there;
-- yande.re's samples before it filters and returns few posts, or none.
local function moebooru(base, shuffles)
    return {
        shuffles = shuffles,
        url = function(tags, page, random)
            local all = `{tags} rating:safe ratio:1.3..{random and " order:random" or ""}`
            return `{base}/post.json?limit=24&page={page}&tags={encode(all)}`
        end,
        posts = function(data)
            local out = {}
            for _, p in ipairs(data) do
                table.insert(out, { id = p.id, preview = p.preview_url, full = p.jpeg_url, size = `{p.width}x{p.height}`, bytes = p.jpeg_file_size })
            end
            return out
        end,
    }
end

local SOURCES = {
    wallhaven = {
        shuffles = true,
        url = function(tags, page, random)
            local sorting = random and "random" or (tags == "" and "toplist" or "relevance")
            return `https://wallhaven.cc/api/v1/search?q={encode(tags)}&categories=110&purity=100&atleast=1920x1080&ratios=landscape&sorting={sorting}&page={page}`
        end,
        posts = function(data)
            local out = {}
            for _, p in ipairs(data.data or {}) do
                table.insert(out, { id = p.id, preview = p.thumbs.small, full = p.path, size = p.resolution, bytes = p.file_size })
            end
            return out
        end,
    },
    konachan = moebooru("https://konachan.net", true),
    yandere = moebooru("https://yande.re", false),
}

-- What a thumbnail's key stands for: a local path, or a post to download.
local online = {}

local function fetch(source, tags, page, random, done)
    local site = SOURCES[source]
    if not site then
        state.wall_status = `unknown source: {source}`
        return
    end
    state.wall_status = `searching {source}...`
    exec(`curl -fsSL -m 20 -A palettes-bar {q(site.url(tags, page, random))}`, function(out, status)
        local ok, data = pcall(json.decode, out)
        if status ~= 0 or not ok then
            state.wall_status = `{source}: request failed`
            return
        end
        done(site.posts(data))
    end)
end

local function mib(bytes)
    return string.format("%.1f", bytes / 1048576)
end

local function download(source, post)
    local ext = post.full:match("%.(%w+)$") or "jpg"
    local name = `{source}-{post.id}.{ext}`
    local total = (post.bytes or 0) > 0 and ` / {mib(post.bytes)}` or ""
    state.wall_status = `downloading {name} ({post.size})...`
    -- Some boards are slow; show how far it got while it runs.
    local progress = every(1, function()
        exec(`stat -c %s {q(`{settings.dir}/{name}.part`)} 2>/dev/null`, function(out)
            local got = tonumber(out)
            if got then
                state.wall_status = `downloading {name}: {mib(got)}{total} MiB`
            end
        end)
    end)
    -- Prints the file's absolute path, as the local list has it.
    local cmd = `d={q(settings.dir)} && mkdir -p "$d" && f="$(cd "$d" && pwd)"/{q(name)} && \{ [ -s "$f" ] || \{ curl -fsSL -m 600 --speed-limit 1024 --speed-time 30 -A palettes-bar -o "$f.part" {q(post.full)} && mv "$f.part" "$f"; }; } && printf %s "$f"`
    exec(cmd, function(dest, status)
        progress:stop()
        if status ~= 0 or dest == "" then
            state.wall_status = `download failed: {post.full}`
            return
        end
        state.wall_status = `saved {name}`
        set_setting("wallpaper", dest)
        list_wallpapers()
    end)
end

local searching = 0
function search_wallpapers(source, tags, page)
    source, tags, page = source or settings.source, tags or "", math.max(1, page or 1)
    if source ~= settings.source then
        set_setting("source", source)
    end
    searching += 1
    local run = searching
    state.online_page = page
    fetch(source, tags, page, false, function(posts)
        -- Previews download together, those already cached skipped.
        local cache, args, walls = "~/.cache/bar/previews", {}, {}
        for _, p in ipairs(posts) do
            local key = `{source}-{p.id}`
            local thumb = `{cache}/{key}.{p.preview:match("%.(%w+)$") or "jpg"}`
            online[key] = { source = source, post = p }
            table.insert(args, `-o {q(thumb)} {q(p.preview)}`)
            table.insert(walls, { key = key, thumb = thumb, url = p.full, label = p.size })
        end
        if #walls == 0 then
            state.online_walls, state.wall_status = {}, `{source}: nothing found`
            return
        end
        local cmd = `mkdir -p {q(cache)} && curl -sL -m 30 -A palettes-bar --parallel --parallel-max 8 {table.concat(args, " ")}`
        exec(cmd, function()
            if run == searching then
                state.online_walls, state.wall_status = walls, `{source}: page {page}`
            end
        end)
    end)
end

function random_wallpaper(source, tags)
    source, tags = source or settings.source, tags or ""
    local function pick(posts)
        if #posts == 0 then
            state.wall_status = `{source}: nothing found`
            return
        end
        download(source, posts[math.random(#posts)])
    end
    -- Where the site can't shuffle, a random page of its usual order; the
    -- first when the tags have fewer pages than that.
    local shuffles = (SOURCES[source] or {}).shuffles
    local page = shuffles and 1 or math.random(20)
    fetch(source, tags, page, shuffles, function(posts)
        if #posts == 0 and page > 1 then
            fetch(source, tags, 1, false, pick)
        else
            pick(posts)
        end
    end)
end

-- A thumbnail clicked in the settings panel.
function pick_wallpaper(key)
    local post = online[key]
    if post then
        download(post.source, post.post)
    else
        set_setting("wallpaper", key)
    end
end

-- Start -----------------------------------------------------------------------

math.randomseed(os.time())

local ok, saved = pcall(json.decode, read(FILE) or "{}")
for key, value in DEFAULTS do
    local v = ok and type(saved) == "table" and saved[key]
    settings[key] = type(v) == type(value) and v or value
end
publish()
sample(settings.wallpaper)
