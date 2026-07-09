local Screen = require("screen")
local ListScreen = require("list_screen")
local template = require("template")

-- 下敷きとしてファイル一覧を描画するためだけのインスタンス。ListScreenはステートレスなので共有できる
local list_screen = ListScreen.new()

local ConfirmDeleteScreen = setmetatable({}, { __index = Screen })
ConfirmDeleteScreen.__index = ConfirmDeleteScreen

function ConfirmDeleteScreen.new(target)
    local self = Screen.new()
    self.target = target
    return setmetatable(self, ConfirmDeleteScreen)
end

-- ファイル一覧を下敷きに描画した上で、フッター行に確認メッセージを重ねる
-- 画面幅いっぱいにパディングし、下敷きのフッター文字列が上書きされずに残らないようにする
function ConfirmDeleteScreen:view(data)
    list_screen:view(data)
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
