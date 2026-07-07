local utf8width = {}

-- East Asian Ambiguous(UAX #11)の幅。既定は1で、set_ambiguous_widthで切り替え可能
local ambiguous_width = 1

function utf8width.set_ambiguous_width(width)
    ambiguous_width = width
end

-- East Asian Wide/Fullwidth(UAX #11)の範囲
local WIDE_RANGES = {
    { 0x1100, 0x115F },   -- ハングル字母
    { 0x2E80, 0x303E },   -- CJK部首・記号
    { 0x3041, 0x33FF },   -- ひらがな・カタカナ・CJK互換
    { 0x3400, 0x4DBF },   -- CJK統合漢字拡張A
    { 0x4E00, 0x9FFF },   -- CJK統合漢字
    { 0xA000, 0xA4CF },   -- 彝文字
    { 0xAC00, 0xD7A3 },   -- ハングル音節
    { 0xF900, 0xFAFF },   -- CJK互換漢字
    { 0xFF00, 0xFF60 },   -- 全角形
    { 0xFFE0, 0xFFE6 },   -- 全角記号
    { 0x20000, 0x3FFFD }, -- CJK統合漢字拡張B以降
}

-- East Asian Ambiguous(UAX #11)の範囲の一部
-- emダッシュ・三点リーダーは端末・フォントによって全角/半角の描画が分かれるため、
-- Wideと決め打ちせずAmbiguousとして扱い、ambiguous_widthの設定に委ねる
local AMBIGUOUS_RANGES = {
    { 0x00A1, 0x00A1 },
    { 0x2014, 0x2015 },   -- emダッシュ・水平線
    { 0x2026, 0x2026 },   -- 三点リーダー（省略記号）
    { 0x00A4, 0x00A4 },
    { 0x00A7, 0x00A8 },
    { 0x00B0, 0x00B4 },
    { 0x00B6, 0x00BA },
    { 0x00BC, 0x00BF },
    { 0x0391, 0x03A9 },   -- ギリシャ文字(大文字)
    { 0x03B1, 0x03C9 },   -- ギリシャ文字(小文字)
    { 0x0401, 0x0401 },
    { 0x0410, 0x044F },   -- キリル文字
    { 0x0451, 0x0451 },
    { 0x2500, 0x257F },   -- 罫線素片
    { 0x2580, 0x259F },   -- ブロック要素
    { 0x25A0, 0x25FF },   -- 幾何学模様
}

-- 結合文字(幅0)の範囲。macOSのファイルシステムはファイル名をNFD正規化するため、
-- 濁点・半濁点付きの仮名（例:「プ」）が基底文字+結合文字の2コードポイントに分解される
local COMBINING_RANGES = {
    { 0x0300, 0x036F }, -- 結合分音記号
    { 0x3099, 0x309A }, -- 結合濁点・結合半濁点
    { 0x20D0, 0x20FF }, -- 記号用結合分音記号
    { 0xFE20, 0xFE2F }, -- 結合半記号
}

local function in_ranges(cp, ranges)
    for _, r in ipairs(ranges) do
        if cp >= r[1] and cp <= r[2] then
            return true
        end
    end
    return false
end

local function codepoint_width(cp)
    if in_ranges(cp, COMBINING_RANGES) then
        return 0
    elseif in_ranges(cp, WIDE_RANGES) then
        return 2
    elseif in_ranges(cp, AMBIGUOUS_RANGES) then
        return ambiguous_width
    end
    return 1
end

-- strの画面上の表示幅を返す。不正なUTF-8の場合はバイト長を返す
function utf8width.width(str)
    local ok, total = pcall(function()
        local sum = 0
        for _, cp in utf8.codes(str) do
            sum = sum + codepoint_width(cp)
        end
        return sum
    end)
    if ok then
        return total
    end
    return #str
end

local ELLIPSIS = "…"

-- strの末尾を1コードポイントずつ削り、表示幅がbudget以下になるまで縮める
local function shrink_from_end(str, budget)
    local result = str
    while utf8width.width(result) > budget do
        local last = utf8.offset(result, -1)
        if not last or last <= 1 then
            return ""
        end
        result = result:sub(1, last - 1)
    end
    return result
end

-- strの先頭を1コードポイントずつ削り、表示幅がbudget以下になるまで縮める
local function shrink_from_start(str, budget)
    local result = str
    while utf8width.width(result) > budget do
        local next_start = utf8.offset(result, 2)
        if not next_start then
            return ""
        end
        result = result:sub(next_start)
    end
    return result
end

-- strの表示幅がmax_widthを超える場合、末尾を省略記号(…)に置き換えて切り詰める
-- 不正なUTF-8の場合はバイト単位で切り詰める
function utf8width.truncate(str, max_width)
    if utf8width.width(str) <= max_width then
        return str
    end
    local ok, result = pcall(function()
        local budget = math.max(max_width - utf8width.width(ELLIPSIS), 0)
        return shrink_from_end(str, budget) .. ELLIPSIS
    end)
    if ok then
        return result
    end
    return str:sub(1, max_width)
end

-- strの表示幅がmax_widthを超える場合、末尾を削って切り詰める(省略記号なし)
-- 不正なUTF-8の場合はバイト単位で切り詰める
function utf8width.cut_end(str, max_width)
    if utf8width.width(str) <= max_width then
        return str
    end
    local ok, result = pcall(shrink_from_end, str, max_width)
    if ok then
        return result
    end
    return str:sub(1, max_width)
end

-- strの表示幅がmax_widthを超える場合、先頭を削って切り詰める(省略記号なし)
-- 不正なUTF-8の場合はバイト単位で切り詰める
function utf8width.cut_start(str, max_width)
    if utf8width.width(str) <= max_width then
        return str
    end
    local ok, result = pcall(shrink_from_start, str, max_width)
    if ok then
        return result
    end
    return str:sub(-max_width)
end

return utf8width
