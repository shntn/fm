use crate::support::make_temp_dir;
use fm::filesystem;
use mlua::prelude::*;
use std::fs;

fn new_lua() -> Lua {
    let lua = Lua::new();
    filesystem::register(&lua).unwrap();
    lua
}

mod list {
    use super::*;

    #[test]
    fn returns_file_names_in_directory() {
        let dir = make_temp_dir("list-files");
        fs::write(dir.join("a.txt"), b"hello").unwrap();

        let lua = new_lua();
        let names: Vec<String> = lua
            .load(format!(
                r#"
                local names = {{}}
                for _, f in ipairs(fs.list("{}")) do
                    table.insert(names, f.name)
                end
                return names
                "#,
                dir.display()
            ))
            .eval()
            .unwrap();

        assert!(names.contains(&"a.txt".to_string()));
        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn marks_directory_entries_with_is_dir() {
        let dir = make_temp_dir("list-isdir");
        fs::create_dir(dir.join("sub")).unwrap();

        let lua = new_lua();
        let is_dir: bool = lua
            .load(format!(
                r#"
                for _, f in ipairs(fs.list("{}")) do
                    if f.name == "sub" then return f.is_dir end
                end
                return false
                "#,
                dir.display()
            ))
            .eval()
            .unwrap();

        assert!(is_dir);
        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn returns_nil_and_error_message_for_missing_path() {
        let lua = new_lua();
        let (list, err): (LuaValue, Option<String>) = lua
            .load(r#"return fs.list("/path/does/not/exist-fm-test")"#)
            .eval()
            .unwrap();

        assert!(matches!(list, LuaValue::Nil));
        assert!(err.is_some());
    }
}

mod cwd {
    use super::*;

    #[test]
    fn returns_current_working_directory() {
        let lua = new_lua();
        let cwd: String = lua.load("return fs.cwd()").eval().unwrap();
        let expected = std::env::current_dir().unwrap().to_string_lossy().into_owned();
        assert_eq!(expected, cwd);
    }
}

mod run {
    use super::*;

    #[test]
    fn returns_exit_code_of_command() {
        let lua = new_lua();
        let code: i32 = lua.load(r#"return fs.run("exit 3")"#).eval().unwrap();
        assert_eq!(3, code);
    }
}
