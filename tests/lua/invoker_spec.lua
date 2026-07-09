package.path = package.path .. ";lua/?.lua"

describe("Invoker.run", function()
    local Invoker

    before_each(function()
        package.loaded["invoker"] = nil
        Invoker = require("invoker")
    end)

    it("登録されたコマンドをコマンド名で実行する", function()
        local called = false
        Invoker.commands.greet = function()
            called = true
        end

        Invoker.run("greet")

        assert.is_true(called)
    end)

    it("実行時に渡したargsがそのままコマンド関数に渡る", function()
        local received = nil
        Invoker.commands.echo = function(args)
            received = args
        end

        Invoker.run("echo", { target = "a.txt" })

        assert.same({ target = "a.txt" }, received)
    end)

    it("コマンド関数の戻り値がそのまま返る", function()
        Invoker.commands.fail = function()
            return "エラーが発生しました"
        end

        local err = Invoker.run("fail")

        assert.equals("エラーが発生しました", err)
    end)

    it("実行時に渡したstateがそのままコマンド関数に渡る", function()
        local received = nil
        Invoker.commands.remember_state = function(_args, state)
            received = state
        end
        local state = { message = "hello" }

        Invoker.run("remember_state", nil, state)

        assert.equals(state, received)
    end)

    it("未登録のコマンド名を渡すとエラーにならずnilを返す", function()
        local result = Invoker.run("unknown_command")

        assert.is_nil(result)
    end)
end)
