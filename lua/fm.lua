local layout = require("layout")
local template = require("template")

-- 状態
local dir = fs.cwd()
local files = {}
local cursor = 1

local COLUMNS = {
    m = { field = "files[].mark" },
    n = { field = "files[].name" },
    p = { field = "files[].perm" },
    s = { field = "files[].size", align = "right" },
    d = { field = "files[].modified" },
}

-- 幅width、タグ名keyの #key###...# 形式のタグ文字列を組み立てる
local function tag(key, width)
    return "#" .. key .. string.rep("#", width - #key - 1)
end

-- ファイル一覧を読み込む
local function load_dir(path)
    local list, err = fs.list(path)
    if err then
        return nil, err
    end
    -- ディレクトリを先に、その中でアルファベット順にソート
    table.sort(list, function(a, b)
        if a.is_dir ~= b.is_dir then return a.is_dir end
        return a.name < b.name
    end)
    -- 先頭に .. を追加
    table.insert(list, 1, { name = "..", is_dir = true, size = 0, modified = "", perm = "rwxr-xr-x" })
    return list
end

-- 画面描画
local function draw()
    local width, height = screen.get_size()
    local list_h = height - 2  -- ヘッダー1行 + フッター1行

    local tmpl = table.concat({
        " fm  {dir}",
        "@" .. tag("m", 2) .. " " .. tag("n", 40) .. "  " .. tag("p", 9) .. "  " .. tag("s", 8) .. "  " .. tag("d", 19),
        " j/down:↓  k/up:↑  enter:開く  q:終了",
    }, "\n")

    local vars = { dir = dir }
    for r = 0, list_h - 1 do
        local f = files[r + 1]
        local prefix = "files[" .. r .. "]."
        vars[prefix .. "mark"] = (f and r + 1 == cursor) and ">" or " "
        vars[prefix .. "name"] = f and (f.is_dir and (f.name .. "/") or f.name) or ""
        vars[prefix .. "perm"] = f and f.perm or ""
        vars[prefix .. "size"] = f and tostring(f.size) or ""
        vars[prefix .. "modified"] = f and f.modified or ""
    end

    screen.clear()
    local lines = layout.expand(tmpl, COLUMNS, width, height)
    for i, line in ipairs(lines) do
        screen.write(0, i - 1, template.render(line, vars))
    end
end

-- 初期化
function on_init()
    local list, err = load_dir(dir)
    if err then
        screen.clear()
        screen.write(0, 0, "error: " .. err)
        return
    end
    files = list
    draw()
end

-- キー処理
function on_key(key)
    if key == "q" or key == "escape" then
        return false
    end

    if key == "j" or key == "down" then
        if cursor < #files then
            cursor = cursor + 1
        end
        draw()

    elseif key == "k" or key == "up" then
        if cursor > 1 then
            cursor = cursor - 1
        end
        draw()

    elseif key == "enter" then
        local f = files[cursor]
        if f and f.is_dir then
            -- ディレクトリに移動
            local newdir
            if f.name == ".." then
                -- 親ディレクトリへ
                newdir = dir:match("^(.*)/[^/]+$") or "/"
            else
                newdir = dir .. "/" .. f.name
            end
            local list, err = load_dir(newdir)
            if not err then
                dir = newdir
                files = list
                cursor = 1
                draw()
            end
        end
    end

    return true
end