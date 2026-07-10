local Invoker = require("invoker")
local ListScreen = require("list_screen")
local GridScreen = require("grid_screen")
local ConfirmDeleteScreen = require("confirm_delete_screen")
local ConfirmFindScreen = require("confirm_find_screen")
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
        --
        -- ここには「ファイルマネージャの永続的な状態」だけを置く。コマンド実行結果
        -- としての「データ準備に対する今回限りの指示」（再読み込みが必要か等）は
        -- stateに混ぜず、Invoker.runの戻り値（instruction）としてon_key/drawへ
        -- 明示的に受け渡す（詳細はprepare_dataを参照）
        { cwd = fs.cwd(), cursor = 1, show_hidden = true, search_query = "", all_files = {}, files = {} },
    },
    active_pane = 1,
    message = "",
}

local function current_pane(state)
    return state.panes[state.active_pane]
end

local list_screen = ListScreen.new()
local grid_screen = GridScreen.new()

-- 標準画面(一覧などの、割り込みが何もない時に表示する画面)
local default_screen = list_screen
-- push_screenで置かれた「次に見せたい割り込み画面」。select_screenが消費するまで保持する
local pushed_screen = nil
-- 今アクティブなスクリーンのインスタンス。select_screenでのみ更新する
local current_screen = default_screen

local function get_current_screen()
    return current_screen
end

local function push_screen(screen_instance)
    pushed_screen = screen_instance
end

local function get_default_screen()
    return default_screen
end

-- 標準画面自体を切り替える(一覧⇔2段組など、割り込みとは無関係な表示切り替えに使う)
local function set_default_screen(screen_instance)
    default_screen = screen_instance
end

-- pushed_screenがあればそれをcurrent_screenとして採用し(1回で消費する)、
-- なければdefault_screenを採用する。コマンドを実行した直後にのみ呼ぶこと
-- （何もコマンドが実行されていないのに呼ぶと、割り込み画面がpushed_screen消費済みの
-- まま誤ってdefault_screenに戻ってしまう）
local function select_screen()
    if pushed_screen then
        current_screen = pushed_screen
        pushed_screen = nil
    else
        current_screen = default_screen
    end
end

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- ディレクトリナビゲーション
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

local function load_dir(path)
    local list, err = fs.list(path)
    if err then
        return nil, err
    end
    table.sort(list, function(a, b)
        if a.is_dir ~= b.is_dir then return a.is_dir end
        return a.name < b.name
    end)
    table.insert(list, 1, { name = "..", is_dir = true, size = 0, modified = "", perm = "rwxr-xr-x" })
    return list
end

local function matches_search(name, search_query)
    if search_query == "" then
        return true
    end
    return name:lower():find(search_query:lower(), 1, true) ~= nil
end

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

local function refresh_files(pane)
    pane.files = build_visible_files(pane.all_files, pane.show_hidden, pane.search_query)
    if pane.cursor > #pane.files then
        pane.cursor = math.max(#pane.files, 1)
    end
end

local function find_index_by_name(list, name)
    for i, item in ipairs(list) do
        if item.name == name then
            return i
        end
    end
    return nil
end

-- pane.cwdの一覧をディスクから読み込み、pane.all_files/pane.filesを更新する。
-- 読み込みに失敗した場合はpane.cwdを変更せず維持し、一覧を空にした上で
-- state.messageにエラー内容を表示する。成功した場合はfallback_message
-- （省略時は空文字）をstate.messageにセットする。
--
-- ファイルシステムは他プロセスからも操作されうる外部の状態であり、この失敗は
-- 「ディレクトリ移動時」に限らず一覧の再取得が発生するあらゆるタイミングで
-- 起こりうる。専用のエラー画面や確認ダイアログは設けず、通常の一覧画面のまま
-- （一覧は空、フッターにメッセージ）で継続する。カレントディレクトリ自体が
-- 削除された場合も同様で、ユーザーが親ディレクトリへ移動する操作を繰り返せば、
-- いずれ生きているディレクトリに到達して自然に回復する
local function load_pane_files(pane, state, fallback_message)
    local list, err = load_dir(pane.cwd)
    if err then
        pane.all_files = {}
        state.message = "error: " .. err
    else
        pane.all_files = list
        state.message = fallback_message or ""
    end
    refresh_files(pane)
end

-- cwdをディスクから再読み込みしfilesを再構築する
-- （コマンド実行そのものではなく、view呼び出し直前の「データ準備」で行う）。
-- instruction.fallback_messageがあれば、再読み込みが成功した場合にstate.messageへ
-- 表示する（例えば削除コマンドが、rmの失敗理由をここで伝える。再読み込み自体が
-- 失敗した場合は、より実情を表すエラーが優先されるため使われない）。
-- instruction.cursor_nameがnilでなければ、再読み込み後のカーソル位置もここで決める
-- （falseなら先頭、文字列ならその名前の要素。詳細はprepare_dataのコメントを参照）
local function reload(pane, state, instruction)
    load_pane_files(pane, state, instruction.fallback_message)
    if instruction.cursor_name ~= nil then
        local cursor_name = instruction.cursor_name
        pane.cursor = (cursor_name and find_index_by_name(pane.files, cursor_name)) or 1
    end
end

-- データ準備: view呼び出し前に、コマンド実行結果を反映した表示用データを整える。
--
-- instructionは、直前に実行したコマンド（Invoker.run経由）の戻り値。コマンドが
-- 「データ準備に対して何をしてほしいか」を伝えるための、stateとは別の明示的な
-- 経路。stateは「ファイルマネージャの永続的な状態」の置き場所であり、そこに
-- コマンド実行結果としての一時的な指示を混ぜると、コマンドが増えるほどstateが
-- 何のためのフィールドか分からなくなっていくため、意図的に分離している。
--
-- 現状の指示は以下の通り（今後コマンドが増えるにつれ必要な範囲で拡張する）:
--   instruction.reload           trueならディレクトリを再読み込みする
--   instruction.cursor_name      再読み込み後にカーソルを合わせる要素名
--                                 （false/文字列/nilの意味はreloadを参照）
--   instruction.fallback_message 再読み込み成功時にstate.messageへ表示する文字列
local function prepare_data(state, instruction)
    if instruction and instruction.reload then
        reload(current_pane(state), state, instruction)
    end
end

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- コマンド定義
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

Commands.register({
    current_pane = current_pane,
    push_screen = push_screen,
    get_default_screen = get_default_screen,
    set_default_screen = set_default_screen,
    list_screen = list_screen,
    grid_screen = grid_screen,
    ConfirmDeleteScreen = ConfirmDeleteScreen,
    ConfirmFindScreen = ConfirmFindScreen,
})

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- コールバック
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

-- instruction: 直前に実行したコマンドの戻り値（Invoker.run参照）。データ準備に
-- 何を伝えるかはprepare_dataが解釈する。on_initからの呼び出しなど、直前に
-- コマンドを実行していない場合は省略してよい（nilとして扱われる）
local function draw(state, instruction)
    local width, height = screen.get_size()
    state.display.width = width
    state.display.height = height
    prepare_data(state, instruction)
    get_current_screen():view(state)
end

function on_init()
    load_pane_files(current_pane(app_state), app_state)
    draw(app_state)
end

function on_key(key)
    local command_name, args = get_current_screen():command_mapper(key)
    if command_name == "quit" then
        return false
    end
    local instruction = nil
    if command_name then
        instruction = Invoker.run(command_name, args, app_state)
        select_screen()
    end
    draw(app_state, instruction)
    return true
end
