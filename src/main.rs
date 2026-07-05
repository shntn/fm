use fm::terminal::{RawModeGuard, read_key};
use fm::lua_bridge::LuaBridge;

fn main() {
    let bridge = LuaBridge::new().unwrap_or_else(|e| {
        eprintln!("エラー: Luaランタイムの初期化に失敗しました: {}", e);
        std::process::exit(1);
    });

    bridge.load_script("lua/fm.lua").unwrap_or_else(|e| {
        eprintln!("エラー: {}", e);
        std::process::exit(1);
    });

    let _guard = RawModeGuard::new().expect("rawモードに入れませんでした");

    bridge.call_on_init().unwrap_or_else(|e| {
        eprintln!("on_init エラー: {}", e);
        std::process::exit(1);
    });

    loop {
        if let Some(key) = read_key() {
            match bridge.call_on_key(&key) {
                Ok(false) => break,
                Ok(true) => {}
                Err(e) => {
                    eprintln!("on_key エラー: {}", e);
                    break;
                }
            }
        }
    }
}