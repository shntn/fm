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

    // _guard生成後のエラーはstd::process::exitを使わないこと。
    // Dropが実行されず、ターミナルの状態(rawモード・代替画面バッファ)が復元されないまま終了してしまう
    bridge.call_on_init().unwrap_or_else(|e| {
        panic!("on_init エラー: {}", e);
    });

    loop {
        if let Some(key) = read_key() {
            // Ctrl+Cは強制終了。Luaに渡さずここでメインループを抜けることで、
            // _guardのDropが実行されターミナルの状態が復元される
            if key == "ctrl-c" {
                break;
            }
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