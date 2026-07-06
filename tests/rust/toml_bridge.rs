use fm::toml_bridge;
use mlua::prelude::*;

fn new_lua() -> Lua {
    let lua = Lua::new();
    toml_bridge::register(&lua).unwrap();
    lua
}

mod parse {
    use super::*;

    #[test]
    fn converts_string_values() {
        let lua = new_lua();
        let value: String = lua
            .load(r#"return toml.parse('name = "fm"').name"#)
            .eval()
            .unwrap();
        assert_eq!("fm", value);
    }

    #[test]
    fn converts_nested_tables() {
        let lua = new_lua();
        let value: String = lua
            .load(r#"return toml.parse('[associations]\nzip = "unzip $C"').associations.zip"#)
            .eval()
            .unwrap();
        assert_eq!("unzip $C", value);
    }

    #[test]
    fn returns_nil_and_error_message_for_invalid_toml() {
        let lua = new_lua();
        let (value, err): (LuaValue, Option<String>) = lua
            .load(r#"return toml.parse("not = valid = toml")"#)
            .eval()
            .unwrap();

        assert!(matches!(value, LuaValue::Nil));
        assert!(err.is_some());
    }
}

mod config_toml {
    use super::*;
    use fm::filesystem;

    // lua/config.toml は設定ファイルのサンプル・開発時のFM_CONFIG動作確認用。
    // 有効なTOMLであり続けることを保証する
    #[test]
    fn is_valid_toml_and_has_expected_associations() {
        let lua = Lua::new();
        filesystem::register(&lua).unwrap();
        toml_bridge::register(&lua).unwrap();

        let zip: String = lua
            .load(r#"return toml.parse(fs.read_file("lua/config.toml")).associations.zip"#)
            .eval()
            .unwrap();

        assert_eq!("unzip -l $P/$C | less", zip);
    }
}
