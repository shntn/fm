local config = {}

-- 設定ファイルが存在しない、または読み込みに失敗した場合に使う既定値。
-- 実際の設定ファイルと同じTOML形式の文字列として持ち、同じパーサーに通す
local DEFAULT_CONFIG = [[
[associations]
zip = "unzip -l $P/$C | less"
tar = "tar tvf $P/$C | less"
gz = "tar tzvf $P/$C | less"
md = "glow -p $P/$C"
]]

local function config_path()
    return os.getenv("FM_CONFIG") or (os.getenv("HOME") .. "/.config/fm/config.toml")
end

-- toml.parseは不正なTOMLに対してnilを返すため、既定値へのフォールバックはparsedの真偽判定だけで済む
function config.load()
    local text = fs.read_file(config_path())
    local parsed = text and toml.parse(text)
    return parsed or toml.parse(DEFAULT_CONFIG)
end

return config
