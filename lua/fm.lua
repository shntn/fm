local Invoker = require("invoker")
local ListScreen = require("list_screen")
local GridScreen = require("grid_screen")
local ConfirmDeleteScreen = require("confirm_delete_screen")
local Commands = require("commands")

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- 状態
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

-- 現状は単一ペインのみ対応のため、panesの要素は常に1つ
--
-- この変数自体はモジュールローカルだが、on_init/on_key以外の関数には
-- クロージャで暗黙に渡さず、必ず引数stateとして明示的に渡すこと
local app_state = {
    display = { width = 0, height = 0 },
    panes = {
        -- all_files: fs.list()の結果に".."を加えた生の一覧
        -- files: all_filesにshow_hidden・search_queryのフィルタを適用した、実際に表示・操作する一覧
        -- needs_reload: trueならdraw()のデータ準備でall_filesを再読み込みする
        --   （削除コマンドなど、コマンド実行の副作用でディレクトリの中身が変わった場合に立てる）
        {
            cwd = fs.cwd(), cursor = 1, show_hidden = true, search_query = "",
            all_files = {}, files = {}, needs_reload = false,
        },
    },
    active_pane = 1,
    message = "",
}

-- 操作対象のペインを返す
local function current_pane(state)
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

-- pane.needs_reloadが立っていれば、cwdをディスクから再読み込みしfilesを再構築する
-- （コマンド実行そのものではなく、view呼び出し直前の「データ準備」で行う）
local function reload_if_needed(pane)
    if not pane.needs_reload then
        return
    end
    local list, err = load_dir(pane.cwd)
    if err then
        return
    end
    pane.all_files = list
    pane.needs_reload = false
    refresh_files(pane)
end

-- データ準備: view呼び出し前に、コマンド実行結果を反映した表示用データを整える
-- （現状はneeds_reloadに応じた再読み込みのみだが、今後ここに追加していく）
local function prepare_data(state)
    reload_if_needed(current_pane(state))
end

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- コマンド定義
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

Commands.register({
    current_pane = current_pane,
    refresh_files = refresh_files,
    load_dir = load_dir,
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
local function draw(state)
    local width, height = screen.get_size()
    state.display.width = width
    state.display.height = height
    prepare_data(state)
    screen.clear()
    get_current_screen():view(state)
end

-- 初期化
function on_init()
    local pane = current_pane(app_state)
    local list, err = load_dir(pane.cwd)
    if err then
        screen.clear()
        screen.write(0, 0, "error: " .. err)
        return
    end
    pane.all_files = list
    refresh_files(pane)
    draw(app_state)
end

-- 直前のon_key呼び出しでterminal.request_line_inputを呼び、行入力の結果待ちかどうか
local awaiting_search = false

-- キー処理
function on_key(key)
    if awaiting_search then
        awaiting_search = false
        if key ~= "escape" then
            -- keyは1文字のキー名ではなく、確定した検索文字列そのもの
            Invoker.run("search", { query = key }, app_state)
        end
        draw(app_state)
        return true
    end

    local command_name, args = get_current_screen():command_mapper(key)
    if command_name == "quit" then
        return false
    end
    if command_name == "search" then
        awaiting_search = true
        terminal.request_line_input(0, app_state.display.height - 1, app_state.display.width, "/")
        return true
    end
    if command_name then
        Invoker.run(command_name, args, app_state)
    end
    draw(app_state)
    return true
end
