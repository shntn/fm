local Screen = require("screen")

local ConfirmFindScreen = setmetatable({}, { __index = Screen })
ConfirmFindScreen.__index = ConfirmFindScreen

function ConfirmFindScreen.new()
    local self = Screen.new()
    return setmetatable(self, ConfirmFindScreen)
end

-- 検索プロンプト自体はRust側のread_lineがon_key終了後に描画するため、
-- ここでは何も描画しない(Screen:viewの既定通り、直前のフレームの表示がそのまま残る)

-- keyはキー名ではなく、Rust側のread_lineが確定/キャンセルした結果そのもの。
-- "escape"ならキャンセル、それ以外は確定した検索文字列
function ConfirmFindScreen:command_mapper(key) -- luacheck: ignore
    if key == "escape" then
        return "cancel"
    end
    return "search", { query = key }
end

return ConfirmFindScreen
