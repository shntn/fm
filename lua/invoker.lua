-- インボーカー: コマンドマッパーが決定したコマンド名を受け取り、実際に実行する統一入口
local Invoker = {}

-- コマンド名 → 実行関数 のテーブル。呼び出し側(スクリーンなど)がここに登録する
Invoker.commands = {}

-- コマンド名が示す実行関数を呼ぶ。未登録のコマンド名の場合は何もせずnilを返す
function Invoker.run(command_name, args)
    local fn = Invoker.commands[command_name]
    if not fn then
        return nil
    end
    return fn(args)
end

return Invoker
