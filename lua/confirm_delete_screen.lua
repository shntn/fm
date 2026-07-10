local Screen = require("screen")
local template = require("template")

local ConfirmDeleteScreen = setmetatable({}, { __index = Screen })
ConfirmDeleteScreen.__index = ConfirmDeleteScreen

function ConfirmDeleteScreen.new(target)
    local self = Screen.new()
    self.target = target
    return setmetatable(self, ConfirmDeleteScreen)
end

-- フッター行に確認メッセージを書く。画面幅いっぱいにパディングし、
-- 直前のフレームの表示が右側に残らないようにする
function ConfirmDeleteScreen:view(data)
    local message = '"' .. self.target.name .. '" を削除しますか？ (y/n)'
    screen.write(0, data.display.height - 1,
        template.render("{message:" .. data.display.width .. "}", { message = message }))
end

function ConfirmDeleteScreen:command_mapper(key)
    if key == "y" then
        return "delete", { target = self.target }
    elseif key == "n" or key == "escape" then
        return "cancel"
    end
    return nil
end

return ConfirmDeleteScreen
