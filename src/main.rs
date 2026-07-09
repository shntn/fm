use fm::terminal::{RawModeGuard, read_key};
use fm::line_input::read_line;
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
        // 直前のon_key呼び出し中にterminal.request_line_inputが呼ばれていれば、
        // 今回の反復は1文字ずつではなく行入力モードでキーを読む
        let key = if let Some(request) = bridge.take_pending_line_input() {
            read_line(request.x, request.y, request.max_width, &request.prompt)
        } else {
            match read_key() {
                Some(k) => k,
                None => continue,
            }
        };

        // Ctrl+Cは強制終了。メインループの通常の終了経路で抜けることで、
        // _guardのDropが実行されターミナルの状態が復元される
        if key == "ctrl-c" {
            break;
        }

        if !dispatch_key(&bridge, &key) {
            break;
        }
    }
}

/// 1回のon_key呼び出し結果を処理し、ループを継続すべきかを返す
fn dispatch_key(bridge: &LuaBridge, key: &str) -> bool {
    match bridge.call_on_key(key) {
        Ok(false) => false,
        Ok(true) => true,
        Err(e) => {
            eprintln!("on_key エラー: {}", e);
            false
        }
    }
}
