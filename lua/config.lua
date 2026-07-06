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

-- 設定ファイルのパスを返す。FM_CONFIG環境変数があればそちらを優先する
local function config_path()
    return os.getenv("FM_CONFIG") or (os.getenv("HOME") .. "/.config/fm/config.toml")
end

-- 設定を読み込む。ファイルが存在しない、または不正なTOMLの場合は内蔵の既定値を使う
function config.load()
    local text = fs.read_file(config_path())
    local parsed = text and toml.parse(text)
    return parsed or toml.parse(DEFAULT_CONFIG)
end

return config
