-- スクリーンの基底テーブル。画面バリエーション（ファイル一覧・確認ダイアログなど）は
-- これを継承し、viewとcommand_mapperを上書きして実装する
local Screen = {}
Screen.__index = Screen

function Screen.new()
    local self = setmetatable({}, Screen)
    return self
end

-- 画面に何を表示するかの描画処理。既定では何もしない
function Screen:view(data) -- luacheck: ignore
end

-- キー入力から実行すべきコマンドを決定する処理。既定では何も反応しない
-- 戻り値: command_name, args（実行すべきコマンドがない場合はnil）
function Screen:command_mapper(key) -- luacheck: ignore
    return nil
end

return Screen
