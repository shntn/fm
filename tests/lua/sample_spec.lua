-- Luaテストを書く際に踏みやすい落とし穴を集めたファイル。
-- 新しいテストで原因不明のエラーに遭遇したら、ここに類似のケースがないか確認する。
-- 単なるドキュメントではなく実際に実行されるテストなので、挙動が変わればここが壊れて気づける。

describe("package.path", function()
    it("先頭にlua/?.luaを追加しないと、lua/配下のモジュールをrequireできない", function()
        -- このファイルはbustedによってプロジェクトルートから実行されるため、
        -- package.pathにlua/?.luaを追加しないとrequire("template")などが
        -- 「module not found」で失敗する。各specファイルの1行目に
        -- package.path = package.path .. ";lua/?.lua" が必要
        package.path = package.path .. ";lua/?.lua"
        assert.has_no.errors(function()
            require("template")
        end)
    end)
end)

describe("bustedのサンドボックス化", function()
    -- bustedは各specファイルを、本物の_Gとは別のサンドボックステーブルの中で実行する。
    -- サンドボックスは読み取り時だけ_Gにフォールバックするので、"describe"や"assert"は
    -- 見えるが、specファイル内で普通に変数へ代入しても本物の_Gには書き込まれない。
    --
    -- 一方、dofile()やload()（envを指定しない場合）は常に本物の_Gを使って実行される。
    -- そのため fm_spec.lua で dofile("lua/fm.lua") する際、fs/screenのようなモックを
    -- 単に `fs = ...` と書いても fm.lua からは見えず、`_G.fs = ...` と明示する必要がある。

    it("サンドボックスへの代入は、_Gを使うチャンクからは見えない", function()
        sandbox_only_value = "サンドボックスの中にしか存在しない" -- luacheck: ignore

        local chunk = load("return sandbox_only_value")
        assert.is_nil(chunk())
    end)

    it("_G経由の代入は、_Gを使うチャンクからも見える", function()
        _G.shared_value = "_G経由なのでどこからでも見える"

        local chunk = load("return shared_value")
        assert.equals("_G経由なのでどこからでも見える", chunk())

        _G.shared_value = nil
    end)
end)
