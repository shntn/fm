local layout = require("layout")
local template = require("template")

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- 状態
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

local dir = fs.cwd()
local files = {}
local cursor = 1

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- 画面描画
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

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

local TMPL = table.concat({
    " fm  {dir}",
    "@" .. tag("m", 2) .. " " .. tag("n", 40) .. "  " .. tag("p", 9) .. "  " .. tag("s", 8) .. "  " .. tag("d", 19),
    " j/down:↓  k/up:↑  enter:開く  q:終了",
}, "\n")

-- カーソルが含まれるページの先頭インデックス(0始まり)を返す
local function page_offset(list_h)
    return math.floor((cursor - 1) / list_h) * list_h
end

-- ファイル一覧をtemplate.render用の変数テーブルに変換する
local function build_vars(list_h)
    local offset = page_offset(list_h)
    local vars = { dir = dir }
    for r = 0, list_h - 1 do
        local index = offset + r + 1
        local f = files[index]
        local prefix = "files[" .. r .. "]."
        vars[prefix .. "mark"] = (f and index == cursor) and ">" or " "
        vars[prefix .. "name"] = f and (f.is_dir and (f.name .. "/") or f.name) or ""
        vars[prefix .. "perm"] = f and f.perm or ""
        vars[prefix .. "size"] = f and tostring(f.size) or ""
        vars[prefix .. "modified"] = f and f.modified or ""
    end
    return vars
end

-- 行テンプレートの配列を、変数を展開して画面に書き込む
local function render_lines(lines, vars)
    for i, line in ipairs(lines) do
        screen.write(0, i - 1, template.render(line, vars))
    end
end

-- 画面描画
local function draw()
    local width, height = screen.get_size()
    local list_h = height - 2  -- ヘッダー1行 + フッター1行

    local vars = build_vars(list_h)
    local lines = layout.expand(TMPL, COLUMNS, width, height)

    screen.clear()
    render_lines(lines, vars)
end

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- ディレクトリナビゲーション
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

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

-- カーソルを1行下に移動する
local function move_cursor_down()
    if cursor < #files then
        cursor = cursor + 1
    end
    draw()
end

-- カーソルを1行上に移動する
local function move_cursor_up()
    if cursor > 1 then
        cursor = cursor - 1
    end
    draw()
end

-- リストの中からnameと一致する要素のインデックスを探す
local function find_index_by_name(list, name)
    for i, item in ipairs(list) do
        if item.name == name then
            return i
        end
    end
    return nil
end

-- pathの親ディレクトリのパスを返す
local function parent_dir(path)
    return path:match("^(.*)/[^/]+$") or "/"
end

-- pathの末尾の要素名を返す
local function last_segment(path)
    return path:match("([^/]+)$")
end

-- newdirに移動する。cursor_nameが指定されていれば、その名前の要素にカーソルを合わせる
local function enter_directory(newdir, cursor_name)
    local list, err = load_dir(newdir)
    if err then
        return
    end
    dir = newdir
    files = list
    cursor = (cursor_name and find_index_by_name(files, cursor_name)) or 1
    draw()
end

-- カーソル位置の要素を開く
local function open_selected()
    local f = files[cursor]
    if not f or not f.is_dir then
        return
    end
    if f.name == ".." then
        -- 親ディレクトリへ。戻った後は元いた子ディレクトリの位置にカーソルを合わせる
        enter_directory(parent_dir(dir), last_segment(dir))
    else
        enter_directory(dir .. "/" .. f.name, nil)
    end
end

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- コールバック
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

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
        move_cursor_down()
    elseif key == "k" or key == "up" then
        move_cursor_up()
    elseif key == "enter" then
        open_selected()
    end

    return true
end
