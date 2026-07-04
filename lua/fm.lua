-- 状態
local dir = fs.cwd()
local files = {}
local cursor = 1

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
    local _, h = screen.get_size()
    local list_h = h - 2  -- ヘッダー1行 + フッター1行

    screen.clear()

    -- ヘッダー
    local header = "fm  " .. dir
    screen.write(0, 0, header)

    -- ファイル一覧
    for i, f in ipairs(files) do
        if i > list_h then break end
        local name = f.name
        if f.is_dir then name = name .. "/" end
        local line = string.format("%-40s %s %8d  %s",
            name, f.perm, f.size, f.modified)
        if i == cursor then
            -- カーソル行は > でマーク
            screen.write(0, i, "> " .. line)
        else
            screen.write(0, i, "  " .. line)
        end
    end

    -- フッター
    screen.write(0, h - 1, "j/down:↓  k/up:↑  enter:開く  q:終了")
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