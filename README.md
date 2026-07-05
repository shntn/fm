# fm

ターミナルで動作するファイルマネージャ。

Rust と Lua の2層構造で、Rust は OS とのやり取りを行う薄いインタフェース層、
Lua がファイルマネージャとしての制御ロジックを持つ。ロジックを Lua 側に
置くことで、試作や変更をしやすくすることを狙っている。

個人的な学習・実験目的のプロジェクトで、最低限の機能を実装した段階。

## 必要環境

- Rust 1.70+ (edition 2021)
- macOS または Linux
- ファイルを開く機能で `less` / `xxd` / `grep` を利用する

## ビルドと実行

```sh
cargo build
cargo run
```

## キー操作

| キー | 動作 |
|---|---|
| `j` / `↓` | カーソルを下へ移動 |
| `k` / `↑` | カーソルを上へ移動 |
| `enter` | ディレクトリに入る、またはファイルを開く |
| `backspace` | 親ディレクトリへ移動 |
| `q` / `escape` | 終了 |

## ファイルを開く

カーソル位置のファイルで `enter` を押すと、拡張子に応じたコマンドで開く。

- 拡張子ごとのコマンド定義（`lua/fm.lua` の `OPENERS`）がある場合はそれを実行する
  - `$C`: ファイル名（拡張子あり）
  - `$X`: ファイル名（拡張子なし）
  - `$P`: カレントディレクトリのフルパス
  - 例: `zip = "unzip -l $P/$C | less"`
- 定義がない場合はテキストファイルを `less`、バイナリファイルは `xxd` でダンプして `less` に渡す

## プロジェクト構成

```
fm/
├─ src/    Rust コード（terminal/screen/filesystem/lua_bridge の薄いインタフェース層）
├─ lua/    Lua コード（fm.lua がアプリケーション本体、layout/template/utf8width が支援モジュール）
├─ tests/
│  ├─ rust/  Rust の単体・結合テスト
│  ├─ lua/   Lua の単体テスト
│  └─ e2e/   実バイナリを疑似端末上で動かすスモークテスト（手動実行用）
└─ docs/
   ├─ fm-spec-v0.1.md    プロジェクト全体の仕様
   ├─ API.md             Rust⇔Lua インタフェース仕様
   └─ fm-internal-api.md fm.lua 内部のモジュール間API
```

## テスト

```sh
cargo test
busted tests/lua/
for f in tests/e2e/*.sh; do bash "$f"; done
```

Lint:

```sh
cargo clippy
luacheck lua/
```

## License

MIT License. 詳細は [LICENSE](LICENSE) を参照。
