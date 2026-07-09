use crate::support::make_temp_dir;
use fm::lua_bridge::LuaBridge;
use std::fs;

#[test]
fn load_script_errors_when_file_does_not_exist() {
    let bridge = LuaBridge::new().unwrap();
    let err = bridge
        .load_script("/path/does/not/exist-fm-test.lua")
        .unwrap_err();

    assert!(err.to_string().contains("見つかりません"));
}

#[test]
fn call_on_key_returns_false_for_quit_key() {
    let dir = make_temp_dir("bridge-quit");
    let script = dir.join("main.lua");
    fs::write(
        &script,
        r#"
        function on_init() end
        function on_key(key)
            if key == "q" then return false end
            return true
        end
        "#,
    )
    .unwrap();

    let bridge = LuaBridge::new().unwrap();
    bridge.load_script(script.to_str().unwrap()).unwrap();
    bridge.call_on_init().unwrap();

    assert!(!bridge.call_on_key("q").unwrap());
    fs::remove_dir_all(&dir).ok();
}

#[test]
fn call_on_key_returns_true_for_other_keys() {
    let dir = make_temp_dir("bridge-continue");
    let script = dir.join("main.lua");
    fs::write(
        &script,
        r#"
        function on_init() end
        function on_key(key)
            if key == "q" then return false end
            return true
        end
        "#,
    )
    .unwrap();

    let bridge = LuaBridge::new().unwrap();
    bridge.load_script(script.to_str().unwrap()).unwrap();
    bridge.call_on_init().unwrap();

    assert!(bridge.call_on_key("j").unwrap());
    fs::remove_dir_all(&dir).ok();
}

#[test]
fn load_script_allows_requiring_sibling_modules() {
    let dir = make_temp_dir("bridge-require");
    fs::write(
        dir.join("helper.lua"),
        r#"
        local helper = {}
        function helper.value() return 42 end
        return helper
        "#,
    )
    .unwrap();
    fs::write(
        dir.join("main.lua"),
        r#"
        local helper = require("helper")
        assert(helper.value() == 42)
        function on_init() end
        function on_key(key) return true end
        "#,
    )
    .unwrap();

    let bridge = LuaBridge::new().unwrap();
    let result = bridge.load_script(dir.join("main.lua").to_str().unwrap());

    assert!(result.is_ok());
    fs::remove_dir_all(&dir).ok();
}

#[test]
fn take_pending_line_input_returns_request_made_during_on_key() {
    let dir = make_temp_dir("bridge-line-input");
    let script = dir.join("main.lua");
    fs::write(
        &script,
        r#"
        function on_init() end
        function on_key(key)
            terminal.request_line_input(0, 23, 80, "/")
            return true
        end
        "#,
    )
    .unwrap();

    let bridge = LuaBridge::new().unwrap();
    bridge.load_script(script.to_str().unwrap()).unwrap();
    bridge.call_on_init().unwrap();

    assert!(bridge.take_pending_line_input().is_none());
    bridge.call_on_key("/").unwrap();
    let request = bridge.take_pending_line_input().unwrap();
    assert_eq!("/", request.prompt);
    assert!(bridge.take_pending_line_input().is_none());

    fs::remove_dir_all(&dir).ok();
}
