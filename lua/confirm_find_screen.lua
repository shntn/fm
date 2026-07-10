local Screen = require("screen")

local ConfirmFindScreen = setmetatable({}, { __index = Screen })
ConfirmFindScreen.__index = ConfirmFindScreen

-- previous_screen: 呼び出し元のスクリーン(下敷きの描画と、検索確定/キャンセル後の復帰先の両方に使う)
function ConfirmFindScreen.new(previous_screen)
    local self = Screen.new()
    self.previous_screen = previous_screen
    return setmetatable(self, ConfirmFindScreen)
end

-- 検索プロンプト自体はRust側のread_lineがon_key終了後に描画するため、
-- ここでは呼び出し元のスクリーンをそのまま描画するだけでよい
function ConfirmFindScreen:view(data)
    self.previous_screen:view(data)
end

-- keyはキー名ではなく、Rust側のread_lineが確定/キャンセルした結果そのもの。
-- "escape"ならキャンセル、それ以外は確定した検索文字列
function ConfirmFindScreen:command_mapper(key)
    if key == "escape" then
        return "cancel", { previous_screen = self.previous_screen }
    end
    return "search", { query = key, previous_screen = self.previous_screen }
end

return ConfirmFindScreen
