local layout = require("layout")
local template = require("template")
-- 文字列の表示幅を数える処理には必ずutf8widthを使うこと。#strのバイト長では、
-- 日本語などのマルチバイト文字や、macOSがNFD正規化する濁点付き仮名で幅がずれる
local utf8width = require("utf8width")

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- 状態
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

-- dirとファイル名の結合には必ずjoin_path()を使うこと。".."演算子で直接連結すると、
-- dirがルート"/"のときに"//"になる（過去に実際に発生した不具合）
local dir = fs.cwd()
local files = {}
local cursor = 1

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- ユーティリティ
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

-- nameの拡張子を返す。拡張子がない場合（.gitignoreのようなドットファイルを含む）はnilを返す
local function file_extension(name)
    local base, ext = name:match("^(.+)%.([^.]+)$")
    if base and base ~= "" then
        return ext
    end
    return nil
end

-- nameから拡張子を取り除いた部分を返す
local function strip_extension(name)
    local ext = file_extension(name)
    if not ext then
        return name
    end
    return name:sub(1, #name - #ext - 1)
end

-- nameの表示幅がmax_widthを超える場合、拡張子は残したまま手前を省略記号(…)に置き換える
local function truncate_name(name, max_width)
    if utf8width.width(name) <= max_width then
        return name
    end
    local ext = file_extension(name)
    if not ext then
        return utf8width.truncate(name, max_width)
    end
    local suffix = "." .. ext
    local base = strip_extension(name)
    local budget = math.max(max_width - utf8width.width(suffix), 0)
    return utf8width.truncate(base, budget) .. suffix
end

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- 画面描画
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

local NAME_WIDTH = 40

-- カーソル行の反転表示に使うエスケープシーケンス
local CURSOR_ON = "\27[7m"
local CURSOR_OFF = "\27[0m"

local COLUMNS = {
    n = { field = "files[].name", before = true },
    p = { field = "files[].perm" },
    s = { field = "files[].size", align = "right" },
    d = { field = "files[].modified", after = true },
}

-- 幅width、タグ名keyの #key###...# 形式のタグ文字列を組み立てる
local function tag(key, width)
    return "#" .. key .. string.rep("#", width - #key - 1)
end

local TMPL = table.concat({
    " fm  {dir}",
    "@" .. "   " .. tag("n", NAME_WIDTH) .. "  " .. tag("p", 9)
        .. "  " .. tag("s", 8) .. "  " .. tag("d", 19),
    " j/down:↓  k/up:↑  enter:開く  backspace:親へ  q:終了",
}, "\n")

-- カーソルが含まれるページの先頭インデックス(0始まり)を返す
local function page_offset(list_h)
    return math.floor((cursor - 1) / list_h) * list_h
end

-- ファイル一覧表示用に、切り詰め・ディレクトリの'/'付与を行った名前を返す
local function display_name(f)
    if f.is_dir then
        return truncate_name(f.name, NAME_WIDTH - 1) .. "/"
    end
    return truncate_name(f.name, NAME_WIDTH)
end

-- ファイル一覧をtemplate.render用の変数テーブルに変換する
local function build_vars(list_h)
    local offset = page_offset(list_h)
    local vars = { dir = dir }
    for r = 0, list_h - 1 do
        local index = offset + r + 1
        local f = files[index]
        local prefix = "files[" .. r .. "]."
        vars[prefix .. "name"] = f and display_name(f) or ""
        vars[prefix .. "perm"] = f and f.perm or ""
        vars[prefix .. "size"] = f and tostring(f.size) or ""
        vars[prefix .. "modified"] = f and f.modified or ""
        if f and index == cursor then
            vars[prefix .. "before"] = CURSOR_ON
            vars[prefix .. "after"] = CURSOR_OFF
        end
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
    local base = path:match("^(.*)/[^/]+$")
    if not base or base == "" then
        return "/"
    end
    return base
end

-- pathの末尾の要素名を返す
local function last_segment(path)
    return path:match("([^/]+)$")
end

-- dirとnameを結合したパスを返す。dirがルート"/"の場合に"//"にならないようにする
local function join_path(base, name)
    if base == "/" then
        return "/" .. name
    end
    return base .. "/" .. name
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

-- 親ディレクトリへ移動する。戻った後は元いた子ディレクトリの位置にカーソルを合わせる
local function go_to_parent()
    enter_directory(parent_dir(dir), last_segment(dir))
end

-- 拡張子ごとに開くコマンドを定義する。$C=拡張子ありファイル名、$X=拡張子なしファイル名、$P=カレントディレクトリのフルパス
-- 将来的にコンフィグファイルから読み込む想定で、事前にグローバルのOPENERSが定義されていればそれを使う
local OPENERS = _G.OPENERS or {
    zip = "unzip -l $P/$C | less",
    tar = "tar tvf $P/$C | less",
    gz = "tar tzvf $P/$C | less",
    md = "glow -p $P/$C",
}

-- シェルコマンドの引数として安全な形にpathをクォートする
-- fs.run()に渡す文字列にファイル名を組み込む際は、必ずこれを経由すること
-- （スペースや引用符を含むファイル名でコマンドが壊れる、または意図しないコマンド実行につながる）
local function shell_quote(path)
    return "'" .. path:gsub("'", "'\\''") .. "'"
end

-- cmd内の$C/$X/$Pを、シェルクォートしたvaluesの値に置き換える
local function expand_command(cmd, values)
    return (cmd:gsub("%$%a", function(token)
        local value = values[token]
        if not value then
            return token
        end
        return shell_quote(value)
    end))
end

-- pathがテキストファイルならtrue、バイナリファイルならfalseを返す
local function is_text_file(path)
    return fs.run("grep -Iq '' " .. shell_quote(path)) == 0
end

-- ファイルを開く。テキストファイルはlessで、バイナリファイルはダンプをlessで表示する
local function open_file(f)
    local quoted = shell_quote(join_path(dir, f.name))
    if f.size == 0 or is_text_file(join_path(dir, f.name)) then
        fs.run("less " .. quoted)
    else
        fs.run("xxd " .. quoted .. " | less")
    end
    draw()
end

-- 拡張子に対応するコマンドでファイルを開く
local function open_with_command(cmd_template, f)
    local values = { ["$C"] = f.name, ["$X"] = strip_extension(f.name), ["$P"] = dir }
    fs.run(expand_command(cmd_template, values))
    draw()
end

-- カーソル位置の要素を開く
local function open_selected()
    local f = files[cursor]
    if not f then
        return
    end
    if not f.is_dir then
        local cmd_template = OPENERS[file_extension(f.name)]
        if cmd_template then
            open_with_command(cmd_template, f)
        else
            open_file(f)
        end
    elseif f.name == ".." then
        go_to_parent()
    else
        enter_directory(join_path(dir, f.name), nil)
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
    elseif key == "backspace" then
        go_to_parent()
    end

    return true
end
