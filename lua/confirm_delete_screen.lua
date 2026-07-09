local Screen = require("screen")
local template = require("template")

local ConfirmDeleteScreen = setmetatable({}, { __index = Screen })
ConfirmDeleteScreen.__index = ConfirmDeleteScreen

-- previous_screen: 呼び出し元のスクリーン(下敷きの描画と、y/n後の復帰先の両方に使う)
function ConfirmDeleteScreen.new(target, previous_screen)
    local self = Screen.new()
    self.target = target
    self.previous_screen = previous_screen
    return setmetatable(self, ConfirmDeleteScreen)
end

-- 呼び出し元のスクリーンを下敷きに描画した上で、フッター行に確認メッセージを重ねる
-- 画面幅いっぱいにパディングし、下敷きのフッター文字列が上書きされずに残らないようにする
function ConfirmDeleteScreen:view(data)
    self.previous_screen:view(data)
    local message = '"' .. self.target.name .. '" を削除しますか？ (y/n)'
    screen.write(0, data.display.height - 1,
        template.render("{message:" .. data.display.width .. "}", { message = message }))
end

function ConfirmDeleteScreen:command_mapper(key)
    if key == "y" then
        return "delete", { target = self.target, previous_screen = self.previous_screen }
    elseif key == "n" or key == "escape" then
        return "cancel", { previous_screen = self.previous_screen }
    end
    return nil
end

return ConfirmDeleteScreen
