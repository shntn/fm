local Invoker = require("invoker")

local Commands = {}

-- ctx（fm.luaが持つ状態・関数への依存をまとめたテーブル）を受け取り、
-- Invoker.commandsにコマンドを登録する。
--
-- ctx:
--   state              状態テーブル(state.message書き換え用)
--   current_pane       操作対象のペインを返す関数
--   refresh_files      pane.all_filesからpane.filesを再構築する関数
--   enter_directory    ディレクトリ移動関数
--   go_to_parent       親ディレクトリへ移動する関数
--   join_path          パス結合関数
--   shell_quote        シェルクォート関数
--   open_file          デフォルトのファイルを開く関数
--   open_with_command  拡張子対応コマンドでファイルを開く関数
--   file_extension     拡張子取得関数
--   ASSOCIATIONS       拡張子ごとのコマンド定義
--   get_current_screen アクティブなスクリーンを返す関数
--   set_current_screen アクティブなスクリーンを切り替える関数
--   list_screen        ListScreenのインスタンス
--   grid_screen        GridScreenのインスタンス
--   ConfirmDeleteScreen ConfirmDeleteScreenモジュール
function Commands.register(ctx)
    Invoker.commands.cursor_down = function()
        local pane = ctx.current_pane()
        if pane.cursor < #pane.files then
            pane.cursor = pane.cursor + 1
        end
    end

    Invoker.commands.cursor_up = function()
        local pane = ctx.current_pane()
        if pane.cursor > 1 then
            pane.cursor = pane.cursor - 1
        end
    end

    Invoker.commands.go_to_parent = function()
        ctx.go_to_parent()
    end

    Invoker.commands.toggle_hidden = function()
        local pane = ctx.current_pane()
        pane.show_hidden = not pane.show_hidden
        ctx.refresh_files(pane)
    end

    -- カーソル位置の要素の削除を確認するスクリーンに切り替える（".."は対象外）
    -- 呼び出し元のスクリーン(一覧/2段組)を渡し、下敷きの描画とy/n後の復帰先に使う
    Invoker.commands.confirm_delete = function()
        local pane = ctx.current_pane()
        local f = pane.files[pane.cursor]
        if not f or f.name == ".." then
            return
        end
        ctx.set_current_screen(ctx.ConfirmDeleteScreen.new(f, ctx.get_current_screen()))
    end

    -- 確認ダイアログで"y"が押されたときに呼ばれる。実際の削除を実行する
    Invoker.commands.delete = function(args)
        local pane = ctx.current_pane()
        local target = args.target
        local quoted = ctx.shell_quote(ctx.join_path(pane.cwd, target.name))
        local cmd = target.is_dir and ("rm -r " .. quoted) or ("rm " .. quoted)
        if fs.run(cmd) == 0 then
            ctx.state.message = ""
            ctx.enter_directory(pane.cwd, nil)
        else
            ctx.state.message = '"' .. target.name .. '" の削除に失敗しました'
        end
        ctx.set_current_screen(args.previous_screen)
    end

    -- 確認ダイアログで"n"/escapeが押されたときに呼ばれる。何もせず呼び出し元のスクリーンへ戻る
    Invoker.commands.cancel = function(args)
        ctx.set_current_screen(args.previous_screen)
    end

    -- 検索文字列が確定した後に呼ばれる。ファイル一覧を絞り込む
    Invoker.commands.search = function(args)
        local pane = ctx.current_pane()
        pane.search_query = args.query or ""
        ctx.refresh_files(pane)
    end

    -- 一覧表示(1列)と2段組表示を切り替える
    Invoker.commands.toggle_layout = function()
        if ctx.get_current_screen() == ctx.list_screen then
            ctx.set_current_screen(ctx.grid_screen)
        else
            ctx.set_current_screen(ctx.list_screen)
        end
    end

    -- カーソル位置の要素を開く
    Invoker.commands.open_selected = function()
        local pane = ctx.current_pane()
        local f = pane.files[pane.cursor]
        if not f then
            return
        end
        if not f.is_dir then
            local cmd_template = ctx.ASSOCIATIONS[ctx.file_extension(f.name)]
            if cmd_template then
                ctx.open_with_command(cmd_template, pane.cwd, f)
            else
                ctx.open_file(pane.cwd, f)
            end
        elseif f.name == ".." then
            ctx.go_to_parent()
        else
            ctx.enter_directory(ctx.join_path(pane.cwd, f.name), nil)
        end
    end
end

return Commands
