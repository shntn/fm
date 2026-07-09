local Invoker = require("invoker")
local ListScreen = require("list_screen")
local GridScreen = require("grid_screen")
local ConfirmDeleteScreen = require("confirm_delete_screen")
local Commands = require("commands")
local config = require("config")

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- 状態
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

-- cwdとファイル名の結合には必ずjoin_path()を使うこと。".."演算子で直接連結すると、
-- cwdがルート"/"のときに"//"になる（過去に実際に発生した不具合）
-- 現状は単一ペインのみ対応のため、panesの要素は常に1つ
local state = {
    display = { width = 0, height = 0 },
    panes = {
        -- all_files: fs.list()の結果に".."を加えた生の一覧
        -- files: all_filesにshow_hidden・search_queryのフィルタを適用した、実際に表示・操作する一覧
        { cwd = fs.cwd(), cursor = 1, show_hidden = true, search_query = "", all_files = {}, files = {} },
    },
    active_pane = 1,
    message = "",
}

-- 操作対象のペインを返す
local function current_pane()
    return state.panes[state.active_pane]
end

local list_screen = ListScreen.new()
local grid_screen = GridScreen.new()

-- 今アクティブなスクリーンのインスタンス
local current_screen = list_screen

local function get_current_screen()
    return current_screen
end

local function set_current_screen(screen_instance)
    current_screen = screen_instance
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

-- nameがsearch_queryを含むか判定する（大小文字を区別しない部分一致）。空文字は常にマッチする
local function matches_search(name, search_query)
    if search_query == "" then
        return true
    end
    return name:lower():find(search_query:lower(), 1, true) ~= nil
end

-- all_filesに、show_hidden・search_queryに応じた絞り込みを適用したものを返す
-- ".."はどちらのフィルタの対象にもせず、常に含める
local function build_visible_files(all_files, show_hidden, search_query)
    local filtered = {}
    for _, f in ipairs(all_files) do
        if f.name == ".." then
            table.insert(filtered, f)
        elseif (show_hidden or not f.name:match("^%.")) and matches_search(f.name, search_query) then
            table.insert(filtered, f)
        end
    end
    return filtered
end

-- ペインのall_filesからfilesを再構築し、カーソルが範囲外になっていれば補正する
local function refresh_files(pane)
    pane.files = build_visible_files(pane.all_files, pane.show_hidden, pane.search_query)
    if pane.cursor > #pane.files then
        pane.cursor = math.max(#pane.files, 1)
    end
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
    local pane = current_pane()
    pane.cwd = newdir
    pane.all_files = list
    pane.search_query = ""
    refresh_files(pane)
    pane.cursor = (cursor_name and find_index_by_name(pane.files, cursor_name)) or 1
end

-- 親ディレクトリへ移動する。戻った後は元いた子ディレクトリの位置にカーソルを合わせる
local function go_to_parent()
    local pane = current_pane()
    enter_directory(parent_dir(pane.cwd), last_segment(pane.cwd))
end

-- 拡張子ごとに開くコマンドを定義する。$C=拡張子ありファイル名、$X=拡張子なしファイル名、$P=カレントディレクトリのフルパス
-- config.load()が返す設定ファイル(またはその既定値)のassociationsセクションから読み込む
local ASSOCIATIONS = config.load().associations

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
local function open_file(cwd, f)
    local quoted = shell_quote(join_path(cwd, f.name))
    if f.size == 0 or is_text_file(join_path(cwd, f.name)) then
        fs.run("less " .. quoted)
    else
        fs.run("xxd " .. quoted .. " | less")
    end
end

-- 拡張子に対応するコマンドでファイルを開く
local function open_with_command(cmd_template, cwd, f)
    local values = { ["$C"] = f.name, ["$X"] = strip_extension(f.name), ["$P"] = cwd }
    fs.run(expand_command(cmd_template, values))
end

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- コマンド定義
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

Commands.register({
    state = state,
    current_pane = current_pane,
    refresh_files = refresh_files,
    enter_directory = enter_directory,
    go_to_parent = go_to_parent,
    join_path = join_path,
    shell_quote = shell_quote,
    open_file = open_file,
    open_with_command = open_with_command,
    file_extension = file_extension,
    ASSOCIATIONS = ASSOCIATIONS,
    get_current_screen = get_current_screen,
    set_current_screen = set_current_screen,
    list_screen = list_screen,
    grid_screen = grid_screen,
    ConfirmDeleteScreen = ConfirmDeleteScreen,
})

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- コールバック
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

-- 画面描画
local function draw()
    local width, height = screen.get_size()
    state.display.width = width
    state.display.height = height
    screen.clear()
    get_current_screen():view(state)
end

-- 初期化
function on_init()
    local pane = current_pane()
    local list, err = load_dir(pane.cwd)
    if err then
        screen.clear()
        screen.write(0, 0, "error: " .. err)
        return
    end
    pane.all_files = list
    refresh_files(pane)
    draw()
end

-- 直前のon_key呼び出しでterminal.request_line_inputを呼び、行入力の結果待ちかどうか
local awaiting_search = false

-- キー処理
function on_key(key)
    if awaiting_search then
        awaiting_search = false
        if key ~= "escape" then
            -- keyは1文字のキー名ではなく、確定した検索文字列そのもの
            Invoker.run("search", { query = key })
        end
        draw()
        return true
    end

    local command_name, args = get_current_screen():command_mapper(key)
    if command_name == "quit" then
        return false
    end
    if command_name == "search" then
        awaiting_search = true
        terminal.request_line_input(0, state.display.height - 1, state.display.width, "/")
        return true
    end
    if command_name then
        Invoker.run(command_name, args)
    end
    draw()
    return true
end
