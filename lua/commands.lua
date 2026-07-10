local Invoker = require("invoker")
local config = require("config")

local Commands = {}

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

-- ctx（fm.luaが持つ関数への依存をまとめたテーブル）を受け取り、
-- Invoker.commandsにコマンドを登録する。
--
-- 状態テーブル(state)はここでは保持せず、Invoker.run経由で呼び出しのたびに
-- 引数として渡される。ctxが持つ関数もstateをクロージャで捕捉せず、
-- 引数として明示的に受け取る形にしてある
--
-- ctx:
--   current_pane       (state) -> 操作対象のペインを返す関数
--   refresh_files      (pane) -> pane.all_filesからpane.filesを再構築する関数
--   get_current_screen アクティブなスクリーンを返す関数
--   set_current_screen アクティブなスクリーンを切り替える関数
--   list_screen        ListScreenのインスタンス
--   grid_screen        GridScreenのインスタンス
--   ConfirmDeleteScreen ConfirmDeleteScreenモジュール
function Commands.register(ctx)
    -- 拡張子ごとに開くコマンドを定義する。$C=拡張子ありファイル名、$X=拡張子なしファイル名、$P=カレントディレクトリのフルパス
    -- config.load()が返す設定ファイル(またはその既定値)のassociationsセクションから読み込む
    local associations = config.load().associations

    -- newdirに移動する。cursor_nameが指定されていれば、その名前の要素にカーソルを合わせる。
    -- ファイル一覧の読み込み・カーソルの実際の配置はここでは行わず、戻り値の
    -- instructionを通じてdraw()のデータ準備に委ねる（詳細はfm.luaのprepare_dataを
    -- 参照）。cursor_nameのnilは「対象指定なし（読み込み後カーソルは先頭に置く）」を
    -- 意味するが、そのままinstruction.cursor_nameに入れると「カーソルには触れない」
    -- （削除コマンドのinstructionのように、cursor_nameキー自体を持たない場合）と
    -- 区別できなくなるため、falseに変換して保持する
    local function enter_directory(state, newdir, cursor_name)
        local pane = ctx.current_pane(state)
        pane.cwd = newdir
        pane.search_query = ""
        return { reload = true, cursor_name = cursor_name or false }
    end

    -- 親ディレクトリへ移動する。戻った後は元いた子ディレクトリの位置にカーソルを合わせる
    local function go_to_parent(state)
        local pane = ctx.current_pane(state)
        return enter_directory(state, parent_dir(pane.cwd), last_segment(pane.cwd))
    end

    Invoker.commands.cursor_down = function(_args, state)
        local pane = ctx.current_pane(state)
        if pane.cursor < #pane.files then
            pane.cursor = pane.cursor + 1
        end
    end

    Invoker.commands.cursor_up = function(_args, state)
        local pane = ctx.current_pane(state)
        if pane.cursor > 1 then
            pane.cursor = pane.cursor - 1
        end
    end

    Invoker.commands.go_to_parent = function(_args, state)
        return go_to_parent(state)
    end

    Invoker.commands.toggle_hidden = function(_args, state)
        local pane = ctx.current_pane(state)
        pane.show_hidden = not pane.show_hidden
        ctx.refresh_files(pane)
    end

    -- カーソル位置の要素の削除を確認するスクリーンに切り替える（".."は対象外）
    -- 呼び出し元のスクリーン(一覧/2段組)を渡し、下敷きの描画とy/n後の復帰先に使う
    Invoker.commands.confirm_delete = function(_args, state)
        local pane = ctx.current_pane(state)
        local f = pane.files[pane.cursor]
        if not f or f.name == ".." then
            return
        end
        ctx.set_current_screen(ctx.ConfirmDeleteScreen.new(f, ctx.get_current_screen()))
    end

    -- 確認ダイアログで"y"が押されたときに呼ばれる。実際の削除を実行する。
    -- rmの成否によらず常に再読み込みする（削除操作中にディレクトリごと消えている
    -- 場合など、一覧を現状に合わせて検証し直す必要があるため）。rmが失敗した場合の
    -- メッセージは、再読み込みが成功した場合（＝ディレクトリ自体は生きている）に
    -- 表示するフォールバックとしてinstructionに乗せる。再読み込み自体が失敗した
    -- 場合は、そのエラーの方が実情を表すため優先される
    Invoker.commands.delete = function(args, state)
        local pane = ctx.current_pane(state)
        local target = args.target
        local quoted = shell_quote(join_path(pane.cwd, target.name))
        local cmd = target.is_dir and ("rm -r " .. quoted) or ("rm " .. quoted)
        local instruction = { reload = true }
        if fs.run(cmd) ~= 0 then
            instruction.fallback_message = '"' .. target.name .. '" の削除に失敗しました'
        end
        ctx.set_current_screen(args.previous_screen)
        return instruction
    end

    -- 確認ダイアログで"n"/escapeが押されたときに呼ばれる。何もせず呼び出し元のスクリーンへ戻る
    Invoker.commands.cancel = function(args, _state)
        ctx.set_current_screen(args.previous_screen)
    end

    -- 検索文字列が確定した後に呼ばれる。ファイル一覧を絞り込む
    Invoker.commands.search = function(args, state)
        local pane = ctx.current_pane(state)
        pane.search_query = args.query or ""
        ctx.refresh_files(pane)
    end

    -- 一覧表示(1列)と2段組表示を切り替える
    Invoker.commands.toggle_layout = function(_args, _state)
        if ctx.get_current_screen() == ctx.list_screen then
            ctx.set_current_screen(ctx.grid_screen)
        else
            ctx.set_current_screen(ctx.list_screen)
        end
    end

    -- カーソル位置の要素を開く
    Invoker.commands.open_selected = function(_args, state)
        local pane = ctx.current_pane(state)
        local f = pane.files[pane.cursor]
        if not f then
            return
        end
        if not f.is_dir then
            local cmd_template = associations[file_extension(f.name)]
            if cmd_template then
                open_with_command(cmd_template, pane.cwd, f)
            else
                open_file(pane.cwd, f)
            end
        elseif f.name == ".." then
            return go_to_parent(state)
        else
            return enter_directory(state, join_path(pane.cwd, f.name), nil)
        end
    end
end

return Commands
